//
//  DKLongPressMenu.h
//  长按菜单：作品与评论两种长按菜单共用的菜单项目录、移除开关与宫格列数，供各 hook 与设置页使用。
//

#ifndef DKLongPressMenu_h
#define DKLongPressMenu_h

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, DKLongPressMenuKind) {
    DKLongPressMenuFeed = 0,      // 视频与图文的长按菜单
    DKLongPressMenuComment = 1,   // 评论的长按菜单
};

// 目录项字段。
static NSString *const DKLongPressMenuFieldID    = @"id";      // 菜单项标识
static NSString *const DKLongPressMenuFieldTitle = @"title";   // 首次收录时的菜单文案

#ifdef __cplusplus
extern "C" {
#endif

/// 打开过的菜单里出现过的原生菜单项，按收录顺序；只返回 id 为字符串的字典项。
NSArray<NSDictionary *> *DKLongPressMenuCatalog(DKLongPressMenuKind kind);

/// 一次菜单的原生项（按菜单顺序的 {id, title}）并入目录：新项追加在后，已有项不变；目录不变时不写。
void DKLongPressMenuRecord(DKLongPressMenuKind kind, NSArray<NSDictionary *> *entries);

/// 该菜单项的移除开关键。
NSString *DKLongPressMenuHideKey(DKLongPressMenuKind kind, NSString *itemID);

/// 该菜单项是否已勾选移除。
BOOL DKLongPressMenuHidden(DKLongPressMenuKind kind, NSString *itemID);

/// 目录中已勾选移除的项数。
NSInteger DKLongPressMenuHiddenCount(DKLongPressMenuKind kind);

/// 宫格每行个数：1（抖音原生列表）到 4。
NSInteger DKLongPressMenuColumns(DKLongPressMenuKind kind);

/// 作品长按菜单的分组换上新的菜单项后复制一份，其余属性照抄；原生行数跟随条目数时同步新条目数。
/// source 不是 AWELongPressPanelViewGroupModel 时返回 nil。
id DKFeedMenuCopyGroup(id source, NSArray *items);

/// 记下最近一次菜单的处理摘要，供诊断输出。
void DKLongPressMenuNote(DKLongPressMenuKind kind, NSString *note);

/// 输出两种菜单的设置、目录与最近一次处理摘要，供调试探针使用。
NSString *DKLongPressMenuStatus(void);

/// 作品长按菜单液态玻璃的当前状态（DKFeedMenuGlass.xm）。
NSString *DKFeedMenuGlassStatus(void);

#ifdef __cplusplus
}
#endif

#endif /* DKLongPressMenu_h */
