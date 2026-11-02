// 播放页动态目录：区域统一档位、按分组展示的已收录类型，以及自定义名称。
#import "DKPlaybackCatalog.h"
#import "DKPlaybackClean.h"
#import "DKKeys.h"
#import "DKSettings.h"

static NSArray<NSString *> *DKCatalogOptions(void) { return @[ @"显示", @"隐藏", @"移除" ]; }

static NSString *DKCatalogPageTitle(DKPlaybackCatalogKind kind) {
    return kind == DKPlaybackCatalogAnchors ? @"昵称上方标签" : @"底部相关栏目";
}

static NSString *DKCatalogMasterTitle(DKPlaybackCatalogKind kind) {
    return kind == DKPlaybackCatalogAnchors ? @"全部昵称上方标签" : @"全部底栏相关";
}

static NSString *DKCatalogRowInfo(void) {
    return @"显示：按抖音原样显示；隐藏：保留位置与点击；移除：取消点击并收起占位。";
}

static void DKCatalogSetIcon(AWESettingItemModel *item, NSString *icon) {
    if (item && icon.length) item.svgIconImageName = icon;
}

/// 分区标题为空的分组（底部相关栏目）沿用原来的「已收录类型」标题。
static NSString *DKCatalogSectionTitle(NSDictionary *group) {
    NSString *title = [group[@"title"] isKindOfClass:NSString.class] ? group[@"title"] : @"";
    return title.length ? title : @"已收录类型";
}

static NSArray<NSDictionary *> *DKCatalogEntriesInGroup(DKPlaybackCatalogKind kind, NSUInteger group) {
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    for (NSDictionary *entry in DKPlaybackCatalogEntries(kind)) {
        if (DKPlaybackCatalogGroupOf(entry) == group) [rows addObject:entry];
    }
    return rows;
}

// 区域专属的统一项，排在统一档位之后。
static NSArray<AWESettingItemModel *> *DKCatalogExtraMasterItems(DKPlaybackCatalogKind kind) {
    if (kind != DKPlaybackCatalogBottomBars) return @[];
    AWESettingItemModel *transparent = DKMakeSwitch(DKKeyPlaybackBottomBarTransparent, @"底部相关背景透明",
        @"去掉相关搜索、合集、热点等全部底部相关栏目的背景和内部底色，只保留文字与图标；点击区域不变。");
    DKCatalogSetIcon(transparent, @"ic_rectangleonrectangleup_outlined_20");
    DKSettingsOnChange(transparent, ^{ DKPlaybackCleanRefresh(); });
    return @[ transparent ];
}

static NSString *DKCatalogDescription(DKPlaybackCatalogKind kind, NSArray *values, BOOL brief) {
    NSInteger master = values[0] == NSNull.null ? 0 : [values[0] integerValue];
    NSString *head = [NSString stringWithFormat:@"全部%@", DKCatalogOptions()[MIN(2, MAX(0, master))]];
    NSMutableArray *parts = [NSMutableArray arrayWithObject:head];
    NSUInteger changed = 0;
    for (NSDictionary *entry in DKPlaybackCatalogEntries(kind)) {
        NSString *identifier = entry[@"id"];
        NSInteger mode = DKPlaybackCatalogItemMode(kind, identifier);
        if (mode != 0) changed++;
        [parts addObject:[NSString stringWithFormat:@"%@：%@", DKPlaybackCatalogTitle(kind, entry) ?: identifier,
            DKCatalogOptions()[MIN(2, MAX(0, mode))]]];
    }
    if (kind == DKPlaybackCatalogBottomBars && [values[3] isKindOfClass:NSNumber.class] && [values[3] boolValue]) {
        [parts addObject:@"背景透明"];
    }
    NSDictionary *names = values[2];
    if ([names isKindOfClass:NSDictionary.class] && names.count) {
        NSUInteger renamed = 0;
        for (NSString *identifier in names) {
            if (DKPlaybackCatalogCustomName(kind, identifier)) renamed++;
        }
        if (renamed) [parts addObject:[NSString stringWithFormat:@"改名 %lu 项", (unsigned long)renamed]];
    }
    return brief ? [head stringByAppendingFormat:@" · 独立调整 %lu 项", (unsigned long)changed]
        : [parts componentsJoinedByString:@"、"];
}

// 重命名页：与主页面同分区、同图标，一项一个输入框，留空即恢复首次原文。
static void DKCatalogOpenRename(DKPlaybackCatalogKind kind, UIViewController *presenter) {
    NSMutableArray<AWESettingSectionModel *> *sections = [NSMutableArray array];
    for (NSDictionary *group in DKPlaybackCatalogGroups(kind)) {
        NSArray<NSDictionary *> *entries = DKCatalogEntriesInGroup(kind, DKPlaybackCatalogGroupOf(group));
        if (!entries.count) continue;
        NSMutableArray<AWESettingItemModel *> *rows = [NSMutableArray arrayWithCapacity:entries.count];
        for (NSDictionary *entry in entries) {
            NSString *identifier = entry[@"id"];
            NSString *raw = entry[@"raw"];
            NSString *key = DKPlaybackCatalogNameKey(kind, identifier);
            NSString *placeholder = raw.length ? raw : (DKPlaybackCatalogTitle(kind, entry) ?: identifier);
            AWESettingItemModel *row = DKMakeTextInputWithPrompt(key, DKPlaybackCatalogTitle(kind, entry) ?: placeholder,
                placeholder, 24, @"留空后恢复抖音默认名称。", @"默认", @"恢复默认");
            DKCatalogSetIcon(row, group[@"icon"]);
            [rows addObject:row];
        }
        [sections addObject:DKSettingsMakeSection(DKCatalogSectionTitle(group), nil, rows)];
    }
    if (!sections.count) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"尚未收录类型"
                                                                       message:@"先浏览带有这类入口的作品，再回来命名。"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
        [presenter presentViewController:alert animated:YES completion:nil];
        return;
    }
    DKSettingsPushNotedSections(presenter, @"重命名已收录类型",
        @"这里只改显示名称，不影响显示 / 隐藏 / 移除的档位；名称会跟随备份恢复。", sections);
}

static void DKCatalogOpen(DKPlaybackCatalogKind kind, UIViewController *presenter) {
    AWESettingItemModel *master = DKMakeChoice(DKPlaybackCatalogMasterKey(kind), DKCatalogMasterTitle(kind), DKCatalogOptions());
    DKSettingsWithInfo(master, @"显示：由下方各项独立配置；隐藏或移除：统一处理下面所有分区，暂停收录，保留各项原选择。");
    DKCatalogSetIcon(master, @"ic_eyeslash_outlined_20");
    DKSettingsOnChange(master, ^{ DKPlaybackCleanRefresh(); });

    NSMutableArray<AWESettingSectionModel *> *sections = [NSMutableArray array];
    NSArray *masterItems = [@[ master ] arrayByAddingObjectsFromArray:DKCatalogExtraMasterItems(kind)];
    [sections addObject:DKSettingsMakeSection(@"统一设置", nil, masterItems)];
    NSUInteger total = 0;
    for (NSDictionary *group in DKPlaybackCatalogGroups(kind)) {
        NSArray<NSDictionary *> *entries = DKCatalogEntriesInGroup(kind, DKPlaybackCatalogGroupOf(group));
        if (!entries.count) continue;
        NSMutableArray<AWESettingItemModel *> *rows = [NSMutableArray arrayWithCapacity:entries.count];
        for (NSDictionary *entry in entries) {
            NSString *identifier = entry[@"id"];
            AWESettingItemModel *row = DKMakeChoice(DKPlaybackCatalogModeKey(kind, identifier),
                DKPlaybackCatalogTitle(kind, entry) ?: identifier, DKCatalogOptions());
            DKSettingsWithInfo(row, DKCatalogRowInfo());
            DKCatalogSetIcon(row, group[@"icon"]);
            DKSettingsOnChange(row, ^{ DKPlaybackCleanRefresh(); });
            [rows addObject:row];
        }
        total += rows.count;
        [sections addObject:DKSettingsMakeSection(DKCatalogSectionTitle(group), nil, rows)];
    }
    if (total) {
        NSString *renameKey = DKPlaybackCatalogRenamePageKey(kind);
        AWESettingItemModel *rename = DKMakeAction(renameKey, @"重命名已收录类型", nil,
            ^(__unused AWESettingItemModel *item, UIViewController *presenter) {
                DKCatalogOpenRename(kind, presenter);
            });
        DKSettingsWithInfo(rename, @"给不直观的类型起一个自己看得懂的名字，例如把「视频｜xxx的付费视频」改成「付费视频锚点」。");
        DKCatalogSetIcon(rename, @"ic_pensketch_outlined_20");
        [sections addObject:DKSettingsMakeSection(@"名称", nil, @[ rename ])];
    }
    NSString *note = @"浏览作品时自动收录遇到的类型；未遇到的类型不会出现在列表中。"
        @"顶部选择隐藏或移除时，下面所有分区一起生效并暂停收录，恢复显示后按各项原选择处理。";
    if (!total) note = [@"尚未收录类型，先浏览带有此类入口的作品，再回到这里配置。\n" stringByAppendingString:note];
    DKSettingsPushNotedSections(presenter, DKCatalogPageTitle(kind), note, sections);
}

static void DKCatalogRegister(DKPlaybackCatalogKind kind, NSString *pageKey) {
    DKSettingsRegister(pageKey, ^{
        AWESettingItemModel *item = DKMakeAction(pageKey, DKCatalogPageTitle(kind), nil,
            ^(__unused AWESettingItemModel *row, UIViewController *presenter) { DKCatalogOpen(kind, presenter); });
        NSMutableArray *values = [NSMutableArray arrayWithObjects:
            [DKSettingsValue integerWithKey:DKPlaybackCatalogMasterKey(kind) minimum:0 maximum:2],
            [DKSettingsValue integerMapWithPrefix:DKPlaybackCatalogModePrefix(kind) minimum:0 maximum:2],
            [DKSettingsValue stringMapWithPrefix:DKPlaybackCatalogNamePrefix(kind) maxWidth:24], nil];
        if (kind == DKPlaybackCatalogBottomBars) [values addObject:[DKSettingsValue boolWithKey:DKKeyPlaybackBottomBarTransparent]];
        for (NSString *key in DKPlaybackCatalogLegacyKeys(kind)) {
            [values addObject:[DKSettingsValue integerWithKey:key minimum:0 maximum:2]];
        }
        DKSettingsWithValues(item, values, ^NSString *(NSArray *stored, BOOL brief) {
            return DKCatalogDescription(kind, stored, brief);
        });
        return DKSettingsOnChange(item, ^{ DKPlaybackCleanRefresh(); });
    });
}

%ctor {
    DKCatalogRegister(DKPlaybackCatalogAnchors, DKPlaybackCatalogPageKey(DKPlaybackCatalogAnchors));
    DKCatalogRegister(DKPlaybackCatalogBottomBars, DKPlaybackCatalogPageKey(DKPlaybackCatalogBottomBars));
}
