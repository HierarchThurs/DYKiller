//
//  DKInfoAppearance.h
//  DYKiller
//
//  视频左下昵称与文案区域的外观定制：透明度、缩放与上移。
//

#ifndef DKInfoAppearance_h
#define DKInfoAppearance_h

#import <UIKit/UIKit.h>

@class AWEElementStackView;

#ifdef __cplusplus
extern "C" {
#endif

/// 元素栈一行（AWEBaseElementView）的元素对象；不是元素行时返回 nil。
id DKInfoRowElement(UIView *row);

/// 左侧信息栈布局后应用外观；不是左侧栈时直接返回。由元素栈的统一布局入口调用。
void DKInfoAppearanceApplyStack(AWEElementStackView *stack);

/// 设置改变后立即刷新当前页面上的左侧信息栈。
void DKInfoAppearanceRefresh(void);

/// 输出当前可见左侧信息栈的状态，供调试探针使用。
NSString *DKInfoAppearanceStatus(void);

#ifdef __cplusplus
}
#endif

#endif /* DKInfoAppearance_h */
