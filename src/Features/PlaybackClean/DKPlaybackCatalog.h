// 播放页昵称上方标签、底部相关栏目的类型目录：分组、稳定身份、首次原文、用户改名与独立档位。
#ifndef DKPlaybackCatalog_h
#define DKPlaybackCatalog_h

#import <UIKit/UIKit.h>
#import "DKUtils.h"

typedef NS_ENUM(NSUInteger, DKPlaybackCatalogKind) {
    DKPlaybackCatalogAnchors,
    DKPlaybackCatalogBottomBars,
};

/// 已收录项的分组：抖音标签（锚点族）、广告卡片（Lynx 推广卡片）。
typedef NS_ENUM(NSUInteger, DKPlaybackCatalogGroup) {
    DKPlaybackCatalogGroupLabel = 0,
    DKPlaybackCatalogGroupCard = 1,
};

#ifdef __cplusplus
extern "C" {
#endif

/// 区域统一档位键（0 显示 / 1 隐藏 / 2 移除）与子页入口键。
NSString *DKPlaybackCatalogMasterKey(DKPlaybackCatalogKind kind);
NSString *DKPlaybackCatalogPageKey(DKPlaybackCatalogKind kind);
NSString *DKPlaybackCatalogRenamePageKey(DKPlaybackCatalogKind kind);
/// 逐项档位与自定义名称的键前缀。
NSString *DKPlaybackCatalogModePrefix(DKPlaybackCatalogKind kind);
NSString *DKPlaybackCatalogNamePrefix(DKPlaybackCatalogKind kind);
/// 本机目录的落盘键（不进备份）。
NSString *DKPlaybackCatalogStorageKey(DKPlaybackCatalogKind kind);

/// 已收录项：id / raw（首次原文）/ legacy（旧设置键，可无）/ group（分组序号）。
NSArray<NSDictionary *> *DKPlaybackCatalogEntries(DKPlaybackCatalogKind kind);
/// 分组描述：group / title / icon，按展示顺序；标题为空表示该区域只有一区，不显示分区标题。
NSArray<NSDictionary *> *DKPlaybackCatalogGroups(DKPlaybackCatalogKind kind);
NSUInteger DKPlaybackCatalogGroupOf(NSDictionary *entry);
/// 旧版逐项设置键，按界面顺序；用于备份声明与统一项联动。
NSArray<NSString *> *DKPlaybackCatalogLegacyKeys(DKPlaybackCatalogKind kind);
/// 旧设置键对应的语义名（旧界面文案）。
NSString *DKPlaybackCatalogLegacyTitle(NSString *key);
/// 逐项档位键：已登记旧键的类型沿用旧键，其余用「前缀 + 编码后的身份」。
NSString *DKPlaybackCatalogModeKey(DKPlaybackCatalogKind kind, NSString *identifier);
DKDisplayMode DKPlaybackCatalogItemMode(DKPlaybackCatalogKind kind, NSString *identifier);

/// 界面标题：用户改名 > 旧设置语义名 > 首次原文。
NSString *DKPlaybackCatalogTitle(DKPlaybackCatalogKind kind, NSDictionary *entry);
/// 用户改名（空串表示恢复原文）。
NSString *DKPlaybackCatalogNameKey(DKPlaybackCatalogKind kind, NSString *identifier);
NSString *DKPlaybackCatalogCustomName(DKPlaybackCatalogKind kind, NSString *identifier);
void DKPlaybackCatalogSetCustomName(DKPlaybackCatalogKind kind, NSString *identifier, NSString *name);

/// 元素栈是否为所属播放交互控制器的底部容器（底部相关栏目所在的栈）。
BOOL DKPlaybackCatalogStackIsBottom(UIView *stack);

/// 对应区域统一档位优先；其他区域返回 NO，由原有精简规则处理。
BOOL DKPlaybackCatalogRowMode(UIView *row, DKDisplayMode *mode);

/// 仅在所属作品正在展示、原生行可见、且统一档位为显示时登记；标题为空的身份不登记。
void DKPlaybackCatalogRecordRow(UIView *row);
void DKPlaybackCatalogRecordController(UIViewController *controller);

NSString *DKPlaybackCatalogStatus(void);

#ifdef __cplusplus
}
#endif
#endif
