//
//  DKViewAdjust.h
//  DYKiller
//
//  可复位的视图调整：透明度乘系数、transform 叠加、mask 淡出，以及元素栈的逐行缩放几何。
//  用关联对象记下基础值与写入值，只还原本模块改过的对象；宿主在下一轮写入的新值成为下一轮的基础值。
//

#ifndef DKViewAdjust_h
#define DKViewAdjust_h

#import <UIKit/UIKit.h>

/// 逐行缩放时各行贴住的水平边。
typedef NS_ENUM(NSInteger, DKStackEdge) {
    DKStackEdgeLeft = 0,
    DKStackEdgeRight = 1,
};

#ifdef __cplusplus
extern "C" {
#endif

/// 两个 transform 在显示精度内是否相同。
BOOL DKAdjustTransformEqual(CGAffineTransform lhs, CGAffineTransform rhs);

/// 透明度乘系数（0–1），乘在宿主当前 alpha 上；系数为 1 时还原宿主值。
void DKAdjustAlpha(UIView *view, CGFloat factor);

/// delta 叠加在宿主当前 transform 之后；delta 为单位矩阵时还原宿主值。
void DKAdjustTransform(UIView *view, CGAffineTransform delta);

/// 整个视图按系数（0–1）淡出：挂半透明 mask，不改 alpha / hidden，命中不受影响。
/// mask 向四周外扩 outset，覆盖超出 bounds 的子视图；系数为 1 时摘掉自己的 mask；宿主自带 mask 时不覆盖。
void DKAdjustFade(UIView *view, CGFloat factor, CGSize outset);

/// 视图上本模块 mask 的系数；没挂或已被宿主替换时返回 1。
CGFloat DKAdjustFadeFactor(UIView *view);

/// 元素栈逐行缩放：每行按 scaleForRow 贴 edge 一侧缩放，自下而上累计各行缩掉的高度，上方各行依次收拢。
/// 最底可见行以 contentBottomForRow 返回的内容底边（行坐标）为锚，内容底边保持原位。隐藏行不参与并还原。
void DKAdjustStackRows(UIStackView *stack, DKStackEdge edge,
                       CGFloat (^scaleForRow)(UIView *row),
                       CGFloat (^contentBottomForRow)(UIView *row));

#ifdef __cplusplus
}
#endif

#endif /* DKViewAdjust_h */
