//
//  DKCommentDanmaku.xm
//  半屏评论区打开时保持弹幕可见，全屏评论区保持抖音原生行为（弹幕隐藏）。
//
//  抖音隐弹幕就是把 DDanmakuPlayerView 的 alpha 从 1 改成 0——三份导出对照读出来的：
//  容器 AWEDanmakuContainerView 恒为 hidden=false alpha=1，各条弹幕视图也都在，只有这一层变。
//  所以接管点就是这一个属性，不去追弹幕控制器那套 setHide: / updateDanmakuShowStatusIfNeed:
//  （静态看不出评论面板走的是哪一条）。
//
//  iPad 横屏评论区以分栏打开时不写 alpha，而是把视频列连同弹幕层一起收窄，开合各引起一次重排：
//  · AWEDanmakuFeedController viewDidLayoutSubviews 发现容器父视图宽度与 lastDanmakuContainerBounds
//    不同，重新布局弹幕，并经容器控制器 pause → clearAllDisplayingDanmakus → play 从头开始；
//  · DDanmakuPlayer layoutDidChanged: 每轮把渲染引擎 frame 写成弹幕层 bounds，在屏弹幕按新宽度重排。
//  分栏期间两处都保持原宽：记录的容器宽度不更新、渲染区不收窄，评论栏一侧由视频列裁掉；
//  关闭评论区后宽度回到原值，与记录一致，不再重排。
//

#import "DouyinHeaders.h"
#import "DKCommentGlass.h"
#import "DKVideoFullscreen.h"

#import <math.h>

// 接管过的那一层。全屏进出时抖音不会再写一次 alpha，得靠它主动切回去。
static __weak UIView *gDanmakuView = nil;
static NSUInteger gKeepHits = 0;
static NSUInteger gStageKeepHits = 0;
static NSUInteger gLayoutKeepHits = 0;

NSString *DKCommentDanmakuStats(void) {
    UIView *view = gDanmakuView;
    return [NSString stringWithFormat:@"弹幕接管=%lu 次  当前 alpha=%@  分栏保持渲染宽度=%lu 次  分栏跳过弹幕重排=%lu 轮",
            (unsigned long)gKeepHits,
            view ? [NSString stringWithFormat:@"%.2f", view.alpha] : @"(未接管过)",
            (unsigned long)gStageKeepHits, (unsigned long)gLayoutKeepHits];
}

// 评论面板开着、且不在全屏态时，弹幕该保持可见。
// 面板在不在屏用玻璃那把尺子（DKCommentGlassCurrentSlot），与探针同一判据。
static BOOL DKShouldKeepDanmaku(void) {
    if (!DKCommentFreezeOn() || DKCommentFullPanelOnScreen()) return NO;

    UIView *slot = DKCommentGlassCurrentSlot();
    return slot.window != nil && !slot.hidden;
}

void DKCommentDanmakuSyncForFullPanel(void) {
    UIView *view = gDanmakuView;
    if (!view) return;

    CGFloat wanted = DKShouldKeepDanmaku() ? 1.0 : 0.0;
    if (fabs(view.alpha - wanted) > 0.01) view.alpha = wanted;
}

%hook DDanmakuPlayerView

- (void)setAlpha:(CGFloat)alpha {
    // 只顶「压成透明」这一种写入，且只在评论面板开着时顶。长按面板、横屏、用户自己关弹幕
    // 同样走这个 setter，那些一律放行。
    if (alpha >= 0.01 || !DKShouldKeepDanmaku()) {
        %orig;
        return;
    }

    gDanmakuView = self;
    gKeepHits++;
    %orig(1.0);
}

%end

// 只认「原本占满窗口宽、同一窗口内只收窄宽度」这一种变化：高度、原点或窗口尺寸变了（旋转、
// 多任务窗口缩放、新建的弹幕层）一律放行；本就窄于窗口的卡片播放器不受影响。
static BOOL DKSplitKeepsDanmakuWidth(UIWindow *window, CGRect previous, CGRect next) {
    if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad || !window) return NO;
    if (!DKCommentFreezeOn() || DKCommentFullPanelOnScreen()) return NO;

    CGFloat windowWidth = CGRectGetWidth(window.bounds);
    return CGRectGetWidth(next) < CGRectGetWidth(previous) - 0.5
        && fabs(CGRectGetWidth(previous) - windowWidth) <= 0.5
        && fabs(CGRectGetHeight(next) - CGRectGetHeight(previous)) <= 0.5
        && CGPointEqualToPoint(next.origin, previous.origin);
}

%hook AWEDanmakuFeedController

// viewDidLayoutSubviews 只经这个 getter 读记录；分栏期间报告「未变化」，记录保持原宽。
- (CGRect)lastDanmakuContainerBounds {
    CGRect last = %orig;
    UIView *host = self.danmakuContainerView.superview;
    if (!host || !DKSplitKeepsDanmakuWidth(host.window, last, host.bounds)) return last;
    gLayoutKeepHits++;
    return host.bounds;
}

%end

%hook DDanmakuRenderEngine

- (void)setFrame:(CGRect)frame {
    CGRect current = self.frame;
    if (DKSplitKeepsDanmakuWidth(self.view.window, current, frame)) {
        gStageKeepHits++;
        frame.size.width = CGRectGetWidth(current);
    }
    %orig(frame);
}

%end
