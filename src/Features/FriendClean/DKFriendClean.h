//
//  DKFriendClean.h
//  DYKiller
//
//  朋友页精简：顶栏与作品元素的显示 / 隐藏 / 移除，以及朋友推荐卡片过滤。
//  作品的行与昵称右侧标签由播放页精简框架按设置键处理（DKPlaybackCleanRules.m）。
//

#ifndef DKFriendClean_h
#define DKFriendClean_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 设置改变后立即刷新（主线程执行）。
void DKFriendCleanRefresh(void);

/// 输出各项档位与已见视图的状态，供调试探针使用。
NSString *DKFriendCleanStatus(void);

/// 顶栏部分的刷新与诊断（DKFriendCleanTopBar.xm）。
void DKFriendCleanTopBarRefresh(void);
NSString *DKFriendCleanTopBarStatus(void);

/// 私信图标的刷新与诊断（DKFriendCleanSendMessage.xm）。
void DKFriendCleanSendMessageRefresh(void);
NSString *DKFriendCleanSendMessageStatus(void);

/// 朋友推荐卡片的过滤开关与计数（DKFriendRecommendCardFilter.xm）。
NSString *DKFriendRecommendCardStatus(void);

#ifdef __cplusplus
}
#endif

#endif /* DKFriendClean_h */
