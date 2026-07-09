//
//  DKChatVideoFullscreen.xm
//  聊天页「分享视频」详情页 —— 竖屏视频画面填满整屏，HUD 原地不动。
//
//  实现：
//   拦截视频容器 `AWEDPlayerViewController_Merge.view` 的 setFrame:，
//   将竖屏高比例视频容器设置为整屏高度。视频子树通过 autoresize 跟随容器，
//   HUD 位于兄弟层。横屏与低比例视频按真实宽高比排除。
//

#import "DouyinHeaders.h"
#import "DKUtils.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import <objc/runtime.h>
#import <math.h>

// 高/宽达到此阈值才进入全屏处理。低比例竖屏 / 横屏保持原布局。
static const CGFloat kDKFullscreenMinAspect = 1.70;
static const long long kDKAwemeTypeImage = 68; // 图文/图集，保持抖音原生布局

static Class DKMergeClass(void) {
    static Class cls; static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(@"AWEDPlayerViewController_Merge"); });
    return cls;
}

// 该 Merge 是否本插件全屏目标：IM 详情页 + 竖高视频（排除图文、横屏、低比例）。
static BOOL DKMergeIsFullscreenTarget(AWEDPlayerViewController_Merge *merge) {
    if (!merge || !DKVCInIMDetail(merge)) return NO;
    AWEAwemeModel *model = merge.model;
    if (model.awemeType == kDKAwemeTypeImage) return NO;
    if (merge.hasInlandscape) return NO;
    if ([merge respondsToSelector:@selector(isInLandscapeFeedStatus)] && [merge isInLandscapeFeedStatus]) return NO;
    // 读取视频宽高计算比例
    AWEVideoModel *video = model.video;
    double w = video.width.doubleValue, h = video.height.doubleValue;
    if (w > 0.0 && h > 0.0 && (h / w) < kDKFullscreenMinAspect) return NO;
    return YES;
}

#pragma mark - 视频容器：拦截 setFrame 设置整屏高度

%hook UIView

- (void)setFrame:(CGRect)frame {
    if (!DKPrefBool(DKKeyChatVideoFullscreen)) { %orig; return; }

    // 通过 nextResponder 确认 Merge.view
    Class mergeCls = DKMergeClass();
    UIResponder *nr = [self nextResponder];
    if (!mergeCls || ![nr isKindOfClass:mergeCls]) { %orig; return; }

    AWEDPlayerViewController_Merge *merge = (AWEDPlayerViewController_Merge *)nr;
    if (!DKMergeIsFullscreenTarget(merge)) { %orig; return; }

    CGFloat fullH = DKFullCellHeight(self);            // cell 满高 926；取不到则放行
    if (fullH <= 0.0) { %orig; return; }
    CGFloat W = self.superview ? self.superview.bounds.size.width : frame.size.width;

    // 全屏目标视频：设置整屏高度、origin 归零。
    %orig(CGRectMake(0.0, 0.0, W, fullH));
}

%end

#pragma mark - 评论 shrink：目标全屏视频保持全屏状态

%hook AWEDPlayerViewController_Merge

- (void)videoDidShrink {
    if (!DKPrefBool(DKKeyChatVideoFullscreen) || !DKMergeIsFullscreenTarget(self)) {
        %orig;
        return;
    }

    UIView *gradient = self.gradientBackgroundView;
    if (gradient && gradient.alpha < 1.0) gradient.alpha = 1.0;
}

%end

#pragma mark - 评论态 HUD 顶部状态栏黑底：全屏目标隐藏并可复位
//
// 评论区打开时，HUD（AWEPlayInteractionViewController.view）顶部可能出现
// 「安全区高 × 满宽、纯黑不透明」覆盖层。本功能按结构签名识别该覆盖层，
// 并在全屏目标下 hidden 掉，关联对象标记用于关闭时复位。

// 同 cell 的兄弟视频容器：HUD 与 Merge 同属 AWEAwemeDetailCellViewController 的子 VC。
static AWEDPlayerViewController_Merge *DKSiblingMerge(UIViewController *hud) {
    Class mergeCls = DKMergeClass();
    if (!mergeCls) return nil;
    for (UIViewController *child in hud.parentViewController.childViewControllers) {
        if ([child isKindOfClass:mergeCls]) return (AWEDPlayerViewController_Merge *)child;
    }
    return nil;
}

static BOOL DKColorIsOpaqueBlack(UIColor *color) {
    if (!color) return NO;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if ([color getRed:&r green:&g blue:&b alpha:&a])
        return r <= 0.02 && g <= 0.02 && b <= 0.02 && a >= 0.98;
    CGFloat w = 0;
    if ([color getWhite:&w alpha:&a])
        return w <= 0.02 && a >= 0.98;
    return NO;
}

// 按结构签名查找顶部黑底：本类 UIView、贴顶、满宽、高≈安全区顶、纯黑不透明。
static UIView *DKFindHUDStatusBarCover(UIView *hudView) {
    CGFloat safeTop = hudView.safeAreaInsets.top;
    if (safeTop <= 1.0) return nil;
    CGFloat W = hudView.bounds.size.width;
    for (UIView *v in hudView.subviews) {
        if (object_getClass(v) != [UIView class]) continue;   // 恰为 UIView 本类，非子类
        if (!v.opaque || v.hidden) continue;
        CGRect f = v.frame;
        if (fabs(f.origin.x) > 1.0 || fabs(f.origin.y) > 1.0) continue;
        if (fabs(f.size.width - W) > 1.0) continue;
        if (fabs(f.size.height - safeTop) > 2.0) continue;
        if (!DKColorIsOpaqueBlack(v.backgroundColor)) continue;
        return v;
    }
    return nil;
}

static char kDKStatusBarCoverHiddenKey;

static void DKUpdateHUDStatusBarCover(UIViewController *hud) {
    BOOL shouldHide = DKPrefBool(DKKeyChatVideoFullscreen)
                      && DKMergeIsFullscreenTarget(DKSiblingMerge(hud));

    if (shouldHide) {
        UIView *cover = DKFindHUDStatusBarCover(hud.view);
        if (cover) {
            cover.hidden = YES;
            objc_setAssociatedObject(cover, &kDKStatusBarCoverHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }

    // 不适用（关开关 / 非目标）：只还原本插件隐藏过的黑底
    for (UIView *v in hud.view.subviews) {
        if (objc_getAssociatedObject(v, &kDKStatusBarCoverHiddenKey)) {
            v.hidden = NO;
            objc_setAssociatedObject(v, &kDKStatusBarCoverHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

%hook AWEPlayInteractionViewController

- (void)viewDidLayoutSubviews {
    %orig;
    DKUpdateHUDStatusBarCover(self);
}

%end

#pragma mark - 底部压暗渐变：随全屏延伸到底
//
// 用 transform 把底边补到容器底。
// 仅处理底边未到容器底的渐变，关闭时复位本功能写入的 transform。

static char kDKGradTransformKey;

%hook AWEGradientView

- (void)layoutSubviews {
    %orig;
    BOOL applied = objc_getAssociatedObject(self, &kDKGradTransformKey) != nil;

    if (DKPrefBool(DKKeyChatVideoFullscreen) && DKViewInIMDetail(self)) {
        UIView *container = self.superview;
        CGFloat h = self.bounds.size.height;                    // 与 transform 无关
        if (container && h > 0.0) {
            CGFloat top = self.center.y - h / 2.0;              // 父坐标里的顶边（transform 无关）
            CGFloat containerH = container.bounds.size.height;
            // 底部压暗渐变：顶边在中下部、底边原本贴近容器底；top≈0 的顶部渐变不处理
            if (top > 1.0 && (top + h) < containerH - 1.0) {
                CGFloat sy = (containerH - top) / h;            // 顶边不动、底边补到容器底
                CGAffineTransform t = CGAffineTransformMake(1, 0, 0, sy, 0, (h / 2.0) * (sy - 1.0));
                if (!CGAffineTransformEqualToTransform(self.transform, t)) self.transform = t;
                if (!applied) objc_setAssociatedObject(self, &kDKGradTransformKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                return;
            }
        }
    }

    // 关闭 / 不适用：只复位本插件加过 transform 的渐变
    if (applied) {
        self.transform = CGAffineTransformIdentity;
        objc_setAssociatedObject(self, &kDKGradTransformKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%end

#pragma mark - 设置项注册

%ctor {
    DKSettingsRegisterItem(@"聊天页", ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyChatVideoFullscreen, @"聊天页视频全屏", @"竖屏视频画面填满整屏，HUD 不变");
    });
}
