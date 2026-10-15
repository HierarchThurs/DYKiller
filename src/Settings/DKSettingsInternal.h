//
//  DKSettingsInternal.h
//  设置页内部接口：注册表、建页收尾、联动锁、ⓘ 文案与弹层。仅供 src/Settings 使用。
//

#ifndef DKSettingsInternal_h
#define DKSettingsInternal_h

#import "DKSettings.h"

#ifdef __cplusplus
extern "C" {
#endif

#pragma mark - 注册表（DKSettingsMenu.xm）

/// 用已登记的 builder 新建该键的项；未登记返回 nil。
AWESettingItemModel *DKSettingsBuildItem(NSString *key);

/// 当前显示的 DYKiller 设置页，弹窗与刷新都以它为宿主。
UIViewController *DKSettingsCurrentPage(void);

/// 设置值改变后调用：重算当前页的联动锁，只刷新可用态变化的行，被点的开关保留切换动画。
void DKSettingsValuesChanged(void);

#pragma mark - 项标记（DKSettingsItems.xm）

/// 项上挂的 ⓘ 说明；没有返回 nil。
NSString *DKSettingsItemInfo(AWESettingItemModel *item);

/// 是否单选项（联动原因写「需先设置」而非「需先开启」）。
BOOL DKSettingsItemIsChoice(AWESettingItemModel *item);

#pragma mark - 收尾与联动锁（DKSettingsLock.m）

/// 建页收尾：卡片配色、图标、记下 builder 给的可用态，并按系统版本上玻璃锁。DYKiller 页面的每一项都要过一遍。
void DKSettingsPrepareItem(AWESettingItemModel *item, NSString *icon);

/// 是否经过 DKSettingsPrepareItem 的项（cell 与页面 hook 只处理这类项）。
BOOL DKSettingsIsOwnItem(AWESettingItemModel *item);

/// 按前置关系重算各项可用态：可用 = builder 给的可用态 && 未被玻璃锁 && 前置项都已生效。返回可用态变化的项。
NSArray<AWESettingItemModel *> *DKSettingsApplyLocks(NSArray *sections);

/// 被联动锁时的原因，如「需先开启「悬浮玻璃底栏」」；未被联动锁返回 nil。
NSString *DKSettingsLockReason(AWESettingItemModel *item);

#pragma mark - 弹层（DKSettingsPopup.m）

/// 在 source 旁弹说明气泡。点气泡无反应；点外部只收起气泡，这一下不传给下面的控件。
void DKSettingsShowTip(UIView *source, NSString *text);

/// 弹作者信息卡片，host 用来取窗口与深浅色。
void DKSettingsShowAuthorCard(UIView *host);

#ifdef __cplusplus
}
#endif

#endif /* DKSettingsInternal_h */
