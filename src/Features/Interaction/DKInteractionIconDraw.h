#ifndef DKInteractionIconDraw_h
#define DKInteractionIconDraw_h
#import <CoreGraphics/CoreGraphics.h>
#import "DKInteractionIconRules.h"
#ifdef __cplusplus
extern "C" {
#endif
/// iOS 16.x 的 UIGraphicsImageRenderer 位图上下文在 CGContextBeginTransparencyLayer
/// 内部会触发 CGGStateSetFillColor -> CFRetain 的 arm64e 指针认证崩溃（EXC_BREAKPOINT）。
/// 返回当前系统是否可以使用原来的透明层绘制路径；16.x 返回 NO，改走无透明层的兼容分支。
BOOL DKInteractionIconUsesTransparencyLayer(void);

/// 24 单位网格；context 原点在左上，y 向下。style 为 1 或 2。
void DKInteractionIconDraw(CGContextRef context, DKInteractionIconSlot slot, NSInteger style, CGRect rect);
#ifdef __cplusplus
}
#endif
#endif
