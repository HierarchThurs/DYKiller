//
//  DKGlassTabBar.h
//  DYKiller
//
//  悬浮玻璃底栏对外只暴露当前的两个实例（胶囊与拍摄圆键），供调试导出采集其状态。
//

#ifndef DKGlassTabBar_h
#define DKGlassTabBar_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 当前挂载中的玻璃底栏；功能关闭时为 nil。
UITabBar *DKGlassTabBarCurrent(void);

/// 当前挂载中的拍摄圆键；功能关闭时为 nil。
UIVisualEffectView *DKGlassPlusKeyCurrent(void);

#ifdef __cplusplus
}
#endif

#endif /* DKGlassTabBar_h */
