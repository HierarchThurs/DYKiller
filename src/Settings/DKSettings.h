//
//  DKSettings.h
//  设置菜单的对外 API：功能按设置键登记自己的那一行（标题、取值、交互）。
//  这一行在哪个子页、哪个分区、排第几、用什么图标、依赖哪个前置项，统一由 DKSettingsLayout.m 决定。
//

#ifndef DKSettings_h
#define DKSettings_h

#import "DouyinHeaders.h"

/// 每次建页时调用，返回一个新构建的设置项（以反映当前状态）。返回项的 identifier 应等于登记的键。
typedef AWESettingItemModel *(^DKSettingItemBuilder)(void);

// 实现分散在 .xm（ObjC++）与 .m（ObjC）两种编译单元里，需统一为 C 链接以正确链接。
#ifdef __cplusplus
extern "C" {
#endif

/// 按设置键登记一行。键未写进布局表时，这一行出现在一级页末尾的「未归类」分区。
void DKSettingsRegister(NSString *key, DKSettingItemBuilder builder);

/// 给设置项挂上 ⓘ 说明文案，返回 item 本身，便于直接写在 builder 的 return 里。
AWESettingItemModel *DKSettingsWithInfo(AWESettingItemModel *item, NSString *info);

/// 开关项（identifier 即 NSUserDefaults 键）。detail 作为 ⓘ 说明，行内不显示。
AWESettingItemModel *DKMakeSwitch(NSString *key, NSString *title, NSString *detail);

/// 单选项：点击弹底部列表，选中项的下标写进 NSUserDefaults（整数），options[0] 对应 0。
/// 当前选中项显示在行右侧。
AWESettingItemModel *DKMakeChoice(NSString *key, NSString *title, NSArray<NSString *> *options);

/// 液态玻璃材质单选：关闭 / 模糊玻璃 / 清透玻璃。存成 key（开启）与 clearKey（清透）两个 BOOL，
/// 前置联动按 key 判定。onChange 在选定并写入后调用，可空。
AWESettingItemModel *DKMakeGlassChoice(NSString *key, NSString *clearKey, NSString *title, void (^onChange)(void));

/// 点击后弹出 0–100 滑条。未写入过时显示 defaultPercent。onChange 可空。
AWESettingItemModel *DKMakePercentSlider(NSString *key, NSString *title, NSString *message,
                                         NSInteger defaultPercent, void (^onChange)(NSInteger percent));

/// 动作项：点击时把该项与当前设置页交给 onTap，界面由功能自己弹。
/// 状态不落在 NSUserDefaults 上（key 只作 identifier）的功能用它。
AWESettingItemModel *DKMakeAction(NSString *key, NSString *title, NSString *detail,
                                  void (^onTap)(AWESettingItemModel *item, UIViewController *presenter));

/// 重算当前设置页的联动灰显并刷新整页。改完某项的 detail 或写入取值后调用。
void DKSettingsReloadCurrentPage(void);

/// 从 presenter 所在导航栈推入一个单分区子设置页，items 为空时不推入。
/// 返回上一页时，上一页重新接管弹窗并刷新。
void DKSettingsPushPage(UIViewController *presenter, NSString *title, NSString *sectionHeader,
                        NSArray<AWESettingItemModel *> *items);

#ifdef __cplusplus
}
#endif

#endif /* DKSettings_h */
