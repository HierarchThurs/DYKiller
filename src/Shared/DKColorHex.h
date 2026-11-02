// 颜色的规范化：DKColorHexNormalize 只留 RGB；DKColorHexNormalizeAlpha 保留 #AARRGGBB 的透明度。
#ifndef DKColorHex_h
#define DKColorHex_h
#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif
NSString *DKColorHexNormalize(id raw);
/// 规范化为 #AARRGGBB：三位补全、六位补 FF、八位原样保留。
NSString *DKColorHexNormalizeAlpha(id raw);
NSString *DKColorHexNormalizeScheme(id raw, BOOL gradient, NSString **reason);
/// 同上，但每个颜色都输出 #AARRGGBB。
NSString *DKColorHexNormalizeSchemeAlpha(id raw, BOOL gradient, NSString **reason);
#ifdef __cplusplus
}
#endif
#endif
