//
//  DKCommentFullPanel.xm
//  评论区放大到全屏时，让背后仍然是视频而不是黑屏。
//
//  实现约束（0.5.0）：
//
//  · 抖音的全屏评论是 push 一个 AWECommentFullScreenContainerViewController。push 完成后
//    UIKit 会把下层那个装视频的 VC 的 view 移出层级（导出会记录 hidden=YES 的视图，
//    而播放器子树彻底不存在，两者可区分），于是玻璃背后什么都没有。
//
//  · beta6 试过在全屏容器里手动插回下层视图，结果必崩：崩溃日志停在
//    -[UIView _associatedViewControllerForwardsAppearanceCallbacks:performHierarchyCheck:]
//    抛异常 → abort。把一个控制器的 view 塞进另一个控制器的层级而没有包含关系，
//    UIKit 的层级一致性检查直接拒绝。**不要再走那条路。**
//
//  · 本版改为根本不 push：拦下这一次 push，用标准的控制器包含把全屏容器盖在当前页上。
//    页面从不导航，视频原地不动、不被移除、不被暂停，也不需要搬任何视图。
//    返回时对称地解除包含。
//
//  · 任一前置条件不满足（玻璃关着、类名对不上、取不到 topViewController）一律走原生 push，
//    宁可退回黑底也不留半截状态。
//
//  · 抖音的 AWEDPlayerPiPWindow 只在原生全屏路径出现，且 windowLevel = 2000 在主窗口之上，
//    垫不到面板背后，不走它。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKUtils.h"

#import <objc/runtime.h>

// 宿主控制器 → 当前挂着的全屏评论覆盖层。
static char kDKOverlayKey;
// 覆盖层 → 宿主，供覆盖层自己走返回时解开（弱引用，宿主不该被面板续命）。
static char kDKOverlayHostKey;

static BOOL DKIsFullPanel(UIViewController *controller) {
    return [controller isKindOfClass:NSClassFromString(@"AWECommentFullScreenContainerViewController")];
}

// 用标准包含把全屏容器盖上去。成功返回 YES；任何一步不成立都返回 NO 让调用方走原生 push。
static BOOL DKPresentOverlay(UIViewController *host, UIViewController *panel) {
    if (!host.isViewLoaded || !panel || objc_getAssociatedObject(host, &kDKOverlayKey)) return NO;

    [host addChildViewController:panel];

    UIView *view = panel.view;
    view.frame = host.view.bounds;
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    // 容器自带不透明黑底，清掉才能看见背后的视频。
    view.backgroundColor = UIColor.clearColor;
    [host.view addSubview:view];

    [panel didMoveToParentViewController:host];
    objc_setAssociatedObject(host, &kDKOverlayKey, panel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(panel, &kDKOverlayHostKey, host, OBJC_ASSOCIATION_ASSIGN);
    return YES;
}

// 返回被解开的覆盖层；本来就没有覆盖层时返回 nil，调用方据此决定要不要走原生流程。
static UIViewController *DKDismissOverlay(UIViewController *host) {
    UIViewController *panel = objc_getAssociatedObject(host, &kDKOverlayKey);
    if (!panel) return nil;

    [panel willMoveToParentViewController:nil];
    [panel.view removeFromSuperview];
    [panel removeFromParentViewController];
    objc_setAssociatedObject(host, &kDKOverlayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(panel, &kDKOverlayHostKey, nil, OBJC_ASSOCIATION_ASSIGN);
    return panel;
}

%hook UINavigationController

- (void)pushViewController:(UIViewController *)controller animated:(BOOL)animated {
    if (!DKPrefBool(DKKeyCommentGlass) || !DKIsFullPanel(controller)) {
        %orig;
        return;
    }
    if (!DKPresentOverlay(self.topViewController, controller)) %orig;
}

- (UIViewController *)popViewControllerAnimated:(BOOL)animated {
    // 覆盖层没进导航栈，pop 收起全屏评论时要对称地解除包含，不能让它真去弹当前页。
    UIViewController *panel = DKDismissOverlay(self.topViewController);
    return panel ?: %orig;
}

%end

// 关闭按钮走的是容器自己的 backAction，不一定经过导航栈，单独接一次。
%hook AWECommentFullScreenContainerViewController

- (void)backAction {
    if (DKDismissOverlay(objc_getAssociatedObject(self, &kDKOverlayHostKey))) return;
    %orig;
}

%end
