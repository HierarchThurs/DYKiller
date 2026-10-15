//
//  DKBackupEntries.h
//  从已登记的设置项收集可备份项，以及备份的诊断信息。
//

#ifndef DKBackupEntries_h
#define DKBackupEntries_h

#import <Foundation/Foundation.h>

@class DKBackupEntry;

#ifdef __cplusplus
extern "C" {
#endif

/// 按布局顺序建出每个已登记的项并取它的值声明，主线程调用。
/// 调试工具开关、声明了不备份的项不在其中；未声明或值键重复的项记入诊断并跳过。
NSArray<DKBackupEntry *> *DKBackupCollectEntries(void);

/// 记下最近一次备份操作与结果，进诊断。主线程调用。
void DKBackupRecordOperation(NSString *operation, NSString *result);

/// 诊断：可备份 / 已排除 / 未声明 / 值键重复的键，以及最近一次操作。任意线程调用。
NSDictionary *DKSettingsBackupDiagnostics(void);

#ifdef __cplusplus
}
#endif

#endif /* DKBackupEntries_h */
