//
//  DKSettingsLayout.h
//  设置页结构表：页面、分区、行序、图标与前置关系的唯一来源。
//  与 docs/settings-preview.html 脚本开头的数据段（MAIN / ICON_OF / REQUIRES）一一对应。
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

/// 该键的前置项：任一前置项未生效时该行灰显。无前置项返回空数组。
NSArray<NSString *> *DKSettingsLayoutRequires(NSString *key);

#ifdef __cplusplus
}
#endif

#endif /* DKSettingsLayout_h */
