//
//  DKProfileCleanTopBar.xm
//  DYKiller
//
//  个人主页精简 —— 顶栏四项：添加好友、访客、搜索图标、侧栏图标。
//
//  实现：
//   - 顶栏组件向条目控制器逐个询问 canShow，为真的放进左右数据源再按顺序排布。
//     移除：自己主页上该项的 canShow 在 %orig 之后返回 NO，同侧其余条目按抖音原生排布收拢。
//   - 隐藏：条目控制器交出 navigationItemView 时记下是哪一项，顶栏容器布局后给它挂全透明 mask，命中不受影响。
//     移除时条目本就不在顶栏上，mask 与容器 hitTest 只作兜底。
//   - 设置改动：对记下的顶栏组件 reloadData（重新询问 canShow 并重排），再给已见条目重挂 mask。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKProfileClean.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"
#import <objc/runtime.h>

typedef NS_ENUM(NSInteger, DKProfileNaviItem) {
    DKProfileNaviItemNone = 0,
    DKProfileNaviItemAddFriend,
    DKProfileNaviItemVisitor,
    DKProfileNaviItemSearch,
    DKProfileNaviItemSideBar,
};

static char kDKProfileNaviItemKey;
// 弱表（顶栏组件、条目视图），只在主线程读写。
static NSHashTable *gDKProfileNaviComponents;
static NSHashTable<UIView *> *gDKProfileNaviViews;

static NSString *DKProfileNaviKey(DKProfileNaviItem item) {
    switch (item) {
        case DKProfileNaviItemAddFriend: return DKKeyProfileAddFriendMode;
        case DKProfileNaviItemVisitor: return DKKeyProfileVisitorMode;
        case DKProfileNaviItemSearch: return DKKeyProfileSearchMode;
        case DKProfileNaviItemSideBar: return DKKeyProfileSideBarMode;
        default: return nil;
    }
}

static NSString *DKProfileNaviName(DKProfileNaviItem item) {
    switch (item) {
        case DKProfileNaviItemAddFriend: return @"添加好友";
        case DKProfileNaviItemVisitor: return @"访客";
        case DKProfileNaviItemSearch: return @"搜索图标";
        case DKProfileNaviItemSideBar: return @"侧栏图标";
        default: return @"-";
    }
}

static DKDisplayMode DKProfileNaviMode(DKProfileNaviItem item) {
    NSString *key = DKProfileNaviKey(item);
    return key ? DKPrefDisplayMode(key) : DKDisplayModeShow;
}

static BOOL DKProfileNaviIsMine(id controller) {
    AWEProfileContext *context = [controller respondsToSelector:@selector(profileContext)] ? [controller profileContext] : nil;
    return [context respondsToSelector:@selector(isCurrentUser)] && [context isCurrentUser];
}

static BOOL DKProfileNaviCanShow(id controller, DKProfileNaviItem item, BOOL canShow) {
    if (!canShow || DKProfileNaviMode(item) != DKDisplayModeRemove) return canShow;
    return !DKProfileNaviIsMine(controller);
}

// 只给自己主页上的条目视图记项目；视图上没有记号的一律按「显示」处理。
static DKProfileNaviItem DKProfileNaviItemOfView(UIView *view) {
    return (DKProfileNaviItem)[objc_getAssociatedObject(view, &kDKProfileNaviItemKey) integerValue];
}

static void DKProfileNaviApplyView(UIView *view) {
    DKProfileNaviItem item = DKProfileNaviItemOfView(view);
    DKAdjustFade(view, DKProfileNaviMode(item) == DKDisplayModeShow ? 1.0 : 0.0, view.bounds.size);
}

static UIView *DKProfileNaviTrackView(id controller, DKProfileNaviItem item, UIView *view) {
    if (![view isKindOfClass:UIView.class] || !NSThread.isMainThread) return view;
    BOOL mine = DKProfileNaviIsMine(controller);
    objc_setAssociatedObject(view, &kDKProfileNaviItemKey, mine ? @(item) : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!gDKProfileNaviViews) gDKProfileNaviViews = [NSHashTable weakObjectsHashTable];
    [gDKProfileNaviViews addObject:view];
    id component = [controller respondsToSelector:@selector(delegate)] ? [controller delegate] : nil;
    if (mine && [component isKindOfClass:%c(AWEProfileNavigationBaseComponent)]) {
        if (!gDKProfileNaviComponents) gDKProfileNaviComponents = [NSHashTable weakObjectsHashTable];
        [gDKProfileNaviComponents addObject:component];
    }
    return view;
}

static BOOL DKProfileNaviHitRemoved(UIView *container, UIView *hit) {
    for (UIView *view in container.subviews) {
        DKProfileNaviItem item = DKProfileNaviItemOfView(view);
        if (item != DKProfileNaviItemNone && DKProfileNaviMode(item) == DKDisplayModeRemove && [hit isDescendantOfView:view]) {
            return YES;
        }
    }
    return NO;
}

void DKProfileCleanTopBarRefresh(void) {
    for (AWEProfileNavigationBaseComponent *component in gDKProfileNaviComponents.allObjects) {
        if ([component respondsToSelector:@selector(reloadData)]) [component reloadData];
    }
    for (UIView *view in gDKProfileNaviViews.allObjects) DKProfileNaviApplyView(view);
}

NSString *DKProfileCleanTopBarStatus(void) {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"已见顶栏组件=%lu\n", (unsigned long)gDKProfileNaviComponents.allObjects.count];
    for (UIView *view in gDKProfileNaviViews.allObjects) {
        DKProfileNaviItem item = DKProfileNaviItemOfView(view);
        if (item == DKProfileNaviItemNone) continue;
        [out appendFormat:@"  %@ %@ 在顶栏=%d 在窗口=%d frame=%@ 淡出=%.2f\n", DKProfileNaviName(item),
            NSStringFromClass(view.class), [view.superview isKindOfClass:%c(AWEProfileNavigationContainerView)],
            view.window != nil, NSStringFromCGRect([view convertRect:view.bounds toView:nil]), DKAdjustFadeFactor(view)];
    }
    return out;
}

%hook AWEProfileNaviAddFriendItemController

- (BOOL)canShow {
    return DKProfileNaviCanShow(self, DKProfileNaviItemAddFriend, %orig);
}

- (UIView *)navigationItemView {
    return DKProfileNaviTrackView(self, DKProfileNaviItemAddFriend, %orig);
}

%end

%hook AWEProfileNavVisitorItemController

- (BOOL)canShow {
    return DKProfileNaviCanShow(self, DKProfileNaviItemVisitor, %orig);
}

- (UIView *)navigationItemView {
    return DKProfileNaviTrackView(self, DKProfileNaviItemVisitor, %orig);
}

%end

%hook AWEProfileNavSearchItemController

- (BOOL)canShow {
    return DKProfileNaviCanShow(self, DKProfileNaviItemSearch, %orig);
}

- (UIView *)navigationItemView {
    return DKProfileNaviTrackView(self, DKProfileNaviItemSearch, %orig);
}

%end

%hook AWEProfileNavMoreFuncItemController

- (BOOL)canShow {
    return DKProfileNaviCanShow(self, DKProfileNaviItemSideBar, %orig);
}

- (UIView *)navigationItemView {
    return DKProfileNaviTrackView(self, DKProfileNaviItemSideBar, %orig);
}

%end

%hook AWEProfileNavigationContainerView

- (void)layoutSubviews {
    %orig;
    for (UIView *view in self.subviews) {
        if (DKProfileNaviItemOfView(view) != DKProfileNaviItemNone || DKAdjustFadeFactor(view) < 1.0) DKProfileNaviApplyView(view);
    }
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = %orig;
    return (hit && DKProfileNaviHitRemoved(self, hit)) ? nil : hit;
}

%end
