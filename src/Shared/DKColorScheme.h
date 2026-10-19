//
//  DKColorScheme.h
//  文字改色的颜色方案：六种互斥模式、存值读取、颜色序列与渐变图案色。弹幕改色与发布时间地区共用。
//  存值只有 RGB（规范化见 DKColorHex），输出均为不透明颜色，透明度由使用方继承宿主。
//

#ifndef DKColorScheme_h
#define DKColorScheme_h

#import <UIKit/UIKit.h>

/// 颜色模式，存为单选下标。
typedef NS_ENUM(NSInteger, DKColorSchemeMode) {
    DKColorSchemeFixed = 0,           // 固定颜色
    DKColorSchemeRandom = 1,          // 随机纯色
    DKColorSchemeRandomGradient = 2,  // 随机三色渐变
    DKColorSchemeRainbow = 3,         // 固定七色彩虹
    DKColorSchemeCustomGradient = 4,  // 自定义 2–8 色渐变
    DKColorSchemeRotatingRainbow = 5, // 七色彩虹，起始色按序号轮换
};

#ifdef __cplusplus
extern "C" {
#endif

extern NSString *const DKColorSchemeDefaultColor;
extern NSString *const DKColorSchemeDefaultGradient;

/// 单选项的选项文字，下标即 DKColorSchemeMode。
NSArray<NSString *> *DKColorSchemeModeTitles(void);

/// 读模式存值；未设置或越界按固定颜色。
DKColorSchemeMode DKColorSchemeStoredMode(NSString *key);

/// 读颜色存值的规范值；未设置或不合法时取默认值。
NSString *DKColorSchemeStoredColor(NSString *key, BOOL gradient);

/// #RRGGBB → 不透明颜色；不合法按白色。
UIColor *DKColorSchemeRGB(NSString *hex);

/// 方案标识：模式与它用到的存值。标识不变时已生成的颜色序列可以继续用。
NSString *DKColorSchemeSignature(DKColorSchemeMode mode, NSString *fixedHex, NSString *gradientHex);

/// 颜色序列：固定色与自定义渐变取传入的规范值；随机模式每次调用重新生成；
/// 旋转彩虹以 rotation 对 7 取模作为起始色。
NSArray<UIColor *> *DKColorSchemePalette(DKColorSchemeMode mode, NSString *fixedHex, NSString *gradientHex,
                                         NSUInteger rotation);

/// 颜色序列 → 文字前景色。单色原样返回；多色生成水平渐变图案色，渐变铺在 [start, start + width]，
/// 坐标以绘制文字的视图原点为准（图案相位跟随视图原点）。
UIColor *DKColorSchemeRender(NSArray<UIColor *> *colors, CGFloat start, CGFloat width, CGFloat scale);

#ifdef __cplusplus
}
#endif

#endif /* DKColorScheme_h */
