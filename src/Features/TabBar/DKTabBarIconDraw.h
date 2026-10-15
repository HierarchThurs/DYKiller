//
//  DKTabBarIconDraw.h
//  DYKiller
//
//  底栏图标的绘制核心：纯 CoreGraphics，不依赖 UIKit，可在 macOS 上渲染核对。
//  图形取自 docs/tab-bar-icons-preview.html 的定稿路径，24×24 网格、线宽 1.75。
//  context 须为 UIKit 朝向（原点在左上、y 向下），且带 alpha（镂空用 kCGBlendModeClear）。
//

#ifndef DKTabBarIconDraw_h
#define DKTabBarIconDraw_h

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, DKTabBarGlyph) {
    DKTabBarGlyphHome = 0,
    DKTabBarGlyphMall,
    DKTabBarGlyphFriends,
    DKTabBarGlyphMessage,
    DKTabBarGlyphMe,
};

#ifdef __cplusplus
extern "C" {
#endif

/// 把 SVG path data 解析成 CGPath（M/L/H/V/C/S/A/Z 大小写）。解析失败返回 NULL。调用方负责释放。
CGPathRef DKSVGPathCreate(const char *data);

/// 在 rect（正方形）里画 tab 图标：filled 为选中态的实心画法，否则为线框。
void DKTabBarDrawGlyph(CGContextRef context, DKTabBarGlyph glyph, BOOL filled, CGRect rect, CGColorRef color);

/// 实心照相机（镜头环与闪光点镂空）。
void DKTabBarDrawCamera(CGContextRef context, CGRect rect, CGColorRef color);

/// 双色照相机的彩色层：青、红两层机身各向左右错开 0.9，镜头与闪光点处挖空。
/// 与 DKTabBarDrawCamera 的机身叠在一起即为完整的双色图标。
void DKTabBarDrawCameraAccent(CGContextRef context, CGRect rect);

#ifdef __cplusplus
}
#endif

#endif /* DKTabBarIconDraw_h */
