#ifndef DKInteractionIconDraw_h
#define DKInteractionIconDraw_h
#import <CoreGraphics/CoreGraphics.h>
#import "DKInteractionIconRules.h"
#ifdef __cplusplus
extern "C" {
#endif
/// 24 单位网格；context 原点在左上，y 向下。style 为 1 或 2。
/// 激活态用 SourceIn 给画布已有像素上色，context 须为未设阴影的透明画布。
void DKInteractionIconDraw(CGContextRef context, DKInteractionIconSlot slot, NSInteger style, CGRect rect);
#ifdef __cplusplus
}
#endif
#endif
