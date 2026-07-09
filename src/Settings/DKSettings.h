//
//  DKSettings.h
//  设置菜单的对外 API：功能模块用它把自己的开关注册进「抖音设置 → DYKiller」。
//  每个功能在自己的 %ctor 里注册，互不耦合，加功能不用改菜单文件。
//

#ifndef DKSettings_h
#define DKSettings_h

#import "DouyinHeaders.h"

/// 打开设置页时调用，返回一个新构建的设置项（以反映当前开关状态）。
typedef AWESettingItemModel *(^DKSettingItemBuilder)(void);

/// 把一个设置项注册到某分区。相同 header 的项归入同一分区，按注册顺序排列。
void DKSettingsRegisterItem(NSString *sectionHeader, DKSettingItemBuilder builder);

/// 生成一个开关型设置项（identifier 即 NSUserDefaults 键）。
AWESettingItemModel *DKMakeSwitch(NSString *key, NSString *title, NSString *detail);

#endif /* DKSettings_h */
