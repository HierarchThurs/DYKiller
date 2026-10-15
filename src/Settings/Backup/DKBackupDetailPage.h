//
//  DKBackupDetailPage.h
//  恢复明细页，以及备份来源与时间的展示文案。
//

#ifndef DKBackupDetailPage_h
#define DKBackupDetailPage_h

#import <UIKit/UIKit.h>

@class DKBackupDocument;
@class DKBackupPlan;

#ifdef __cplusplus
extern "C" {
#endif

/// 推入恢复明细页：备份信息 → 按所在子页分组的变更 → 跳过。变更行右侧为恢复后的值，ⓘ 写当前与恢复后。
/// confirm 非空时末尾加一行「恢复这些设置」，点击时调用。
void DKBackupShowDetail(UIViewController *presenter, DKBackupDocument *document, DKBackupPlan *plan,
                        dispatch_block_t confirm);

/// 来源，如「DYKiller 0.6.0-beta12 · 抖音 40.7.0 · iOS 26.1」；没有来源信息时为「来源未知」。
NSString *DKBackupSourceText(DKBackupDocument *document);

/// 备份时间，如「2026-10-15 10:30」，按本机时区。
NSString *DKBackupTimeText(NSDate *date);

#ifdef __cplusplus
}
#endif

#endif /* DKBackupDetailPage_h */
