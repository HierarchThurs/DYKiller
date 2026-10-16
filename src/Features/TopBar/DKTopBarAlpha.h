//
//  DKTopBarAlpha.h
//  DYKiller
//
//  首页顶栏透明度：一处作用于左侧栏入口、全部频道与搜索图标。
//

#ifndef DKTopBarAlpha_h
#define DKTopBarAlpha_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 顶栏透明度系数（0–1）。评论区打开时的搜索图标副本也按它淡出。
CGFloat DKTopBarAlphaFactor(void);

/// 设置改变后立即刷新已见过的顶栏容器。
void DKTopBarAlphaRefresh(void);

/// 顶栏容器与设置值的状态，一段多行文字，供探针输出。
NSString *DKTopBarAlphaStatus(void);

#ifdef __cplusplus
}
#endif

#endif /* DKTopBarAlpha_h */
