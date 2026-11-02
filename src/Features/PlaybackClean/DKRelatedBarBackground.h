// 底部相关栏目背景透明：由元素栈统一布局入口调用，设置变化经 DKPlaybackCleanRefresh 重排后生效。
#ifndef DKRelatedBarBackground_h
#define DKRelatedBarBackground_h
#import <UIKit/UIKit.h>
#ifdef __cplusplus
extern "C" {
#endif
void DKRelatedBarBackgroundApplyStack(UIView *stack);
/// 单行的接管结果与残留底色，供调试探针使用。
NSString *DKRelatedBarBackgroundRowStatus(UIView *row);
#ifdef __cplusplus
}
#endif
#endif
