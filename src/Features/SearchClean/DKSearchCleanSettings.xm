// 搜索页精简：固定区域开关与自动收录的榜单选择页。
#import "DKSearchClean.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"

static NSString *DKSearchRankDetail(void) {
    NSUInteger count = 0;
    for (NSDictionary *entry in DKSearchRankCatalog()) if (DKSearchRankHidden(entry[@"id"])) count++;
    return count ? [NSString stringWithFormat:@"已移除 %lu 项", (unsigned long)count] : @"未移除";
}

static void DKSearchOpenRanks(AWESettingItemModel *entryItem, UIViewController *presenter) {
    NSMutableArray *rows = [NSMutableArray array];
    __weak AWESettingItemModel *weakEntry = entryItem;
    for (NSDictionary *entry in DKSearchRankCatalog()) {
        NSString *title = entry[@"title"];
        AWESettingItemModel *row = DKSettingsNeedsRestart(DKMakeSwitch(DKSearchRankHideKey(entry[@"id"]), title,
            [NSString stringWithFormat:@"从搜索页移除「%@」标签及其内容，重启抖音后生效。", title]));
        DKSettingsOnChange(row, ^{ weakEntry.detail = DKSearchRankDetail(); });
        [rows addObject:row];
    }
    NSString *note = rows.count
        ? @"打开搜索页时自动收录榜单，新榜单会继续补入；同城类型统一显示为「同城榜」。勾选后重启抖音生效，全部移除时收起榜单区域。"
        : @"尚未收录榜单：先打开一次抖音搜索页，再返回这里选择。";
    DKSettingsPushNotedSections(presenter, @"移除搜索榜单", note,
                               @[ DKSettingsMakeSection(@"移除榜单", nil, rows) ]);
}

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
            @"移除搜索页整块榜单区域，包括全部榜单标签、榜单内容与查看完整榜单按钮。开启时下方两项灰显，原选择保留。重启抖音后生效。"));
    });
    DKSettingsRegister(DKKeySearchRanks, ^{
        AWESettingItemModel *item = DKMakeAction(DKKeySearchRanks, @"移除搜索榜单", DKSearchRankDetail(),
            ^(AWESettingItemModel *it, UIViewController *presenter) {
                DKSearchOpenRanks(it, presenter);
            });
        DKSettingsWithValues(item, @[ [DKSettingsValue idSetWithPrefix:DKKeySearchRankHidePrefix] ],
            ^NSString *(NSArray *values, BOOL brief) {
                NSArray *ids = values.firstObject;
                if (!ids.count) return @"未移除";
                if (brief) return [NSString stringWithFormat:@"已移除 %lu 项", (unsigned long)ids.count];
                NSMutableDictionary *titles = [NSMutableDictionary dictionary];
                for (NSDictionary *entry in DKSearchRankCatalog()) titles[entry[@"id"]] = entry[@"title"];
                NSMutableArray *names = [NSMutableArray array];
                for (NSString *rankID in ids) [names addObject:titles[rankID] ?: rankID];
                return [names componentsJoinedByString:@"、"];
            });
        return DKSettingsNeedsRestart(DKSettingsWithInfo(item,
            @"自动收录搜索页出现的榜单，逐个选择移除；同城类型统一命名为「同城榜」。重启抖音后生效。"));
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
