// 图片的非透明区域：按 alpha 求包围盒，结果缓存在图片上。
#ifndef DKImageOpaque_h
#define DKImageOpaque_h
#import <UIKit/UIKit.h>
#ifdef __cplusplus
extern "C" {
#endif
// 非透明像素的包围盒，单位为像素（CGImage 坐标，原点在左上）；没有位图或整张透明时为 CGRectNull。
CGRect DKImageOpaquePixelRect(UIImage *image);
#ifdef __cplusplus
}
#endif
#endif
