//
//  DKCommentGlass.h
//  DYKiller
//
//  评论区液态玻璃提供槽位状态查询和输入栏覆盖刷新入口。
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

/// 最近接管的输入框槽位（那枚圆角胶囊）；从未接管过时为 nil。
/// 它的尺寸由抖音在常驻态与回复态之间来回改，探针据此核对玻璃有没有跟上。
UIView *DKCommentGlassCurrentField(void);

/// 最近接管的输入栏容器；从未接管过时为 nil。
/// 整个输入区（底色槽、艾特面板、表情面板）共用挂在它身上的那一块玻璃，与主面板玻璃上下拼接。
/// 探针据此核对主面板有没有正确让位、容器里的不透明底清干净没有。
UIView *DKCommentGlassCurrentInputContainer(void);

/// 在场的小表情栏（键盘输入附件，住在 UITextEffectsWindow 里）；不在屏时为 nil。
/// 它靠透出输入栏那块玻璃取得同档观感，探针据此核对底色清了没有、玻璃在不在它背后。
UIView *DKCommentGlassCurrentEmoticonPanel(void);

/// 本次会话拦下「不透明绘制优化」网关的次数。恒为 0 说明抖音没走这个网关——
/// 那就要靠探针的「残留面板底色」判断面板有没有被刷上底色。
NSUInteger DKCommentGlassRenderOptimizeBlocks(void);

/// 输入栏显隐改变后，按当前实际覆盖重新同步主面板玻璃。
void DKCommentGlassRefreshInputCoverage(UIView *container);

#ifdef __cplusplus
}
#endif

#endif /* DKCommentGlass_h */
