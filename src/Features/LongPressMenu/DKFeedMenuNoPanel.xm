//
//  DKFeedMenuNoPanel.xm
//  长按菜单：长按作品不弹出长按面板。
//
//  实现：
//   - 推荐页等播放页、主页作品格、搜索结果、私信作品等长按入口在弹面板前都问
//     -[AWELongPressPanelManager shouldShowPanelWhenUserDidLongPressWithModel:referString:scene:]，
//     返回 NO 时不弹面板；两参数版本转调这一个。开关开启时返回 NO。
//   - iPad 播放页的「更多」按钮用同一判定决定显示与弹出，开关开启时一并不显示。
//   - 屏幕两侧长按倍速是另一个手势，不经过这个判定。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"

%group DKFeedMenuNoPanelHooks

%hook AWELongPressPanelManager

- (BOOL)shouldShowPanelWhenUserDidLongPressWithModel:(id)model referString:(id)referString scene:(id)scene {
    return DKPrefBool(DKKeyFeedMenuNoPanel) ? NO : %orig;
}

%end

%end

%ctor {
    DKSettingsRegister(DKKeyFeedMenuNoPanel, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyFeedMenuNoPanel, @"长按不弹出长按面板",
                            @"开启后长按视频、图文或作品封面都不再弹出长按面板，iPad 播放页的「更多」按钮一并隐藏。屏幕两侧长按倍速不受影响。");
    });

    Class manager = NSClassFromString(@"AWELongPressPanelManager");
    if ([manager instancesRespondToSelector:@selector(shouldShowPanelWhenUserDidLongPressWithModel:referString:scene:)]) {
        %init(DKFeedMenuNoPanelHooks);
    }
}
