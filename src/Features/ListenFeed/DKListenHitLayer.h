//
//  DKListenHitLayer.h
//  铺满宿主的透明层：落在登记的玻璃上的触摸交给最近的原生控件，其余位置放行。
//

#ifndef DKListenHitLayer_h
#define DKListenHitLayer_h

#import <UIKit/UIKit.h>

@interface DKListenHitLayer : UIView

/// 宿主上的透明层；create 为 NO 且尚未建立时返回 nil。
+ (instancetype)layerInHost:(UIView *)host create:(BOOL)create;

/// 移除宿主上的透明层。
+ (void)removeFromHost:(UIView *)host;

/// 清空登记。
- (void)removeAllRegions;

/// 登记一块玻璃和它代表的控件；一块玻璃对应多个控件时按水平距离分段。
- (void)addRegionForGlass:(UIView *)glass targets:(NSArray<UIView *> *)targets;

@end

#endif /* DKListenHitLayer_h */
