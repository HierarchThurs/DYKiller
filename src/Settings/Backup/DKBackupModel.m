//
//  DKBackupModel.m
//

#import "DKBackupModel.h"

static NSString *const kDKUnknownSettingReason = @"当前版本没有此设置";
static NSString *const kDKGlassReason = @"需 iOS 26+";

// 没有自定义文案的项按值的种类给出默认文案。
static NSString *DKDefaultText(DKSettingsValue *value, id normalized, BOOL brief) {
    switch (value.kind) {
        case DKSettingsValueKindBool:
            return [normalized isKindOfClass:NSNumber.class] && [normalized boolValue] ? @"开" : @"关";
        case DKSettingsValueKindInteger:
            return [normalized isKindOfClass:NSNumber.class] ? [normalized stringValue] : @"未设置";
        case DKSettingsValueKindIDSet: {
            NSArray *ids = [normalized isKindOfClass:NSArray.class] ? normalized : @[];
            if (ids.count == 0) return @"未选择";
            return brief ? [NSString stringWithFormat:@"已选 %lu 项", (unsigned long)ids.count]
                         : [ids componentsJoinedByString:@"、"];
        }
        case DKSettingsValueKindImage:
            return [normalized isKindOfClass:NSData.class] ? @"已自定义" : @"默认";
        case DKSettingsValueKindString:
            return [normalized isKindOfClass:NSString.class] ? normalized : @"默认";
    }
    return @"";
}

@implementation DKBackupEntry {
    DKSettingsDescribe _describe;
    dispatch_block_t _onChange;
}

- (instancetype)initWithIdentifier:(NSString *)identifier title:(NSString *)title group:(NSString *)group
                              icon:(NSString *)icon values:(NSArray<DKSettingsValue *> *)values
                          describe:(DKSettingsDescribe)describe onChange:(dispatch_block_t)onChange
                      needsRestart:(BOOL)needsRestart gated:(BOOL)gated {
    if ((self = [super init])) {
        _identifier = [identifier copy];
        _title = [title copy];
        _group = [group copy];
        _icon = [icon copy];
        _values = [values copy];
        _describe = [describe copy];
        _onChange = [onChange copy];
        _needsRestart = needsRestart;
        _gated = gated;
    }
    return self;
}

- (NSString *)describe:(NSArray *)values brief:(BOOL)brief {
    if (_describe) return _describe(values, brief);
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:values.count];
    [self.values enumerateObjectsUsingBlock:^(DKSettingsValue *value, NSUInteger index, __unused BOOL *stop) {
        [parts addObject:DKDefaultText(value, index < values.count ? values[index] : NSNull.null, brief)];
    }];
    return [parts componentsJoinedByString:@" / "];
}

- (void)runOnChange {
    if (_onChange) _onChange();
}

@end

@implementation DKBackupDocument

- (instancetype)init {
    if ((self = [super init])) {
        _source = @{};
        _settings = @{};
        _sets = @{};
        _files = @{};
        _fileErrors = @{};
    }
    return self;
}

@end

@implementation DKBackupChange

- (instancetype)initWithEntry:(DKBackupEntry *)entry oldValues:(NSArray *)oldValues values:(NSArray *)values {
    if ((self = [super init])) {
        _entry = entry;
        _oldValues = [oldValues copy];
        _values = [values copy];
        _oldText = [entry describe:oldValues brief:NO];
        _text = [entry describe:values brief:NO];
        _briefText = [entry describe:values brief:YES];
        _visible = ![_oldText isEqualToString:_text];
    }
    return self;
}

@end

@implementation DKBackupSkip

- (instancetype)initWithTitle:(NSString *)title reason:(NSString *)reason icon:(NSString *)icon {
    if ((self = [super init])) {
        _title = [title copy];
        _reason = [reason copy];
        _icon = [icon copy];
    }
    return self;
}

@end

@implementation DKBackupPlan

- (instancetype)initWithChanges:(NSArray<DKBackupChange *> *)changes skips:(NSArray<DKBackupSkip *> *)skips {
    if ((self = [super init])) {
        _changes = [changes copy];
        _skips = [skips copy];
        _unwrittenTitles = @[];
        NSMutableArray<DKBackupChange *> *visible = [NSMutableArray array];
        NSMutableArray<NSString *> *restart = [NSMutableArray array];
        for (DKBackupChange *change in changes) {
            if (!change.visible) continue;
            [visible addObject:change];
            if (change.entry.needsRestart) [restart addObject:change.entry.title];
            [change.entry.values enumerateObjectsUsingBlock:^(DKSettingsValue *value, NSUInteger index, __unused BOOL *stop) {
                if (value.kind != DKSettingsValueKindImage || [change.oldValues[index] isEqual:change.values[index]]) return;
                if ([change.values[index] isKindOfClass:NSData.class]) self->_replacedImages++;
                else self->_clearedImages++;
            }];
        }
        _visibleChanges = [visible copy];
        _restartTitles = [restart copy];
    }
    return self;
}

@end

#pragma mark - 计划

// 文档里该值所在的节；值没出现时返回 NO。
static BOOL DKDocumentRawValue(DKBackupDocument *document, DKSettingsValue *value, id *raw) {
    NSDictionary *section = nil;
    switch (value.kind) {
        case DKSettingsValueKindBool:
        case DKSettingsValueKindInteger:
        case DKSettingsValueKindString: section = document.settings; break;
        case DKSettingsValueKindIDSet: section = document.sets; break;
        case DKSettingsValueKindImage:
            section = document.files;
            if (document.fileErrors[value.key]) {
                *raw = nil;
                return YES;
            }
            break;
    }
    id found = section[value.key];
    if (!found) return NO;
    *raw = found;
    return YES;
}

static NSArray<DKBackupSkip *> *DKUnknownSkips(NSDictionary *section, NSSet<NSString *> *claimed) {
    NSMutableArray<DKBackupSkip *> *skips = [NSMutableArray array];
    for (NSString *key in [section.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if ([claimed containsObject:key]) continue;
        [skips addObject:[[DKBackupSkip alloc] initWithTitle:key reason:kDKUnknownSettingReason icon:nil]];
    }
    return skips;
}

DKBackupPlan *DKBackupMakePlan(DKBackupDocument *document, NSArray<DKBackupEntry *> *entries,
                               id<DKSettingsStore> store, BOOL glassAvailable) {
    NSMutableArray<DKBackupChange *> *changes = [NSMutableArray array];
    NSMutableArray<DKBackupSkip *> *skips = [NSMutableArray array];
    NSMutableSet<NSString *> *claimedSettings = [NSMutableSet set];
    NSMutableSet<NSString *> *claimedSets = [NSMutableSet set];
    NSMutableSet<NSString *> *claimedFiles = [NSMutableSet set];

    for (DKBackupEntry *entry in entries) {
        NSMutableArray *oldValues = [NSMutableArray arrayWithCapacity:entry.values.count];
        NSMutableArray *newValues = [NSMutableArray arrayWithCapacity:entry.values.count];
        BOOL present = NO;
        NSString *failure = nil;

        for (DKSettingsValue *value in entry.values) {
            switch (value.kind) {
                case DKSettingsValueKindBool:
                case DKSettingsValueKindInteger:
                case DKSettingsValueKindString: [claimedSettings addObject:value.key]; break;
                case DKSettingsValueKindIDSet: [claimedSets addObject:value.key]; break;
                case DKSettingsValueKindImage: [claimedFiles addObject:value.key]; break;
            }
            id current = [value currentValueInStore:store];
            [oldValues addObject:current];

            id raw = nil;
            if (!DKDocumentRawValue(document, value, &raw)) {
                [newValues addObject:current];
                continue;
            }
            present = YES;
            NSString *reason = document.fileErrors[value.key];
            id normalized = reason ? nil : [value normalize:raw reason:&reason];
            if (!normalized) failure = failure ?: reason;
            [newValues addObject:normalized ?: current];
        }

        if (!present) continue;
        if (failure) {
            [skips addObject:[[DKBackupSkip alloc] initWithTitle:entry.title reason:failure icon:entry.icon]];
            continue;
        }
        if ([oldValues isEqualToArray:newValues]) continue;
        if (entry.gated && !glassAvailable) {
            [skips addObject:[[DKBackupSkip alloc] initWithTitle:entry.title reason:kDKGlassReason icon:entry.icon]];
            continue;
        }
        [changes addObject:[[DKBackupChange alloc] initWithEntry:entry oldValues:oldValues values:newValues]];
    }

    [skips addObjectsFromArray:DKUnknownSkips(document.settings, claimedSettings)];
    [skips addObjectsFromArray:DKUnknownSkips(document.sets, claimedSets)];
    [skips addObjectsFromArray:DKUnknownSkips(document.files, claimedFiles)];
    [skips addObjectsFromArray:DKUnknownSkips(document.fileErrors, claimedFiles)];
    return [[DKBackupPlan alloc] initWithChanges:changes skips:skips];
}
