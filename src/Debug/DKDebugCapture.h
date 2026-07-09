//
//  DKDebugCapture.h
//  DYKiller
//
//  抓取当前页面的运行时快照（窗口/视图树/VC 树/图层/截图/本页类），产出
//  一个只含"已算好数据"的 DKDebugExportContext，交给 DKDebugExport 落盘。
//

#ifndef DKDebugCapture_h
#define DKDebugCapture_h

#import <UIKit/UIKit.h>

/// 一次页面快照的产物（纯数据；序列化由 DKDebugExport 负责）。
@interface DKDebugExportContext : NSObject
@property (nonatomic, strong) NSDictionary *metadata;
@property (nonatomic, strong) NSArray *windowsJSON;
@property (nonatomic, strong) NSArray *viewTreeJSON;
@property (nonatomic, copy) NSString *viewTreeText;
@property (nonatomic, strong) NSDictionary *selectedViewJSON;
@property (nonatomic, copy) NSString *viewControllersText;
@property (nonatomic, strong) NSArray *layersJSON;
@property (nonatomic, strong) NSData *screenshotPNG;
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, strong) NSArray<NSString *> *pageClassNames;
@property (nonatomic, weak) UIView *sourceView;
@property (nonatomic, weak) UIViewController *presenter;
@end

#ifdef __cplusplus
extern "C" {
#endif

/// 前台 key 窗口（排除调试自身窗口）。
UIWindow *DKDebugTargetWindow(void);

/// 某窗口当前最顶层的 VC（穿透 present/nav/tab）。
UIViewController *DKDebugTopPresenter(UIWindow *window);

/// 抓取一次页面快照。
DKDebugExportContext *DKDebugCaptureContext(UIWindow *targetWindow, CGPoint point, UIView *selectedView);

#ifdef __cplusplus
}
#endif

#endif /* DKDebugCapture_h */
