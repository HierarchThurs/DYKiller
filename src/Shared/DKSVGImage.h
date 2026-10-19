#ifndef DKSVGImage_h
#define DKSVGImage_h

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

#ifdef __cplusplus
extern "C" {
#endif

BOOL DKSVGImageAvailable(void);
/// 检查静态 SVG 的文档、资源引用及画布；不访问外部资源。
BOOL DKSVGImageInspect(NSData *data, CGSize *size, NSString **reason);
/// 返回带透明通道的位图；调用方负责释放。尺寸为像素，context 使用 CoreGraphics 朝向。
CGImageRef DKSVGImageCreate(NSData *data, CGSize pixels);

#ifdef __cplusplus
}
#endif
#endif
