//
//  DKTabBarIcons.h
//  DYKiller
//
//  底栏图标的 UIKit 出图：按抖音 tabID 取图标，模板图与烤色图都按尺寸缓存。
//

#ifndef DKTabBarIcons_h
#define DKTabBarIcons_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 该 tabID 是否有设计好的图标（首页、朋友、商城、消息、我）。
BOOL DKTabBarHasIcon(NSString *tabID);

/// tab 图标模板图：selected 为实心，否则为线框。表外 tabID 返回 nil。只在主线程调用。
UIImage *DKTabBarIconTemplate(NSString *tabID, BOOL selected, CGFloat side);

/// 实心照相机模板图（拍摄按钮「新图标」，也是「新双色图标」的机身层）。
UIImage *DKTabBarCameraTemplate(CGFloat side);

/// 双色照相机的青红彩色层，叠在机身层下面。
UIImage *DKTabBarCameraAccent(CGFloat side);

#ifdef __cplusplus
}
#endif

#endif /* DKTabBarIcons_h */
