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

static NSString *DKTopChannelRowDetail(NSDictionary *entry) {
    if ([entry[DKTopChannelFieldLocked] boolValue]) return @"不可移除";
    if (![entry[DKTopChannelFieldPresent] boolValue]) return @"当前未出现";
    NSString *name = DKTopChannelString(entry, DKTopChannelFieldName);
    NSString *title = DKTopChannelString(entry, DKTopChannelFieldTitle);
    return name && title && ![name isEqualToString:title] ? name : @"";
}

static AWESettingItemModel *DKTopChannelRow(NSDictionary *entry, AWESettingItemModel *entryItem) {
    NSString *channelID = entry[DKTopChannelFieldID];
    NSString *title = DKTopChannelString(entry, DKTopChannelFieldTitle)
        ?: DKTopChannelString(entry, DKTopChannelFieldName) ?: channelID;
    AWESettingItemModel *item = DKMakeSwitch(DKTopChannelHideKey(channelID), title, DKTopChannelRowDetail(entry));

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
    DKSettingsRegisterItem(@"顶部频道", ^AWESettingItemModel *{
        return DKMakeAction(DKKeyTopChannels, @"移除顶部频道", DKTopChannelEntryDetail(),
                            ^(AWESettingItemModel *item, UIViewController *presenter) {
            DKTopChannelOpen(item, presenter);
        });
    });
}
