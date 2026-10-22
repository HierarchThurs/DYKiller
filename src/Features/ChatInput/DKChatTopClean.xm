// 普通聊天顶栏精简，按钮和标题通过原生 provider 退出布局。
#import "DKChatTopBar.h"
#import "DKChatInput.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"
#import "DouyinHeaders.h"
#import <objc/runtime.h>

static NSHashTable *gDKChatUnreadViews;
static NSHashTable *gDKChatAvatarComponents;
static NSHashTable *gDKChatGroupBars;
static char kDKChatUnreadCountKey;

static BOOL DKChatTopRemoved(id component, NSString *key) {
    return DKPrefBool(key) && DKChatInputController(component);
}

static void DKChatBackSync(AWEIMNavigationUnreadView *view) {
    if (!DKChatInputControllerForPageView(view)) return;
    [gDKChatUnreadViews addObject:view];
    DKAdjustFade(view.backButton, DKPrefBool(DKKeyChatRemoveBack) ? 0.0 : 1.0, CGSizeZero);
}

static void DKChatOnlineDotSync(AWEIMMessageListNaviBarTitleAvatarComponent *component) {
    if (!DKChatInputController(component)) return;
    [gDKChatAvatarComponents addObject:component];
    DKAdjustFade(component.onlineDotView, DKPrefBool(DKKeyChatRemoveOnline) ? 0.0 : 1.0, CGSizeZero);
}

static void DKChatGroupCleanSync(UIView *view) {
    if (!DKChatInputControllerForPageView(view)) return;
    [gDKChatGroupBars addObject:view];
    DKAdjustAlpha(view, DKPrefBool(DKKeyChatRemoveMenu) ? 0.0 : 1.0);
}

void DKChatTopCleanRefresh(void) {
    for (AWEIMNavigationUnreadView *view in gDKChatUnreadViews.allObjects) {
        NSNumber *count = objc_getAssociatedObject(view, &kDKChatUnreadCountKey);
        if (count) [view updateWithCount:count.longLongValue];
        DKChatBackSync(view);
    }
    for (id component in gDKChatAvatarComponents.allObjects) DKChatOnlineDotSync(component);
    for (UIView *bar in gDKChatGroupBars.allObjects) DKChatGroupCleanSync(bar);
}

%group DKChatTopCleanHooks
%hook AWEIMNavigationUnreadView
- (void)updateWithCount:(long long)count {
    objc_setAssociatedObject(self, &kDKChatUnreadCountKey, @(count), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BOOL remove = DKPrefBool(DKKeyChatRemoveUnread) && DKChatInputControllerForPageView(self);
    %orig(remove ? 0 : count);
    DKChatBackSync(self);
}
- (void)p_updateUI { %orig; DKChatBackSync(self); }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (DKPrefBool(DKKeyChatRemoveBack) && DKChatInputControllerForPageView(self)
        && CGRectContainsPoint(self.backButton.frame, point)) return nil;
    return %orig;
}
%end
%hook AWEIMMessageListNaviBarBackAndUnreadCountComponent
- (UIView *)naviBarView {
    AWEIMNavigationUnreadView *view = (id)%orig;
    if (!view || !DKChatInputController(self)) return view;
    NSNumber *count = objc_getAssociatedObject(view, &kDKChatUnreadCountKey);
    if (count) [view updateWithCount:count.longLongValue];
    DKChatBackSync(view);
    if (DKPrefBool(DKKeyChatRemoveBack) && (DKPrefBool(DKKeyChatRemoveUnread) || view.unreadCountView.hidden || view.unreadCountView.alpha <= 0.01)) return nil;
    return view;
}
%end
%hook AWEIMMessageListOnLineComponent
- (UIView *)naviBarTitleCustomView {
    UIView *view = %orig;
    return DKChatTopRemoved(self, DKKeyChatRemoveOnline) ? nil : view;
}
%end
%hook AWEIMMessageListNaviBarTitleAvatarComponent
- (void)p_updateDots { %orig; DKChatOnlineDotSync(self); }
- (UIView *)naviBarTitleCustomView {
    UIView *view = %orig;
    DKChatOnlineDotSync(self);
    return view;
}
%end
%hook AWEIMMessageListNaviVoIPEntryComponent
- (UIView *)naviBarView {
    UIView *view = %orig;
    return DKChatTopRemoved(self, DKKeyChatRemoveCall) ? nil : view;
}
%end
%hook AWEIMMessageListNaviBarChatDetailComponent
- (UIView *)naviBarView {
    UIView *view = %orig;
    return DKChatTopRemoved(self, DKKeyChatRemoveMenu) ? nil : view;
}
%end
%hook AWEIMMessageListNaviBarGroupZoneToggleComponent
- (UIView *)naviBarView {
    UIView *view = %orig;
    return DKChatTopRemoved(self, DKKeyChatRemoveMenu) ? nil : view;
}
%end
%hook AWEIMGroupZoneConversationComponent
- (double)desiredGroupZoneHeight {
    return DKChatTopRemoved(self, DKKeyChatRemoveMenu) ? 0.0 : %orig;
}
%end
%hook DKChatCleanGroupEntryBar
- (void)layoutSubviews { %orig; DKChatGroupCleanSync(self); }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (DKPrefBool(DKKeyChatRemoveMenu) && DKChatInputControllerForPageView(self)) return nil;
    return %orig;
}
%end
%end

%ctor {
    gDKChatUnreadViews = [NSHashTable weakObjectsHashTable];
    gDKChatAvatarComponents = [NSHashTable weakObjectsHashTable];
    gDKChatGroupBars = [NSHashTable weakObjectsHashTable];
    NSArray *rows = @[
        @[ DKKeyChatRemoveBack, @"移除返回按钮", @"移除聊天页顶部的返回箭头并关闭箭头区域的点击，未读数字由独立设置控制。" ],
        @[ DKKeyChatRemoveUnread, @"移除未读数字显示", @"移除返回箭头旁的未读数字与底板，返回箭头保持原生功能。" ],
        @[ DKKeyChatRemoveOnline, @"移除在线状态显示", @"移除聊天页顶部头像上的在线圆点及名称下方的在线状态文字。" ],
        @[ DKKeyChatRemoveCall, @"移除通话按钮", @"移除聊天页顶部的通话入口，并收回布局占位。" ],
        @[ DKKeyChatRemoveMenu, @"移除菜单按钮", @"移除群聊顶部的展开按钮与群功能栏并收回占位；私聊移除右上角聊天详情入口。" ],
    ];
    for (NSArray *row in rows) DKSettingsRegister(row[0], ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(row[0], row[1], row[2]);
        DKSettingsOnChange(item, ^{ DKChatTopBarRefresh(); });
        return item;
    });
    %init(DKChatTopCleanHooks, DKChatCleanGroupEntryBar = NSClassFromString(@"AWEIMGroupImpl.GroupZoneEntryBarView"));
}
