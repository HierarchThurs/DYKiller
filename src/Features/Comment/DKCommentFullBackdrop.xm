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
//  关掉之后视频留在 feed 页原地继续播，全屏与半屏的视频行为完全一致。
//

#import "DouyinHeaders.h"
#import "DKVideoFullscreen.h"

#import <objc/runtime.h>

static char kDKBackdropPageKey;   // 全屏容器 → 垫回去的那一页的 view
static char kDKPanelColorKey;     // 全屏容器 view → 原底色（NSNull 表示原本就是 nil）

static NSUInteger gPiPGateHits = 0;

// 在屏的全屏容器。用弱引用而不是计数：交互式返回中途取消会再发一次 viewDidAppear:
// 而没有配对的 viewWillDisappear:，计数会一去不回。
static __weak UIViewController *gFullPanel = nil;

NSString *DKCommentPiPGateStats(void) {
    return [NSString stringWithFormat:@"内嵌画中画闸门已关=%lu 次", (unsigned long)gPiPGateHits];
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
