//
//  DKSettings.h
//  设置菜单的对外 API：功能按设置键登记自己的那一行（标题、取值、交互）。
//  这一行在哪个子页、哪个分区、排第几、用什么图标、依赖哪个前置项，统一由 DKSettingsLayout.m 决定。
//  每一行存了什么由项上的值声明说明，备份工具据此导出与恢复：标准工厂建出的项自带声明，
//  DKMakeAction 自管存储的项用 DKSettingsWithValues 声明，或用 DKSettingsWithoutBackup 排除。
//

#ifndef DKSettings_h
#define DKSettings_h

#import "DouyinHeaders.h"
#import "DKSettingsValue.h"

/// 每次建页时调用，返回一个新构建的设置项（以反映当前状态）。返回项的 identifier 应等于登记的键。
/// 备份工具也会调用它来收集值声明，所以 builder 只建项，不改全局状态。
typedef AWESettingItemModel *(^DKSettingItemBuilder)(void);

/// 颜色设置的预览样例，色板与十六进制 / 渐变输入页共用。alpha 在打开编辑页时求值，未给为 1；
/// alphaNote 由该不透明度给出说明文字（如「抖音原生不透明度 62%（只读）」），未给不显示。
@interface DKColorSample : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) CGFloat (^alpha)(void);
@property (nonatomic, copy) NSString *(^alphaNote)(CGFloat alpha);
@end

// 实现分散在 .xm（ObjC++）与 .m（ObjC）两种编译单元里，需统一为 C 链接以正确链接。
#ifdef __cplusplus
extern "C" {
#endif

/// 按设置键登记一行。键未写进布局表时，这一行出现在一级页末尾的「未归类」分区。
void DKSettingsRegister(NSString *key, DKSettingItemBuilder builder);

/// 给设置项挂上 ⓘ 说明文案，返回 item 本身，便于直接写在 builder 的 return 里。
AWESettingItemModel *DKSettingsWithInfo(AWESettingItemModel *item, NSString *info);

/// 声明项的落盘值。describe 把规范值转成恢复预览里的文案，可空（按值的种类给默认文案）。
AWESettingItemModel *DKSettingsWithValues(AWESettingItemModel *item, NSArray<DKSettingsValue *> *values,
                                          DKSettingsDescribe describe);

/// 值变化后的刷新：界面上改值写入后、恢复写入后都会调用，在主线程。
AWESettingItemModel *DKSettingsOnChange(AWESettingItemModel *item, dispatch_block_t onChange);

/// 不进备份的项：纯动作，或按设备临时开关的项（调试工具）。
AWESettingItemModel *DKSettingsWithoutBackup(AWESettingItemModel *item);

/// 改动后要重启抖音才完全生效：恢复结果里单独点名。
AWESettingItemModel *DKSettingsNeedsRestart(AWESettingItemModel *item);

/// 破坏性动作：标题与图标显示为红色。
AWESettingItemModel *DKSettingsMarkDestructive(AWESettingItemModel *item);

/// 更新项自身的可用态（builder 给的那一层），并按联动锁与玻璃锁重算、刷新这一行。
void DKSettingsSetItemEnabled(AWESettingItemModel *item, BOOL enabled);

/// 开关项（identifier 即 NSUserDefaults 键）。detail 作为 ⓘ 说明，行内不显示。
AWESettingItemModel *DKMakeSwitch(NSString *key, NSString *title, NSString *detail);

/// 打开前须确认的开关：用户打开时先交给 confirm，confirm 调用 commit 才写入并触发 onChange；
/// 不调用即保持关闭。关闭不经确认。
AWESettingItemModel *DKMakeSwitchConfirmingOn(NSString *key, NSString *title, NSString *detail,
                                              void (^confirm)(UIViewController *presenter, dispatch_block_t commit));

/// 单选项：点击弹底部列表，选中项的下标写进 NSUserDefaults（整数），options[0] 对应 0。
/// 当前选中项显示在行右侧。
AWESettingItemModel *DKMakeChoice(NSString *key, NSString *title, NSArray<NSString *> *options);

/// 单选项：选中某项后先交给 confirm，confirm 调用 commit 才写入、刷新并触发 onChange；不调用即保持原值。
/// commit 可以异步调用（如先选图，成功后再提交），与页面是否还在无关。
AWESettingItemModel *DKMakeChoiceConfirm(NSString *key, NSString *title, NSArray<NSString *> *options,
                                         void (^confirm)(NSInteger index, UIViewController *presenter, dispatch_block_t commit));

/// 单行文字：点击弹输入框（取消 / 恢复默认 / 保存），行右侧显示当前文字或「默认」。
/// placeholder 是留空时显示的默认文字；maxWidth 按 DKSettingsTextWidth 计。值自动声明为 String，空串即未设置。
AWESettingItemModel *DKMakeTextInput(NSString *key, NSString *title, NSString *placeholder, NSUInteger maxWidth);

/// 同 DKMakeTextInput，另指定输入弹窗的说明 message、留空时行右侧显示的 emptyDetail 与清空按钮标题 resetTitle。
AWESettingItemModel *DKMakeTextInputWithPrompt(NSString *key, NSString *title, NSString *placeholder, NSUInteger maxWidth,
                                               NSString *message, NSString *emptyDetail, NSString *resetTitle);

/// 液态玻璃材质单选：关闭 / 模糊玻璃 / 清透玻璃。存成 key（开启）与 clearKey（清透）两个 BOOL，
/// 前置联动按 key 判定。onChange 在选定并写入后、以及恢复写入后调用，可空。
AWESettingItemModel *DKMakeGlassChoice(NSString *key, NSString *clearKey, NSString *title, void (^onChange)(void));

/// 点击后弹出 0–100 滑条。未写入过时显示 defaultPercent。onChange 在拖动写入时与恢复写入后调用，可空。
AWESettingItemModel *DKMakePercentSlider(NSString *key, NSString *title, NSString *message,
                                         NSInteger defaultPercent, void (^onChange)(NSInteger percent));

/// 点击后弹出有界数值滑条。值按 minimum–maximum 保存，详情与读数显示「值 + unit」（如 @" pt"）。
AWESettingItemModel *DKMakeUnitSlider(NSString *key, NSString *title, NSString *message,
                                      NSInteger minimum, NSInteger maximum, NSInteger defaultValue,
                                      NSString *unit, void (^onChange)(NSInteger value));

/// 点击后弹出有界百分比滑条。值按 minimum–maximum 保存，详情显示百分比；用于缩放等非 0–100 的范围。
AWESettingItemModel *DKMakeRangeSlider(NSString *key, NSString *title, NSString *message,
                                       NSInteger minimum, NSInteger maximum, NSInteger defaultValue,
                                       void (^onChange)(NSInteger value));

/// 缩放与位移类滑条：范围、默认值与单位取自 DKAdjustRange 登记表，随「扩展所有缩放与位移」放宽；
/// 说明末尾附当前可调范围。落盘值按扩展范围声明。key 必须已在登记表中。
AWESettingItemModel *DKMakeAdjustSlider(NSString *key, NSString *title, NSString *message,
                                        void (^onChange)(NSInteger value));

/// 动作项：点击时把该项与当前设置页交给 onTap，界面由功能自己弹。
/// 状态不落在 NSUserDefaults 上（key 只作 identifier）的功能用它；须声明值或排除备份。
AWESettingItemModel *DKMakeAction(NSString *key, NSString *title, NSString *detail,
                                  void (^onTap)(AWESettingItemModel *item, UIViewController *presenter));

/// 网页入口：点击用系统浏览器打开 url，不进备份。
AWESettingItemModel *DKMakeWebLink(NSString *key, NSString *title, NSString *url);

/// 固定颜色：点击打开色谱 / RGB 选色页，存为 #RRGGBB。值自动声明为单色。
AWESettingItemModel *DKMakeColorPicker(NSString *key, NSString *title, DKColorSample *sample);

/// 固定颜色的十六进制入口：identifier 只作行标识，读写 colorKey 的存值，不进备份。
AWESettingItemModel *DKMakeColorHexInput(NSString *identifier, NSString *colorKey, NSString *title, DKColorSample *sample);

/// 渐变颜色：2–8 个十六进制颜色，英文逗号分隔。值自动声明为渐变。
AWESettingItemModel *DKMakeColorGradientInput(NSString *key, NSString *title, DKColorSample *sample);

/// 重算当前设置页的联动灰显并刷新整页。改完某项的 detail 或写入取值后调用。
void DKSettingsReloadCurrentPage(void);

/// 建一个卡片分区；header、footer 可空。
AWESettingSectionModel *DKSettingsMakeSection(NSString *header, NSString *footer, NSArray<AWESettingItemModel *> *items);

/// 从 presenter 所在导航栈推入一个多分区子设置页，各项按 DKSettingsPrepareItem 收尾（保留项上已设的图标）。
/// sections 为空时不推入；返回上一页时，上一页重新接管弹窗并刷新。
void DKSettingsPushSections(UIViewController *presenter, NSString *title, NSArray<AWESettingSectionModel *> *sections);

/// 同 DKSettingsPushSections，另在第一个分区之上显示一段说明文字（抖音页脚样式，按页面宽度完整换行）；note 为空时不显示。
void DKSettingsPushNotedSections(UIViewController *presenter, NSString *title, NSString *note,
                                 NSArray<AWESettingSectionModel *> *sections);

/// 从 presenter 所在导航栈推入一个单分区子设置页，items 为空时不推入。
/// 返回上一页时，上一页重新接管弹窗并刷新。
void DKSettingsPushPage(UIViewController *presenter, NSString *title, NSString *sectionHeader,
                        NSArray<AWESettingItemModel *> *items);

/// 从 presenter 所在导航栈推入 DYKiller 设置一级页（推入时隐藏底栏）；presenter 不在导航栈里时不推入。
void DKSettingsOpenMain(UIViewController *presenter);

#ifdef __cplusplus
}
#endif

#endif /* DKSettings_h */
