//
//  DKBackupDetailPage.xm
//  明细页的行用 DYKillerBackupPreview. 开头的 identifier，不与设置键重名，
//  所以不受联动锁与玻璃锁影响；行本身没有点击动作。
//

#import "DKBackupDetailPage.h"
#import "DKBackupModel.h"
#import "DKSettingsInternal.h"

static NSString *const kDKPreviewPrefix = @"DYKillerBackupPreview.";

NSString *DKBackupSourceText(DKBackupDocument *document) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSDictionary<NSString *, NSString *> *source = document.source;
    if (source[@"plugin"].length) [parts addObject:[@"DYKiller " stringByAppendingString:source[@"plugin"]]];
    if (source[@"app"].length) [parts addObject:[@"抖音 " stringByAppendingString:source[@"app"]]];
    if (source[@"system"].length) [parts addObject:[@"iOS " stringByAppendingString:source[@"system"]]];
    return parts.count ? [parts componentsJoinedByString:@" · "] : @"来源未知";
}

NSString *DKBackupTimeText(NSDate *date) {
    if (!date) return @"";
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm";
    return [formatter stringFromDate:date];
}

static AWESettingItemModel *DKDetailRow(NSString *suffix, NSString *title, NSString *detail, NSString *icon, NSString *info) {
    AWESettingItemModel *item = DKMakeAction([kDKPreviewPrefix stringByAppendingString:suffix], title, detail, nil);
    if (icon.length) item.svgIconImageName = icon;
    DKSettingsWithoutBackup(item);
    return info.length ? DKSettingsWithInfo(item, info) : item;
}

static AWESettingSectionModel *DKInfoSection(DKBackupDocument *document) {
    NSMutableArray<AWESettingItemModel *> *rows = [NSMutableArray array];
    if (document.createdAt) {
        [rows addObject:DKDetailRow(@"time", @"备份时间", DKBackupTimeText(document.createdAt), @"ic_clock_outlined_20", nil)];
    }
    NSDictionary<NSString *, NSString *> *source = document.source;
    NSString *brief = source[@"app"].length
        ? [NSString stringWithFormat:@"%@ · 抖音 %@", source[@"plugin"] ?: @"", source[@"app"]]
        : (source[@"plugin"] ?: @"");
    [rows addObject:DKDetailRow(@"source", @"来源", brief, @"ic_gearsimplify_outlined_20", DKBackupSourceText(document))];
    return DKSettingsMakeSection(@"备份信息", nil, rows);
}

// 变更按所在子页分组，组的先后取第一次出现的顺序。
static NSArray<AWESettingSectionModel *> *DKChangeSections(DKBackupPlan *plan) {
    NSMutableArray<NSString *> *groups = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<AWESettingItemModel *> *> *rows = [NSMutableDictionary dictionary];
    for (DKBackupChange *change in plan.visibleChanges) {
        NSString *group = change.entry.group;
        if (!rows[group]) {
            rows[group] = [NSMutableArray array];
            [groups addObject:group];
        }
        NSString *info = [NSString stringWithFormat:@"当前：%@\n恢复后：%@", change.oldText, change.text];
        [rows[group] addObject:DKDetailRow(change.entry.identifier, change.entry.title, change.briefText, change.entry.icon, info)];
    }
    NSMutableArray<AWESettingSectionModel *> *sections = [NSMutableArray arrayWithCapacity:groups.count];
    for (NSString *group in groups) [sections addObject:DKSettingsMakeSection(group, nil, rows[group])];
    return sections;
}

static AWESettingSectionModel *DKSkipSection(DKBackupPlan *plan) {
    NSMutableArray<AWESettingItemModel *> *rows = [NSMutableArray arrayWithCapacity:plan.skips.count];
    [plan.skips enumerateObjectsUsingBlock:^(DKBackupSkip *skip, NSUInteger index, __unused BOOL *stop) {
        NSString *suffix = [NSString stringWithFormat:@"skip.%lu", (unsigned long)index];
        [rows addObject:DKDetailRow(suffix, skip.title, skip.reason, skip.icon, nil)];
    }];
    return DKSettingsMakeSection(@"跳过", nil, rows);
}

void DKBackupShowDetail(UIViewController *presenter, DKBackupDocument *document, DKBackupPlan *plan,
                        dispatch_block_t confirm) {
    NSMutableArray<AWESettingSectionModel *> *sections = [NSMutableArray arrayWithObject:DKInfoSection(document)];
    [sections addObjectsFromArray:DKChangeSections(plan)];
    if (plan.skips.count) [sections addObject:DKSkipSection(plan)];
    if (confirm) {
        dispatch_block_t confirmCopy = [confirm copy];
        AWESettingItemModel *row = DKMakeAction([kDKPreviewPrefix stringByAppendingString:@"confirm"], @"恢复这些设置", @"",
                                                ^(__unused AWESettingItemModel *item, __unused UIViewController *page) {
            confirmCopy();
        });
        row.svgIconImageName = @"ic_circlearrowin_outlined_20";
        DKSettingsWithoutBackup(row);
        [sections addObject:DKSettingsMakeSection(@"", @"恢复前会自动保存当前配置快照，可以撤销。", @[ row ])];
    }
    DKSettingsPushSections(presenter, @"恢复明细", sections);
}
