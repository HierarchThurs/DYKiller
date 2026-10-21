//
//  DKTopBarSettings.xm
//  功能：顶栏入口 —— 设置项注册：左侧栏入口、滑动展开屏蔽、搜索图标、顶栏透明度。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKTopBarAlpha.h"

%ctor {
    // 下标与 DKTopBarEntrance.xm 的显示模式一致：0 显示 / 1 隐藏 / 2 移除。
    NSArray<NSString *> *modes = @[ @"显示", @"隐藏", @"移除" ];
    DKSettingsRegister(DKKeyTopBarSideBarMode, ^AWESettingItemModel *{
        return DKSettingsWithInfo(DKMakeChoice(DKKeyTopBarSideBarMode, @"左侧栏入口", modes),
            @"首页顶栏左上角的侧边栏入口（≡）。隐藏：图标不显示，原位置仍可点击打开侧边栏；移除：不显示，点击也无反应。");
    });
    DKSettingsRegister(DKKeyBlockSideBarSwipe, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyBlockSideBarSwipe, @"屏蔽滑动展开左侧栏", @"在最左侧频道右滑不再拉出左侧栏");
    });
    DKSettingsRegister(DKKeyTopBarSearchMode, ^AWESettingItemModel *{
        return DKSettingsWithInfo(DKMakeChoice(DKKeyTopBarSearchMode, @"搜索图标", modes),
            @"首页顶栏右上角的搜索图标，打开评论区时右上角的搜索图标一并生效。隐藏：不显示，仍可点击进入搜索；移除：不显示，点击也无反应。");
    });
    DKSettingsRegister(DKKeyTopBarAlpha, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeRangeSlider(DKKeyTopBarAlpha, @"顶栏透明度",
                                                      @"透明度：0% 完全透明，100% 保持抖音原样。",
                                                      0, 100, 100, ^(__unused NSInteger value) {
            DKTopBarAlphaRefresh();
        });
        return DKSettingsWithInfo(item,
            @"同时调整首页顶栏左侧栏入口、全部频道与搜索图标的透明度；打开评论区时右上角的搜索图标一并生效。"
            @"透明后仍可点击。");
    });
}
