//
//  DKFeedVideoFullscreen.h
//  DYKiller
//
//  首页/朋友页全屏对外暴露两项：作用域判定（供进度条黑边等共用逻辑复用），
//  以及 HUD 钉位的命中统计（调试导出用）。
//

#ifndef DKFeedVideoFullscreen_h
#define DKFeedVideoFullscreen_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 该视图是否位于一条已被撑高的 feed 内（即首页/朋友页全屏正在生效）。
BOOL DKFeedFullscreenActiveForView(UIView *view);

/// HUD 钉位命中统计的可读文本。
NSString *DKFeedFullscreenStats(void);

#ifdef __cplusplus
}
#endif

#endif /* DKFeedVideoFullscreen_h */
