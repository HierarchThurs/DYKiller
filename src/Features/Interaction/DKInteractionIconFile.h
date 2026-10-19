#ifndef DKInteractionIconFile_h
#define DKInteractionIconFile_h
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#ifdef __cplusplus
extern "C" {
#endif
NSString *DKInteractionIconDataDetail(NSData *data);
NSData *DKInteractionIconNormalize(NSData *data, BOOL album, NSString **reason);
/// 按完整画布等比居中输出；调用方负责释放。
CGImageRef DKInteractionIconRasterize(NSData *data, CGSize pixels);
#ifdef __cplusplus
}
#endif
#endif
