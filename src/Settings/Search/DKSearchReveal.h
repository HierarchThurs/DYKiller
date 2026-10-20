//
//  DKSearchReveal.h
//  搜索结果的导航与定位：页面路径记录、跨页补齐、滚动到目标行并短暂渐变提示。
//

#ifndef DKSearchReveal_h
#define DKSearchReveal_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class DKSearchEntry;

#ifdef __cplusplus
extern "C" {
#endif

/// 记下页面的布局路径（根 → 叶的子页 identifier）。一级页传空数组，未知路径传 nil。
void DKSearchSetPagePath(UIViewController *page, NSArray<NSString *> *path);

/// 页面的布局路径；未记录返回 nil。
NSArray<NSString *> *DKSearchPagePath(UIViewController *page);

/// 页面出现后要定位的行（跨页跳转时由前一个页面挂上）。
void DKSearchMarkPendingReveal(UIViewController *page, NSString *identifier);

/// 消费待定位标记：滚动到该行并闪现。页面 viewDidAppear 时调用。
void DKSearchConsumePendingReveal(UIViewController *page);

/// 打开一条搜索结果：当前页就地定位，否则补齐页面路径后定位。
void DKSearchRevealTarget(UIViewController *from, DKSearchEntry *entry);

#ifdef __cplusplus
}
#endif

#endif /* DKSearchReveal_h */
