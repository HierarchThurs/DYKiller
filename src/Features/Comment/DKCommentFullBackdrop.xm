//
//  DKCommentFullBackdrop.xm
//  评论区放大到全屏后，让玻璃背后仍然是视频那一页。
//
//  实测（beta11 五份导出）：全屏是 push 一个 AWECommentFullScreenContainerViewController，
//  push 完成后导航把上一页的 view 从 UIViewControllerWrapperView 里摘掉——那一页的 VC 仍在导航栈
//  里、view 对象也还活着（frame 仍是满屏），只是 superview 为 nil；再加上全屏容器自己的 view 是
//  不透明黑，于是玻璃背后什么都没有。
//
//  做法是把那一页的 view 放回导航自己的转场舞台、垫在本页 wrapper 之下——那一页本来就是这个导航
//  控制器的子控制器，这正是 UIKit 在 pop 时做的事。与 beta6 崩掉的做法是两回事：那次是把它插进
//  全屏容器（一个与它没有包含关系的 VC）的层级里，触发
//  -[UIView _associatedViewControllerForwardsAppearanceCallbacks:performHierarchyCheck:] 抛异常。
//
//  背后只有画面、没有文案 / 昵称 / 点赞栏，是抖音自己在评论态就把 HUD 藏了，本文件不介入。
//
//  另一半是关掉内嵌画中画：视频还在播时进全屏评论区，抖音原生会把视频交给
//  AWEDPlayerPiPWindow（windowLevel 2000）缩成右上角小窗，垫回的这一页就只剩静帧。
//  关掉之后视频留在 feed 页原地继续播，全屏与半屏的视频行为完全一致；随之要自己接上
//  「播完再放一遍」——原生那一环挂在画中画播放器上，见文件末尾的循环补播。
//

#import "DouyinHeaders.h"
#import "DKVideoFullscreen.h"

#import <objc/runtime.h>

static char kDKBackdropPageKey;   // 全屏容器 → 垫回去的那一页的 view
static char kDKPanelColorKey;     // 全屏容器 view → 原底色（NSNull 表示原本就是 nil）

static NSUInteger gPiPGateHits = 0;
static NSUInteger gLoopResumeHits = 0;
static NSUInteger gPauseHits = 0;

// 最近一次补播的现场读数。
static NSString *gLastResumeTrace = nil;

// 在屏的全屏容器。用弱引用而不是计数：交互式返回中途取消会再发一次 viewDidAppear:
// 而没有配对的 viewWillDisappear:，计数会一去不回。
static __weak UIViewController *gFullPanel = nil;

NSString *DKCommentPiPGateStats(void) {
    return [NSString stringWithFormat:@"内嵌画中画闸门已关=%lu 次", (unsigned long)gPiPGateHits];
}

NSString *DKCommentLoopResumeStats(void) {
    return [NSString stringWithFormat:@"全屏评论区补播=%lu 次  期间主播放器 pause=%lu 次  最近一次: %@",
            (unsigned long)gLoopResumeHits, (unsigned long)gPauseHits,
            gLastResumeTrace ?: @"(还没发生过)"];
}

BOOL DKCommentFullPanelOnScreen(void) {
    return gFullPanel != nil;
}

// 导航栈里本页下面那一页；本页不在栈里或已是栈底时返回 nil。
static UIViewController *DKPageBelowPanel(UIViewController *panel) {
    NSArray<UIViewController *> *stack = panel.navigationController.viewControllers;
    NSUInteger index = [stack indexOfObject:panel];
    return (index == NSNotFound || index == 0) ? nil : stack[index - 1];
}

static void DKAttachBackdrop(UIViewController *panel) {
    if (!DKCommentFreezeOn() || objc_getAssociatedObject(panel, &kDKBackdropPageKey)) return;

    UIView *panelView = panel.viewIfLoaded;
    UIView *wrapper = panelView.superview;   // 承载本页的 wrapper
    UIView *stage = wrapper.superview;       // 导航的转场舞台
    UIView *page = DKPageBelowPanel(panel).viewIfLoaded;
    // 只接管「被导航摘下来的」那一页：还在栈里、view 还活着、但已不在任何层级。
    if (!stage || !page || page.superview) return;

    [stage insertSubview:page belowSubview:wrapper];
    objc_setAssociatedObject(panel, &kDKBackdropPageKey, page,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 垫上了才清底色：清了却没垫上只会更黑。
    objc_setAssociatedObject(panelView, &kDKPanelColorKey,
                             panelView.backgroundColor ?: (id)[NSNull null],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    panelView.backgroundColor = UIColor.clearColor;
    panelView.opaque = NO;
}

static void DKDetachBackdrop(UIViewController *panel) {
    UIView *page = objc_getAssociatedObject(panel, &kDKBackdropPageKey);
    if (!page) return;

    UIView *panelView = panel.viewIfLoaded;
    id baseline = objc_getAssociatedObject(panelView, &kDKPanelColorKey);
    if (baseline) {
        UIColor *color = (baseline == [NSNull null]) ? nil : (UIColor *)baseline;
        panelView.backgroundColor = color;
        // opaque 由记下的底色推出来，不额外留一份状态。
        panelView.opaque = color && CGColorGetAlpha(color.CGColor) >= 0.99;
        objc_setAssociatedObject(panelView, &kDKPanelColorKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    [page removeFromSuperview];
    objc_setAssociatedObject(panel, &kDKBackdropPageKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook AWECommentFullScreenContainerViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // 转场已结束，此时插入不干扰动画；交互式返回中途取消会再走一次，与下面的摘除天然对称。
    gFullPanel = self;
    DKAttachBackdrop(self);
    // 全屏态弹幕该回到抖音原生的隐藏；标记先于同步，判据才是新状态。
    DKCommentDanmakuSyncForFullPanel();
}

- (void)viewWillDisappear:(BOOL)animated {
    // 必须早于 %orig：pop 之后 UIKit 会把那一页放回它自己的 wrapper，得先还回原状。
    gFullPanel = nil;
    DKDetachBackdrop(self);
    DKCommentDanmakuSyncForFullPanel();
    %orig;
}

%end

// 内嵌画中画的唯一闸门，纯 BOOL 查询。返回 NO 不会留下半进入的状态：进入、显示、退出、
// 为交接而暂停 / 恢复主播放器，全都不会发生——主播放器因此留在 feed 页继续播。
//
// 不去跟小窗的几何缠斗：那条路要在它进 PiP 窗口之前就判出「它将来属于哪个窗口」，
// 而那一刻 view.window 还是 nil（beta13 实测两份导出一对一错，就是这个时序洞）。
%hook AWEPlayInteractionCommentPanelController

- (BOOL)enableShowInnerPiPWhenFullScreen {
    if (!DKCommentFreezeOn()) return %orig;

    gPiPGateHits++;
    return NO;
}

%end

// 闸门关掉之后剩下的那一环：谁负责「播完之后」。
//
// 抖音原生进全屏评论区时会把主播放器暂停（tryToPauseByInnerPlayer：闸门开 + 已进画中画 +
// 正在播 → pause），画面交给内嵌画中画那个独立播放器，循环由它负责，主播放器根本走不到播完。
// 闸门关掉后主播放器留在原地继续播，于是走到了原生不存在的那一步，而全屏评论区的状态机里
// 没有这一支，视频就停在最后一帧。半屏不进这条流程，所以半屏播完照常重播。
//
// 用 play 而不是 replay：`-[AWEDPlayerPlayControlContainer replay]` 头一件事就是重发
// `AWEDPlayerCoreEvent.PlayerWillStartNextLoopEvent`——正是刚被否掉的那个事件，等于把同一次
// 表决再走一遍（beta16 实测补播 2 次、画面纹丝不动）。play 走的是 `_play:` → `play:` 那条
// 真正的播放入口。
%hook AWEPlayVideoViewController

- (void)playerWillLoopPlaying:(id)player {
    %orig;
    if (!DKCommentFreezeOn() || !DKCommentFullPanelOnScreen()) return;

    AWEDPlayerViewController_Merge *merge = (AWEDPlayerViewController_Merge *)self.parentViewController;
    if (![merge isKindOfClass:%c(AWEDPlayerViewController_Merge)]) return;

    // 落到下一轮 runloop，才排在抖音自己那串同步监听之后；它自己续上了就不插手。
    __weak AWEDPlayerViewController_Merge *weakMerge = merge;
    dispatch_async(dispatch_get_main_queue(), ^{
        AWEDPlayerViewController_Merge *strongMerge = weakMerge;
        if (!strongMerge || !DKCommentFullPanelOnScreen() || [strongMerge isPlaying]) return;

        gLoopResumeHits++;
        // 播放入口 `_play:` / `play:` 都先问 videoShouldPlay（第一个判据就是 shouldPreventPlay）。
        // 这两个值直接读就有，不必为了拿它们挂钩子——beta17 曾在 videoShouldPlay 上挂过一层
        // 放行，实测原始答复恒为 YES，那层从未改变过任何一次结果，已删。
        BOOL prevent = [strongMerge shouldPreventPlay];
        BOOL shouldPlay = [strongMerge videoShouldPlay];
        [strongMerge play];

        // 播没播起来要等引擎一拍，下一轮再采。
        dispatch_async(dispatch_get_main_queue(), ^{
            gLastResumeTrace = [NSString stringWithFormat:
                @"shouldPreventPlay=%@ videoShouldPlay=%@ play 后 isPlaying=%@",
                prevent ? @"YES" : @"NO",
                shouldPlay ? @"YES" : @"NO",
                [weakMerge isPlaying] ? @"YES" : @"NO"];
        });
    });
}

%end

// 只数不拦，纯排查用：分辨「播放请求被拒」与「播起来之后又被停掉」，
// 这正是 beta16 → beta17 花了两轮才分清的那个问题。
%hook AWEDPlayerViewController_Merge

- (void)pause {
    if (DKCommentFreezeOn() && DKCommentFullPanelOnScreen()) gPauseHits++;
    %orig;
}

%end
