//
//  DKProgressTime.h
//  DYKiller
//
//  显示视频时长：在进度条旁显示已播时长与总时长。
//

#ifndef DKProgressTime_h
#define DKProgressTime_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 进度条容器每轮布局后调用：按设置挂上、摆放或拆掉时长读数。由进度条容器的统一布局入口调用。
void DKProgressTimeLayoutContainer(UIView *container);

/// 时长放在进度条上方时，昵称文案与互动区两栏至少要上移的高度（pt）。
/// view 为元素栈或进度条容器；时长不在上方、或 view 所在交互层没有进度条时为 0。
CGFloat DKProgressTimeLift(UIView *view);

/// 设置与各进度条时长读数的当前状态，一段多行文字，供探针输出。
NSString *DKProgressTimeStatus(void);

#ifdef __cplusplus
}
#endif

#endif /* DKProgressTime_h */
