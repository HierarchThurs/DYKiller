//
//  DKBackupSettings.xm
//  备份工具页的四行：备份到文件、从文件恢复、撤销上次恢复、恢复默认设置。
//  导出与读入走系统文件选择器；恢复先弹摘要，可进明细页；
//  恢复、撤销与恢复默认完成后统一弹结果提示，建议彻底退出并重新打开抖音，不提供重启、不强制。
//

#import "DKBackupDetailPage.h"
#import "DKBackupEntries.h"
#import "DKBackupStore.h"
#import "DKSettingsInternal.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>

static char kDKPickerRelayKey;

// 导出或读入进行中，不响应重复点击。
static BOOL gDKBackupBusy = NO;

#pragma mark - 存储

static NSString *DKBackupDirectory(void) {
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    return [[support stringByAppendingPathComponent:@"DYKiller"] stringByAppendingPathComponent:@"Backups"];
}

static NSString *DKExportDirectory(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"DYKillerBackup"];
}

static NSDictionary<NSString *, NSString *> *DKBackupSource(void) {
    id app = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return @{
        @"plugin": DK_VERSION,
        @"app": [app isKindOfClass:NSString.class] ? app : @"",
        @"system": UIDevice.currentDevice.systemVersion ?: @"",
    };
}

static DKBackupStore *DKMakeStore(void) {
    return [[DKBackupStore alloc] initWithDirectory:DKBackupDirectory() store:NSUserDefaults.standardUserDefaults
                                             source:DKBackupSource() glassAvailable:DKGlassOSAvailable()];
}

// 选择器交来的副本在本 App 的临时目录里，读完即删；不在临时目录的文件一律不动。
static void DKRemoveTemporaryCopy(NSURL *url) {
    NSString *path = url.URLByResolvingSymlinksInPath.path;
    NSString *temporary = [NSURL fileURLWithPath:NSTemporaryDirectory()].URLByResolvingSymlinksInPath.path;
    if (path.length && temporary.length && [path hasPrefix:[temporary stringByAppendingString:@"/"]]) {
        [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
    }
}

#pragma mark - 文案

static NSString *DKShortTime(NSDate *date) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"MM-dd HH:mm";
    return [formatter stringFromDate:date];
}

static NSString *DKExportDetail(void) {
    id date = [NSUserDefaults.standardUserDefaults objectForKey:DKKeyBackupLastExportDate];
    return [date isKindOfClass:NSDate.class] ? [@"上次 " stringByAppendingString:DKShortTime(date)] : @"";
}

static NSString *DKUndoDetail(NSDate *snapshot) {
    return snapshot ? DKShortTime(snapshot) : @"";
}

static NSString *DKImagesText(DKBackupPlan *plan) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (plan.replacedImages) [parts addObject:[NSString stringWithFormat:@"替换 %lu 张", (unsigned long)plan.replacedImages]];
    if (plan.clearedImages) [parts addObject:[NSString stringWithFormat:@"清除 %lu 张", (unsigned long)plan.clearedImages]];
    return parts.count ? [@"自定义图片：" stringByAppendingString:[parts componentsJoinedByString:@"、"]] : nil;
}

static NSString *DKSourceLines(DKBackupDocument *document) {
    NSString *text = [@"来自 " stringByAppendingString:DKBackupSourceText(document)];
    if (!document.createdAt) return text;
    return [NSString stringWithFormat:@"%@\n备份时间 %@", text, DKBackupTimeText(document.createdAt)];
}

#pragma mark - 弹窗

static void DKShowAlert(UIViewController *presenter, NSString *title, NSString *message) {
    if (!presenter) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

// 确认后的动作退一拍执行：接下来的弹窗不能压在这个弹窗的消失动画上。
static void DKShowConfirm(UIViewController *presenter, NSString *title, NSString *message, NSString *confirm,
                          BOOL destructive, dispatch_block_t handler) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    UIAlertActionStyle style = destructive ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault;
    [alert addAction:[UIAlertAction actionWithTitle:confirm style:style handler:^(__unused UIAlertAction *action) {
        dispatch_async(dispatch_get_main_queue(), handler);
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 文件选择器

@interface DKBackupPickerRelay : NSObject <UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate>
@property (nonatomic, copy) void (^onFinish)(NSArray<NSURL *> *urls);   // 取消时 urls 为空
@end

@implementation DKBackupPickerRelay {
    BOOL _finished;
}

- (void)finishWithURLs:(NSArray<NSURL *> *)urls {
    if (_finished) return;
    _finished = YES;
    if (self.onFinish) self.onFinish(urls ?: @[]);
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    [self finishWithURLs:urls];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    [self finishWithURLs:nil];
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    [self finishWithURLs:nil];
}

@end

static void DKPresentPicker(UIViewController *presenter, UIDocumentPickerViewController *picker,
                            void (^onFinish)(NSArray<NSURL *> *urls)) {
    DKBackupPickerRelay *relay = [[DKBackupPickerRelay alloc] init];
    relay.onFinish = onFinish;
    picker.delegate = relay;
    picker.presentationController.delegate = relay;
    // delegate 是弱引用，relay 跟着 picker 一起活着。
    objc_setAssociatedObject(picker, &kDKPickerRelayKey, relay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [presenter presentViewController:picker animated:YES completion:nil];
}

#pragma mark - 备份页的行

// 按当前状态重写「备份到文件」「撤销上次恢复」的右侧文案与可用态。
static void DKRefreshRows(void) {
    UIViewController *page = DKSettingsCurrentPage();
    DKSettingsFindItem(page, DKKeyBackupExport).detail = DKExportDetail();
    AWESettingItemModel *undo = DKSettingsFindItem(page, DKKeyBackupUndo);
    if (undo) {
        NSDate *snapshot = [DKMakeStore() snapshotDate];
        undo.detail = DKUndoDetail(snapshot);
        DKSettingsSetItemEnabled(undo, snapshot != nil);
    }
    DKSettingsReloadCurrentPage();
}

#pragma mark - 提交与结果

static NSString *DKModeName(DKBackupMode mode) {
    switch (mode) {
        case DKBackupModeRestore: return @"restore";
        case DKBackupModeUndo: return @"undo";
        case DKBackupModeReset: return @"reset";
    }
    return @"";
}

static void DKShowResult(UIViewController *presenter, DKBackupMode mode, DKBackupPlan *plan) {
    NSUInteger count = plan.visibleChanges.count;
    if (count == 0 && plan.unwrittenTitles.count == 0) {
        NSString *title = mode == DKBackupModeRestore ? @"备份与当前设置一致"
                        : mode == DKBackupModeUndo ? @"当前设置与快照一致" : @"当前已是默认设置";
        DKShowAlert(presenter, title, nil);
        return;
    }

    NSString *title = mode == DKBackupModeRestore ? @"已恢复备份"
                    : mode == DKBackupModeUndo ? @"已撤销上次恢复" : @"已恢复默认设置";
    NSMutableString *message = [NSMutableString stringWithFormat:
        @"已修改 %lu 项。建议彻底退出并重新打开抖音，让所有设置完整生效", (unsigned long)count];
    if (plan.restartTitles.count) {
        [message appendFormat:@"；「%@」需重启后才会生效。", [plan.restartTitles componentsJoinedByString:@"」「"]];
    } else {
        [message appendString:@"。"];
    }
    if (plan.unwrittenTitles.count) {
        [message appendFormat:@"\n「%@」未能写入。", [plan.unwrittenTitles componentsJoinedByString:@"」「"]];
    }
    DKShowAlert(presenter, title, message);
}

static void DKCommit(DKBackupDocument *document, DKBackupMode mode) {
    NSError *error = nil;
    DKBackupPlan *plan = [DKMakeStore() commitDocument:document entries:DKBackupCollectEntries() mode:mode error:&error];
    DKRefreshRows();
    UIViewController *presenter = DKSettingsCurrentPage();
    if (!plan) {
        DKBackupRecordOperation(DKModeName(mode), error.localizedDescription);
        NSString *title = mode == DKBackupModeRestore ? @"恢复失败" : mode == DKBackupModeUndo ? @"撤销失败" : @"重置失败";
        DKShowAlert(presenter, title, error.localizedDescription);
        return;
    }
    DKBackupRecordOperation(DKModeName(mode), [NSString stringWithFormat:@"修改 %lu 项，跳过 %lu 项，未写入 %lu 项",
        (unsigned long)plan.visibleChanges.count, (unsigned long)plan.skips.count, (unsigned long)plan.unwrittenTitles.count]);
    DKShowResult(presenter, mode, plan);
}

// 明细页确认：先回到备份页，转场结束后再提交，结果提示与行刷新都落在备份页上。
static void DKCommitFromDetail(DKBackupDocument *document) {
    UINavigationController *navigation = DKSettingsCurrentPage().navigationController;
    [navigation popViewControllerAnimated:YES];
    id<UIViewControllerTransitionCoordinator> coordinator = navigation.transitionCoordinator;
    if (!coordinator) {
        DKCommit(document, DKBackupModeRestore);
        return;
    }
    [coordinator animateAlongsideTransition:nil completion:^(__unused id<UIViewControllerTransitionCoordinatorContext> context) {
        DKCommit(document, DKBackupModeRestore);
    }];
}

#pragma mark - 四个动作

static void DKExport(UIViewController *presenter) {
    if (gDKBackupBusy) return;
    gDKBackupBusy = YES;
    NSArray<DKBackupEntry *> *entries = DKBackupCollectEntries();
    NSDictionary<NSString *, NSString *> *source = DKBackupSource();
    BOOL glassAvailable = DKGlassOSAvailable();
    NSDate *now = NSDate.date;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSString *path = nil;
        NSData *data = DKBackupEncode(entries, NSUserDefaults.standardUserDefaults, source, now, glassAvailable, &error);
        if (data) {
            NSFileManager *fm = NSFileManager.defaultManager;
            [fm removeItemAtPath:DKExportDirectory() error:NULL];
            NSString *directory = [DKExportDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
            path = [directory stringByAppendingPathComponent:DKBackupFileName(now)];
            if (![fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL]
                || ![data writeToFile:path options:NSDataWritingAtomic error:NULL]) {
                path = nil;
                error = DKBackupMakeError(DKBackupErrorWriteFailed, @"无法写入临时文件");
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!path) {
                gDKBackupBusy = NO;
                DKBackupRecordOperation(@"export", error.localizedDescription);
                DKShowAlert(presenter, @"备份失败", error.localizedDescription);
                return;
            }
            UIDocumentPickerViewController *picker =
                [[UIDocumentPickerViewController alloc] initForExportingURLs:@[ [NSURL fileURLWithPath:path] ] asCopy:YES];
            DKPresentPicker(presenter, picker, ^(NSArray<NSURL *> *urls) {
                [NSFileManager.defaultManager removeItemAtPath:DKExportDirectory() error:NULL];
                gDKBackupBusy = NO;
                if (!urls.count) return;
                [NSUserDefaults.standardUserDefaults setObject:NSDate.date forKey:DKKeyBackupLastExportDate];
                DKBackupRecordOperation(@"export", urls.firstObject.lastPathComponent);
                DKRefreshRows();
            });
        });
    });
}

static void DKPresentSummary(UIViewController *presenter, DKBackupDocument *document, DKBackupPlan *plan) {
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithObject:DKSourceLines(document)];
    NSUInteger changes = plan.visibleChanges.count, skips = plan.skips.count;
    BOOL hasChanges = changes > 0;
    if (hasChanges) {
        [lines addObject:@""];
        [lines addObject:skips ? [NSString stringWithFormat:@"将修改 %lu 项，跳过 %lu 项", (unsigned long)changes, (unsigned long)skips]
                               : [NSString stringWithFormat:@"将修改 %lu 项", (unsigned long)changes]];
        NSString *images = DKImagesText(plan);
        if (images) [lines addObject:images];
        [lines addObject:@"恢复前会自动保存当前配置快照，可以撤销。"];
    } else if (skips) {
        [lines addObject:[NSString stringWithFormat:@"\n跳过 %lu 项", (unsigned long)skips]];
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:hasChanges ? @"恢复备份配置？" : @"备份与当前设置一致"
                                                                   message:[lines componentsJoinedByString:@"\n"]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    if (hasChanges) {
        [alert addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            dispatch_async(dispatch_get_main_queue(), ^{ DKCommit(document, DKBackupModeRestore); });
        }]];
    }
    if (hasChanges || skips) {
        [alert addAction:[UIAlertAction actionWithTitle:@"查看明细" style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            dispatch_block_t confirm = nil;
            if (hasChanges) confirm = ^{ DKCommitFromDetail(document); };
            DKBackupShowDetail(presenter, document, plan, confirm);
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:hasChanges ? @"取消" : @"好" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

static void DKRestore(UIViewController *presenter) {
    if (gDKBackupBusy) return;
    gDKBackupBusy = YES;
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeData ] asCopy:YES];
    picker.allowsMultipleSelection = NO;
    DKPresentPicker(presenter, picker, ^(NSArray<NSURL *> *urls) {
        NSURL *url = urls.firstObject;
        if (!url) {
            gDKBackupBusy = NO;
            return;
        }
        // 读文件与解析在后台；算计划会调各项的文案 block，回主线程再算。
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *error = nil;
            NSData *data = DKBackupReadFile(url.path, &error);
            DKRemoveTemporaryCopy(url);
            DKBackupDocument *document = data ? DKBackupDecode(data, &error) : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                gDKBackupBusy = NO;
                if (!document) {
                    DKBackupRecordOperation(@"read", error.localizedDescription);
                    DKShowAlert(presenter, @"无法恢复", error.localizedDescription);
                    return;
                }
                DKBackupPlan *plan = DKBackupMakePlan(document, DKBackupCollectEntries(),
                                                      NSUserDefaults.standardUserDefaults, DKGlassOSAvailable());
                DKPresentSummary(presenter, document, plan);
            });
        });
    });
}

static void DKUndo(UIViewController *presenter) {
    DKShowConfirm(presenter, @"撤销上次恢复？", @"将还原到上次恢复或重置前的设置和自定义拍摄图标。撤销后，这份快照将被清除。",
                  @"撤销恢复", NO, ^{
        NSError *error = nil;
        DKBackupDocument *snapshot = [DKMakeStore() loadSnapshot:&error];
        if (!snapshot) {
            DKRefreshRows();
            DKShowAlert(DKSettingsCurrentPage(), @"撤销失败", error.localizedDescription);
            return;
        }
        DKCommit(snapshot, DKBackupModeUndo);
    });
}

static void DKReset(UIViewController *presenter) {
    DKShowConfirm(presenter, @"恢复默认设置？", @"所有设置将回到默认，自定义拍摄图标一起清除。重置前会自动保存当前配置快照，可以撤销。",
                  @"恢复默认", YES, ^{
        DKCommit(DKBackupDefaultsDocument(DKBackupCollectEntries()), DKBackupModeReset);
    });
}

#pragma mark - 设置项注册

%ctor {
    DKSettingsRegister(DKKeyBackupExport, ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeAction(DKKeyBackupExport, @"备份到文件", DKExportDetail(),
            ^(__unused AWESettingItemModel *item, UIViewController *presenter) { DKExport(presenter); }));
    });
    DKSettingsRegister(DKKeyBackupRestore, ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeAction(DKKeyBackupRestore, @"从文件恢复", @"",
            ^(__unused AWESettingItemModel *item, UIViewController *presenter) { DKRestore(presenter); }));
    });
    DKSettingsRegister(DKKeyBackupUndo, ^AWESettingItemModel *{
        NSDate *snapshot = [DKMakeStore() snapshotDate];
        AWESettingItemModel *item = DKMakeAction(DKKeyBackupUndo, @"撤销上次恢复", DKUndoDetail(snapshot),
            ^(__unused AWESettingItemModel *it, UIViewController *presenter) { DKUndo(presenter); });
        item.isEnable = snapshot != nil;
        return DKSettingsWithoutBackup(item);
    });
    DKSettingsRegister(DKKeyBackupReset, ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKSettingsMarkDestructive(DKMakeAction(DKKeyBackupReset, @"恢复默认设置", @"",
            ^(__unused AWESettingItemModel *item, UIViewController *presenter) { DKReset(presenter); })));
    });
}
