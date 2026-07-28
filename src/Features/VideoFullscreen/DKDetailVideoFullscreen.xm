//
//  DKDetailVideoFullscreen.xm
//  好友页与搜索页详情页：竖屏视频画面填满整屏，其他比例视频把抖音原生背景色延伸到底栏，
//  并清除进度条底边的黑条。HUD 位置与尺寸全程不变。
//
//  竖屏全屏只拦截 AWEDPlayerViewController_Merge.view 的 frame 写入，视频子树随容器伸展，
//  HUD 位于兄弟层不受影响。
//

#import "DouyinHeaders.h"
#import "DKUtils.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import <objc/runtime.h>
#import <math.h>

// 高/宽达到此阈值才进入全屏处理。低比例竖屏与横屏保持原布局。
static const CGFloat kDKFullscreenMinAspect = 1.70;
static const long long kDKAwemeTypeImage = 68;
// 结构签名的统一容差：覆盖 @3x 像素对齐与进度条收放时的亚像素漂移。
static const CGFloat kDKSignatureTolerance = 0.5;

static Class DKMergeClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cls = NSClassFromString(@"AWEDPlayerViewController_Merge");
    });
    return cls;
}

static BOOL DKColorIsOpaqueBlack(UIColor *color) {
    if (!color) return NO;

    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    CGFloat alpha = 0.0;
    if ([color getRed:&red green:&green blue:&blue alpha:&alpha]) {
        return red <= 0.02 && green <= 0.02 && blue <= 0.02 && alpha >= 0.98;
    }

    CGFloat white = 0.0;
    if ([color getWhite:&white alpha:&alpha]) {
        return white <= 0.02 && alpha >= 0.98;
    }
    return NO;
}

#pragma mark - 全屏目标判定

static AWEDPlayerViewController_Merge *DKMergeForView(UIView *view) {
    Class mergeCls = DKMergeClass();
    if (!mergeCls) return nil;

    UIResponder *responder = view.nextResponder;
    for (NSUInteger i = 0; responder && i < 40; i++) {
        if ([responder isKindOfClass:mergeCls]) {
            return (AWEDPlayerViewController_Merge *)responder;
        }
        responder = responder.nextResponder;
    }
    return nil;
}

// 图文、横屏、低比例竖屏一律保持原生布局，避免误伤或 aspect-fill 过裁。
static BOOL DKMergeHasEligibleVideo(AWEDPlayerViewController_Merge *merge) {
    AWEAwemeModel *model = merge.model;
    if (model.awemeType == kDKAwemeTypeImage) return NO;
    if (merge.hasInlandscape) return NO;
    if ([merge respondsToSelector:@selector(isInLandscapeFeedStatus)]
        && [merge isInLandscapeFeedStatus]) {
        return NO;
    }

    AWEVideoModel *video = model.video;
    double width = video.width.doubleValue;
    double height = video.height.doubleValue;
    return width <= 0.0
        || height <= 0.0
        || (height / width) >= kDKFullscreenMinAspect;
}

static BOOL DKMergeIsFullscreenTarget(AWEDPlayerViewController_Merge *merge) {
    if (!merge) return NO;
    if (!DKDetailPageFullscreenOn(DKDetailPageForResponder(merge))) return NO;
    return DKMergeHasEligibleVideo(merge);
}

#pragma mark - 视频容器

%hook UIView

- (void)setFrame:(CGRect)frame {
    Class mergeCls = DKMergeClass();
    UIResponder *nextResponder = self.nextResponder;
    if (!mergeCls || ![nextResponder isKindOfClass:mergeCls]) {
        %orig;
        return;
    }

    AWEDPlayerViewController_Merge *merge =
        (AWEDPlayerViewController_Merge *)nextResponder;
    if (!DKMergeIsFullscreenTarget(merge)) {
        %orig;
        return;
    }

    CGFloat fullHeight = DKFullCellHeight(self);
    CGFloat width = self.superview
        ? CGRectGetWidth(self.superview.bounds)
        : CGRectGetWidth(frame);
    if (fullHeight <= 0.0 || width <= 0.0) {
        %orig;
        return;
    }

    %orig(CGRectMake(0.0, 0.0, width, fullHeight));
}

%end

#pragma mark - 评论区开合

%hook AWEDPlayerViewController_Merge

- (void)videoDidShrink {
    if (!DKMergeIsFullscreenTarget(self)) {
        %orig;
        return;
    }

    UIView *gradient = self.gradientBackgroundView;
    if (gradient && gradient.alpha < 1.0) {
        gradient.alpha = 1.0;
    }
}

%end

#pragma mark - 背景延伸至底栏

// 抖音把横屏智能背景色画在 playerBackgroundView 上；该色在首帧渲染出图后才算出来，
// 因此同步点必须是抖音自己落色的时刻，而不是 setModel:/setFrame: 这类首帧之前的入口。
static char kDKBackdropAppliedKey;    // 挂播放控制器：是否接管过
static char kDKCellBackdropKey;       // 挂承载视图：原背景色

// 容器下方那块空区由哪一层兜住，两页不同（好友页是 Cell contentView，搜索页是铺满且不透明的
// CellVC.view）。故动态求：从播放器 view 往上，第一个高度超过它底边的祖先才是会露出来的那层。
static UIView *DKBackdropCanvas(UIView *playerView) {
    UIView *contentView = DKCellContentView(playerView);
    if (!contentView) return nil;

    for (UIView *ancestor = playerView.superview; ancestor; ancestor = ancestor.superview) {
        CGRect rect = [playerView convertRect:playerView.bounds toView:ancestor];
        if (CGRectGetHeight(ancestor.bounds)
            > CGRectGetMaxY(rect) + kDKSignatureTolerance) {
            return ancestor;
        }
        if (ancestor == contentView) break;
    }
    return nil;
}

// 承载层会随页面/布局变化，按标记回收，不假设它是哪一个。
static void DKRestoreBackdrop(UIView *playerView, UIView *except) {
    UIView *ancestor = playerView.superview;
    for (NSUInteger i = 0; ancestor && i < 12; i++, ancestor = ancestor.superview) {
        if (ancestor == except) continue;

        id baseline = objc_getAssociatedObject(ancestor, &kDKCellBackdropKey);
        if (!baseline) continue;

        ancestor.backgroundColor =
            baseline == [NSNull null] ? nil : (UIColor *)baseline;
        objc_setAssociatedObject(
            ancestor,
            &kDKCellBackdropKey,
            nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }
}

static void DKSyncCellBackdrop(AWEPlayVideoViewController *controller) {
    // 仅当背景层确实挂在视图树上并可见时才算「抖音画了背景」，避免跟随已摘除的残留层。
    UIView *backdrop = controller.playerBackgroundView;
    UIColor *color =
        (backdrop.superview && !backdrop.hidden) ? backdrop.backgroundColor : nil;
    BOOL applied =
        objc_getAssociatedObject(controller, &kDKBackdropAppliedKey) != nil;
    // 绝大多数视频没有原生背景，这里直接退出，不做任何链式遍历。
    if (!color && !applied) return;

    UIView *playerView = controller.viewIfLoaded;
    if (!playerView) return;

    UIView *canvas = nil;
    if (color && DKDetailPageFullscreenOn(DKDetailPageForResponder(controller))) {
        canvas = DKBackdropCanvas(playerView);
    }

    DKRestoreBackdrop(playerView, canvas);
    if (!canvas) {
        objc_setAssociatedObject(
            controller,
            &kDKBackdropAppliedKey,
            nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
        return;
    }

    if (!objc_getAssociatedObject(canvas, &kDKCellBackdropKey)) {
        objc_setAssociatedObject(
            canvas,
            &kDKCellBackdropKey,
            canvas.backgroundColor ?: (id)[NSNull null],
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }
    if (![canvas.backgroundColor isEqual:color]) {
        canvas.backgroundColor = color;
    }
    objc_setAssociatedObject(
        controller,
        &kDKBackdropAppliedKey,
        @YES,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}

%hook AWEPlayVideoViewController

- (void)setPlayerBackgroundView:(UIView *)backgroundView {
    %orig;
    DKSyncCellBackdrop(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    DKSyncCellBackdrop(self);
}

%end

#pragma mark - 进度条底边黑条

static char kDKProgressUnderColorKey;
static char kDKProgressUnderOpaqueKey;

// 不能带位置锚点：相对滑杆的位置随进度条收放漂移，相对容器底边的位置随页面 HUD 高度而变。
// 「容器直属 + 普通 UIView + 满宽 + 极薄 + 纯黑不透明」本身已足够唯一。
static BOOL DKIsProgressUnderView(UIView *view, UIView *container) {
    if (object_getClass(view) != [UIView class]) return NO;

    CGRect frame = view.frame;
    CGFloat height = CGRectGetHeight(frame);
    return height > 0.0
        && height <= 2.0 + kDKSignatureTolerance
        && fabs(CGRectGetMinX(frame)) <= kDKSignatureTolerance
        && fabs(CGRectGetWidth(frame) - CGRectGetWidth(container.bounds))
            <= kDKSignatureTolerance
        && DKColorIsOpaqueBlack(view.backgroundColor);
}

static void DKClearProgressUnderView(UIView *view) {
    if (!objc_getAssociatedObject(view, &kDKProgressUnderColorKey)) {
        objc_setAssociatedObject(
            view,
            &kDKProgressUnderColorKey,
            view.backgroundColor,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
        objc_setAssociatedObject(
            view,
            &kDKProgressUnderOpaqueKey,
            @(view.opaque),
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }

    if (![view.backgroundColor isEqual:[UIColor clearColor]]) {
        view.backgroundColor = [UIColor clearColor];
    }
    if (view.opaque) view.opaque = NO;
}

static void DKRestoreProgressUnderView(UIView *view) {
    UIColor *color = objc_getAssociatedObject(view, &kDKProgressUnderColorKey);
    if (!color) return;

    NSNumber *opaque = objc_getAssociatedObject(view, &kDKProgressUnderOpaqueKey);
    view.backgroundColor = color;
    view.opaque = opaque.boolValue;
    objc_setAssociatedObject(
        view,
        &kDKProgressUnderColorKey,
        nil,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
    objc_setAssociatedObject(
        view,
        &kDKProgressUnderOpaqueKey,
        nil,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}

%hook AWEDPlayerProgressContainerView

- (void)layoutSubviews {
    %orig;

    BOOL enabled = DKDetailPageFullscreenOn(DKDetailPageForResponder(self));
    for (UIView *view in self.subviews) {
        // 已接管的视图只按开关决定去留：进度条收起时签名会漂移，据此还原会让黑条重现。
        if (objc_getAssociatedObject(view, &kDKProgressUnderColorKey)) {
            enabled ? DKClearProgressUnderView(view) : DKRestoreProgressUnderView(view);
        } else if (enabled && DKIsProgressUnderView(view, self)) {
            DKClearProgressUnderView(view);
        }
    }
}

%end

#pragma mark - 评论态 HUD 顶部遮罩

// 评论展开时抖音会在 HUD 顶部现场插入一条「安全区高 × 满宽」的纯黑遮罩，
// 它是「视频缩小」态的产物，被强钉满屏的视频顶上去就成了黑边。
static char kDKStatusBarCoverHiddenKey;

static UIView *DKFindHUDStatusBarCover(UIView *hudView) {
    CGFloat safeTop = hudView.safeAreaInsets.top;
    CGFloat width = CGRectGetWidth(hudView.bounds);
    if (safeTop <= 1.0 || width <= 0.0) return nil;

    for (UIView *view in hudView.subviews) {
        if (object_getClass(view) != [UIView class]) continue;
        if (!view.opaque || view.hidden) continue;

        CGRect frame = view.frame;
        if (fabs(CGRectGetMinX(frame)) > 1.0
            || fabs(CGRectGetMinY(frame)) > 1.0
            || fabs(CGRectGetWidth(frame) - width) > 1.0
            || fabs(CGRectGetHeight(frame) - safeTop) > 2.0) {
            continue;
        }
        if (DKColorIsOpaqueBlack(view.backgroundColor)) return view;
    }
    return nil;
}

static void DKUpdateHUDStatusBarCover(
    AWEPlayInteractionViewController *interaction
) {
    AWEDPlayerViewController_Merge *merge = nil;
    Class mergeCls = DKMergeClass();
    for (UIViewController *child in interaction.parentViewController.childViewControllers) {
        if (mergeCls && [child isKindOfClass:mergeCls]) {
            merge = (AWEDPlayerViewController_Merge *)child;
            break;
        }
    }

    if (DKMergeIsFullscreenTarget(merge)) {
        UIView *cover = DKFindHUDStatusBarCover(interaction.view);
        if (cover) {
            cover.hidden = YES;
            objc_setAssociatedObject(
                cover,
                &kDKStatusBarCoverHiddenKey,
                @YES,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC
            );
        }
        return;
    }

    for (UIView *view in interaction.view.subviews) {
        if (!objc_getAssociatedObject(view, &kDKStatusBarCoverHiddenKey)) continue;
        view.hidden = NO;
        objc_setAssociatedObject(
            view,
            &kDKStatusBarCoverHiddenKey,
            nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }
}

%hook AWEPlayInteractionViewController

- (void)viewDidLayoutSubviews {
    %orig;
    DKUpdateHUDStatusBarCover(self);
}

%end

#pragma mark - 底部压暗渐变

// 渐变由 Auto Layout 管理，改 frame 会被滑动重排冲掉并可能触发布局环，只能叠 transform。
static char kDKGradientTransformKey;

%hook AWEGradientView

- (void)layoutSubviews {
    %orig;

    BOOL applied =
        objc_getAssociatedObject(self, &kDKGradientTransformKey) != nil;
    AWEDPlayerViewController_Merge *merge = DKMergeForView(self);

    if (DKMergeIsFullscreenTarget(merge)) {
        UIView *container = self.superview;
        CGFloat height = CGRectGetHeight(self.bounds);
        if (container && height > 0.0) {
            CGFloat top = self.center.y - height / 2.0;
            CGFloat containerHeight = CGRectGetHeight(container.bounds);
            if (top > 1.0 && top + height < containerHeight - 1.0) {
                CGFloat scaleY = (containerHeight - top) / height;
                CGAffineTransform transform = CGAffineTransformMake(
                    1.0,
                    0.0,
                    0.0,
                    scaleY,
                    0.0,
                    (height / 2.0) * (scaleY - 1.0)
                );
                if (!CGAffineTransformEqualToTransform(self.transform, transform)) {
                    self.transform = transform;
                }
                if (!applied) {
                    objc_setAssociatedObject(
                        self,
                        &kDKGradientTransformKey,
                        @YES,
                        OBJC_ASSOCIATION_RETAIN_NONATOMIC
                    );
                }
                return;
            }
        }
    }

    if (applied) {
        self.transform = CGAffineTransformIdentity;
        objc_setAssociatedObject(
            self,
            &kDKGradientTransformKey,
            nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }
}

%end

#pragma mark - 设置项注册

%ctor {
    DKSettingsRegisterItem(@"好友页", ^AWESettingItemModel *{
        return DKMakeSwitch(
            DKKeyChatVideoFullscreen,
            @"好友页视频全屏",
            @"竖屏视频填满整屏，其他比例视频的原生背景延伸至底栏"
        );
    });

    DKSettingsRegisterItem(@"搜索页", ^AWESettingItemModel *{
        return DKMakeSwitch(
            DKKeySearchVideoFullscreen,
            @"搜索页视频全屏",
            @"竖屏视频填满整屏，其他比例视频的原生背景延伸至底栏"
        );
    });
}
