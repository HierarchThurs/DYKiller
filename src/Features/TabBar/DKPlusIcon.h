//
//  DKPlusIcon.h
//  DYKiller
//
//  拍摄圆键的自定义图标。只对外提供取图，替换与清除都在设置页里完成。
//

#ifndef DKPlusIcon_h
#define DKPlusIcon_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 用户设置的拍摄图标；未设置时为 nil。圆形 alpha 已烘进图内，取到即可直接显示。
/// 首次读盘一次后常驻内存，可放在逐帧布局路径上。只在主线程调用。
UIImage *DKPlusIconCustom(void);

/// 走相册选图 → 圆形裁剪 → 写盘；completion 只在写盘成功后以 YES 调用，取消或失败为 NO。
void DKPlusIconPick(UIViewController *presenter, void (^completion)(BOOL picked));

#ifdef __cplusplus
}
#endif

#endif /* DKPlusIcon_h */
