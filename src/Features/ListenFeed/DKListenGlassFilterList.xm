//
//  DKListenGlassFilterList.xm
//  DYKiller
//
//  听抖音分类列表页：返回圆钮与标题胶囊，列表铺到屏幕顶边并从玻璃下方滑过。
//  列表没有依赖 contentOffset 为 0 的逻辑，顶部留白用 contentInset。
//

#import "DKListenGlass.h"
#import "DouyinHeaders.h"

#import <objc/runtime.h>

static char kDKListenListTopInsetKey;
static char kDKListenListAdjustmentKey;

static NSHashTable<AWEListenFeedFilterListViewController *> *gDKListenFilterLists;

// 原生每轮布局都写回 frame，这里只在开启时盖上一层；关闭时撤掉 inset。
static void DKListenListExtend(UICollectionView *list) {
    NSNumber *applied = objc_getAssociatedObject(list, &kDKListenListTopInsetKey);
    if (!DKListenGlassOn()) {
        if (!applied) return;
        UIEdgeInsets inset = list.contentInset;
        inset.top -= applied.doubleValue;
        list.contentInset = inset;
        list.verticalScrollIndicatorInsets = UIEdgeInsetsZero;
        list.contentInsetAdjustmentBehavior = (UIScrollViewContentInsetAdjustmentBehavior)[objc_getAssociatedObject(list, &kDKListenListAdjustmentKey) integerValue];
        objc_setAssociatedObject(list, &kDKListenListTopInsetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    CGRect frame = list.frame;
    CGFloat top = CGRectGetMinY(frame);
    if (top <= 0.0) return;
    frame.origin.y = 0.0;
    frame.size.height += top;
    list.frame = frame;
    if (applied) return;

    objc_setAssociatedObject(list, &kDKListenListAdjustmentKey, @(list.contentInsetAdjustmentBehavior), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(list, &kDKListenListTopInsetKey, @(top), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    list.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    // UIScrollView 写 contentInset 时可能自己挪 contentOffset，这里按写之前的值定位，首行保持原位。
    CGPoint offset = list.contentOffset;
    UIEdgeInsets inset = list.contentInset;
    inset.top += top;
    list.contentInset = inset;
    list.verticalScrollIndicatorInsets = UIEdgeInsetsMake(top, 0.0, 0.0, 0.0);
    list.contentOffset = CGPointMake(offset.x, offset.y - top);
}

void DKListenFilterListGlassRefresh(void) {
    for (AWEListenFeedFilterListViewController *page in gDKListenFilterLists.allObjects) {
        [page.view setNeedsLayout];
        DKListenGlassSyncNav(page.view, page.backButton, page.titleLabel, 0.0);
    }
}

%group DKListenGlassFilterListHooks

%hook AWEListenFeedFilterListViewController

- (void)customLayoutCollectionView:(UICollectionView *)list {
    %orig;
    DKListenListExtend(list);
}

- (void)viewDidLayoutSubviews {
    %orig;
    [gDKListenFilterLists addObject:self];
    DKListenGlassSyncNav(self.view, self.backButton, self.titleLabel, 0.0);
}

%end

%end

%ctor {
    gDKListenFilterLists = [NSHashTable weakObjectsHashTable];
    if (DKGlassOSAvailable()) %init(DKListenGlassFilterListHooks);
}
