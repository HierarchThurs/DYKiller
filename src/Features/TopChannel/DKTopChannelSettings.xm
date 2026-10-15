//
//  DKTopChannelSettings.xm
//  功能：顶部频道 —— 设置主页入口，以及按扫描目录逐个勾选的子页面。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKTopChannels.h"

static NSString *DKTopChannelEntryDetail(void) {
    NSInteger count = DKTopChannelHiddenCount();
    return count ? [NSString stringWithFormat:@"已移除 %ld 个", (long)count] : @"未移除";
}

static NSString *DKTopChannelString(NSDictionary *entry, NSString *field) {
    id value = entry[field];
    return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}

// 频道行的 ⓘ 说明；顶栏文案与频道名不同时（如同城显示为城市名）一并给出频道名。
static NSString *DKTopChannelRowInfo(NSDictionary *entry, NSString *title) {
    if ([entry[DKTopChannelFieldLocked] boolValue]) return [NSString stringWithFormat:@"「%@」是首页主频道，不可移除。", title];
    NSString *name = DKTopChannelString(entry, DKTopChannelFieldName);
    NSString *label = name && ![name isEqualToString:title] ? [NSString stringWithFormat:@"「%@」（%@）", title, name]
                                                           : [NSString stringWithFormat:@"「%@」", title];
    NSString *absent = [entry[DKTopChannelFieldPresent] boolValue] ? @"" : @"该频道最近一次扫描时未出现。";
    return [NSString stringWithFormat:@"开启后从首页顶栏移除%@频道，重启抖音后生效。%@", label, absent];
}

static AWESettingItemModel *DKTopChannelRow(NSDictionary *entry, AWESettingItemModel *entryItem) {
    NSString *channelID = entry[DKTopChannelFieldID];
    NSString *title = DKTopChannelString(entry, DKTopChannelFieldTitle)
        ?: DKTopChannelString(entry, DKTopChannelFieldName) ?: channelID;
    AWESettingItemModel *item = DKMakeSwitch(DKTopChannelHideKey(channelID), title, DKTopChannelRowInfo(entry, title));

    if ([entry[DKTopChannelFieldLocked] boolValue]) {
        item.isEnable = NO;
        item.isSwitchOn = NO;
        __weak AWESettingItemModel *weakItem = item;
        item.switchChangedBlock = ^{
            weakItem.isSwitchOn = NO;
        };
        return item;
    }

    // 勾选后同步主页入口的计数，返回主页时随页面刷新显示。
    __weak AWESettingItemModel *weakEntry = entryItem;
    void (^original)(void) = item.switchChangedBlock;
    item.switchChangedBlock = ^{
        if (original) original();
        weakEntry.detail = DKTopChannelEntryDetail();
    };
    return item;
}

// 按目录里的顶栏文案列出频道；目录里没有的 ID 原样列出。
static NSString *DKTopChannelNames(NSArray<NSString *> *channelIDs) {
    NSMutableDictionary<NSString *, NSString *> *titles = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in DKTopChannelCatalog()) {
        NSString *title = DKTopChannelString(entry, DKTopChannelFieldTitle) ?: DKTopChannelString(entry, DKTopChannelFieldName);
        if (title) titles[entry[DKTopChannelFieldID]] = title;
    }
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:channelIDs.count];
    for (NSString *channelID in channelIDs) [names addObject:titles[channelID] ?: channelID];
    return [names componentsJoinedByString:@"、"];
}

static void DKTopChannelOpen(AWESettingItemModel *entryItem, UIViewController *presenter) {
    NSArray<NSDictionary *> *catalog = DKTopChannelCatalog();
    if (catalog.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"尚未扫描到顶部频道"
                                                                       message:@"打开首页后再进入。"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
        [presenter presentViewController:alert animated:YES completion:nil];
        return;
    }

    NSMutableArray<AWESettingItemModel *> *rows = [NSMutableArray arrayWithCapacity:catalog.count];
    for (NSDictionary *entry in catalog) [rows addObject:DKTopChannelRow(entry, entryItem)];
    DKSettingsPushPage(presenter, @"移除顶部频道", @"勾选后重启抖音生效", rows);
}

#pragma mark - 设置项注册

%ctor {
    DKSettingsRegister(DKKeyTopChannels, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeAction(DKKeyTopChannels, @"移除顶部频道", DKTopChannelEntryDetail(),
                                                 ^(AWESettingItemModel *it, UIViewController *presenter) {
            DKTopChannelOpen(it, presenter);
        });
        DKSettingsWithValues(item, @[ [DKSettingsValue idSetWithPrefix:DKKeyTopChannelHidePrefix] ],
            ^NSString *(NSArray *values, BOOL brief) {
                NSArray<NSString *> *channelIDs = values[0];
                if (channelIDs.count == 0) return @"未移除";
                return brief ? [NSString stringWithFormat:@"已移除 %lu 个", (unsigned long)channelIDs.count]
                             : DKTopChannelNames(channelIDs);
            });
        return DKSettingsNeedsRestart(DKSettingsWithInfo(item,
            @"逐个选择要从首页顶栏移除的频道，重启抖音后生效；「推荐」不可移除。需先打开过首页，才能扫描到频道列表。"));
    });
}
