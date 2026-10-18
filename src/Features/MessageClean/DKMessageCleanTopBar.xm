//
//  DKMessageCleanTopBar.xm
//  DYKiller
//
//  消息页精简 —— 顶栏四项：左侧栏、装扮商店（左二运营位）、搜索图标、加号。
//
//  实现：
//   - 导航栏每个槽位是一组候选按钮组件，布局时取第一个 canShowInNaviBar 为真的组件放上去。
//     移除：组件的 canShowInNaviBar 在 %orig 之后返回 NO，重排时不再放它，同侧其余按钮按抖音原生排布收拢。
//     侧边栏组件的 canShowInNaviBar 每次都会新建氛围对象与入口视图，故始终先走 %orig，本模块也不额外调用它。
//   - 右一（加号位）是右侧容器的锚，右二（搜索位）只挂在右一左边。加号移除且右一其余候选都不能显示时，
//     resolve 之后把右二的候选提到右一，搜索落在最右。右一其余候选的 canShowInNaviBar 只做条件判断。
//   - 隐藏：布局向组件取入口视图时记下是哪一项，布局后给入口视图挂全透明 mask，命中不受影响，点击照常。
//   - 设置改动：对记下的导航栏组件 reloadNaviBarButtons（重新 resolve 并重排）。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKMessageClean.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"
#import <objc/runtime.h>

typedef NS_ENUM(NSInteger, DKMessageNaviItem) {
    DKMessageNaviItemNone = 0,
    DKMessageNaviItemSideBar,
    DKMessageNaviItemSlot,
    DKMessageNaviItemSearch,
    DKMessageNaviItemPlus,
};

static char kDKMessageNaviItemKey;
static NSHashTable<AWEIMMessageTabNaviBarComponent *> *gDKMessageNaviBars;
static NSHashTable<UIView *> *gDKMessageNaviViews;

static NSString *DKMessageNaviKey(DKMessageNaviItem item) {
    switch (item) {
        case DKMessageNaviItemSideBar: return DKKeyMessageSideBarMode;
        case DKMessageNaviItemSlot: return DKKeyMessageSlotMode;
        case DKMessageNaviItemSearch: return DKKeyMessageSearchMode;
        case DKMessageNaviItemPlus: return DKKeyMessagePlusMode;
        default: return nil;
    }
}

static NSString *DKMessageNaviName(DKMessageNaviItem item) {
    switch (item) {
        case DKMessageNaviItemSideBar: return @"左侧栏";
        case DKMessageNaviItemSlot: return @"装扮商店";
        case DKMessageNaviItemSearch: return @"搜索图标";
        case DKMessageNaviItemPlus: return @"加号";
        default: return @"-";
    }
}

static DKDisplayMode DKMessageNaviMode(DKMessageNaviItem item) {
    NSString *key = DKMessageNaviKey(item);
    return key ? DKPrefDisplayMode(key) : DKDisplayModeShow;
}

static DKMessageNaviItem DKMessageNaviItemForProvider(id provider) {
    if ([provider isKindOfClass:%c(AWEIMMessageTabSideBarButtonComponent)]) return DKMessageNaviItemSideBar;
    if ([provider isKindOfClass:%c(AWEIMMessageTabNavBarResourceSlotComponentV2)] ||
        [provider isKindOfClass:%c(AWEIMMessageTabNavBarResourceSlotComponent)]) return DKMessageNaviItemSlot;
    if ([provider isKindOfClass:%c(AWEIMMessageTabSearchComponent)]) return DKMessageNaviItemSearch;
    if ([provider isKindOfClass:%c(AWEIMMessageTabPlusButtonComponent)]) return DKMessageNaviItemPlus;
    return DKMessageNaviItemNone;
}

static BOOL DKMessageNaviRemoved(DKMessageNaviItem item) {
    return DKMessageNaviMode(item) == DKDisplayModeRemove;
}

// 隐藏与移除都不绘制入口；移除时入口本就不在导航栏上，mask 只作兜底。
static void DKMessageNaviApplyView(UIView *view) {
    DKMessageNaviItem item = (DKMessageNaviItem)[objc_getAssociatedObject(view, &kDKMessageNaviItemKey) integerValue];
    DKAdjustFade(view, DKMessageNaviMode(item) == DKDisplayModeShow ? 1.0 : 0.0, view.bounds.size);
}

static void DKMessageNaviPromoteSearch(AWEIMMessageTabNaviBarComponent *bar) {
    if (!DKMessageNaviRemoved(DKMessageNaviItemPlus)) return;
    if (![bar respondsToSelector:@selector(rightFirstBtnComponents)] ||
        ![bar respondsToSelector:@selector(setRightFirstBtnComponents:)]) return;
    for (id component in bar.rightFirstBtnComponents) {
        if (DKMessageNaviItemForProvider(component) == DKMessageNaviItemPlus) continue;
        if ([component respondsToSelector:@selector(canShowInNaviBar)] && [component canShowInNaviBar]) return;
    }
    NSArray *second = bar.rightSecondBtnComponents;
    if (!second.count) return;
    bar.rightFirstBtnComponents = second;
    bar.rightSecondBtnComponents = @[];
}

void DKMessageCleanTopBarRefresh(void) {
    for (AWEIMMessageTabNaviBarComponent *bar in gDKMessageNaviBars.allObjects) {
        if ([bar respondsToSelector:@selector(reloadNaviBarButtons)]) [bar reloadNaviBarButtons];
    }
    for (UIView *view in gDKMessageNaviViews.allObjects) DKMessageNaviApplyView(view);
}

static NSString *DKMessageNaviSlotText(NSArray *components) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (id component in components) [names addObject:NSStringFromClass([component class])];
    return names.count ? [names componentsJoinedByString:@", "] : @"空";
}

NSString *DKMessageCleanTopBarStatus(void) {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"已见导航栏组件=%lu\n", (unsigned long)gDKMessageNaviBars.allObjects.count];
    for (AWEIMMessageTabNaviBarComponent *bar in gDKMessageNaviBars.allObjects) {
        if (![bar respondsToSelector:@selector(rightFirstBtnComponents)]) continue;
        [out appendFormat:@"  右一=[%@]\n  右二=[%@]\n",
            DKMessageNaviSlotText(bar.rightFirstBtnComponents), DKMessageNaviSlotText(bar.rightSecondBtnComponents)];
    }
    for (UIView *view in gDKMessageNaviViews.allObjects) {
        DKMessageNaviItem item = (DKMessageNaviItem)[objc_getAssociatedObject(view, &kDKMessageNaviItemKey) integerValue];
        [out appendFormat:@"  %@ %@ 在窗口=%d frame=%@ 淡出=%.2f\n", DKMessageNaviName(item), NSStringFromClass(view.class),
            view.window != nil, NSStringFromCGRect([view convertRect:view.bounds toView:nil]), DKAdjustFadeFactor(view)];
    }
    return out;
}

%hook AWEIMMessageTabNaviBarComponent

- (void)p_resolveButtonComponent {
    %orig;
    DKMessageNaviPromoteSearch(self);
}

- (id)p_getCustomNaviButtonViewFromProvider:(id)provider {
    id view = %orig;
    DKMessageNaviItem item = DKMessageNaviItemForProvider(provider);
    if (item != DKMessageNaviItemNone && [view isKindOfClass:UIView.class]) {
        objc_setAssociatedObject(view, &kDKMessageNaviItemKey, @(item), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!gDKMessageNaviViews) gDKMessageNaviViews = [NSHashTable weakObjectsHashTable];
        [gDKMessageNaviViews addObject:view];
    }
    return view;
}

- (void)p_layoutNaviButtons {
    %orig;
    if (!gDKMessageNaviBars) gDKMessageNaviBars = [NSHashTable weakObjectsHashTable];
    [gDKMessageNaviBars addObject:self];
    for (UIView *view in gDKMessageNaviViews.allObjects) DKMessageNaviApplyView(view);
}

%end

%hook AWEIMMessageTabSideBarButtonComponent

- (BOOL)canShowInNaviBar {
    BOOL show = %orig;
    return show && !DKMessageNaviRemoved(DKMessageNaviItemSideBar);
}

%end

%hook AWEIMMessageTabNavBarResourceSlotComponentV2

- (BOOL)canShowInNaviBar {
    BOOL show = %orig;
    return show && !DKMessageNaviRemoved(DKMessageNaviItemSlot);
}

%end

%hook AWEIMMessageTabNavBarResourceSlotComponent

- (BOOL)canShowInNaviBar {
    BOOL show = %orig;
    return show && !DKMessageNaviRemoved(DKMessageNaviItemSlot);
}

%end

%hook AWEIMMessageTabSearchComponent

- (BOOL)canShowInNaviBar {
    BOOL show = %orig;
    return show && !DKMessageNaviRemoved(DKMessageNaviItemSearch);
}

%end

%hook AWEIMMessageTabPlusButtonComponent

- (BOOL)canShowInNaviBar {
    BOOL show = %orig;
    return show && !DKMessageNaviRemoved(DKMessageNaviItemPlus);
}

%end
