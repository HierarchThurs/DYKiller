//
//  DKPlaybackCleanRules.h
//  DYKiller
//
//  播放页精简的元素识别：元素栈的行、昵称右侧标签与标签元素子视图 → 设置键。只做判定，不改任何视图。
//

#ifndef DKPlaybackCleanRules_h
#define DKPlaybackCleanRules_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 元素栈行（AWEBaseElementView）的元素对象；不是元素行时返回 nil。
id DKCleanRowElement(UIView *row);

/// 向上找到视图所在的元素行；找不到返回 nil。
UIView *DKCleanRowForView(UIView *view);

/// 整行由一个设置项管理时返回该设置键，否则返回 nil。
NSString *DKCleanKeyForRow(UIView *row);

/// 是否锚点行（游戏标签、汽水音乐、付费内容等，按锚点业务号区分；含没有单独设置项的业务号）。
BOOL DKCleanIsAnchorRow(UIView *row);

/// 锚点行的业务号（templateAnchorInfo.name），供诊断使用；取不到返回 nil。
NSString *DKCleanAnchorName(UIView *row);

/// 元素是否为标签元素（其他用户推荐、好友推荐、好友分享所在的行）。
BOOL DKCleanIsTagsElement(id element);

/// 标签元素里由设置项管理的子视图。
void DKCleanEnumerateTagsElementViews(id element, void (^block)(UIView *view, NSString *key));

/// 作者元素当前显示的昵称右侧标签；不是作者元素时不回调。
void DKCleanEnumerateAuthorTags(id element, void (^block)(UIView *tagView, NSString *key));

/// 标签管理器（AWEVideoTagsPriorityManager）当前显示的标签。
void DKCleanEnumerateManagerTags(id manager, void (^block)(UIView *tagView, NSString *key));

#ifdef __cplusplus
}
#endif

#endif /* DKPlaybackCleanRules_h */
