//
//  DKProgressOffset.h
//  DYKiller
//
//  进度条上移与图片指示器上移。
//

#ifndef DKProgressOffset_h
#define DKProgressOffset_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 进度条容器每轮布局后调用：登记容器并记下进度条的原生底边位置。由进度条容器的统一布局入口调用。
void DKProgressOffsetLayoutContainer(UIView *container);

/// 图片指示器布局后、挂入窗口时调用：播放交互层里的实例按设置上移并记下原生底边位置，其余实例不处理。
/// 由图片指示器的统一布局入口调用。
void DKStoryIndicatorLayout(UIView *view);

/// 设置、本机实测位置与各进度条 / 图片指示器的当前状态，一段多行文字，供探针输出。
NSString *DKProgressOffsetStatus(void);

#ifdef __cplusplus
}
#endif

#endif /* DKProgressOffset_h */
