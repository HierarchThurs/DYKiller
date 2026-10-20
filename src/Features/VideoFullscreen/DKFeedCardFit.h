//
//  DKFeedCardFit.h
//  DYKiller
//
//  视频全屏下的非视频条目（Lynx 特殊卡、音乐卡、长文章）：内容按视频表撑高前的高度排版，背景铺满。
//
//  特殊卡收短根视图，音乐卡收短 Lynx 容器；背景条挂在仍为满高的宿主中。
//
#ifndef DKFeedCardFit_h
#define DKFeedCardFit_h

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSUInteger, DKFeedCardType) {
    DKFeedCardTypeSpecial,
    DKFeedCardTypeMusic,
    DKFeedCardTypeArticle,
    DKFeedCardTypeCount
};

#ifdef __cplusplus
extern "C" {
#endif

/// 宿主实际越过当前行原生安全底边的高度；全屏关闭或不在已撑高的视频表中时为 0。
CGFloat DKFeedCardInset(UIView *view);

/// 把 container 与上层视图（父视图至所在 cell）之间的底边约束收短 inset，返回是否已接管；inset 为 0 时还原。缺失时返回 NO。
BOOL DKFeedCardFitContainer(UIView *container, CGFloat inset, DKFeedCardType type);

/// 当前底边约束是否由本功能接管。
BOOL DKFeedCardContainerIsFitted(UIView *container);

/// 在 host 底部维持 inset 高的背景条（不接收触摸，位于最上层）；inset 为 0 时移除。
void DKFeedCardSyncBackdrop(UIView *host, CGFloat inset, DKFeedCardType type);

/// 条目内容可能变化后安排背景条取样：合并连续请求，并在稍后补一次，覆盖晚到的图片与 Lynx 渲染。
void DKFeedCardRequestBackdropSample(UIView *host);

/// 视频全屏关闭时立即还原全部接管过的约束并移除背景条。
void DKFeedCardRestore(void);

/// 各类条目的收短与背景条统计，供调试探针使用。
NSString *DKFeedCardStats(void);

#ifdef __cplusplus
}
#endif

#endif /* DKFeedCardFit_h */
