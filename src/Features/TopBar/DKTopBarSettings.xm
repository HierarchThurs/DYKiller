//
//  DKTopBarSettings.xm
//  功能：顶栏入口 —— 设置项注册：左侧栏入口、滑动展开屏蔽、搜索图标。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"

%ctor {
    // 下标与 DKTopBarEntrance.xm 的显示模式一致：0 显示 / 1 隐藏 / 2 移除。
    NSArray<NSString *> *modes = @[ @"显示", @"隐藏（可点击）", @"移除（不可点击）" ];
    DKSettingsRegisterItem(@"顶栏", ^AWESettingItemModel *{
        return DKMakeChoice(DKKeyTopBarSideBarMode, @"左侧栏入口", modes);
    });
    DKSettingsRegisterItem(@"顶栏", ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyBlockSideBarSwipe, @"屏蔽滑动展开左侧栏", @"在最左侧频道右滑不再拉出左侧栏");
    });
    DKSettingsRegisterItem(@"顶栏", ^AWESettingItemModel *{
        return DKMakeChoice(DKKeyTopBarSearchMode, @"搜索图标", modes);
    });
}
