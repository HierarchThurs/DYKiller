//
//  DKBackupStore.h
//  恢复、撤销与恢复默认的提交，以及撤销快照的存取。只依赖 Foundation。
//

#ifndef DKBackupStore_h
#define DKBackupStore_h

#import "DKBackupCodec.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DKBackupMode) {
    DKBackupModeRestore,   // 按备份恢复，先拍快照
    DKBackupModeUndo,      // 按快照还原，完成后删除快照
    DKBackupModeReset,     // 恢复默认，先拍快照
};

@interface DKBackupStore : NSObject

/// directory 存放撤销快照；source 写进快照的来源信息。
- (instancetype)initWithDirectory:(NSString *)directory store:(id<DKSettingsStore>)store
                           source:(NSDictionary<NSString *, NSString *> *)source
                   glassAvailable:(BOOL)glassAvailable NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// 撤销快照的时间，没有快照返回 nil。只读文件属性，不改动文件。
- (nullable NSDate *)snapshotDate;

/// 读撤销快照；上次提交中断留下的待定快照先转为快照。
- (nullable DKBackupDocument *)loadSnapshot:(NSError **)error;

/// 按文档提交，必须在主线程调用：按当前存值重算计划；有可见变化时先拍快照（撤销模式不拍），
/// 再写图片与设置值并读回核对，最后对有变化的项调 onChange。没有变化时不拍快照、不写入，
/// 返回空计划（撤销模式仍删除快照）。图片写入失败时已换上的图片还原、设置值不动，返回 nil。
- (nullable DKBackupPlan *)commitDocument:(DKBackupDocument *)document entries:(NSArray<DKBackupEntry *> *)entries
                                     mode:(DKBackupMode)mode error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

#endif /* DKBackupStore_h */
