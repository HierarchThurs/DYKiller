//
//  DKDebugExport.h
//  DYKiller
//
//  把 DKDebugExportContext 落盘成分类文件并打成 zip。
//

#ifndef DKDebugExport_h
#define DKDebugExport_h

#import <Foundation/Foundation.h>
#import "DKDebugCapture.h"

#ifdef __cplusplus
extern "C" {
#endif

/// 生成 zip。默认导出当前页面结构、截图与本页类；
/// includeAppClasses=YES 时追加 runtime/ 目录下的应用类头文件导出。
NSURL *DKDebugCreateExportZip(DKDebugExportContext *context,
                              BOOL includeAppClasses,
                              void (^progress)(NSString *text));

#ifdef __cplusplus
}
#endif

#endif /* DKDebugExport_h */
