//
//  DKTabBarRemoval.h
//  DYKiller
//
//  底栏项目移除：按抖音 tabID 认按钮，移除状态落在抖音按钮自身的 hidden 上，
//  玻璃底栏镜像按钮时自然跟随。设置页与玻璃几何共用这里的项目表与计数。
//

#ifndef DKTabBarRemoval_h
#define DKTabBarRemoval_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 可移除项目的 tabID，按设置页顺序：朋友、商城、消息、我、拍摄。
NSArray<NSString *> *DKTabBarRemovableTabIDs(void);

/// 可移除项目的显示名；不在表里返回 nil。
NSString *DKTabBarRemovableTitle(NSString *tabID);

/// 抖音底栏按钮的 tabID（如 homepage_profile）；映射表不可用或无法识别时返回 nil。
NSString *DKTabBarButtonTabID(id button);

/// 该按钮当前是否由本功能隐藏。
BOOL DKTabBarRemovalHides(id button);

/// 已勾选移除的项目数（只算表内项目）。
NSInteger DKTabBarRemovedCount(void);

/// 按当前设置重排一次抖音底栏，玻璃底栏随之更新。
void DKTabBarRemovalRefresh(void);

#ifdef __cplusplus
}
#endif

#endif /* DKTabBarRemoval_h */
