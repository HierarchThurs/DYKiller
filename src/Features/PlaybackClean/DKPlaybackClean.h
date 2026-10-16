//
//  DKPlaybackClean.h
//  DYKiller
//
//  播放页精简：播放页元素、文案上方、昵称右侧与文案下方各元素的显示 / 隐藏 / 移除。
//

#ifndef DKPlaybackClean_h
#define DKPlaybackClean_h

#import <UIKit/UIKit.h>

@class AWEElementStackView;

#ifdef __cplusplus
extern "C" {
#endif

/// 元素栈布局前应用：行内容淡出、标签与子视图显隐、行显隐同步。由元素栈的统一布局入口调用。
void DKPlaybackCleanApplyStack(AWEElementStackView *stack);

/// 行是否由播放页精简移除（整行项为「移除」，或标签行里只剩被移除的内容）。
BOOL DKPlaybackCleanRowRemoved(UIView *row);

/// 设置改变后立即刷新当前页面上的元素栈与全屏观看入口。
void DKPlaybackCleanRefresh(void);

/// 输出各项档位与可见元素栈的逐行状态，供调试探针使用。
NSString *DKPlaybackCleanStatus(void);

#ifdef __cplusplus
}
#endif

#endif /* DKPlaybackClean_h */
