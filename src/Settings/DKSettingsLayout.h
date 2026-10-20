//
//  DKSettingsLayout.h
//  设置页结构表：页面、分区、行序、图标与前置关系的唯一来源。
//  与 docs/settings-preview.html 脚本开头的数据段（MAIN / ICON_OF / REQUIRES / BLOCKED_BY）一一对应。
//

#ifndef DKSettingsLayout_h
#define DKSettingsLayout_h

#import <Foundation/Foundation.h>

/// 一行设置：取已登记的设置键对应的项。
@interface DKSettingsRow : NSObject
@property (nonatomic, copy, readonly) NSString *key;
@property (nonatomic, copy, readonly) NSString *icon;      // 抖音内置 svgIconImageName
@end

/// 子页入口：点进去是一个多分区设置页；没有任何可显示的行时显示空页占位。
@interface DKSettingsPage : NSObject
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *icon;
@property (nonatomic, copy, readonly) NSString *identifier;   // 入口项 identifier；玻璃守卫按它灰显
@property (nonatomic, copy, readonly) NSString *note;         // 页面顶部说明，可空
@property (nonatomic, copy, readonly) NSArray *sections;      // DKSettingsSection
@end

/// 一级页上的自定义动作入口。
typedef NS_ENUM(NSInteger, DKSettingsLinkAction) {
    DKSettingsLinkAuthor,     // 作者信息卡片
};

@interface DKSettingsLink : NSObject
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *icon;
@property (nonatomic, assign, readonly) DKSettingsLinkAction action;
@end

/// 阻断项的判定方式。
typedef NS_ENUM(NSInteger, DKSettingsBlockerMatch) {
    DKSettingsBlockerWhenOn,         // 开关为开
    DKSettingsBlockerWhenEqual,      // 单选等于 value
    DKSettingsBlockerWhenNotEqual,   // 单选不等于 value
};

/// 阻断项：条件成立时目标行灰显，reason 即灰显原因。
/// shownValue 非空时，条件成立期间该行按此值显示（开关 0 / 1、单选下标），功能按同一条件取有效值；存值不动。
@interface DKSettingsBlocker : NSObject
@property (nonatomic, copy, readonly) NSString *key;
@property (nonatomic, assign, readonly) DKSettingsBlockerMatch match;
@property (nonatomic, assign, readonly) NSInteger value;
@property (nonatomic, copy, readonly) NSString *reason;
@property (nonatomic, strong, readonly) NSNumber *shownValue;
@end

/// 分区：rows 里可以是 DKSettingsRow、DKSettingsPage、DKSettingsLink。
@interface DKSettingsSection : NSObject
@property (nonatomic, copy, readonly) NSString *header;
@property (nonatomic, copy, readonly) NSString *footer;
@property (nonatomic, copy, readonly) NSArray *rows;
@end

#ifdef __cplusplus
extern "C" {
#endif

/// DYKiller 一级页的分区。
NSArray<DKSettingsSection *> *DKSettingsLayoutMain(void);

/// 布局表里出现过的全部设置键（含子页内的），用于找出已登记却未排布的键。
NSSet<NSString *> *DKSettingsLayoutKeys(void);

/// 布局表里的全部设置键，按页面从上到下的顺序。
NSArray<NSString *> *DKSettingsLayoutOrderedKeys(void);

/// 该键所在子页的标题（一级页上的行为「DYKiller」）与行图标；不在布局表里返回 nil。
NSString *DKSettingsLayoutPageTitle(NSString *key);
NSString *DKSettingsLayoutIcon(NSString *key);

/// 该键的前置项：任一前置项未生效时该行灰显。无前置项返回空数组。
NSArray<NSString *> *DKSettingsLayoutRequires(NSString *key);

/// 该键的「任一」前置项：全部未生效时该行灰显，任一生效即可。无此类前置项返回空数组。
NSArray<NSString *> *DKSettingsLayoutRequiresAny(NSString *key);

/// 该键的阻断项，按原因展示顺序排列。任一阻断条件成立时该行灰显。无阻断项返回空数组。
NSArray<DKSettingsBlocker *> *DKSettingsLayoutBlockers(NSString *key);

#ifdef __cplusplus
}
#endif

#endif /* DKSettingsLayout_h */
