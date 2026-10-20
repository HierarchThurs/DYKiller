//
//  DKFeedCardFit.m
//  DYKiller
//
//  非视频条目的让位规则：底边约束收短与底部背景条。接入点见 DKFeedCardHooks.xm。
//
// 约束接管保存原常量，关闭时还原；背景条沿内容底边取样并纵向延伸。
//
#import "DKFeedCardFit.h"
#import "DKVideoFeedTable.h"
#import "DKVideoFullscreen.h"
#import <objc/runtime.h>
#import <math.h>

// 覆盖 @3x 像素对齐带来的亚像素漂移。
static const CGFloat kDKCardTolerance = 0.5;
// 从内容视图往上找视频表的层数上限：音乐卡在图文列表与集合视图 cell 里，比普通视频深。
static const NSUInteger kDKCardTableDepth = 16;
// 背景条取样：合并后的首次取样与补取样的延迟。
static const NSTimeInterval kDKSampleDelay = 0.05;
static const NSTimeInterval kDKResampleDelay = 0.6;

static char kDKConstraintOriginalKey;   // NSLayoutConstraint：接管前的 constant

static NSHashTable<NSLayoutConstraint *> *gDKFittedConstraints;
static NSHashTable<UIView *> *gDKBackdropHosts;

struct DKFeedCardCounters {
    NSUInteger fits;        // 写入收短后的约束常量
    NSUInteger backdrops;   // 新建背景条
};
static struct DKFeedCardCounters gDKCardCounters[DKFeedCardTypeCount];
static NSUInteger gDKMissingConstraints, gDKSamples, gDKSkippedSamples;

@interface DKFeedCardBackdropView : UIImageView
@property (nonatomic) BOOL samplePending;
@property (nonatomic) BOOL resamplePending;
@end

@implementation DKFeedCardBackdropView
@end

#pragma mark - 让位高度

CGFloat DKFeedCardInset(UIView *view) {
    if (!view || !DKVideoFullscreenOn()) return 0.0;
    Class tableClass = DKVideoFeedTableClass();
    if (!tableClass) return 0.0;

    UIView *table = view.superview;
    UITableViewCell *cell = [view isKindOfClass:UITableViewCell.class] ? (UITableViewCell *)view : nil;
    for (NSUInteger depth = 0; table && depth < kDKCardTableDepth; depth++, table = table.superview) {
        if ([table isKindOfClass:tableClass]) break;
        if ([table isKindOfClass:UITableViewCell.class]) cell = (UITableViewCell *)table;
    }
    if (!table || ![table isKindOfClass:tableClass] || !cell) return 0.0;
    NSNumber *original = DKVideoFeedTableOriginalHeight(table);
    if (!original) return 0.0;

    // 原高以当前行顶边为锚；换到宿主坐标后，只让出它实际越过安全底边的部分。
    CGPoint safeBottom = [cell convertPoint:CGPointMake(0.0, original.doubleValue) toView:view];
    CGFloat inset = CGRectGetMaxY(view.bounds) - safeBottom.y;
    return inset > kDKCardTolerance ? MIN(CGRectGetHeight(view.bounds), inset) : 0.0;
}

#pragma mark - 底边约束

// container.bottom == anchor.bottom（或两项颠倒）的等式约束，装在 anchor 上；reversed 表示 anchor 在前，常量方向相反。
// anchor 从父视图往上找到所在 cell 为止：特殊卡根视图在 contentView 里，底边约束连的是 cell。
static NSLayoutConstraint *DKCardBottomConstraint(UIView *container, BOOL *reversed) {
    for (UIView *anchor = container.superview; anchor; anchor = anchor.superview) {
        for (NSLayoutConstraint *constraint in anchor.constraints) {
            if (!constraint.active || constraint.relation != NSLayoutRelationEqual
                || constraint.firstAttribute != NSLayoutAttributeBottom
                || constraint.secondAttribute != NSLayoutAttributeBottom
                || constraint.multiplier != 1.0) continue;
            if (constraint.firstItem == container && constraint.secondItem == anchor) {
                *reversed = NO;
                return constraint;
            }
            if (constraint.firstItem == anchor && constraint.secondItem == container) {
                *reversed = YES;
                return constraint;
            }
        }
        if ([anchor isKindOfClass:UITableViewCell.class] || [anchor isKindOfClass:UICollectionViewCell.class]) break;
    }
    return nil;
}

static void DKCardRestoreConstraint(NSLayoutConstraint *constraint) {
    NSNumber *original = objc_getAssociatedObject(constraint, &kDKConstraintOriginalKey);
    if (!original) return;
    constraint.constant = original.doubleValue;
    objc_setAssociatedObject(constraint, &kDKConstraintOriginalKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gDKFittedConstraints removeObject:constraint];
}

BOOL DKFeedCardFitContainer(UIView *container, CGFloat inset, DKFeedCardType type) {
    if (!container.superview || type >= DKFeedCardTypeCount) return NO;
    BOOL reversed = NO;
    NSLayoutConstraint *bottom = DKCardBottomConstraint(container, &reversed);
    if (!bottom) {
        if (inset > 0.0) gDKMissingConstraints++;
        return NO;
    }
    if (inset <= 0.0) {
        DKCardRestoreConstraint(bottom);
        return NO;
    }

    NSNumber *original = objc_getAssociatedObject(bottom, &kDKConstraintOriginalKey);
    if (!original) {
        original = @(bottom.constant);
        objc_setAssociatedObject(bottom, &kDKConstraintOriginalKey, original, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!gDKFittedConstraints) gDKFittedConstraints = [NSHashTable weakObjectsHashTable];
        [gDKFittedConstraints addObject:bottom];
    }
    CGFloat target = original.doubleValue + (reversed ? inset : -inset);
    if (fabs(bottom.constant - target) <= kDKCardTolerance) return YES;
    bottom.constant = target;
    gDKCardCounters[type].fits++;
    return YES;
}

BOOL DKFeedCardContainerIsFitted(UIView *container) {
    BOOL reversed = NO;
    NSLayoutConstraint *bottom = DKCardBottomConstraint(container, &reversed);
    return bottom && objc_getAssociatedObject(bottom, &kDKConstraintOriginalKey) != nil;
}

#pragma mark - 背景条

static DKFeedCardBackdropView *DKCardBackdrop(UIView *host) {
    for (UIView *subview in host.subviews) {
        if ([subview isKindOfClass:DKFeedCardBackdropView.class]) return (DKFeedCardBackdropView *)subview;
    }
    return nil;
}

void DKFeedCardSyncBackdrop(UIView *host, CGFloat inset, DKFeedCardType type) {
    if (!host || type >= DKFeedCardTypeCount) return;
    DKFeedCardBackdropView *strip = DKCardBackdrop(host);
    if (inset <= 0.0) {
        [strip removeFromSuperview];
        [gDKBackdropHosts removeObject:host];
        return;
    }
    if (!strip) {
        strip = [[DKFeedCardBackdropView alloc] initWithFrame:CGRectZero];
        strip.userInteractionEnabled = NO;
        strip.contentMode = UIViewContentModeScaleToFill;
        [host addSubview:strip];
        if (!gDKBackdropHosts) gDKBackdropHosts = [NSHashTable weakObjectsHashTable];
        [gDKBackdropHosts addObject:host];
        gDKCardCounters[type].backdrops++;
    } else if (host.subviews.lastObject != strip) {
        [host bringSubviewToFront:strip];
    }
    CGRect frame = CGRectMake(0.0, CGRectGetHeight(host.bounds) - inset, CGRectGetWidth(host.bounds), inset);
    if (!CGRectEqualToRect(strip.frame, frame)) strip.frame = frame;
}

// 取背景条正上方 1pt 的整行像素。这一行在背景条之外，渲染结果不含背景条自己。
static void DKCardSampleBackdrop(UIView *host) {
    DKFeedCardBackdropView *strip = DKCardBackdrop(host);
    CGFloat width = CGRectGetWidth(host.bounds);
    CGFloat row = CGRectGetMinY(strip.frame) - 1.0;
    if (!strip || !host.window || width <= 0.0 || row < 0.0) {
        gDKSkippedSamples++;
        return;
    }
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(width, 1.0) format:format];
    strip.image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextTranslateCTM(context.CGContext, 0.0, -row);
        [host.layer renderInContext:context.CGContext];
    }];
    gDKSamples++;
}

// 每条背景条各合并一次短延迟取样与一次补取样；布局连续到达时不会累积延时任务。
static void DKCardScheduleSample(UIView *host, NSTimeInterval delay, BOOL resample) {
    DKFeedCardBackdropView *strip = DKCardBackdrop(host);
    if (resample ? strip.resamplePending : strip.samplePending) return;
    if (resample) strip.resamplePending = YES;
    else strip.samplePending = YES;
    __weak UIView *weakHost = host;
    __weak DKFeedCardBackdropView *weakStrip = strip;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIView *strongHost = weakHost;
        DKFeedCardBackdropView *strongStrip = weakStrip;
        if (!strongStrip || !DKVideoFullscreenOn() || DKCardBackdrop(strongHost) != strongStrip) return;
        if (resample) strongStrip.resamplePending = NO;
        else strongStrip.samplePending = NO;
        DKCardSampleBackdrop(strongHost);
    });
}

void DKFeedCardRequestBackdropSample(UIView *host) {
    if (!DKVideoFullscreenOn() || !host || !DKCardBackdrop(host)) return;
    DKCardScheduleSample(host, kDKSampleDelay, NO);
    DKCardScheduleSample(host, kDKResampleDelay, YES);
}

#pragma mark - 还原与统计

void DKFeedCardRestore(void) {
    for (NSLayoutConstraint *constraint in gDKFittedConstraints.allObjects) DKCardRestoreConstraint(constraint);
    [gDKFittedConstraints removeAllObjects];
    for (UIView *host in gDKBackdropHosts.allObjects) [DKCardBackdrop(host) removeFromSuperview];
    [gDKBackdropHosts removeAllObjects];
}

NSString *DKFeedCardStats(void) {
    static NSString *const names[DKFeedCardTypeCount] = { @"特殊卡", @"音乐卡", @"文章" };
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger type = 0; type < DKFeedCardTypeCount; type++) {
        [out appendFormat:@"%@ 收短=%lu 背景条=%lu  ", names[type],
            (unsigned long)gDKCardCounters[type].fits, (unsigned long)gDKCardCounters[type].backdrops];
    }
    [out appendFormat:@"底边约束缺失=%lu 取样=%lu 跳过=%lu 接管中约束=%lu 背景条宿主=%lu",
        (unsigned long)gDKMissingConstraints, (unsigned long)gDKSamples, (unsigned long)gDKSkippedSamples,
        (unsigned long)gDKFittedConstraints.allObjects.count, (unsigned long)gDKBackdropHosts.allObjects.count];
    return out;
}
