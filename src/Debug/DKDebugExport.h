//
//  DKDebugExport.h
//  DYKiller
//
//  把主线程采集完成的调试上下文序列化并打包。
//

#ifndef DKDebugExport_h
#define DKDebugExport_h

#import <Foundation/Foundation.h>
#import "DKDebugCapture.h"

typedef NS_ENUM(NSUInteger, DKDebugExportMode) {
    DKDebugExportModePage,
    DKDebugExportModeAudio,
};

/// ZIP 生成失败时，工作目录会被保留，路径放在 error.userInfo 的这个键上。
extern NSString *const DKDebugExportWorkingDirectoryKey;

@interface DKDebugExportResult : NSObject
@property (nonatomic, strong) NSURL *zipURL;
@property (nonatomic, strong) NSURL *workingDirectoryURL;
@end

#ifdef __cplusplus
extern "C" {
#endif

/// 在后台线程生成导出包。失败时返回 nil，并通过 error 返回真实原因。
DKDebugExportResult *DKDebugCreateExport(DKDebugExportContext *context,
                                         DKDebugExportMode mode,
                                         void (^progress)(NSString *text),
                                         NSError **error);

/// 分享完成或取消后删除工作目录和 zip。
void DKDebugCleanupExport(DKDebugExportResult *result);

#ifdef __cplusplus
}
#endif

#endif /* DKDebugExport_h */
