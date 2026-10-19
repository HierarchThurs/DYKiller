//
//  DKProfileClean.h
//  DYKiller
//
//  个人主页精简：顶栏、头像与昵称、数据与按钮、发布引导横幅的显示 / 隐藏 / 移除，以及分页移除。
//  只作用于自己的主页。
//

#ifndef DKProfileClean_h
#define DKProfileClean_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 输出各项档位与已见对象的状态，供调试探针使用。
NSString *DKProfileCleanStatus(void);

/// 各部分的即时刷新（主线程调用）与诊断。
/// 顶栏四项（DKProfileCleanTopBar.xm）。
void DKProfileCleanTopBarRefresh(void);
NSString *DKProfileCleanTopBarStatus(void);

/// 头部分区：数据与按钮、功能区、发布引导横幅（DKProfileCleanHeader.xm）。
void DKProfileCleanHeaderRefresh(void);
NSString *DKProfileCleanHeaderStatus(void);

/// 头像加号、切换账号箭头、胶囊行（DKProfileCleanNameArea.xm）。
void DKProfileCleanNameAreaRefresh(void);
NSString *DKProfileCleanNameAreaStatus(void);

/// 分页移除（DKProfileCleanTabs.xm）。
void DKProfileCleanTabsRefresh(void);
NSString *DKProfileCleanTabsStatus(void);

/// 功能区末尾的 DYKiller 设置入口（DKProfileSettingsEntry.xm，设置项在「插件工具」）。可在任意线程调用。
void DKProfileSettingsEntryRefresh(void);
NSString *DKProfileSettingsEntryStatus(void);

#ifdef __cplusplus
}
#endif

#endif /* DKProfileClean_h */
