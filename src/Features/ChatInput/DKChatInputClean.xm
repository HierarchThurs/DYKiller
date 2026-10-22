//
//  DKChatInputClean.xm
//  DYKiller
//
//  聊天页输入区精简：表情快捷提示条、输入框左侧的玩法入口，以及加号面板上方的最近照片条。
//

#import "DKChatInput.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import "DouyinHeaders.h"
#import <objc/runtime.h>

static NSHashTable<AWEIMInputActionBarInteractor *> *gDKChatActionBars;
static char kDKChatPlayDisabledKey;

static UIView *DKChatPlayButton(id component) {
    id play = DKChatInputComponent(component, @"IESIMInputPlayEntryComponent");
    return DKChatInputObjectIvar(play, "_playEntryBtn");
}

// 玩法入口的开关：打开即「移除」，输入框向左补满。
static BOOL DKChatPlayRemoved(void) {
    return DKPrefBool(DKKeyChatPlayEntryMode);
}

// 只过滤返回的副本，不改原生可变数组。
static NSArray *DKChatFilterPlayButton(id policy, NSArray *buttons) {
    if (!DKChatPlayRemoved() || !DKChatInputController(policy)) return buttons;
    UIView *play = DKChatPlayButton(policy);
    if (!play || ![buttons containsObject:play]) return buttons;
    NSMutableArray *filtered = [buttons mutableCopy];
    [filtered removeObjectIdenticalTo:play];
    return [filtered copy];
}

// 按钮退出布局后补一层命中关闭，避免过渡帧里还能点到它。
static void DKChatPlayApply(id layout) {
    UIView *play = DKChatPlayButton(layout);
    if (!play) return;
    if (DKChatInputController(layout) && DKChatPlayRemoved()) {
        if (!play.userInteractionEnabled) return;
        objc_setAssociatedObject(play, &kDKChatPlayDisabledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        play.userInteractionEnabled = NO;
    } else if (objc_getAssociatedObject(play, &kDKChatPlayDisabledKey)) {
        play.userInteractionEnabled = YES;
        objc_setAssociatedObject(play, &kDKChatPlayDisabledKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// 提示条只接管普通单聊群聊那一套配置，最近照片等浮动业务不受影响。
static BOOL DKChatSuggestionsSupported(AWEIMInputActionBarInteractor *bar) {
    return DKChatInputController(bar)
        && DKChatInputIsKind(bar.barMaker, @"AWEIMInputActionBarMaker_NormalGroupOrPrivate");
}

void DKChatInputCleanRefresh(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKChatInputCleanRefresh(); });
        return;
    }
    for (AWEIMInputActionBarInteractor *bar in gDKChatActionBars.allObjects) {
        if (!DKChatSuggestionsSupported(bar)) continue;
        if (DKPrefBool(DKKeyChatRemoveEmojiSuggestions)) [bar hideActionBarIfNeeded];
        else [bar showActionBarIfPossible];
    }
}

%group DKChatInputCleanHooks
%hook IESIMInputLeftComponentPolicy
- (NSArray *)leftButtonsForShow {
    return DKChatFilterPlayButton(self, %orig);
}
%end
%hook IESIMInputRightComponentPolicy
- (NSArray *)rightButtonsForShow {
    return DKChatFilterPlayButton(self, %orig);
}
%end
%hook IESIMInputLayoutComponent
- (void)p_layoutInputViewsAfterAdjustButtons {
    %orig;
    DKChatInputRegisterLayout(self);
    DKChatPlayApply(self);
    DKChatInputSync(self);
}
- (void)pp_layoutSubviewsWithAnimated:(BOOL)animated context:(id)context {
    %orig;
    DKChatInputRegisterLayout(self);
    DKChatPlayApply(self);
    DKChatInputSync(self);
}
%end
// 最近照片条只在切到加号面板时经分发询问展示，开关打开时答“不展示”，浮动容器按原生收起。
%hook AWEIMQuickSelectPhotoInteractor
- (BOOL)canShowBarWhenInputTypeChangedTo:(long long)type {
    if (DKPrefBool(DKKeyChatRemovePlusPhotos) && DKChatInputController(self)) return NO;
    return %orig;
}
%end
%hook AWEIMInputActionBarInteractor
// 首次展示判定先于 barMaker 赋值；提交浮动布局时配置已确定，由原生收起路径同步回收高度与展示状态。
- (void)p_layoutActionBarShowAnimated:(BOOL)animated {
    if (DKChatSuggestionsSupported(self)) {
        [gDKChatActionBars addObject:self];
        if (DKPrefBool(DKKeyChatRemoveEmojiSuggestions)) {
            [self p_layoutActionBarDismissAnimated:NO];
            return;
        }
    }
    %orig;
}
- (BOOL)p_shouldShowActionBarAfterTypeResolved {
    if (DKChatSuggestionsSupported(self)) {
        [gDKChatActionBars addObject:self];
        if (DKPrefBool(DKKeyChatRemoveEmojiSuggestions)) return NO;
    }
    return %orig;
}
// 输入类型变化会重新判断提示条，与首次配置解析共用同一功能判据。
- (BOOL)p_shouldShowInputActionBarWithInputType:(NSInteger)type {
    if (DKChatSuggestionsSupported(self)) {
        [gDKChatActionBars addObject:self];
        if (DKPrefBool(DKKeyChatRemoveEmojiSuggestions)) return NO;
    }
    return %orig;
}
// 40.8.0 起提示条经浮动容器分发展示，分发方只按这一询问决定是否显示。
- (BOOL)canShowBarWhenInputTypeChangedTo:(long long)type {
    if (DKChatSuggestionsSupported(self)) {
        [gDKChatActionBars addObject:self];
        if (DKPrefBool(DKKeyChatRemoveEmojiSuggestions)) return NO;
    }
    return %orig;
}
%end
%end

%ctor {
    gDKChatActionBars = [NSHashTable weakObjectsHashTable];
    DKSettingsRegister(DKKeyChatRemoveEmojiSuggestions, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(DKKeyChatRemoveEmojiSuggestions, @"移除表情提示",
            @"移除普通私聊和群聊输入框上方的表情快捷提示，并收回布局占位。最近照片等其他浮动内容保持原生。");
        DKSettingsOnChange(item, ^{ DKChatInputCleanRefresh(); DKChatInputRefresh(); });
        return item;
    });
    DKSettingsRegister(DKKeyChatRemovePlusPhotos, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyChatRemovePlusPhotos, @"点击更多面板不弹出本地照片",
            @"打开普通私聊和群聊的加号面板时，输入框上方不再显示最近照片；相册入口仍在加号面板里。关闭时保持原生。");
    });
    DKSettingsRegister(DKKeyChatPlayEntryMode, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(DKKeyChatPlayEntryMode, @"移除输入框左侧玩法按钮",
            @"移除输入框左侧的玩法入口，输入框向左延伸补满；关闭时保持原生按钮、位置与点击。");
        DKSettingsOnChange(item, ^{ DKChatInputRefresh(); });
        return item;
    });
    %init(DKChatInputCleanHooks);
}
