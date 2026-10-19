//
//  DKFriendCleanTopBar.xm
//  DYKiller
//
//  朋友页精简 —— 顶栏三项：左上角头像和加号（日常相机）、中间「限时日常」胶囊、右上角朋友按钮。
//
//  实现：
//   - 头像和加号、朋友按钮固定在顶栏两端，不涉及收拢。隐藏与移除都给入口挂全透明 mask（未读角标在按钮内，一并不绘制）；
//     移除另让顶栏 hitTest 落在该入口里时返回 nil，触摸交给下层视图。顶栏布局时按设置挂上或摘掉 mask。
//   - 限时日常胶囊：隐藏挂全透明 mask，点击仍可展开；移除时胶囊的 setHidden: 写入「抖音请求值 || 移除」，
//     并让天窗总闸门 enableOpenWithEnterMethod: 返回 NO，点胶囊、刷新后自动展开、下拉都不再展开天窗。
//   - 设置改动：已见顶栏重新挂 mask；胶囊按设置重写 hidden，不再移除时写回抖音最近一次请求的值。
//

#import "DouyinHeaders.h"
#import "DKFriendClean.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"
#import <objc/runtime.h>

static char kDKFriendBubbleRequestedHiddenKey;
// 弱表（顶栏、胶囊、天窗控制器），只在主线程读写。
static NSHashTable *gDKFriendNavViews;
static NSHashTable *gDKFriendBubbles;
static NSHashTable *gDKFriendSkylights;

static void DKFriendTopBarTrack(NSHashTable * __strong *table, id object) {
    if (!object) return;
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKFriendTopBarTrack(table, object); });
        return;
    }
    if (!*table) *table = [NSHashTable weakObjectsHashTable];
    [*table addObject:object];
}

static BOOL DKFriendRemoved(NSString *key) {
    return DKPrefDisplayMode(key) == DKDisplayModeRemove;
}

static CGFloat DKFriendFadeFactor(NSString *key) {
    return DKPrefDisplayMode(key) == DKDisplayModeShow ? 1.0 : 0.0;
}

static UIView *DKFriendNavAvatarEntrance(AWEFamiliarNavView *nav) {
    UIView *view = [nav respondsToSelector:@selector(publishEntranceView)] ? nav.publishEntranceView : nil;
    return [view isKindOfClass:UIView.class] ? view : nil;
}

static UIView *DKFriendNavButton(AWEFamiliarNavView *nav) {
    UIView *view = [nav respondsToSelector:@selector(friendsRequestButton)] ? nav.friendsRequestButton : nil;
    return [view isKindOfClass:UIView.class] ? view : nil;
}

static void DKFriendNavApply(AWEFamiliarNavView *nav) {
    UIView *avatar = DKFriendNavAvatarEntrance(nav);
    if (avatar) DKAdjustFade(avatar, DKFriendFadeFactor(DKKeyFriendAvatarEntryMode), avatar.bounds.size);
    UIView *button = DKFriendNavButton(nav);
    if (button) DKAdjustFade(button, DKFriendFadeFactor(DKKeyFriendButtonMode), button.bounds.size);
}

static BOOL DKFriendNavHitRemoved(AWEFamiliarNavView *nav, UIView *hit) {
    UIView *avatar = DKFriendNavAvatarEntrance(nav);
    if (avatar && DKFriendRemoved(DKKeyFriendAvatarEntryMode) && [hit isDescendantOfView:avatar]) return YES;
    UIView *button = DKFriendNavButton(nav);
    if (button && DKFriendRemoved(DKKeyFriendButtonMode) && [hit isDescendantOfView:button]) return YES;
    return NO;
}

static void DKFriendBubbleApply(UIView *bubble) {
    DKAdjustFade(bubble, DKFriendFadeFactor(DKKeyFriendDailyMode), bubble.bounds.size);
}

void DKFriendCleanTopBarRefresh(void) {
    for (AWEFamiliarNavView *nav in gDKFriendNavViews.allObjects) DKFriendNavApply(nav);
    for (UIView *bubble in gDKFriendBubbles.allObjects) {
        NSNumber *requested = objc_getAssociatedObject(bubble, &kDKFriendBubbleRequestedHiddenKey);
        [bubble setHidden:requested ? requested.boolValue : bubble.isHidden];
        DKFriendBubbleApply(bubble);
    }
}

NSString *DKFriendCleanTopBarStatus(void) {
    NSMutableString *out = [NSMutableString string];
    for (AWEFamiliarNavView *nav in gDKFriendNavViews.allObjects) {
        UIView *avatar = DKFriendNavAvatarEntrance(nav), *button = DKFriendNavButton(nav);
        [out appendFormat:@"顶栏 在窗口=%d 头像和加号=%@ hidden=%d 淡出=%.2f 朋友按钮=%@ hidden=%d 淡出=%.2f\n", nav.window != nil,
            avatar ? NSStringFromCGRect([avatar convertRect:avatar.bounds toView:nil]) : @"-", avatar.isHidden, DKAdjustFadeFactor(avatar),
            button ? NSStringFromCGRect([button convertRect:button.bounds toView:nil]) : @"-", button.isHidden, DKAdjustFadeFactor(button)];
    }
    for (UIView *bubble in gDKFriendBubbles.allObjects) {
        NSNumber *requested = objc_getAssociatedObject(bubble, &kDKFriendBubbleRequestedHiddenKey);
        [out appendFormat:@"限时日常胶囊 在窗口=%d hidden=%d 抖音请求=%@ 淡出=%.2f frame=%@\n", bubble.window != nil, bubble.isHidden,
            requested ?: @"-", DKAdjustFadeFactor(bubble), NSStringFromCGRect([bubble convertRect:bubble.bounds toView:nil])];
    }
    for (AWEFamiliarSkylightViewController *skylight in gDKFriendSkylights.allObjects) {
        [out appendFormat:@"天窗 展开中=%d\n", [skylight respondsToSelector:@selector(isOpening)] && [skylight isOpening]];
    }
    return out;
}

%hook AWEFamiliarNavView

- (void)layoutSubviews {
    %orig;
    DKFriendTopBarTrack(&gDKFriendNavViews, self);
    DKFriendNavApply(self);
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = %orig;
    return (hit && DKFriendNavHitRemoved(self, hit)) ? nil : hit;
}

%end

%hook AWEFamiliarSkylightBubbleView

- (void)setHidden:(BOOL)hidden {
    objc_setAssociatedObject(self, &kDKFriendBubbleRequestedHiddenKey, @(hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(hidden || DKFriendRemoved(DKKeyFriendDailyMode));
}

- (void)layoutSubviews {
    %orig;
    DKFriendTopBarTrack(&gDKFriendBubbles, self);
    DKFriendBubbleApply(self);
}

%end

%hook AWEFamiliarSkylightViewController

- (BOOL)enableOpenWithEnterMethod:(id)enterMethod {
    BOOL enable = %orig;
    DKFriendTopBarTrack(&gDKFriendSkylights, self);
    return enable && !DKFriendRemoved(DKKeyFriendDailyMode);
}

%end
