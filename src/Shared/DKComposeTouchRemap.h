#pragma once

#import <UIKit/UIKit.h>

@interface DKComposeTouchRegion : NSObject
/// 将 sourceView 坐标下的区域和原生目标点转换到 touchView。
+ (instancetype)regionWithRect:(CGRect)rect target:(CGPoint)target
                    sourceView:(UIView *)sourceView touchView:(UIView *)touchView;
@end

#ifdef __cplusplus
extern "C" {
#endif

/// 模块初始化时注册渲染布局后的主线程回调，各回调自行识别目标宿主。
void DKComposeObserveRenderLayout(void (^observer)(UIView *renderView));

/// 为指定行登记布局后的主线程回调，传 nil 注销。回调应弱引用其宿主。
void DKComposeSetRowLayoutObserver(UIView *row, void (^observer)(UIView *row));

/// 沿渲染视图的父链查找 Compose 的触摸视图。
UIView *DKComposeTouchView(UIView *renderView);

/// 替换该触摸视图的换算表。区域重叠时取最先登记的一项，传 nil 清除。
void DKComposeSetTouchRegions(UIView *touchView, NSArray<DKComposeTouchRegion *> *regions);

#ifdef __cplusplus
}
#endif
