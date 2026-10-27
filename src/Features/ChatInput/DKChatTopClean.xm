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
static char kDKChatAvatarNotchKey;

static BOOL DKChatTopRemoved(id component, NSString *key) {
    return DKPrefBool(key) && DKChatInputController(component);
}

static void DKChatBackSync(AWEIMNavigationUnreadView *view) {
    if (!DKChatInputControllerForPageView(view)) return;
    [gDKChatUnreadViews addObject:view];
    DKAdjustFade(view.backButton, DKPrefBool(DKKeyChatRemoveBack) ? 0.0 : 1.0, CGSizeZero);
}

// 原生缺口只为头像上的圆点留外圈：圆点被移除或移出头像期间撤掉缺口，回到头像后按原生规则（圆点显示才挂）挂回；没撤过时不碰。
static void DKChatAvatarNotchApply(AWEIMMessageListNaviBarTitleAvatarComponent *component) {
    UIView *dot = component.onlineDotView;
    BOOL away = DKPrefBool(DKKeyChatRemoveOnline) || DKChatTopOnlineDotAway(dot);
    if (!away && !objc_getAssociatedObject(component, &kDKChatAvatarNotchKey)) return;
    objc_setAssociatedObject(component, &kDKChatAvatarNotchKey, away ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CALayer *layer = component.contentView.layer;
    CALayer *mask = !away && dot && !dot.hidden ? component.notchLayer : nil;
    if (layer.mask != mask) layer.mask = mask;
}

static void DKChatOnlineDotSync(AWEIMMessageListNaviBarTitleAvatarComponent *component) {
    if (!DKChatInputController(component)) return;
    [gDKChatAvatarComponents addObject:component];
    DKAdjustFade(component.onlineDotView, DKPrefBool(DKKeyChatRemoveOnline) ? 0.0 : 1.0, CGSizeZero);
    DKChatAvatarNotchApply(component);
}

void DKChatTopAvatarNotchSync(UIView *dot) {
    if (!dot) return;
    for (AWEIMMessageListNaviBarTitleAvatarComponent *component in gDKChatAvatarComponents.allObjects) {
        if (component.onlineDotView == dot) DKChatAvatarNotchApply(component);
    }
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
// 原生只在这里同步算一次是否展开（不带动画），之后才进入转场与首帧；此时收起，首帧即为收起态。
- (void)hostVC_viewDidLoad {
    %orig;
    if (DKPrefBool(DKKeyChatGroupZoneNoAutoExpand) && DKChatInputController(self) && self.isGroupZoneExpanded) {
        [self toggleGroupZoneExpanded:NO];
    }
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
        @[ DKKeyChatGroupZoneNoAutoExpand, @"不自动展开群聊顶部",
           @"进入群聊时，若群功能栏被自动展开（群主、管理员或功能项有新内容时），在页面显示前收起；未展开时不做处理，仍可点右上角按钮手动展开。" ],
    ];
    for (NSArray *row in rows) DKSettingsRegister(row[0], ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(row[0], row[1], row[2]);
        DKSettingsOnChange(item, ^{ DKChatTopBarRefresh(); });
        return item;
    });
    %init(DKChatTopCleanHooks, DKChatCleanGroupEntryBar = NSClassFromString(@"AWEIMGroupImpl.GroupZoneEntryBarView"));
}
