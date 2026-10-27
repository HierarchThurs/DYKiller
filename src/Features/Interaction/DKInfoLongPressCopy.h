//
//  DKInfoLongPressCopy.h
//  DYKiller
//
//  播放页长按左下昵称 / 文案复制。
//

#ifndef DKInfoLongPressCopy_h
#define DKInfoLongPressCopy_h

#import <UIKit/UIKit.h>

@class AWEElementStackView;

#ifdef __cplusplus
extern "C" {
#endif

/// 元素栈布局后给昵称行、文案行装上长按复制手势，每行一次；两个开关都关闭时不装。由元素栈的统一布局入口调用。
void DKInfoLongPressCopyApplyStack(AWEElementStackView *stack);

#ifdef __cplusplus
}
#endif

#endif /* DKInfoLongPressCopy_h */
