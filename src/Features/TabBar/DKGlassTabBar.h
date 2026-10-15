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

/// 按当前设置重跑一次挂载与几何。给设置页用：改完立刻生效，不必等抖音下一次布局。
void DKGlassTabBarRefresh(void);

/// 拍摄图标当前用的四周内缩：抖音原图与自定义圆形图标是两档。探针据此报告几何。
CGFloat DKGlassPlusIconInset(void);

/// 当前挂载中的拍摄圆键；功能关闭时为 nil。
UIVisualEffectView *DKGlassPlusKeyCurrent(void);

/// 悬浮胶囊本体（_UITabBarItemPlatterView）。音频可视化的环绕轮廓以它为准。
UIView *DKGlassPlatterCurrent(void);

/// 悬浮胶囊玻璃改写的状态，一句话自述。胶囊材质由 platter 自己的 glassEffect 决定，
/// 而非 UITabBarAppearance.backgroundEffect；这行是唯一能证明改写成没成的读数。
NSString *DKGlassPlatterGlassStatus(void);

/// 胶囊几何的当前读数，一句话自述：项目数与参考数、目标与实测胶囊宽、按钮量与内缩来源。
NSString *DKGlassGeometryStatus(void);

/// 内容取色（标题与拍摄图标）的当前判定，一句话自述：极性、两个色、依据来源。
/// 极性跟底色走而非跟深浅色模式走，依据是抖音自绘按钮的文字色。
NSString *DKGlassInkStatus(void);

#ifdef __cplusplus
}
#endif

#endif /* DKGlassTabBar_h */
