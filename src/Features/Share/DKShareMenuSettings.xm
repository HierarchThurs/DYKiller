// 分享面板精简：动态目录中的每个功能按钮独立移除，选择进入配置备份。
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKShareMenu.h"

static void DKOpenShareMenuPage(UIViewController *presenter) {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *entry in DKShareMenuCatalog()) {
        NSString *itemID = entry[@"id"];
        NSString *title = entry[@"title"] ?: itemID;
        NSString *info = [NSString stringWithFormat:@"开启后从视频与图文的分享面板移除「%@」，下次打开面板时生效。", title];
        [rows addObject:DKMakeSwitch(DKShareMenuHideKey(itemID), title, info)];
    }
    NSString *note = rows.count
        ? @"列出打开过的作品分享面板中出现的功能按钮，新按钮自动补入。勾选后下次打开面板生效；全部移除时收起功能行，联系人保留。"
        : @"尚未收录按钮：先打开一次视频或图文的分享面板，再回到这里勾选要移除的按钮。";
    DKSettingsPushNotedSections(presenter, @"分享面板精简", note,
                               @[ DKSettingsMakeSection(@"移除按钮", nil, rows) ]);
}

%ctor {
    DKSettingsRegister(DKKeyShareMenu, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeAction(DKKeyShareMenu, @"分享面板精简", nil,
            ^(__unused AWESettingItemModel *it, UIViewController *presenter) {
                DKOpenShareMenuPage(presenter);
            });
        return DKSettingsWithValues(item, @[ [DKSettingsValue idSetWithPrefix:DKKeyShareMenuHidePrefix] ],
            ^NSString *(NSArray *values, BOOL brief) {
                NSArray *itemIDs = [values.firstObject isKindOfClass:NSArray.class] ? values.firstObject : @[];
                if (!itemIDs.count) return @"未移除";
                if (brief) return [NSString stringWithFormat:@"已移除 %lu 项", (unsigned long)itemIDs.count];
                NSMutableDictionary *titles = [NSMutableDictionary dictionary];
                for (NSDictionary *entry in DKShareMenuCatalog()) titles[entry[@"id"]] = entry[@"title"];
                NSMutableArray *names = [NSMutableArray array];
                for (NSString *itemID in itemIDs) [names addObject:titles[itemID] ?: itemID];
                return [@"移除 " stringByAppendingString:[names componentsJoinedByString:@"、"]];
            });
    });
}
