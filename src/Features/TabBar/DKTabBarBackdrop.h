//
//  DKTabBarBackdrop.h
//  DYKiller
//
//  视频全屏的底栏背景让位：视频全屏开启、悬浮玻璃底栏关闭时，抖音自绘底栏的背景在所有底栏页面透明。
//

#ifndef DKTabBarBackdrop_h
#define DKTabBarBackdrop_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 视频全屏或玻璃底栏开关变了，在下一轮主线程按当前状态重判；同一轮多次调用只跑一次。
void DKTabBarBackdropSetNeedsUpdate(void);

/// 判据输入、背景层与归属状态，一段多行文字，供探针输出。
NSString *DKTabBarBackdropStatus(void);

#ifdef __cplusplus
}
#endif

#endif /* DKTabBarBackdrop_h */
