//
//  DKSearchOverlay.h
//  DYKiller 设置页的搜索入口：右下角玻璃圆钮、键盘上方的搜索胶囊与结果面板。
//  挂在页面 view 的最上层，页面消失时整体撤销。
//

#ifndef DKSearchOverlay_h
#define DKSearchOverlay_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 给 DYKiller 设置页挂上搜索入口；非本插件的页忽略。
void DKSearchAttach(UIViewController *page);

/// 撤销搜索入口，并撤掉为圆钮预留的底部占位。
void DKSearchDetach(UIViewController *page);

/// 按页面尺寸重算底部预留高度（让最后一行能滚到圆钮之上）。
void DKSearchUpdateInsets(UIViewController *page);

#ifdef __cplusplus
}
#endif

#endif /* DKSearchOverlay_h */
