// 底部相关栏目独立位移，由元素栈统一布局入口调用。
#ifndef DKRelatedBarOffset_h
#define DKRelatedBarOffset_h
#import <UIKit/UIKit.h>
#ifdef __cplusplus
extern "C" {
#endif
void DKRelatedBarOffsetApplyStack(UIView *stack);
NSString *DKRelatedBarOffsetStatus(void);
#ifdef __cplusplus
}
#endif
#endif
