//
//  DKCommentGlass.h
//  DYKiller
//
//  评论区液态玻璃对外只暴露最近接管的面板槽位，供调试导出采集其状态。
//  玻璃层挂在槽位的最底层，探针从槽位自己推出来即可。
//

#ifndef DKCommentGlass_h
#define DKCommentGlass_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 最近接管的评论面板槽位；从未接管过时为 nil。
UIView *DKCommentGlassCurrentSlot(void);

#ifdef __cplusplus
}
#endif

#endif /* DKCommentGlass_h */
