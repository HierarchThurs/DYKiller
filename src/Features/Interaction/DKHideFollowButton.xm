//
//  DKHideFollowButton.xm
//  功能：播放体验 —— 移除用户头像下方的「关注(+)」按钮。
//
//  作用面：首页信息流 / 用户主页 / 好友分享页等竖屏播放交互层。
//  目标视图是头像下方的 AWEPlayInteractionFollowPromptView。
//
//  实现：
//   - 用 hidden=YES 隐藏整视图。
//   - 用关联对象标记本功能隐藏过的视图，关闭开关时只还原这些视图。
//   - 只设置 hidden，不写 frame。
//

#import "DouyinHeaders.h"
#import "DKUtils.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import <objc/runtime.h>

static char kDKFollowBtnHiddenByDK;   // 标记：此 + 由本功能隐藏，供关闭时精准还原

%hook AWEPlayInteractionFollowPromptView

- (void)layoutSubviews {
    %orig;

    if (DKPrefBool(DKKeyHideFollowButton)) {
        if (!self.hidden) {   // 已隐藏时不重复置位
            self.hidden = YES;
            objc_setAssociatedObject(self, &kDKFollowBtnHiddenByDK, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } else if (objc_getAssociatedObject(self, &kDKFollowBtnHiddenByDK)) {
        self.hidden = NO;     // 仅还原本功能藏过的视图
        objc_setAssociatedObject(self, &kDKFollowBtnHiddenByDK, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%end

#pragma mark - 设置项注册

%ctor {
    DKSettingsRegisterItem(@"播放体验", ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyHideFollowButton, @"移除关注按钮", @"隐藏头像下方的＋并禁止点击");
    });
}
