//
//  DKVideoPageChrome.xm
//  视频页、图文页与直播预览的页面级修饰：背景色延伸至底栏、评论态顶部黑遮罩、底部压暗渐变拉伸、
//  图文缩放抑制、直播预览 HUD 抬升，以及视频容器几何的两处重钉。
//  进度条底边的黑垫层见 DKProgressUnderline。
//
//  几何本身（容器该多大）统一由 DKVideoGeometry.xm 定义与拦截，本文件只负责在写入被放行
//  之后把它按回去，并处理钉住之后暴露出来的那些页面元素。
//

#import "DouyinHeaders.h"
#import "DKVideoFullscreen.h"
#import "DKVideoFeedTable.h"
#import "DKUtils.h"
#import <objc/runtime.h>
#import <math.h>

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

// 底部渐变要不要拉伸，取决于这条视频的容器有没有被钉得比自然高度更高——只有详情页那几页
// 会出现这种情况（首页/朋友页靠撑高 feed 表，渐变本来就在满高容器里）。
static BOOL DKMergeIsStretchedTarget(AWEDPlayerViewController_Merge *merge) {
    if (!merge || !merge.isViewLoaded) return NO;

    UIView *view = merge.view;
    CGRect target = DKVideoContainerTargetFrame(view);
    if (CGRectIsNull(target) || !view.superview) return NO;
    return CGRectGetHeight(target)
        > CGRectGetHeight(view.superview.bounds) + kDKSignatureTolerance;
}

#pragma mark - 视频容器重钉

// 两条重钉路径各补一个缺口，都不是冗余：
//   · willDisplay —— 钉位目标里「要不要拉满」是 model 的函数（图文/横屏/宽高比）。抖音复用 cell 时
//     可能先写 frame 后绑 model，写入那一刻算出的目标偏小；写完之后 frame 已等于抖音想要的值、
//     不会再写第二次，而预备 cell 是 hidden 的、不脏也不再布局，滑过去就是不全屏。
//     willDisplay 是 model 与视图层级都已就位、且一定早于用户看见的那一刻。
//   · viewDidLayoutSubviews —— 容器还没进 Cell 时算不出满高，那几次写入只能放行。
//     好友聊天页实测同一页两条 cell，一条 926 一条留在 843，就是这个缺口补上的。
// 补正后 frame 与目标一致，下一轮不再写，不会成环。
static NSUInteger gPinWillDisplay = 0;
static NSUInteger gPinLayout = 0;

NSString *DKVideoContainerPinStats(void) {
    return [NSString stringWithFormat:@"willDisplay 重钉=%lu  布局后兜底=%lu",
            (unsigned long)gPinWillDisplay, (unsigned long)gPinLayout];
}

static BOOL DKPinMergeToTarget(UIViewController *merge) {
    UIView *view = merge.viewIfLoaded;
    if (!view) return NO;

    CGRect target = DKVideoContainerTargetFrame(view);
    if (CGRectIsNull(target) || DKRectsClose(view.frame, target)) return NO;

    view.frame = target;
    return YES;
}

%hook AWEDPlayerViewController_Merge

- (void)willDisplay {
    %orig;
    if (DKPinMergeToTarget(self)) gPinWillDisplay++;
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (DKPinMergeToTarget(self)) gPinLayout++;
}

// 抖音展开评论区时靠这里把视频缩成小窗。两个开关任一开着，容器都由我们钉着，
// 缩放只会让玻璃背后只剩黑底、并留下顶部那条黑遮罩，一律压掉。
- (void)videoDidShrink {
    if (!DKVideoFullscreenOn() && !DKCommentFreezeOn()) {
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

static char kDKBackdropAppliedKey;    // 挂内容控制器：是否接管过
static char kDKCellBackdropKey;       // 挂承载视图：原背景色

// 内容下方那块空区由哪一层兜住，各页不同（好友页是 Cell contentView，搜索页是铺满且不透明的
// CellVC.view）。故动态求：从内容根往上，第一个高度超过它底边的祖先才是会露出来的那层。
static UIView *DKBackdropCanvas(UIView *anchor) {
    UIView *contentView = DKCellContentView(anchor);
    if (!contentView) return nil;

    for (UIView *ancestor = anchor.superview; ancestor; ancestor = ancestor.superview) {
        CGRect rect = [anchor convertRect:anchor.bounds toView:ancestor];
        if (CGRectGetHeight(ancestor.bounds)
            > CGRectGetMaxY(rect) + kDKSignatureTolerance) {
            return ancestor;
        }
        if (ancestor == contentView) break;
    }
    return nil;
}

// 承载层会随页面/布局变化，按标记回收，不假设它是哪一个。
static void DKRestoreBackdrop(UIView *anchor, UIView *except) {
    UIView *ancestor = anchor.superview;
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

// 其他比例视频：把 playerBackgroundView 的色涂到 anchor 下方会露出来的祖先上。
// owner 记「接管过没有」；color 为 nil 表示本条不需要延伸。图文不走这里——它钉的是
// AWEKnowledgeGradientView 自身高度（见下方），不取样另涂。
static void DKSyncBackdrop(id owner, UIView *anchor, UIColor *color) {
    BOOL applied = objc_getAssociatedObject(owner, &kDKBackdropAppliedKey) != nil;
    // 绝大多数内容没有原生背景，这里直接退出，不做任何链式遍历。
    if (!anchor || (!color && !applied)) return;

    UIView *canvas = (color && DKVideoFullscreenOn()) ? DKBackdropCanvas(anchor) : nil;

    DKRestoreBackdrop(anchor, canvas);
    if (!canvas) {
        objc_setAssociatedObject(owner, &kDKBackdropAppliedKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    if (!objc_getAssociatedObject(canvas, &kDKCellBackdropKey)) {
        objc_setAssociatedObject(canvas, &kDKCellBackdropKey,
                                 canvas.backgroundColor ?: (id)[NSNull null],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (![canvas.backgroundColor isEqual:color]) {
        canvas.backgroundColor = color;
    }
    objc_setAssociatedObject(owner, &kDKBackdropAppliedKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// 抖音把横屏智能背景色画在 playerBackgroundView 上；该色在首帧渲染出图后才算出来，
// 因此同步点必须是抖音自己落色的时刻，而不是 setModel:/setFrame: 这类首帧之前的入口。
// 仅当背景层确实挂在视图树上并可见时才算「抖音画了背景」，避免跟随已摘除的残留层。
static UIColor *DKPlayerBackdropColor(AWEPlayVideoViewController *controller) {
    UIView *backdrop = controller.playerBackgroundView;
    return (backdrop.superview && !backdrop.hidden) ? backdrop.backgroundColor : nil;
}

static Class DKRichContentContainerClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cls = NSClassFromString(@"RichContentContainerViewController");
    });
    return cls;
}

// 图文 cell 内仍嵌着一套 Merge/PlayVideo（alpha=0）。它与 RichContent 共用祖先链；
// 若让嵌套播放器继续 DKSyncBackdrop，会用黑底或 restore 把图文渐变末色清掉，
// 表现就是「偶发」底栏与图文背景不统一（beta5 导出：同页 contentView 有时透明有时已涂色）。
static BOOL DKIsUnderRichContent(UIViewController *controller) {
    Class richCls = DKRichContentContainerClass();
    if (!richCls) return NO;
    for (NSUInteger i = 0; controller && i < 12; i++) {
        if ([controller isKindOfClass:richCls]) return YES;
        controller = controller.parentViewController;
    }
    return NO;
}

%hook AWEPlayVideoViewController

- (void)setPlayerBackgroundView:(UIView *)backgroundView {
    %orig;
    if (DKIsUnderRichContent(self)) return;
    DKSyncBackdrop(self, self.viewIfLoaded, DKPlayerBackdropColor(self));
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (DKIsUnderRichContent(self)) return;
    DKSyncBackdrop(self, self.viewIfLoaded, DKPlayerBackdropColor(self));
}

%end

#pragma mark - 图文

static NSHashTable<UIView *> *gDKManagedVisualViews;
static char kDKRichClipKey;
static char kDKKnowledgeTransformKey;
static char kDKRichGradientTransformKey;
static char kDKVideoGradientTransformKey;
static char kDKLiveChromeTransformKey;

// center/bounds/anchorPoint 不受 transform 影响，可据此还原应用 transform 前的几何。
static CGRect DKIdentityFrameInSuperview(UIView *view) {
    CGFloat width = CGRectGetWidth(view.bounds);
    CGFloat height = CGRectGetHeight(view.bounds);
    CGFloat minX = view.center.x - width * view.layer.anchorPoint.x;
    CGFloat minY = view.center.y - height * view.layer.anchorPoint.y;
    return CGRectMake(minX, minY, width, height);
}

// 只接管原本没有 transform 的目标；首次修改时保存原值，恢复时不影响其他功能的状态。
static BOOL DKApplyVerticalStretch(
    UIView *view,
    const void *baselineKey,
    CGFloat top,
    CGFloat targetBottom
) {
    if (!view) return NO;

    CGFloat height = CGRectGetHeight(view.bounds);
    if (height <= 0.0 || targetBottom <= top + height + kDKSignatureTolerance) {
        return NO;
    }

    CGFloat scaleY = (targetBottom - top) / height;
    if (scaleY <= 1.0 + 1e-4) return NO;

    NSValue *baseline = objc_getAssociatedObject(view, baselineKey);
    if (!baseline) {
        if (!CGAffineTransformIsIdentity(view.transform)) return NO;
        baseline = [NSValue valueWithCGAffineTransform:view.transform];
        objc_setAssociatedObject(view, baselineKey, baseline,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    CGAffineTransform transform = CGAffineTransformMake(
        1.0, 0.0, 0.0, scaleY, 0.0, (height / 2.0) * (scaleY - 1.0));
    if (!CGAffineTransformEqualToTransform(view.transform, transform)) {
        view.transform = transform;
    }
    return YES;
}

// 纵向平移，用于把被撑高顶下去的 chrome 抬回原位。与上面的拉伸同一套接管规则：
// 只接管原本没有 transform 的目标（抖音自己在动它就让开），首次接管时存下原值。
static BOOL DKApplyVerticalLift(UIView *view, const void *baselineKey, CGFloat lift) {
    if (!view || lift <= kDKSignatureTolerance) return NO;

    NSValue *baseline = objc_getAssociatedObject(view, baselineKey);
    if (!baseline) {
        if (!CGAffineTransformIsIdentity(view.transform)) return NO;
        baseline = [NSValue valueWithCGAffineTransform:view.transform];
        objc_setAssociatedObject(view, baselineKey, baseline,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    CGAffineTransform transform = CGAffineTransformMakeTranslation(0.0, -lift);
    if (!CGAffineTransformEqualToTransform(view.transform, transform)) {
        view.transform = transform;
    }
    return YES;
}

static void DKRestoreTransformBaseline(UIView *view, const void *baselineKey) {
    NSValue *baseline = objc_getAssociatedObject(view, baselineKey);
    if (!baseline) return;

    view.transform = baseline.CGAffineTransformValue;
    objc_setAssociatedObject(view, baselineKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// 图文向 Cell 底部溢出时，只解除真实阻挡它的裁剪层；原本不裁剪的视图不接管。
static void DKAllowRichOverflow(UIView *view) {
    if (!view) return;

    if (!objc_getAssociatedObject(view, &kDKRichClipKey)) {
        if (!view.clipsToBounds) return;
        objc_setAssociatedObject(view, &kDKRichClipKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gDKManagedVisualViews addObject:view];
    }
    if (view.clipsToBounds) view.clipsToBounds = NO;
}

static void DKRestoreRichOverflow(UIView *view) {
    if (!objc_getAssociatedObject(view, &kDKRichClipKey)) return;

    view.clipsToBounds = YES;
    objc_setAssociatedObject(view, &kDKRichClipKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static Class DKKnowledgeGradientClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cls = NSClassFromString(@"AWEKnowledgeGradientView");
    });
    return cls;
}

// 图文的可见背景是列表控制器下的这一层渐变，与图片 / LivePhoto 等内容类型无关（它是整页的
// 背景层，不是单个 cell 的）。容器自己的 richBackgroundColor 实测恒为不透明黑——那正是被渐变
// 盖住的那块黑底，拿它去延伸等于把黑涂到黑上，所以这里不留那条回退。
// CAGradientLayer.colors 恒为 CGColorRef，末色即容器底边处的颜色。供探针读取。
UIColor *DKRichBackdropColor(UIViewController *container) {
    Class gradientCls = DKKnowledgeGradientClass();
    UIView *listView =
        ((RichContentContainerViewController *)container).contentListViewController.viewIfLoaded;
    if (!gradientCls || !listView) return nil;

    for (UIView *subview in listView.subviews) {
        if (subview.hidden || ![subview isKindOfClass:gradientCls]) continue;

        CALayer *layer = subview.layer;
        if (![layer isKindOfClass:CAGradientLayer.class]) return nil;

        id last = ((CAGradientLayer *)layer).colors.lastObject;
        return last ? [UIColor colorWithCGColor:(__bridge CGColorRef)last] : nil;
    }
    return nil;
}

// 图文底色层是 AWEKnowledgeGradientView。不能改它的 frame：父布局每轮写回 843，
// 我们在 setFrame:/layoutSubviews 里撑到 926 会与父互相追赶，主线程卡死 →
// 看门狗 0x8BADF00D（beta6 崩溃：EXC_CRASH SIGKILL / FRONTBOARD 8BADF00D，
// 栈在 layoutSublayers / layoutBelowIfNeeded / UITableView 建 cell）。
//
// 与同文件 AWEGradientView 压暗拉伸同一手段：只叠 transform，不触发布局环；
// 容器 clipsToBounds 放开后，渐变视觉上铺进 Cell 满高（好友页 843→926）。
static void DKSyncRichClips(UIView *view) {
    if (!view) return;

    CGFloat full = DKVideoFullscreenOn() ? DKFullCellHeight(view) : 0.0;
    if (full > CGRectGetHeight(view.bounds) + kDKSignatureTolerance) {
        DKAllowRichOverflow(view);
        return;
    }

    DKRestoreRichOverflow(view);
}

static void DKSyncKnowledgeGradientStretch(UIView *gradient) {
    if (!gradient) return;

    CGFloat height = CGRectGetHeight(gradient.bounds);
    CGFloat full = DKVideoFullscreenOn() ? DKFullCellHeight(gradient) : 0.0;

    if (height > 0.0 && full > height + kDKSignatureTolerance
        && DKApplyVerticalStretch(
            gradient,
            &kDKKnowledgeTransformKey,
            0.0,
            full
        )) {
        [gDKManagedVisualViews addObject:gradient];
        return;
    }

    DKRestoreTransformBaseline(gradient, &kDKKnowledgeTransformKey);
}

// 图文的顶层容器，三种图文列表实现都挂在它下面。
//
// · 缩放：updateShrinkState: 是图文版的 videoDidShrink。
// · 背景：放开 clips，渐变用 transform 视觉延伸（见 AWEKnowledgeGradientView）。
%hook RichContentContainerViewController

- (void)updateShrinkState:(BOOL)shrink insets:(UIEdgeInsets)insets animated:(BOOL)animated {
    // 抑制时一律不调 %orig：class-dump 把 insets 折叠成 (struct)，真实类型只能按参数名推断，
    // 不重新编组它就不依赖这个推断；放行走裸 %orig，Logos 原样透传实参。
    if (shrink && (DKVideoFullscreenOn() || DKCommentFreezeOn())) return;
    %orig;
}

- (void)updateShrinkState:(BOOL)shrink
                   insets:(UIEdgeInsets)insets
                 animated:(BOOL)animated
        animationDuration:(double)duration {
    if (shrink && (DKVideoFullscreenOn() || DKCommentFreezeOn())) return;
    %orig;
}

- (void)viewDidLayoutSubviews {
    %orig;
    DKSyncRichClips(self.viewIfLoaded);
}

%end

%hook AWEKnowledgeGradientView

- (void)layoutSubviews {
    %orig;
    DKSyncKnowledgeGradientStretch(self);
}

%end

#pragma mark - 评论态 HUD 顶部遮罩

// 评论展开时抖音会在 HUD 顶部现场插入一条「安全区高 × 满宽」的纯黑遮罩，
// 它是「视频缩小」态的产物，被强钉满屏的视频顶上去就成了黑边。
static char kDKStatusBarCoverHiddenKey;

// 遮罩的高度是**窗口**安全区高，尺子也必须取窗口的：HUD 根视图在 table cell 里，它自己的安全区
// 随 cell 在滚动视图中的位置变化，滑到不覆盖窗口顶部安全区的位置就是 0，签名会整条失配。
CGFloat DKHUDStatusBarCoverHeight(UIView *hudView) {
    UIWindow *window = hudView.window;
    return window ? window.safeAreaInsets.top : hudView.safeAreaInsets.top;
}

static UIView *DKFindHUDStatusBarCover(UIView *hudView) {
    CGFloat safeTop = DKHUDStatusBarCoverHeight(hudView);
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

// 判据就是两个开关本身：这条遮罩只在评论展开时出现，而那一刻视频容器必被其中一个钉住，
// 遮罩就成了纯粹的黑边。额外要求「找得到 Merge 且比例达标」会让横屏永远留着黑边。
void DKHUDStatusBarCoverSync(UIViewController *interaction) {
    UIView *hudView = interaction.viewIfLoaded;
    if (!hudView) return;

    if (DKVideoFullscreenOn() || DKCommentFreezeOn()) {
        UIView *cover = DKFindHUDStatusBarCover(hudView);
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

    for (UIView *view in hudView.subviews) {
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

// DKVideoFeedTable.xm 也在同一个方法上挂了一层（HUD 高度的布局后补正），两处分属两个功能、
// 各自跟着自己的模块走，串联生效，互不依赖。
%hook AWEPlayInteractionViewController

- (void)viewDidLayoutSubviews {
    %orig;
    DKHUDStatusBarCoverSync(self);
}

%end

#pragma mark - 底部压暗渐变

%hook AWEDPlayerComponentInteraction

- (void)addGradientViews {
    %orig;
    if (!DKVideoFullscreenOn()) return;

    AWEAwemeModel *model = self.model;
    AWEVideoModel *video = model.video;
    double width = video.width.doubleValue;
    double height = video.height.doubleValue;
    if (model.awemeType == 68 || width <= 0.0 || height <= 0.0 || width <= height) return;

    // 渐变创建后同步宿主显隐判定，覆盖播放器已提前就绪的首次展示。
    [self hideGradientViewIfNeeded:self.playerController];
}

%end

// 只叠 transform，不改 frame（防布局环 / 0x8BADF00D）。
//
// 视频与图文的渐变同步点不同：视频在自身 layout 中层级已经完整；图文必须等横滑 collection
// 完成布局、可见 Cell 进入详情页 Cell 后再处理。两条路径分别持有自己的 transform 标记。

%hook AWEGradientView

- (void)layoutSubviews {
    %orig;

    // ① 视频：Merge 被钉得比父视图高时，容器内非贴底的压暗跟着撑满（旧逻辑，保留）。
    AWEDPlayerViewController_Merge *merge = DKMergeForView(self);
    if (DKMergeIsStretchedTarget(merge)) {
        UIView *container = self.superview;
        CGFloat height = CGRectGetHeight(self.bounds);
        if (container && height > 0.0) {
            CGFloat top = self.center.y - height / 2.0;
            CGFloat containerHeight = CGRectGetHeight(container.bounds);
            if (top > 1.0 && top + height < containerHeight - 1.0) {
                if (DKApplyVerticalStretch(
                    self,
                    &kDKVideoGradientTransformKey,
                    top,
                    containerHeight
                )) {
                    [gDKManagedVisualViews addObject:self];
                    return;
                }
            }
        }
    }

    DKRestoreTransformBaseline(self, &kDKVideoGradientTransformKey);
}

%end

static Class DKGradientClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cls = NSClassFromString(@"AWEGradientView");
    });
    return cls;
}

// 图文贴底压暗的结构签名：全宽、贴父底、顶边不在父顶。尺寸随设备和内容布局动态变化。
static BOOL DKIsRichBottomGradient(UIView *view) {
    Class gradientCls = DKGradientClass();
    UIView *parent = view.superview;
    if (!gradientCls || !parent || view.hidden || view.alpha <= 0.01
        || ![view isKindOfClass:gradientCls]) {
        return NO;
    }

    CGFloat parentWidth = CGRectGetWidth(parent.bounds);
    CGFloat parentHeight = CGRectGetHeight(parent.bounds);
    if (parentWidth <= 0.0 || parentHeight <= 0.0) return NO;

    CGRect frame = DKIdentityFrameInSuperview(view);
    CGFloat tolerance = MAX(kDKSignatureTolerance, 1.0);
    return fabs(CGRectGetMinX(frame)) <= tolerance
        && fabs(CGRectGetWidth(frame) - parentWidth) <= tolerance
        && fabs(CGRectGetMaxY(frame) - parentHeight) <= tolerance
        && CGRectGetMinY(frame) > tolerance;
}

static void DKCollectRichBottomGradients(UIView *root, NSMutableArray<UIView *> *output) {
    for (UIView *subview in root.subviews) {
        if (subview.hidden || subview.alpha <= 0.01) continue;
        if (DKIsRichBottomGradient(subview)) {
            [output addObject:subview];
            continue;
        }
        DKCollectRichBottomGradients(subview, output);
    }
}

static NSArray<UIView *> *DKRichBottomGradients(
    AWEStoryContainerCollectionView *collection
) {
    NSMutableArray<UIView *> *gradients = [NSMutableArray array];
    for (UICollectionViewCell *cell in collection.visibleCells) {
        DKCollectRichBottomGradients(cell, gradients);
    }
    return gradients;
}

static BOOL DKViewIsInCollection(UIView *view, UIView *collection) {
    return view == collection || [view isDescendantOfView:collection];
}

static void DKRestoreUnusedRichCollectionState(
    AWEStoryContainerCollectionView *collection,
    NSSet<UIView *> *activeGradients,
    NSSet<UIView *> *activeClipViews
) {
    for (UIView *view in gDKManagedVisualViews.allObjects) {
        if (!DKViewIsInCollection(view, collection)) continue;

        if (objc_getAssociatedObject(view, &kDKRichGradientTransformKey)
            && ![activeGradients containsObject:view]) {
            DKRestoreTransformBaseline(view, &kDKRichGradientTransformKey);
        }
        if (objc_getAssociatedObject(view, &kDKRichClipKey)
            && ![activeClipViews containsObject:view]) {
            DKRestoreRichOverflow(view);
        }
    }
}

static void DKSyncRichCollection(AWEStoryContainerCollectionView *collection) {
    CGFloat contentHeight = CGRectGetHeight(collection.bounds);
    CGFloat fullHeight = DKVideoFullscreenOn() ? DKFullCellHeight(collection) : 0.0;
    if (contentHeight <= 0.0
        || fullHeight <= contentHeight + kDKSignatureTolerance) {
        DKRestoreUnusedRichCollectionState(collection, [NSSet set], [NSSet set]);
        return;
    }

    NSMutableSet<UIView *> *activeGradients = [NSMutableSet set];
    NSMutableSet<UIView *> *activeClipViews = [NSMutableSet set];
    for (UIView *gradient in DKRichBottomGradients(collection)) {
        UIView *contentView = DKCellContentView(gradient);
        UIView *parent = gradient.superview;
        if (!contentView || !parent || ![gradient isDescendantOfView:collection]) continue;

        CGRect identityFrame = DKIdentityFrameInSuperview(gradient);
        CGFloat top = [parent convertPoint:identityFrame.origin toView:contentView].y;
        if (!DKApplyVerticalStretch(
            gradient,
            &kDKRichGradientTransformKey,
            top,
            fullHeight
        )) {
            continue;
        }

        [gDKManagedVisualViews addObject:gradient];
        [activeGradients addObject:gradient];

        for (UIView *ancestor = parent; ancestor; ancestor = ancestor.superview) {
            if (ancestor.clipsToBounds
                || objc_getAssociatedObject(ancestor, &kDKRichClipKey)) {
                DKAllowRichOverflow(ancestor);
                [activeClipViews addObject:ancestor];
            }
            if (ancestor == collection) break;
        }
    }

    DKRestoreUnusedRichCollectionState(collection, activeGradients, activeClipViews);
}

NSString *DKRichBottomGradientStats(UIView *collectionView) {
    Class collectionClass = NSClassFromString(@"AWEStoryContainerCollectionView");
    if (!collectionClass || ![collectionView isKindOfClass:collectionClass]) {
        return @"贴底压暗 = (集合视图无效)";
    }

    AWEStoryContainerCollectionView *collection =
        (AWEStoryContainerCollectionView *)collectionView;
    NSArray<UIView *> *gradients = DKRichBottomGradients(collection);
    if (gradients.count == 0) return @"贴底压暗 = (未命中)";

    UIView *gradient = gradients.firstObject;
    UIView *contentView = DKCellContentView(gradient);
    UIView *parent = gradient.superview;
    CGFloat bottom = 0.0;
    if (contentView && parent) {
        bottom = [parent convertPoint:
            CGPointMake(0.0, CGRectGetMaxY(gradient.frame))
            toView:contentView
        ].y;
    }

    NSUInteger clipping = 0;
    for (UIView *ancestor = parent; ancestor; ancestor = ancestor.superview) {
        if (ancestor.clipsToBounds) clipping++;
        if (ancestor == collection) break;
    }

    return [NSString stringWithFormat:
        @"贴底压暗 × %lu  frame=%@  bounds=%@  transform=%@  "
         "底边=%.1f/%.1f  裁剪阻断=%lu",
        (unsigned long)gradients.count,
        NSStringFromCGRect(gradient.frame),
        NSStringFromCGRect(gradient.bounds),
        NSStringFromCGAffineTransform(gradient.transform),
        bottom,
        contentView ? CGRectGetHeight(contentView.bounds) : 0.0,
        (unsigned long)clipping
    ];
}

%hook AWEStoryContainerCollectionView

- (void)layoutSubviews {
    %orig;
    DKSyncRichCollection(self);
}

%end

#pragma mark - 直播预览 HUD

// 直播预览的画面与背景按窗口尺寸排（容器只有 843 时 TTPlayerView2 已经是 926），撑高表对它们
// 没有影响；chrome 却是挂在容器高度上的——表撑高一个底栏后，「直播中」角标 / 昵称 / 简介 /
// 静音键 /「点击进入直播间」整体跟着容器底边下移 83pt，钻进悬浮底栏后面。要把它们抬回原位。
//
// **只能叠 transform，不能钉 frame**：0.5.3-beta1 钉过 AWELiveNewPreStreamViewController 的根视图，
// IESLive 每轮布局都按 Cell 满高重算它，与钉位互相追赶，进直播频道即卡死、约 10s 被看门狗杀掉。
// 位移量只由「Cell 满高 − 表撑高前的高度」决定，与被移动视图自己的 frame 无关，IESLive 怎么重排
// 都算出同一个值，天然不成环；命中测试跟随 transform，按钮照常可点。
//
// 抬升目标只有两个，都是 4 层容器上的**具名槽位**，不做任何遍历：
//
//   controlContainer ── IESLiveStackView（满高，约束驱动）
//                        ├─ IESLiveLayoutContainerView  顶部空槽（四份导出恒为 h=0）
//                        └─ IESLiveLayoutContainerView  贴底信息块
//                             └ 「点击进入直播间」/ 标签行 / 昵称 / 简介 / 静音键
//   bottomDarkWatermark ── 贴底暗水印，与 chrome 不同槽位，单独判
//
// 0.5.6-beta3~beta7 走的是另一条路：按结构签名去**遍历找**那个贴底信息块。它在冷启动第一个直播上
// 时灵时不灵（beta7 实测六次冷启动生效与不生效交替出现），原因是这个块由 IESLive 的排版系统
// （IESLiveLayoutBaseContainer / IESLiveLayoutContainerItem，约束驱动）在直播间数据回来后**现场
// 生成并插入**：它先在树外建好、在树外定好几何，最后才挂进 stack——树外的几何写入取不到容器，
// 插入之后又不一定还有布局回合，换哪个触发点都会漏（容器布局 / 排版层布局 / setFrame: /
// setBounds: / setCenter: / didMoveToSuperview 六处逐一实测过）。
//
// 而同一份导出里，**暗水印每一次都抬对了**——同一个触发点、同一个位移量，差别只在它是具名槽位、
// 不需要等谁生成。所以问题从来不在触发时机，在目标发现方式：改成只认这两个槽位之后，
// chrome 什么时候被排进来都无所谓，它进的是一个已经抬好的坐标系。

static Class DKLivePreStreamContainerClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cls = NSClassFromString(@"AWELivePreStream4LayerContainerView");
    });
    return cls;
}

// 同步跑了几次、首次接管了几个槽位。两个数分开记：只记接管数时，「钩子没被调用」与
// 「调用了但位移还算不出来」是同一个 0，分不出该往哪边查。
static NSUInteger gLiftRuns = 0;
static NSUInteger gLiftTakeovers = 0;

NSString *DKLiveChromeLiftStats(void) {
    return [NSString stringWithFormat:@"容器布局 跑=%lu 接管=%lu",
            (unsigned long)gLiftRuns, (unsigned long)gLiftTakeovers];
}

// 位移量 = Cell 满高 − 该表撑高前的高度；表没被撑高过（搜索页那种本就满高的）返回 0。
// 容器还没跟着 cell 一起长高时同样返回 0：那一刻 chrome 仍贴着矮容器的底、本来就在原位，
// 抬了会整体上飞一个底栏。判据按容器坐标量，位移就必须与容器同一轮才自洽。
static CGFloat DKLiveChromeLift(UIView *container) {
    NSNumber *original = DKVideoFeedTableOriginalHeight(DKFeedTableForView(container));
    UIView *contentView = DKCellContentView(container);
    if (!original || !contentView) return 0.0;

    CGFloat full = CGRectGetHeight(contentView.bounds);
    if (CGRectGetHeight(container.bounds) < full - kDKSignatureTolerance) return 0.0;
    return full - original.doubleValue;
}

// 目标底边在**容器**坐标里的位置。取 identity frame，免得自己叠上去的位移污染判定。
static CGFloat DKLiveChromeBottom(UIView *view, UIView *container) {
    CGRect frame = DKIdentityFrameInSuperview(view);
    return [view.superview convertPoint:CGPointMake(0.0, CGRectGetMaxY(frame))
                                 toView:container].y;
}

// 暗水印贴底但留了 8pt 边距，只在它确实落进撑出来的那一段里才抬——它与 chrome 不在同一槽位，
// 位置由 IESLive 直接排，不跟着控制层走。
static BOOL DKLiveWatermarkNeedsLift(UIImageView *watermark, UIView *container, CGFloat lift) {
    if (!watermark || watermark.hidden || lift <= kDKSignatureTolerance) return NO;
    return DKLiveChromeBottom(watermark, container)
        > CGRectGetHeight(container.bounds) - lift + kDKSignatureTolerance;
}

// 该抬就抬、不该抬就还原，两个槽位共用。幂等：值没变不写。
static void DKApplyLiveLift(UIView *target, CGFloat lift, BOOL wanted) {
    if (!target) return;

    BOOL managed = objc_getAssociatedObject(target, &kDKLiveChromeTransformKey) != nil;
    if (wanted && DKApplyVerticalLift(target, &kDKLiveChromeTransformKey, lift)) {
        [gDKManagedVisualViews addObject:target];
        if (!managed) gLiftTakeovers++;
        return;
    }
    DKRestoreTransformBaseline(target, &kDKLiveChromeTransformKey);
}

// 位移为 0（表本就满高，或容器还没跟着 cell 长高）时两个槽位都走还原分支，没接管过就是空转。
// 目标是两个具名属性、没有遍历可省，所以不再挂「接管过没有」的标记来提前退出。
static void DKSyncLiveChrome(AWELivePreStream4LayerContainerView *container) {
    gLiftRuns++;

    CGFloat lift = DKVideoFullscreenOn() ? DKLiveChromeLift(container) : 0.0;
    UIImageView *watermark = container.bottomDarkWatermark;

    DKApplyLiveLift(container.controlContainer, lift, lift > kDKSignatureTolerance);
    DKApplyLiveLift(watermark, lift, DKLiveWatermarkNeedsLift(watermark, container, lift));
}

static NSString *DKLiveSlotDesc(UIView *slot) {
    if (!slot) return @"(nil)";
    return [NSString stringWithFormat:@"%@ %p %@",
            NSStringFromClass(slot.class), slot, NSStringFromCGRect(slot.frame)];
}

// 抬升目标逐个给出 identity frame 与实际底边：identity 是抖音排的位置，实际底边是抬完的结果。
static NSString *DKLiveLiftDesc(UIView *target, UIView *contentView) {
    if (!target) return @"(nil)\n";

    CGFloat bottom = contentView
        ? [target.superview convertPoint:CGPointMake(0.0, CGRectGetMaxY(target.frame))
                                  toView:contentView].y
        : 0.0;
    return [NSString stringWithFormat:@"%@ %p  identity=%@  ty=%.1f  实际底边=%.1f\n",
            NSStringFromClass(target.class), target,
            NSStringFromCGRect(DKIdentityFrameInSuperview(target)),
            target.transform.ty, bottom];
}

NSString *DKLiveChromeStats(UIView *view) {
    Class containerCls = DKLivePreStreamContainerClass();
    if (!containerCls || ![view isKindOfClass:containerCls]) return @"  (不是 4 层容器)\n";

    AWELivePreStream4LayerContainerView *container =
        (AWELivePreStream4LayerContainerView *)view;
    UIView *contentView = DKCellContentView(container);
    NSNumber *original = DKVideoFeedTableOriginalHeight(DKFeedTableForView(container));

    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"  容器高=%.1f  Cell 满高=%.1f  表原高=%@  位移=%.1f\n",
     CGRectGetHeight(container.bounds),
     contentView ? CGRectGetHeight(contentView.bounds) : 0.0,
     original ? [NSString stringWithFormat:@"%.1f", original.doubleValue] : @"(未撑高)",
     DKLiveChromeLift(container)];
    // 具名槽位只为采集：本页哪些 chrome 挂在哪一层，下次要补别的房型时照它认人。
    [out appendFormat:@"  left    = %@\n", DKLiveSlotDesc(container.leftContainer)];
    [out appendFormat:@"  center  = %@\n", DKLiveSlotDesc(container.centerContainer)];
    [out appendFormat:@"  bottom  = %@\n", DKLiveSlotDesc(container.bottomContainer)];
    [out appendFormat:@"  渐变层  = %@\n", DKLiveSlotDesc(container.gradientContainerView)];
    [out appendFormat:@"  控制层  = %@", DKLiveLiftDesc(container.controlContainer, contentView)];
    [out appendFormat:@"  暗水印  = %@", DKLiveLiftDesc(container.bottomDarkWatermark, contentView)];
    return out;
}

%hook AWELivePreStream4LayerContainerView

- (void)layoutSubviews {
    %orig;
    DKSyncLiveChrome(self);
}

%end

static void DKPageChromeVisualRestore(void) {
    for (UIView *view in gDKManagedVisualViews.allObjects) {
        DKRestoreTransformBaseline(view, &kDKKnowledgeTransformKey);
        DKRestoreTransformBaseline(view, &kDKRichGradientTransformKey);
        DKRestoreTransformBaseline(view, &kDKVideoGradientTransformKey);
        DKRestoreTransformBaseline(view, &kDKLiveChromeTransformKey);
        DKRestoreRichOverflow(view);
    }
    [gDKManagedVisualViews removeAllObjects];
}

%ctor {
    gDKManagedVisualViews = [NSHashTable weakObjectsHashTable];
    DKVideoFullscreenRegisterRestore(DKPageChromeVisualRestore);
}

// 设置项统一注册在 DKVideoGeometry.xm，本文件只提供页面修饰这一套逻辑。
