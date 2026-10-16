//
//  DKElementRowHiding.h
//  DYKiller
//
//  元素栈行（AWEBaseElementView）显隐的唯一属主：「移除」类设置把行设为隐藏，由抖音的 UIStackView 原生收拢。
//  抖音自己写入的显隐照常记下，设置关闭后还原为抖音最近一次写入的值。
//

#ifndef DKElementRowHiding_h
#define DKElementRowHiding_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 行是否应移除：播放页精简或右侧栏显示方式。
BOOL DKElementRowShouldRemove(UIView *row);

/// 按当前设置重写一次行的显隐。
void DKElementRowSync(UIView *row);

#ifdef __cplusplus
}
#endif

#endif /* DKElementRowHiding_h */
