//
//  DKBackupModel.h
//  备份的数据模型：可备份项、读入的备份文档，以及按文档算出的恢复计划。
//  只依赖 Foundation，与抖音设置类脱钩。
//

#ifndef DKBackupModel_h
#define DKBackupModel_h

#import "DKSettingsValue.h"

NS_ASSUME_NONNULL_BEGIN

/// 一个可备份的设置项，由设置项上的声明复制而来。
@interface DKBackupEntry : NSObject
@property (nonatomic, copy, readonly) NSString *identifier;      // 设置项键
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *group;           // 所在子页标题，明细页分组用
@property (nonatomic, copy, readonly, nullable) NSString *icon;  // 明细页行图标
@property (nonatomic, copy, readonly) NSArray<DKSettingsValue *> *values;
@property (nonatomic, readonly) BOOL needsRestart;               // 改动后需重启抖音才完全生效
@property (nonatomic, readonly) BOOL gated;                      // 受液态玻璃守卫，低于 iOS 26 不导出、不恢复

- (instancetype)initWithIdentifier:(NSString *)identifier title:(NSString *)title group:(NSString *)group
                              icon:(nullable NSString *)icon values:(NSArray<DKSettingsValue *> *)values
                          describe:(nullable DKSettingsDescribe)describe onChange:(nullable dispatch_block_t)onChange
                      needsRestart:(BOOL)needsRestart gated:(BOOL)gated NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// values 为规范值，与 self.values 一一对应。
- (NSString *)describe:(NSArray *)values brief:(BOOL)brief;
/// 恢复写入后调用，与界面上改值后的刷新为同一段代码。主线程调用。
- (void)runOnChange;
@end

/// 读入的备份。各节保留原始 JSON 值，按声明规范化在算计划时进行。
@interface DKBackupDocument : NSObject
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *source;   // plugin / app / system
@property (nonatomic, strong, nullable) NSDate *createdAt;
@property (nonatomic, copy) NSDictionary<NSString *, id> *settings;         // NSUserDefaults 键 → 值 / NSNull
@property (nonatomic, copy) NSDictionary<NSString *, id> *sets;             // 键前缀 → ID 数组 / NSNull
@property (nonatomic, copy) NSDictionary<NSString *, id> *files;            // 图片名 → 已核对的数据 / NSNull
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *fileErrors;   // 图片名 → 核对失败原因
@end

/// 一项设置的变化。
@interface DKBackupChange : NSObject
@property (nonatomic, strong, readonly) DKBackupEntry *entry;
@property (nonatomic, copy, readonly) NSArray *oldValues;
@property (nonatomic, copy, readonly) NSArray *values;
/// 展示文案有变化；存值不同但文案相同（如「未设置」与「显式写入默认值」）的项照写，但不计入「修改」。
@property (nonatomic, readonly) BOOL visible;
@property (nonatomic, copy, readonly) NSString *oldText;
@property (nonatomic, copy, readonly) NSString *text;
@property (nonatomic, copy, readonly) NSString *briefText;
@end

/// 不恢复的一项及原因。
@interface DKBackupSkip : NSObject
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *reason;
@property (nonatomic, copy, readonly, nullable) NSString *icon;
@end

@interface DKBackupPlan : NSObject
@property (nonatomic, copy, readonly) NSArray<DKBackupChange *> *changes;          // 全部有存值差异的项，按 entries 顺序
@property (nonatomic, copy, readonly) NSArray<DKBackupChange *> *visibleChanges;
@property (nonatomic, copy, readonly) NSArray<DKBackupSkip *> *skips;
@property (nonatomic, copy, readonly) NSArray<NSString *> *restartTitles;          // 可见变化中需重启的项标题
@property (nonatomic, readonly) NSUInteger replacedImages;                         // 可见变化中替换的图片数
@property (nonatomic, readonly) NSUInteger clearedImages;                          // 可见变化中清除的图片数
/// 提交时未能写入的项标题，由 DKBackupStore 填写。
@property (nonatomic, copy) NSArray<NSString *> *unwrittenTitles;
@end

#ifdef __cplusplus
extern "C" {
#endif

/// 按文档与当前存值算恢复计划。文档里出现的值按文档覆盖，没出现的保持当前值；
/// 一项里任一值不合法则整项跳过；glassAvailable 为 NO 时受玻璃守卫的项跳过。
DKBackupPlan *DKBackupMakePlan(DKBackupDocument *document, NSArray<DKBackupEntry *> *entries,
                               id<DKSettingsStore> store, BOOL glassAvailable);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END

#endif /* DKBackupModel_h */
