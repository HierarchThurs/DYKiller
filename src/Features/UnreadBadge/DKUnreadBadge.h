//
//  DKUnreadBadge.h
//  DYKiller
//
//  未读红点：移除底栏按钮、首页顶栏频道、左侧栏（≡ 入口与侧边栏面板）的红点。
//

#ifndef DKUnreadBadge_h
#define DKUnreadBadge_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 三个开关与已登记红点的显隐状态，一段多行文字，供探针输出。
NSString *DKUnreadBadgeStatus(void);

#ifdef __cplusplus
}
#endif

#endif /* DKUnreadBadge_h */
