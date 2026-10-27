//
//  DKTabBarPageImmersion.h
//  DYKiller
//
//  底栏页面底部沉浸：悬浮玻璃底栏或视频全屏任一开启时，商城页与个人主页二级分页不再为底栏让出底部高度。
//

#ifndef DKTabBarPageImmersion_h
#define DKTabBarPageImmersion_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 视频全屏或玻璃底栏开关变了，在下一轮主线程把见过的页面按当前状态重判；同一轮多次调用只跑一次。
void DKTabBarPageImmersionSetNeedsUpdate(void);

/// 沉浸判据与各页面的底部约束 / 分区高度，一段多行文字，供探针输出。
NSString *DKTabBarPageImmersionStatus(void);

#ifdef __cplusplus
}
#endif

#endif /* DKTabBarPageImmersion_h */
