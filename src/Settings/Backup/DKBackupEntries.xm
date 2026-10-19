//
//  DKBackupEntries.xm
//

#import "DKBackupEntries.h"
#import "DKBackupModel.h"
#import "DKSettingsInternal.h"
#import "DKSettingsLayout.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"

static NSString *const kDKUnplacedGroup = @"未归类";

static NSDictionary *gDKLastOperation = nil;

// 同一节里的值键必须唯一：Bool 与 Integer 同在 settings，IDSet 在 sets，Image 在 files。
static NSString *DKValueSlot(DKSettingsValue *value) {
    switch (value.kind) {
        case DKSettingsValueKindBool:
        case DKSettingsValueKindInteger:
        case DKSettingsValueKindColor:
        case DKSettingsValueKindString: return [@"settings/" stringByAppendingString:value.key];
        case DKSettingsValueKindIDSet: return [@"sets/" stringByAppendingString:value.key];
        case DKSettingsValueKindImage: return [@"files/" stringByAppendingString:value.key];
    }
    return value.key;
}

static NSArray<DKBackupEntry *> *DKCollect(NSMutableArray<NSString *> *excluded, NSMutableArray<NSString *> *undeclared,
                                           NSMutableArray<NSString *> *duplicates) {
    NSMutableArray<DKBackupEntry *> *entries = [NSMutableArray array];
    NSMutableSet<NSString *> *slots = [NSMutableSet set];
    for (NSString *key in DKSettingsRegisteredKeys()) {
        AWESettingItemModel *item = DKSettingsBuildItem(key);
        if (!item) continue;
        if ([key isEqualToString:DKKeyDebugInspectorEnabled] || DKSettingsItemExcludedFromBackup(item)) {
            [excluded addObject:key];
            continue;
        }
        NSArray<DKSettingsValue *> *values = DKSettingsItemValues(item);
        if (values.count == 0) {
            [undeclared addObject:key];
            continue;
        }
        NSMutableSet<NSString *> *itemSlots = [NSMutableSet set];
        BOOL gated = NO;
        for (DKSettingsValue *value in values) {
            [itemSlots addObject:DKValueSlot(value)];
            gated = gated || DKGlassIsGatedKey(value.key);
        }
        if (itemSlots.count != values.count || [itemSlots intersectsSet:slots]) {
            [duplicates addObject:key];
            continue;
        }
        [slots unionSet:itemSlots];
        [entries addObject:[[DKBackupEntry alloc] initWithIdentifier:key
                                                               title:item.title ?: key
                                                               group:DKSettingsLayoutPageTitle(key) ?: kDKUnplacedGroup
                                                                icon:DKSettingsLayoutIcon(key)
                                                              values:values
                                                            describe:DKSettingsItemDescribe(item)
                                                            onChange:DKSettingsItemOnChange(item)
                                                        needsRestart:DKSettingsItemNeedsRestart(item)
                                                               gated:gated]];
    }
    return entries;
}

NSArray<DKBackupEntry *> *DKBackupCollectEntries(void) {
    NSCAssert(NSThread.isMainThread, @"设置项只能在主线程建");
    NSMutableArray<NSString *> *undeclared = [NSMutableArray array];
    NSMutableArray<NSString *> *duplicates = [NSMutableArray array];
    NSArray<DKBackupEntry *> *entries = DKCollect([NSMutableArray array], undeclared, duplicates);
    if (undeclared.count || duplicates.count) {
        NSLog(@"[DYKiller] 备份：未声明落盘值的设置项 %@，值键重复的设置项 %@", undeclared, duplicates);
    }
    return entries;
}

void DKBackupRecordOperation(NSString *operation, NSString *result) {
    gDKLastOperation = @{ @"operation": operation ?: @"", @"result": result ?: @"", @"time": NSDate.date.description };
}

static NSDictionary *DKDiagnosticsOnMain(void) {
    NSMutableArray<NSString *> *excluded = [NSMutableArray array];
    NSMutableArray<NSString *> *undeclared = [NSMutableArray array];
    NSMutableArray<NSString *> *duplicates = [NSMutableArray array];
    NSArray<DKBackupEntry *> *entries = DKCollect(excluded, undeclared, duplicates);
    NSMutableArray<NSDictionary *> *declared = [NSMutableArray arrayWithCapacity:entries.count];
    for (DKBackupEntry *entry in entries) {
        NSMutableArray<NSString *> *values = [NSMutableArray array];
        for (DKSettingsValue *value in entry.values) [values addObject:value.key];
        [declared addObject:@{ @"key": entry.identifier, @"values": values,
                               @"needs_restart": @(entry.needsRestart), @"glass_gated": @(entry.gated) }];
    }
    return @{
        @"declared": declared,
        @"excluded": excluded,
        @"undeclared": undeclared,
        @"duplicate_values": duplicates,
        @"glass_available": @(DKGlassOSAvailable()),
        @"last_operation": gDKLastOperation ?: @{},
    };
}

NSDictionary *DKSettingsBackupDiagnostics(void) {
    if (NSThread.isMainThread) return DKDiagnosticsOnMain();
    __block NSDictionary *result = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{ result = DKDiagnosticsOnMain(); });
    return result;
}
