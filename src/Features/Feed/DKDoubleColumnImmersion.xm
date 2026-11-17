//
//  DKDoubleColumnImmersion.xm
//  功能：首页双列作品流（点击首页后的推荐双列、「精选」频道）铺满整屏，顶栏与底栏直接悬浮在作品流上方。
//  顶部跟随顶栏液态玻璃；底部跟随底栏页面沉浸（悬浮玻璃底栏或视频全屏）。
//
//  实现：
//   - 列表 frame：列表控制器每轮布局都向代理取 dcFeed:frameForCollectionView:，在两个代理上把原生 frame
//     向上、向下延伸，延伸量记在集合视图上。
//   - 内容留白：延伸量补进布局的内容留白，首屏位置与原生相同，contentOffset 的语义不变（回顶、是否在顶部等
//     原生判断不受影响）。三种瀑布流布局各有留白入口：AWEDCFeedSectionWaterfallLayout 与
//     AWEMVSectionWaterfallLayout 读 totalSectionsInset，AWEBaseListWaterfallLayout 逐分区读
//     awelistkit_insetAtSectionIndex:（延伸量补在首尾分区）。
//   - 底部浮层：约束在列表底边的兄弟视图（AI 按钮等）的常量同步扣除延伸量，保持原生位置。
//

#import "DKDoubleColumnFeed.h"
#import "DKTabBarPageImmersion.h"
#import "DKTopBarGlass.h"
#import "DouyinHeaders.h"

#import <objc/runtime.h>

static char kDKDoubleColumnExtensionKey;
static char kDKDoubleColumnNativeConstantKey;

static NSHashTable<AWEDCFeedListViewController *> *gDKDoubleColumnLists;

static UIEdgeInsets DKDoubleColumnExtension(UICollectionView *collectionView) {
    NSValue *value = objc_getAssociatedObject(collectionView, &kDKDoubleColumnExtensionKey);
    return value ? value.UIEdgeInsetsValue : UIEdgeInsetsZero;
}

static void DKDoubleColumnSyncBottomFloats(UICollectionView *collectionView, CGFloat bottomExtension) {
    for (NSLayoutConstraint *constraint in collectionView.superview.constraints) {
        if (constraint.secondItem != collectionView
            || constraint.firstAttribute != NSLayoutAttributeBottom
            || constraint.secondAttribute != NSLayoutAttributeBottom) {
            continue;
        }
        NSNumber *native = objc_getAssociatedObject(constraint, &kDKDoubleColumnNativeConstantKey);
        if (!native) {
            native = @(constraint.constant);
            objc_setAssociatedObject(constraint, &kDKDoubleColumnNativeConstantKey, native, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        CGFloat target = native.doubleValue - bottomExtension;
        if (constraint.constant != target) constraint.constant = target;
    }
}

static CGRect DKDoubleColumnExtendedFrame(AWEDCFeedListViewController *list, UICollectionView *collectionView, CGRect nativeFrame) {
    if (!gDKDoubleColumnLists) gDKDoubleColumnLists = [NSHashTable weakObjectsHashTable];
    [gDKDoubleColumnLists addObject:list];

    UIEdgeInsets extension = UIEdgeInsetsZero;
    if (DKTopBarGlassEnabled()) {
        extension.top = MAX(CGRectGetMinY(nativeFrame), 0);
    }
    if (DKTabBarPageImmersionActive()) {
        extension.bottom = MAX(CGRectGetHeight(list.view.bounds) - CGRectGetMaxY(nativeFrame), 0);
    }

    if (!UIEdgeInsetsEqualToEdgeInsets(extension, DKDoubleColumnExtension(collectionView))) {
        objc_setAssociatedObject(collectionView, &kDKDoubleColumnExtensionKey,
            [NSValue valueWithUIEdgeInsets:extension], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [collectionView.collectionViewLayout invalidateLayout];
    }
    DKDoubleColumnSyncBottomFloats(collectionView, extension.bottom);

    nativeFrame.origin.y -= extension.top;
    nativeFrame.size.height += extension.top + extension.bottom;
    return nativeFrame;
}

static UIEdgeInsets DKDoubleColumnAddExtension(UIEdgeInsets inset, UICollectionView *collectionView) {
    UIEdgeInsets extension = DKDoubleColumnExtension(collectionView);
    inset.top += extension.top;
    inset.bottom += extension.bottom;
    return inset;
}

void DKDoubleColumnImmersionSetNeedsUpdate(void) {
    for (AWEDCFeedListViewController *list in gDKDoubleColumnLists.allObjects) {
        [list.viewIfLoaded setNeedsLayout];
    }
}

NSString *DKDoubleColumnImmersionStatus(void) {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"顶栏玻璃=%@ 底栏页面沉浸=%@\n",
        DKTopBarGlassEnabled() ? @"开" : @"关", DKTabBarPageImmersionActive() ? @"开" : @"关"];
    NSArray<AWEDCFeedListViewController *> *lists = gDKDoubleColumnLists.allObjects;
    for (AWEDCFeedListViewController *list in lists) {
        UICollectionView *collectionView = list.collectionView;
        UIEdgeInsets extension = DKDoubleColumnExtension(collectionView);
        [out appendFormat:@"  %@ layout=%@ frame=%@ 延伸上=%.1f 下=%.1f offset=%.1f contentH=%.1f\n",
            list.referString, NSStringFromClass(collectionView.collectionViewLayout.class),
            NSStringFromCGRect(collectionView.frame), extension.top, extension.bottom,
            collectionView.contentOffset.y, collectionView.contentSize.height];
    }
    if (lists.count == 0) [out appendString:@"  还没有见到双列列表\n"];
    return out;
}

%hook AWEFeedNewDoubleColumnViewController

- (CGRect)dcFeed:(AWEDCFeedListViewController *)list frameForCollectionView:(UICollectionView *)collectionView {
    return DKDoubleColumnExtendedFrame(list, collectionView, %orig);
}

%end

%hook AWEMVChannelDCDelegator

- (CGRect)dcFeed:(AWEDCFeedListViewController *)list frameForCollectionView:(UICollectionView *)collectionView {
    CGRect frame = %orig;
    if (![self.containerVC isKindOfClass:%c(AWENewMVChannelViewController)]) return frame;
    return DKDoubleColumnExtendedFrame(list, collectionView, frame);
}

%end

%hook AWEDCFeedSectionWaterfallLayout

- (UIEdgeInsets)totalSectionsInset {
    return DKDoubleColumnAddExtension(%orig, self.collectionView);
}

%end

%hook AWEMVSectionWaterfallLayout

- (UIEdgeInsets)totalSectionsInset {
    return DKDoubleColumnAddExtension(%orig, self.collectionView);
}

%end

%hook AWEDCFeedListViewController

- (UIEdgeInsets)awelistkit_insetAtSectionIndex:(NSInteger)section {
    UIEdgeInsets inset = %orig;
    UICollectionView *collectionView = self.collectionView;
    if (![collectionView.collectionViewLayout isKindOfClass:%c(AWEBaseListWaterfallLayout)]) return inset;
    UIEdgeInsets extension = DKDoubleColumnExtension(collectionView);
    if (section == 0) inset.top += extension.top;
    if (extension.bottom > 0 && section == collectionView.numberOfSections - 1) inset.bottom += extension.bottom;
    return inset;
}

%end
