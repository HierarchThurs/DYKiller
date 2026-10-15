//
//  DKBackupStore.m
//

#import "DKBackupStore.h"
#include <stdio.h>

static NSString *const kDKSnapshotName = @"undo.dykbackup";
static NSString *const kDKPendingName = @"undo.pending";
static NSString *const kDKStagingSuffix = @".restore";

// 一张需要换上或清除的图片。
@interface DKBackupImageWrite : NSObject
@property (nonatomic, strong) DKSettingsValue *setting;
@property (nonatomic, strong) id previousData;   // NSData / NSNull
@property (nonatomic, strong) id targetData;   // NSData / NSNull
@property (nonatomic, copy) NSString *stagingPath;
@end

@implementation DKBackupImageWrite
@end

static BOOL DKRename(NSString *from, NSString *to) {
    return rename(from.fileSystemRepresentation, to.fileSystemRepresentation) == 0;
}

static BOOL DKRemoveIfExists(NSString *path) {
    NSFileManager *fm = NSFileManager.defaultManager;
    return ![fm fileExistsAtPath:path] || [fm removeItemAtPath:path error:NULL];
}

// 把一张图片恢复成 data 表示的状态；NSNull 表示删除。
static BOOL DKWriteImageState(NSString *path, id data) {
    if (![data isKindOfClass:NSData.class]) return DKRemoveIfExists(path);
    NSString *directory = path.stringByDeletingLastPathComponent;
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    return [data writeToFile:path options:NSDataWritingAtomic error:NULL];
}

@implementation DKBackupStore {
    NSString *_directory;
    id<DKSettingsStore> _store;
    NSDictionary<NSString *, NSString *> *_source;
    BOOL _glassAvailable;
}

- (instancetype)initWithDirectory:(NSString *)directory store:(id<DKSettingsStore>)store
                           source:(NSDictionary<NSString *, NSString *> *)source glassAvailable:(BOOL)glassAvailable {
    if ((self = [super init])) {
        _directory = [directory copy];
        _store = store;
        _source = [source copy];
        _glassAvailable = glassAvailable;
    }
    return self;
}

- (NSString *)snapshotPath {
    return [_directory stringByAppendingPathComponent:kDKSnapshotName];
}

- (NSString *)pendingPath {
    return [_directory stringByAppendingPathComponent:kDKPendingName];
}

// 上次提交中断留下的待定快照比快照新，两者都在时以它为准。
- (NSDate *)snapshotDate {
    NSFileManager *fm = NSFileManager.defaultManager;
    return [fm attributesOfItemAtPath:self.pendingPath error:NULL].fileModificationDate
        ?: [fm attributesOfItemAtPath:self.snapshotPath error:NULL].fileModificationDate;
}

- (DKBackupDocument *)loadSnapshot:(NSError **)error {
    if ([NSFileManager.defaultManager fileExistsAtPath:self.pendingPath]) DKRename(self.pendingPath, self.snapshotPath);
    NSData *data = DKBackupReadFile(self.snapshotPath, error);
    return data ? DKBackupDecode(data, error) : nil;
}

#pragma mark - 提交

- (DKBackupPlan *)commitDocument:(DKBackupDocument *)document entries:(NSArray<DKBackupEntry *> *)entries
                            mode:(DKBackupMode)mode error:(NSError **)error {
    DKBackupPlan *plan = DKBackupMakePlan(document, entries, _store, _glassAvailable);
    if (plan.changes.count == 0) {
        if (mode == DKBackupModeUndo) DKRemoveIfExists(self.snapshotPath);
        return plan;
    }

    // 只有文案相同的存值差异时不拍快照：撤销回去看不出区别。
    BOOL snapshot = mode != DKBackupModeUndo && plan.visibleChanges.count > 0;
    if (snapshot && ![self writePendingSnapshot:entries error:error]) return nil;

    NSArray<DKBackupImageWrite *> *images = [self imageWritesInPlan:plan];
    if (![self applyImages:images]) {
        DKRemoveIfExists(self.pendingPath);
        if (error) *error = DKBackupMakeError(DKBackupErrorWriteFailed, @"无法写入自定义图片，设置未改动");
        return nil;
    }

    [self writeValuesInPlan:plan];
    plan.unwrittenTitles = [self unwrittenTitlesInPlan:plan];

    if (mode == DKBackupModeUndo) DKRemoveIfExists(self.snapshotPath);
    else if (snapshot) DKRename(self.pendingPath, self.snapshotPath);

    for (DKBackupChange *change in plan.changes) [change.entry runOnChange];
    return plan;
}

- (BOOL)writePendingSnapshot:(NSArray<DKBackupEntry *> *)entries error:(NSError **)error {
    NSData *snapshot = DKBackupEncode(entries, _store, _source, NSDate.date, _glassAvailable, error);
    if (!snapshot) return NO;
    [NSFileManager.defaultManager createDirectoryAtPath:_directory withIntermediateDirectories:YES attributes:nil error:NULL];
    if ([snapshot writeToFile:self.pendingPath options:NSDataWritingAtomic error:NULL]) return YES;
    if (error) *error = DKBackupMakeError(DKBackupErrorWriteFailed, @"无法保存恢复前的快照，设置未改动");
    return NO;
}

- (NSArray<DKBackupImageWrite *> *)imageWritesInPlan:(DKBackupPlan *)plan {
    NSMutableArray<DKBackupImageWrite *> *writes = [NSMutableArray array];
    for (DKBackupChange *change in plan.changes) {
        [change.entry.values enumerateObjectsUsingBlock:^(DKSettingsValue *value, NSUInteger index, __unused BOOL *stop) {
            if (value.kind != DKSettingsValueKindImage || [change.oldValues[index] isEqual:change.values[index]]) return;
            DKBackupImageWrite *write = [[DKBackupImageWrite alloc] init];
            write.setting = value;
            write.previousData = change.oldValues[index];
            write.targetData = change.values[index];
            write.stagingPath = [value.path stringByAppendingString:kDKStagingSuffix];
            [writes addObject:write];
        }];
    }
    return writes;
}

// 先把新图片全部写成同目录的临时文件，再逐个原子换上；中途失败时把已换上的还原。
- (BOOL)applyImages:(NSArray<DKBackupImageWrite *> *)writes {
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL staged = YES;
    for (DKBackupImageWrite *write in writes) {
        if (![write.targetData isKindOfClass:NSData.class]) continue;
        [fm createDirectoryAtPath:write.setting.path.stringByDeletingLastPathComponent
      withIntermediateDirectories:YES attributes:nil error:NULL];
        if (![write.targetData writeToFile:write.stagingPath options:0 error:NULL]) {
            staged = NO;
            break;
        }
    }

    NSMutableArray<DKBackupImageWrite *> *applied = [NSMutableArray array];
    BOOL ok = staged;
    for (DKBackupImageWrite *write in writes) {
        if (!ok) break;
        ok = [write.targetData isKindOfClass:NSData.class] ? DKRename(write.stagingPath, write.setting.path)
                                                       : DKRemoveIfExists(write.setting.path);
        if (ok) [applied addObject:write];
    }
    if (!ok) {
        for (DKBackupImageWrite *write in applied) DKWriteImageState(write.setting.path, write.previousData);
    }
    for (DKBackupImageWrite *write in writes) DKRemoveIfExists(write.stagingPath);
    return ok;
}

- (void)writeValuesInPlan:(DKBackupPlan *)plan {
    for (DKBackupChange *change in plan.changes) {
        [change.entry.values enumerateObjectsUsingBlock:^(DKSettingsValue *value, NSUInteger index, __unused BOOL *stop) {
            if (value.kind == DKSettingsValueKindImage || [change.oldValues[index] isEqual:change.values[index]]) return;
            [value writeValue:change.values[index] toStore:self->_store];
        }];
    }
}

- (NSArray<NSString *> *)unwrittenTitlesInPlan:(DKBackupPlan *)plan {
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (DKBackupChange *change in plan.changes) {
        __block BOOL written = YES;
        [change.entry.values enumerateObjectsUsingBlock:^(DKSettingsValue *value, NSUInteger index, BOOL *stop) {
            if ([[value currentValueInStore:self->_store] isEqual:change.values[index]]) return;
            written = NO;
            *stop = YES;
        }];
        if (!written) [titles addObject:change.entry.title];
    }
    return titles;
}

@end
