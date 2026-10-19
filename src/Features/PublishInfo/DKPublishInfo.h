//
//  DKPublishInfo.h
//  播放页文案下方的发布时间与发布地区：设置刷新与诊断入口。
//

#ifndef DKPublishInfo_h
#define DKPublishInfo_h

#import <Foundation/Foundation.h>

@class UIView;

#ifdef __cplusplus
extern "C" {
#endif

/// 设置变化后重写已显示的信息行；任意线程可调。
void DKPublishInfoRefresh(void);

/// 交互层元素栈排布后调用：按最终几何重算已接管行的标签宽度。主线程。
void DKPublishInfoApplyStack(UIView *stack);

/// 诊断：设置值与已登记时间元素的接管状态。
NSString *DKPublishInfoStatus(void);

#ifdef __cplusplus
}
#endif

#endif /* DKPublishInfo_h */
