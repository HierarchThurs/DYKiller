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
static NSUInteger gDKMissingConstraints, gDKSamples, gDKSkippedSamples, gDKEmptySamples;

@interface DKFeedCardBackdropView : UIImageView
@property (nonatomic) BOOL samplePending;
@property (nonatomic) BOOL resamplePending;
@property (nonatomic) CGFloat contentBottom;
@property (nonatomic) CGRect sourceBounds;
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
        strip.hidden = YES;
        [host insertSubview:strip atIndex:0];
        if (!gDKBackdropHosts) gDKBackdropHosts = [NSHashTable weakObjectsHashTable];
        [gDKBackdropHosts addObject:host];
        gDKCardCounters[type].backdrops++;
    } else if (host.subviews.firstObject != strip) {
        [host insertSubview:strip atIndex:0];
    }
    CGFloat bottom = CGRectGetMaxY(host.bounds) - inset;
    if (strip.contentBottom != bottom || !CGRectEqualToRect(strip.sourceBounds, host.bounds)) {
        strip.contentBottom = bottom;
        strip.sourceBounds = host.bounds;
        strip.image = nil;
        strip.hidden = YES;
        strip.frame = CGRectMake(CGRectGetMinX(host.bounds), bottom, CGRectGetWidth(host.bounds), inset);
        DKFeedCardRequestBackdropSample(host);
    }
}

// 在底部预留量对应的内容横带内，从下往上找整行不透明像素；按设备像素对齐填充起点。
static UIImage *DKCardBottomImage(UIView *host, DKFeedCardBackdropView *strip, CGFloat *bottom) {
    CGRect bounds = host.bounds;
    CGFloat scale = host.traitCollection.displayScale;
    if (scale <= 0.0) return nil;
    CGFloat end = floor(strip.contentBottom * scale) / scale;
    CGFloat depth = MIN(end - CGRectGetMinY(bounds), CGRectGetMaxY(bounds) - strip.contentBottom);
    if (depth <= 0.0 || CGRectGetWidth(bounds) <= 0.0) return nil;
    size_t width = (size_t)floor(CGRectGetWidth(bounds) * scale);
    size_t height = (size_t)ceil(depth * scale);
    CGFloat top = end - height / scale;
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space,
        kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) return nil;

    CGContextTranslateCTM(context, 0.0, height);
    CGContextScaleCTM(context, scale, -scale);
    CGContextTranslateCTM(context, -CGRectGetMinX(bounds), -top);
    // 背景条已延伸进原内容的透明边时，取样仍只读取原页面。
    BOOL hidden = strip.layer.hidden;
    strip.layer.hidden = YES;
    [host.layer renderInContext:context];
    strip.layer.hidden = hidden;

    const uint8_t *pixels = CGBitmapContextGetData(context);
    size_t stride = CGBitmapContextGetBytesPerRow(context);
    UIImage *image = nil;
    for (size_t row = height; row > 0; row--) {
        const uint8_t *line = pixels + (row - 1) * stride;
        BOOL opaque = YES;
        for (size_t x = 0; x < width; x++) {
            if (line[x * 4 + 3] != UINT8_MAX) { opaque = NO; break; }
        }
        if (!opaque) continue;
        CGImageRef snapshot = CGBitmapContextCreateImage(context);
        CGImageRef sample = CGImageCreateWithImageInRect(snapshot, CGRectMake(0, row - 1, width, 1));
        image = [UIImage imageWithCGImage:sample scale:scale orientation:UIImageOrientationUp];
        CGImageRelease(sample);
        CGImageRelease(snapshot);
        *bottom = top + row / scale;
        break;
    }
    CGContextRelease(context);
    return image;
}

static void DKCardSampleBackdrop(UIView *host) {
    DKFeedCardBackdropView *strip = DKCardBackdrop(host);
    if (!strip || !host.window) {
        gDKSkippedSamples++;
        return;
    }
    CGFloat bottom = 0.0;
    UIImage *image = DKCardBottomImage(host, strip, &bottom);
    strip.image = image;
    strip.hidden = image == nil;
    if (!image) {
        gDKEmptySamples++;
        return;
    }
    strip.frame = CGRectMake(CGRectGetMinX(host.bounds), bottom, CGRectGetWidth(host.bounds),
        CGRectGetMaxY(host.bounds) - bottom);
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
    [out appendFormat:@"底边约束缺失=%lu 取样=%lu 跳过=%lu 无有效背景=%lu 接管中约束=%lu 背景条宿主=%lu",
        (unsigned long)gDKMissingConstraints, (unsigned long)gDKSamples, (unsigned long)gDKSkippedSamples,
        (unsigned long)gDKEmptySamples,
        (unsigned long)gDKFittedConstraints.allObjects.count, (unsigned long)gDKBackdropHosts.allObjects.count];
    return out;
}
