// 搜索页精简：各区域与输入入口的设置项。
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"

%ctor {
    DKSettingsRegister(DKKeySearchRemoveHistory, ^{
        return DKSettingsNeedsRestart(DKMakeSwitch(DKKeySearchRemoveHistory, @"移除历史搜索区域",
            @"移除搜索页的历史记录区域，保留已存储的搜索历史。重启抖音后生效。"));
    });

    DKSettingsRegister(DKKeySearchRemoveGuess, ^{
        return DKSettingsNeedsRestart(DKMakeSwitch(DKKeySearchRemoveGuess, @"移除猜你想搜区域",
            @"移除搜索页的「猜你想搜」区域及其占位。重启抖音后生效。"));
    });
    DKSettingsRegister(DKKeySearchRemoveAllRanks, ^{
        return DKSettingsNeedsRestart(DKMakeSwitch(DKKeySearchRemoveAllRanks, @"移除全部榜单",
            @"移除搜索页整块榜单区域，包括全部榜单标签、榜单内容与查看完整榜单按钮。开启时「移除查看完整榜单按钮」灰显，原选择保留。重启抖音后生效。"));
    });
    DKSettingsRegister(DKKeySearchRemoveRankFooter, ^{
        return DKSettingsNeedsRestart(DKMakeSwitch(DKKeySearchRemoveRankFooter, @"移除查看完整榜单按钮",
            @"统一移除搜索页各榜单底部的「查看完整…」按钮并阻止点击。重启抖音后生效。"));
    });
    DKSettingsRegister(DKKeySearchRemoveVoice, ^{
        return DKSettingsNeedsRestart(DKMakeSwitch(DKKeySearchRemoveVoice, @"移除语音输入",
            @"移除搜索页右下角的语音入口，以及展开键盘后居中放大的语音入口。重启抖音后生效。"));
    });
    DKSettingsRegister(DKKeySearchCameraMode, ^{
        AWESettingItemModel *item = DKMakeChoice(DKKeySearchCameraMode, @"相机入口", @[ @"显示", @"隐藏", @"移除" ]);
        return DKSettingsNeedsRestart(DKSettingsWithInfo(item,
            @"搜索框右侧的相机 / 扫一扫入口。显示：保持抖音原样；隐藏：图标不可见，保留位置与点击；移除：不显示、不可点击，按原生布局收拢。重启抖音后生效。"));
    });
}
