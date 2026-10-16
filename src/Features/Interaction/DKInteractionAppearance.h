//
//  DKInteractionAppearance.h
//  DYKiller
//
//  视频右侧互动按钮、头像与听音乐组件的外观定制。
//

#ifndef DKInteractionAppearance_h
#define DKInteractionAppearance_h

#import <UIKit/UIKit.h>

@class AWEElementStackView;

#ifdef __cplusplus
extern "C" {
#endif

/// 右侧互动栈布局后应用外观；不是右侧栈时直接返回。由元素栈的统一布局入口调用。
void DKInteractionAppearanceApplyStack(AWEElementStackView *stack);

/// 设置改变后立即刷新当前页面上的播放交互层。
void DKInteractionAppearanceRefresh(void);

/// 输出当前可见右侧交互层状态，供调试探针使用。
NSString *DKInteractionAppearanceStatus(void);

#ifdef __cplusplus
}
#endif

#endif /* DKInteractionAppearance_h */
