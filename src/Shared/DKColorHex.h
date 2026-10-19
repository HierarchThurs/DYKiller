// RGB 颜色的规范化；八位输入兼容 AARRGGBB，透明度不进入规范值。
#ifndef DKColorHex_h
#define DKColorHex_h
#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif
NSString *DKColorHexNormalize(id raw);
NSString *DKColorHexNormalizeScheme(id raw, BOOL gradient, NSString **reason);
#ifdef __cplusplus
}
#endif
#endif
