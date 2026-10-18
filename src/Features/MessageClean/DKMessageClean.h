//
//  DKMessageClean.h
//  DYKiller
//
//  消息页精简：顶栏（左侧栏、装扮商店、搜索图标、加号）与列表顶部（限时日常、好友大头像、互动消息）的显示 / 隐藏 / 移除。
//

#ifndef DKMessageClean_h
#define DKMessageClean_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 设置改变后立即刷新消息页（主线程执行）。
void DKMessageCleanRefresh(void);

/// 输出各项档位、顶栏槽位与列表顶部的当前状态，供调试探针使用。
NSString *DKMessageCleanStatus(void);

/// 顶栏部分的刷新与诊断（DKMessageCleanTopBar.xm）。
void DKMessageCleanTopBarRefresh(void);
NSString *DKMessageCleanTopBarStatus(void);

/// 列表顶部的刷新与诊断（DKMessageCleanList.xm）。
void DKMessageCleanListRefresh(void);
NSString *DKMessageCleanListStatus(void);

#ifdef __cplusplus
}
#endif

#endif /* DKMessageClean_h */
