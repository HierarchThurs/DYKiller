//
//  DKHideFollowButton.xm
//  功能：头像下方「关注(+)」按钮的显示 / 隐藏 / 移除。
//
//  作用面：首页信息流 / 用户主页 / 好友分享页等竖屏播放交互层。
//  目标视图是头像下方的 AWEPlayInteractionFollowPromptView，叠在头像块底部，不占独立行。
//
//  实现：
//   - 隐藏：挂透明 mask，不改 hidden，仍可点击关注。
//   - 移除：hidden=YES，与抖音对已关注作者的原生形态一致（头像块高度不变）；用关联对象标记本功能隐藏过的视图，
//     切回其他档位时只还原这些视图。只设置 hidden，不写 frame。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"
#import <objc/runtime.h>

static char kDKFollowBtnHiddenByDK;   // 标记：此 + 由本功能隐藏，供切换档位时精准还原

static NSHashTable<UIView *> *gDKFollowButtons;

static void DKFollowButtonApply(UIView *view) {
    DKDisplayMode mode = DKPrefDisplayMode(DKKeyFollowButtonDisplay);
    DKAdjustFade(view, mode == DKDisplayModeHide ? 0.0 : 1.0, CGSizeZero);

    if (mode == DKDisplayModeRemove) {
        if (!view.hidden) {   // 已隐藏时不重复置位
            view.hidden = YES;
            objc_setAssociatedObject(view, &kDKFollowBtnHiddenByDK, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } else if (objc_getAssociatedObject(view, &kDKFollowBtnHiddenByDK)) {
        view.hidden = NO;     // 仅还原本功能藏过的视图
        objc_setAssociatedObject(view, &kDKFollowBtnHiddenByDK, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void DKFollowButtonRefresh(void) {
    for (UIView *view in gDKFollowButtons.allObjects) DKFollowButtonApply(view);
}

%hook AWEPlayInteractionFollowPromptView

- (void)layoutSubviews {
    %orig;
    if (!gDKFollowButtons) gDKFollowButtons = [NSHashTable weakObjectsHashTable];
    [gDKFollowButtons addObject:self];
    DKFollowButtonApply(self);
}

%end

#pragma mark - 设置项注册

%ctor {
    DKSettingsRegister(DKKeyFollowButtonDisplay, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeChoice(DKKeyFollowButtonDisplay, @"关注按钮", @[ @"显示", @"隐藏", @"移除" ]);
        DKSettingsOnChange(item, ^{ DKFollowButtonRefresh(); });
        return DKSettingsWithInfo(item, @"默认显示；隐藏只隐藏头像下方的关注入口，仍可点击；移除不显示、不可点击，与已关注作者时一致。");
    });
}
