// 搜索覆盖层的挂载、键盘跟踪与展开收起事务。
#import "DKSearchOverlay.h"
#import "DKSearchViews.h"
#import "DKSearchIndex.h"
#import "DKSearchReveal.h"
#import "DKSettingsInternal.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
static const CGFloat kDKSearchPanelMinHeight = 44.0;
static const CGFloat kDKSearchRowMinHeight = 52.0;
// 展开：整行容器上移；胶囊先从圆钮向左拉长（右端仍在圆钮下方，两者是一块玻璃），
// 右端再退到融合间距边缘拉出细颈，最后弹开到行间距。
static const NSTimeInterval kDKSearchRiseDuration = 0.48;
static const CGFloat kDKSearchRiseDamping = 0.84;
static const NSTimeInterval kDKSearchStretchDuration = 0.34;
static const CGFloat kDKSearchStretchDamping = 0.80;
static const NSTimeInterval kDKSearchNeckDelay = 0.10;
static const NSTimeInterval kDKSearchNeckDuration = 0.34;
static const NSTimeInterval kDKSearchReleaseDelay = 0.30;
static const NSTimeInterval kDKSearchReleaseDuration = 0.40;
static const CGFloat kDKSearchReleaseDamping = 0.62;
static const NSTimeInterval kDKSearchContentInDelay = 0.16;
static const NSTimeInterval kDKSearchContentInDuration = 0.22;
// 收起：胶囊右端伸向圆钮、在融合间距内连出液桥，并进圆钮下方后整体缩回圆钮；整行容器同时下沉。
static const NSTimeInterval kDKSearchReachDuration = 0.30;
static const NSTimeInterval kDKSearchMergeDelay = 0.14;
static const NSTimeInterval kDKSearchMergeDuration = 0.26;
static const CGFloat kDKSearchMergeDamping = 0.90;
static const NSTimeInterval kDKSearchAbsorbDelay = 0.20;
static const NSTimeInterval kDKSearchAbsorbDuration = 0.34;
static const CGFloat kDKSearchAbsorbDamping = 0.80;
static const NSTimeInterval kDKSearchSinkDuration = 0.44;
static const CGFloat kDKSearchSinkDamping = 0.88;
static const NSTimeInterval kDKSearchContentOutDuration = 0.12;
static const NSTimeInterval kDKSearchFadeDuration = 0.18;
static const NSTimeInterval kDKSearchPanelFadeDuration = 0.16;
// 融合间距取行间距的 0.8：静止时两块玻璃分开，间隙小于它时两者以液桥相连。
static const CGFloat kDKSearchMergeSpacingRatio = 0.8;
// 细颈停在融合间距内 1.5pt；伸向圆钮时停在融合间距的 0.3。
static const CGFloat kDKSearchNeckInset = 1.5;
static const CGFloat kDKSearchReachRatio = 0.3;
static const UIViewAnimationOptions kDKSearchMotionOptions =
    UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction;
// 本进程最近一次弹出的键盘高度，展开起步时用来预估键盘位置。
static CGFloat sDKSearchKeyboardHeight = 0.0;

static UIViewAnimationOptions DKSearchAnimationOptions(UIViewAnimationCurve curve) {
    return (UIViewAnimationOptions)((NSUInteger)curve << 16);
}

static void DKSearchSpring(NSTimeInterval duration, NSTimeInterval delay, CGFloat damping,
                           void (^animations)(void), void (^completion)(BOOL)) {
    [UIView animateWithDuration:duration delay:delay usingSpringWithDamping:damping initialSpringVelocity:0.0
                        options:kDKSearchMotionOptions animations:animations completion:completion];
}

// 圆钮与胶囊所在的整行容器：容器只做纵向位移，行内两块玻璃只做横向分离与融合；上下各留 gap 给 interactive 形变。
static CGRect DKSearchGroupFrame(CGRect row, DKSearchMetrics metrics, CGFloat width) {
    return CGRectMake(0.0, CGRectGetMinY(row) - metrics.gap, width, metrics.diameter + 2.0 * metrics.gap);
}

static CGRect DKSearchInGroup(CGRect frame, DKSearchMetrics metrics) {
    return CGRectMake(CGRectGetMinX(frame), metrics.gap, CGRectGetWidth(frame), metrics.diameter);
}

// 胶囊左端在展开位置，右端离圆钮左缘 gap（负值表示伸进圆钮下方）。
static CGRect DKSearchCapsuleFrame(DKSearchMetrics metrics, CGFloat gap) {
    CGFloat minX = CGRectGetMinX(metrics.capsuleFrame);
    return CGRectMake(minX, metrics.gap, CGRectGetMinX(metrics.closeFrame) - gap - minX, metrics.diameter);
}

static CGFloat DKSearchMergeSpacing(DKSearchMetrics metrics) {
    return round(metrics.gap * kDKSearchMergeSpacingRatio);
}

// 延迟后才开始变化的透明度动画：用关键帧，起步前保持起始值（带延迟的普通动画在延迟期间会显示终值）。
static void DKSearchFadeLater(NSTimeInterval delay, NSTimeInterval duration, void (^animations)(void),
                              void (^completion)(BOOL)) {
    NSTimeInterval total = delay + duration;
    [UIView animateKeyframesWithDuration:total delay:0.0
                                 options:UIViewKeyframeAnimationOptionAllowUserInteraction
                              animations:^{
        [UIView addKeyframeWithRelativeStartTime:delay / total relativeDuration:duration / total animations:animations];
    } completion:completion];
}

#pragma mark - 覆盖层

@interface DKSearchOverlayView : UIView <UITextFieldDelegate>
@property (nonatomic, weak) UIViewController *hostPage;
- (instancetype)initWithHostPage:(UIViewController *)page;
- (void)dkDismissImmediately;
@end

@implementation DKSearchOverlayView {
    UIView *_dimView;
    DKSearchPanelView *_panelView;
    DKSearchResultsView *_tableView;
    DKSearchGlassGroupView *_glassGroup;
    DKSearchCapsuleView *_capsuleView;
    DKSearchGlassButton *_closeButton;
    DKSearchIndex *_index;
    NSArray<DKSearchEntry *> *_results;
    CGFloat _keyboardTop;
    CGFloat _dimTargetAlpha;
    BOOL _expanded;
    BOOL _animating;
    BOOL _keyboardEstimated;
    __weak UIWindowScene *_observedScene;
    id _sceneTraitToken;
    NSUInteger _transitionGeneration;
    NSUInteger _panelGeneration;
}

- (instancetype)initWithHostPage:(UIViewController *)page {
    if ((self = [super initWithFrame:CGRectZero])) {
        _hostPage = page;
        _results = @[];
        self.backgroundColor = UIColor.clearColor;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        _dimView = [[UIView alloc] init];
        _dimView.hidden = YES;
        _dimView.alpha = 0.0;
        [_dimView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                              action:@selector(dkDimTapped)]];
        [self addSubview:_dimView];

        _panelView = [[DKSearchPanelView alloc] initWithEffect:nil];
        _panelView.hidden = YES;
        [self addSubview:_panelView];

        _tableView = [[DKSearchResultsView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
        __weak typeof(self) weakSelf = self;
        _tableView.didChooseEntry = ^(DKSearchEntry *entry) { [weakSelf dkCommitEntry:entry]; };
        [_panelView.contentView addSubview:_tableView];

        _glassGroup = [[DKSearchGlassGroupView alloc] initWithEffect:nil];
        [self addSubview:_glassGroup];

        // initWithEffect: 不经过子类的 initWithFrame:，输入框在那里创建。
        _capsuleView = [[DKSearchCapsuleView alloc] initWithFrame:CGRectZero];
        _capsuleView.hidden = YES;
        _capsuleView.textField.delegate = self;
        [_capsuleView.textField addTarget:self action:@selector(dkTextChanged)
                         forControlEvents:UIControlEventEditingChanged];
        [_glassGroup.contentView addSubview:_capsuleView];

        _closeButton = [[DKSearchGlassButton alloc] initWithFrame:CGRectZero];
        [_closeButton.hitControl addTarget:self action:@selector(dkButtonTapped)
                          forControlEvents:UIControlEventTouchUpInside];
        [_glassGroup.contentView addSubview:_closeButton];

        [self dkApplyDimColor];
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(dkKeyboardWillChange:)
                       name:UIKeyboardWillChangeFrameNotification object:nil];
        [center addObserver:self selector:@selector(dkKeyboardWillHide:)
                       name:UIKeyboardWillHideNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}

#pragma mark 几何

- (DKSearchMetrics)dkMetrics {
    UIView *host = self.superview ?: self;
    UIEdgeInsets insets = DKSearchInsetsForHost(host);
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat keyboard = (_keyboardTop > 0.0 && _keyboardTop < height - 1.0) ? _keyboardTop : 0.0;
    return DKSearchMetricsMake(self.bounds.size, insets, keyboard);
}

- (void)dkApplyDimColor {
    BOOL dark = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    _dimTargetAlpha = dark ? 0.28 : 0.12;
    _dimView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:1.0];
    if (_expanded) _dimView.alpha = _dimTargetAlpha;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (previousTraitCollection.userInterfaceStyle == self.traitCollection.userInterfaceStyle) return;
    [self dkApplyDimColor];
}

#pragma mark 深浅色

// 抖音把窗口的深浅色钉死，整层按场景的真实外观覆盖：玻璃、文字与结果面板都用动态色，随覆盖值解析。
- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self dkObserveScene:self.window.windowScene];
    [self dkApplyAppearance];
}

// 场景外观变化时重新取值（iOS 17+）；更低系统在进入页面与每次展开时取值。
- (void)dkObserveScene:(UIWindowScene *)scene {
    if (@available(iOS 17.0, *)) {
        if (scene == _observedScene && (_sceneTraitToken || !scene)) return;
        if (_sceneTraitToken) [_observedScene unregisterForTraitChanges:_sceneTraitToken];
        _sceneTraitToken = nil;
        _observedScene = scene;
        if (!scene) return;
        __weak typeof(self) weakSelf = self;
        _sceneTraitToken = [scene registerForTraitChanges:@[ UITraitUserInterfaceStyle.class ]
                                              withHandler:^(__unused UIWindowScene *changed,
                                                            __unused UITraitCollection *previous) {
            [weakSelf dkApplyAppearance];
        }];
    }
}

- (UIUserInterfaceStyle)dkSceneStyle {
    UIWindow *window = self.window;
    UIUserInterfaceStyle style = window.windowScene.traitCollection.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified) style = window.traitCollection.userInterfaceStyle;
    return style == UIUserInterfaceStyleUnspecified ? UIUserInterfaceStyleLight : style;
}

- (void)dkApplyAppearance {
    if (!self.window) return;
    UIUserInterfaceStyle style = [self dkSceneStyle];
    if (self.overrideUserInterfaceStyle != style) self.overrideUserInterfaceStyle = style;
    [self dkApplyDimColor];
    UITextField *field = _capsuleView.textField;
    UIKeyboardAppearance keyboard =
        style == UIUserInterfaceStyleDark ? UIKeyboardAppearanceDark : UIKeyboardAppearanceLight;
    if (field.keyboardAppearance == keyboard) return;
    field.keyboardAppearance = keyboard;
    // 键盘已在屏上时重载输入视图，键盘外观立即切换。
    if (field.isFirstResponder) [field reloadInputViews];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    DKSearchMetrics metrics = [self dkMetrics];
    _dimView.frame = self.bounds;
    _panelView.radius = metrics.radius;
    _tableView.rowHeight = MAX(metrics.diameter, kDKSearchRowMinHeight);
    _glassGroup.mergeSpacing = DKSearchMergeSpacing(metrics);
    if (_animating) return;
    if (!_expanded) {
        [self dkApplyCollapsedFrames:metrics];
        return;
    }
    [self dkApplyExpandedFrames:metrics];
    // 键盘/旋转改变可用高度后，重新按当前内容决定面板能否显示。
    BOOL canShow = CGRectGetHeight(metrics.resultsFrame) >= kDKSearchPanelMinHeight;
    if (!canShow) _panelView.hidden = YES;
    else if (_results.count > 0) {
        _panelView.hidden = NO;
        _tableView.alpha = 1.0;
    }
}

- (void)dkApplyExpandedFrames:(DKSearchMetrics)metrics {
    _glassGroup.frame = DKSearchGroupFrame(metrics.closeFrame, metrics, CGRectGetWidth(self.bounds));
    _closeButton.frame = DKSearchInGroup(metrics.closeFrame, metrics);
    _capsuleView.frame = DKSearchInGroup(metrics.capsuleFrame, metrics);
    _panelView.frame = metrics.resultsFrame;
}

// 收起态胶囊与圆钮重合并隐藏：容器里两者是同一块玻璃，展开时从这里分离出来。
- (void)dkApplyCollapsedFrames:(DKSearchMetrics)metrics {
    _glassGroup.frame = DKSearchGroupFrame(metrics.fabFrame, metrics, CGRectGetWidth(self.bounds));
    _closeButton.frame = DKSearchInGroup(metrics.fabFrame, metrics);
    _capsuleView.frame = _closeButton.frame;
}

#pragma mark 键盘

- (void)dkKeyboardWillChange:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    CGRect frame = [info[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect local = [self convertRect:frame fromView:nil];
    CGFloat top = CGRectGetMinY(local);
    CGFloat height = CGRectGetHeight(self.bounds);
    _keyboardTop = (top > 0.0 && top < height - 1.0) ? top : 0.0;
    if (_keyboardTop > 0.0) sDKSearchKeyboardHeight = height - _keyboardTop;
    _keyboardEstimated = NO;
    [self dkFollowKeyboardWithDuration:[info[UIKeyboardAnimationDurationUserInfoKey] doubleValue]
                                 curve:[info[UIKeyboardAnimationCurveUserInfoKey] integerValue]];
}

- (void)dkKeyboardWillHide:(NSNotification *)notification {
    _keyboardTop = 0.0;
    _keyboardEstimated = NO;
    NSDictionary *info = notification.userInfo;
    [self dkFollowKeyboardWithDuration:[info[UIKeyboardAnimationDurationUserInfoKey] doubleValue]
                                 curve:[info[UIKeyboardAnimationCurveUserInfoKey] integerValue]];
}

// 展开过程中与展开后都跟随键盘：只移动整行容器与结果面板，行内的分离动画不受影响。
- (void)dkFollowKeyboardWithDuration:(NSTimeInterval)duration curve:(UIViewAnimationCurve)curve {
    if (!_expanded) return;
    DKSearchMetrics metrics = [self dkMetrics];
    CGRect group = DKSearchGroupFrame(metrics.closeFrame, metrics, CGRectGetWidth(self.bounds));
    [UIView animateWithDuration:duration delay:0.0
                        options:DKSearchAnimationOptions(curve) | kDKSearchMotionOptions
                     animations:^{
        self->_glassGroup.frame = group;
        self->_panelView.frame = metrics.resultsFrame;
    } completion:^(__unused BOOL finished) { [self setNeedsLayout]; }];
}

#pragma mark 展开 / 收起

// 新事务只换代际、不移除在途动画：位置与尺寸动画按叠加方式合成，反向时从当前呈现位置接续。
- (NSUInteger)dkBeginTransition {
    _panelGeneration++;
    return ++_transitionGeneration;
}

- (void)dkStopAnimations {
    [self dkBeginTransition];
    for (UIView *view in @[ _glassGroup, _closeButton, _capsuleView, _dimView, _panelView, _tableView,
                           _capsuleView.glyphView, _capsuleView.textField ]) {
        [view.layer removeAllAnimations];
    }
    _animating = NO;
}

// 一次事务由多段动画组成，全部结束才收尾；被新事务接替后旧回调不再生效。
- (void (^)(BOOL))dkCompletionForParts:(NSUInteger)parts generation:(NSUInteger)generation
                                 finish:(dispatch_block_t)finish {
    __block NSUInteger remaining = parts;
    __weak typeof(self) weakSelf = self;
    return ^(__unused BOOL finished) {
        DKSearchOverlayView *overlay = weakSelf;
        if (!overlay || overlay->_transitionGeneration != generation) return;
        if (--remaining == 0) finish();
    };
}

- (void)dkExpand {
    if (_expanded) return;
    NSUInteger generation = [self dkBeginTransition];
    _expanded = YES;
    _animating = YES;
    _results = @[];
    _tableView.entries = _results;
    // 键盘尚未弹出时按本进程上次的键盘高度起步，通知到达后按真实位置校正。
    if (_keyboardTop <= 0.0 && sDKSearchKeyboardHeight > 0.0) {
        _keyboardTop = CGRectGetHeight(self.bounds) - sDKSearchKeyboardHeight;
        _keyboardEstimated = YES;
    }
    DKSearchMetrics metrics = [self dkMetrics];
    // 起始态不进任何动画上下文：胶囊与圆钮重合，材质与子视图在这里排好。
    [UIView performWithoutAnimation:^{
        self->_dimView.hidden = NO;
        self->_dimView.alpha = 0.0;
        self->_panelView.hidden = YES;
        self->_panelView.transform = CGAffineTransformIdentity;
        self->_panelView.frame = metrics.resultsFrame;
        self->_tableView.alpha = 1.0;
        self->_capsuleView.frame = self->_closeButton.frame;
        self->_capsuleView.hidden = NO;
        [self->_capsuleView dkSetContentAlpha:0.0];
        [self->_glassGroup layoutIfNeeded];
    }];
    BOOL reduced = UIAccessibilityIsReduceMotionEnabled();
    [_closeButton dkSetSymbol:@"xmark" animated:!reduced];
    _closeButton.hitControl.accessibilityLabel = @"关闭搜索";

    __weak typeof(self) weakSelf = self;
    dispatch_block_t finish = ^{
        DKSearchOverlayView *overlay = weakSelf;
        if (!overlay) return;
        overlay->_animating = NO;
        // 没等到键盘通知（如硬件键盘）时撤回预估位置。
        if (overlay->_keyboardEstimated) {
            overlay->_keyboardEstimated = NO;
            overlay->_keyboardTop = 0.0;
            [overlay dkFollowKeyboardWithDuration:kDKSearchFadeDuration curve:UIViewAnimationCurveEaseInOut];
        }
        [overlay setNeedsLayout];
        [overlay dkUpdatePanelVisibility];
    };
    if (reduced) {
        [UIView performWithoutAnimation:^{ [self dkApplyExpandedFrames:metrics]; }];
        [UIView animateWithDuration:kDKSearchFadeDuration delay:0.0 options:kDKSearchMotionOptions animations:^{
            self->_dimView.alpha = self->_dimTargetAlpha;
            [self->_capsuleView dkSetContentAlpha:1.0];
        } completion:[self dkCompletionForParts:1 generation:generation finish:finish]];
    } else {
        void (^part)(BOOL) = [self dkCompletionForParts:5 generation:generation finish:finish];
        CGRect group = DKSearchGroupFrame(metrics.closeFrame, metrics, CGRectGetWidth(self.bounds));
        CGFloat neck = DKSearchMergeSpacing(metrics) - kDKSearchNeckInset;
        DKSearchSpring(kDKSearchRiseDuration, 0.0, kDKSearchRiseDamping, ^{
            self->_glassGroup.frame = group;
            self->_dimView.alpha = self->_dimTargetAlpha;
        }, part);
        DKSearchSpring(kDKSearchStretchDuration, 0.0, kDKSearchStretchDamping, ^{
            self->_capsuleView.frame = DKSearchCapsuleFrame(metrics, -metrics.diameter);
        }, part);
        DKSearchSpring(kDKSearchNeckDuration, kDKSearchNeckDelay, 1.0, ^{
            self->_capsuleView.frame = DKSearchCapsuleFrame(metrics, neck);
        }, part);
        DKSearchSpring(kDKSearchReleaseDuration, kDKSearchReleaseDelay, kDKSearchReleaseDamping, ^{
            self->_capsuleView.frame = DKSearchInGroup(metrics.capsuleFrame, metrics);
        }, part);
        DKSearchFadeLater(kDKSearchContentInDelay, kDKSearchContentInDuration, ^{
            [self->_capsuleView dkSetContentAlpha:1.0];
        }, part);
    }
    [self dkApplyAppearance];
    // 先提交起步动画再唤起键盘：首次唤起键盘会同步占用主线程上百毫秒。
    [CATransaction flush];
    [_capsuleView.textField becomeFirstResponder];
}

- (void)dkCollapseAnimated:(BOOL)animated completion:(dispatch_block_t)completion {
    if (!_expanded) {
        if (completion) completion();
        return;
    }
    _expanded = NO;
    _keyboardEstimated = NO;
    NSUInteger generation = [self dkBeginTransition];
    _animating = YES;
    [_capsuleView.textField resignFirstResponder];
    BOOL reduced = UIAccessibilityIsReduceMotionEnabled();
    [_closeButton dkSetSymbol:@"magnifyingglass" animated:animated && !reduced];
    _closeButton.hitControl.accessibilityLabel = @"搜索设置";

    DKSearchMetrics metrics = [self dkMetrics];
    __weak typeof(self) weakSelf = self;
    dispatch_block_t finish = ^{
        DKSearchOverlayView *overlay = weakSelf;
        if (!overlay) return;
        overlay->_capsuleView.hidden = YES;
        overlay->_panelView.hidden = YES;
        overlay->_panelView.transform = CGAffineTransformIdentity;
        overlay->_tableView.alpha = 1.0;
        overlay->_dimView.hidden = YES;
        overlay->_dimView.alpha = 0.0;
        overlay->_capsuleView.textField.text = @"";
        [overlay->_capsuleView dkSetContentAlpha:0.0];
        overlay->_results = @[];
        overlay->_index = nil;
        overlay->_tableView.entries = overlay->_results;
        overlay->_animating = NO;
        [overlay setNeedsLayout];
        if (completion) completion();
    };

    if (!animated) {
        [self dkStopAnimations];
        finish();
        return;
    }
    if (reduced) {
        [UIView animateWithDuration:kDKSearchFadeDuration delay:0.0 options:kDKSearchMotionOptions animations:^{
            self->_dimView.alpha = 0.0;
            self->_tableView.alpha = 0.0;
            [self->_capsuleView dkSetContentAlpha:0.0];
        } completion:[self dkCompletionForParts:1 generation:generation finish:finish]];
        return;
    }
    void (^part)(BOOL) = [self dkCompletionForParts:5 generation:generation finish:finish];
    CGRect group = DKSearchGroupFrame(metrics.fabFrame, metrics, CGRectGetWidth(self.bounds));
    CGRect button = DKSearchInGroup(metrics.fabFrame, metrics);
    CGFloat reach = round(DKSearchMergeSpacing(metrics) * kDKSearchReachRatio);
    DKSearchSpring(kDKSearchSinkDuration, 0.0, kDKSearchSinkDamping, ^{
        self->_glassGroup.frame = group;
        self->_dimView.alpha = 0.0;
    }, part);
    DKSearchSpring(kDKSearchReachDuration, 0.0, 1.0, ^{
        self->_capsuleView.frame = DKSearchCapsuleFrame(metrics, reach);
    }, part);
    DKSearchSpring(kDKSearchMergeDuration, kDKSearchMergeDelay, kDKSearchMergeDamping, ^{
        self->_capsuleView.frame = DKSearchCapsuleFrame(metrics, -metrics.diameter);
    }, part);
    // 缩回圆钮按定时起步而不用动画延迟：大幅收缩的延迟弹簧在等待期间会把胶囊宽度顶出当前位置。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDKSearchAbsorbDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        DKSearchOverlayView *overlay = weakSelf;
        if (!overlay || overlay->_transitionGeneration != generation) return;
        DKSearchSpring(kDKSearchAbsorbDuration, 0.0, kDKSearchAbsorbDamping, ^{
            overlay->_capsuleView.frame = button;
        }, part);
    });
    [UIView animateWithDuration:kDKSearchContentOutDuration delay:0.0 options:kDKSearchMotionOptions animations:^{
        self->_tableView.alpha = 0.0;
        [self->_capsuleView dkSetContentAlpha:0.0];
    } completion:part];
}

- (void)dkDismissImmediately {
    [self dkStopAnimations];
    _expanded = NO;
    _keyboardEstimated = NO;
    _keyboardTop = 0.0;
    [_capsuleView.textField resignFirstResponder];
    _capsuleView.hidden = YES;
    _capsuleView.textField.text = @"";
    [_capsuleView dkSetContentAlpha:0.0];
    _panelView.hidden = YES;
    _panelView.transform = CGAffineTransformIdentity;
    _dimView.hidden = YES;
    _dimView.alpha = 0.0;
    _tableView.alpha = 1.0;
    _results = @[];
    _index = nil;
    _tableView.entries = _results;
    [_closeButton dkSetSymbol:@"magnifyingglass" animated:NO];
    _closeButton.hitControl.accessibilityLabel = @"搜索设置";
    [self setNeedsLayout];
}

#pragma mark 交互

// 同一个圆钮：收起态点按展开，展开态（含展开动画进行中）点按收起；收起动画进行中忽略。
- (void)dkButtonTapped {
    if (_expanded) {
        [self dkCollapseAnimated:YES completion:nil];
        return;
    }
    if (_animating) return;
    [self dkExpand];
}

- (void)dkDimTapped {
    [self dkCollapseAnimated:YES completion:nil];
}

- (void)dkTextChanged {
    if (_capsuleView.textField.markedTextRange) return;
    // 索引在第一次输入时才建，点按展开不等它。
    if (!_index && _expanded) {
        _index = [DKSearchIndex indexForPage:self.hostPage pagePath:DKSearchPagePath(self.hostPage)];
    }
    _results = [_index resultsForQuery:_capsuleView.textField.text] ?: @[];
    _tableView.entries = _results;
    [self dkUpdatePanelVisibility];
}

// 结果显隐只淡入淡出表格内容，玻璃层保持完整材质。
- (void)dkUpdatePanelVisibility {
    DKSearchMetrics metrics = [self dkMetrics];
    BOOL show = _expanded && _results.count > 0 &&
                CGRectGetHeight(metrics.resultsFrame) >= kDKSearchPanelMinHeight;
    NSUInteger generation = ++_panelGeneration;
    if (show) {
        _panelView.hidden = NO;
        _panelView.frame = metrics.resultsFrame;
    }
    // 回显也始终写 alpha=1，覆盖尚未完成的空结果淡出。
    [UIView animateWithDuration:kDKSearchPanelFadeDuration delay:0.0
                       options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        self->_tableView.alpha = show ? 1.0 : 0.0;
    } completion:^(__unused BOOL finished) {
        if (self->_panelGeneration != generation) return;
        self->_panelView.hidden = !show;
    }];
}

- (void)dkCommitEntry:(DKSearchEntry *)entry {
    if (!entry) return;
    UIViewController *host = self.hostPage;
    [self dkCollapseAnimated:YES completion:^{
        if (host) DKSearchRevealTarget(host, entry);
    }];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField.markedTextRange) return YES;
    DKSearchEntry *first = _results.firstObject;
    if (first) {
        [self dkCommitEntry:first];
        return NO;
    }
    [self dkCollapseAnimated:YES completion:nil];
    return NO;
}

@end

#pragma mark - 挂载

static char kDKSearchOverlayKey;
static char kDKSearchFooterKey;
static char kDKSearchOriginalFooterKey;

static CGFloat DKSearchReservedHeight(UIView *host) {
    DKSearchMetrics metrics = DKSearchMetricsMake(host.bounds.size, DKSearchInsetsForHost(host), 0.0);
    if (metrics.diameter < 1.0) return 0.0;
    return metrics.diameter + 2.0 * metrics.edge;
}

void DKSearchAttach(UIViewController *page) {
    if (!page || !DKSettingsPageSections(page)) return;
    if (objc_getAssociatedObject(page, &kDKSearchOverlayKey)) return;
    UIView *host = page.view;
    if (!host) return;
    DKSearchOverlayView *overlay = [[DKSearchOverlayView alloc] initWithHostPage:page];
    overlay.frame = host.bounds;
    objc_setAssociatedObject(page, &kDKSearchOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [host addSubview:overlay];
    [overlay setNeedsLayout];
}

void DKSearchDetach(UIViewController *page) {
    if (!page) return;
    DKSearchOverlayView *overlay = objc_getAssociatedObject(page, &kDKSearchOverlayKey);
    if (overlay) {
        [overlay dkDismissImmediately];
        [overlay removeFromSuperview];
        objc_setAssociatedObject(page, &kDKSearchOverlayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UITableView *table = DKSettingsPageTableView(page);
    UIView *footer = objc_getAssociatedObject(page, &kDKSearchFooterKey);
    if (table && footer && table.tableFooterView == footer) {
        UIView *original = objc_getAssociatedObject(page, &kDKSearchOriginalFooterKey);
        [original removeFromSuperview];
        table.tableFooterView = original;
    }
    objc_setAssociatedObject(page, &kDKSearchFooterKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(page, &kDKSearchOriginalFooterKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void DKSearchUpdateInsets(UIViewController *page) {
    if (!page || !objc_getAssociatedObject(page, &kDKSearchOverlayKey)) return;
    UITableView *table = DKSettingsPageTableView(page);
    if (!table) return;
    CGFloat reserved = DKSearchReservedHeight(page.view);
    if (reserved < 1.0) return;
    UIView *footer = objc_getAssociatedObject(page, &kDKSearchFooterKey);
    UIView *original = objc_getAssociatedObject(page, &kDKSearchOriginalFooterKey);
    if (!footer || table.tableFooterView != footer) {
        original = table.tableFooterView;
        objc_setAssociatedObject(page, &kDKSearchOriginalFooterKey, original, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        footer = [[UIView alloc] initWithFrame:CGRectZero];
        footer.backgroundColor = UIColor.clearColor;
        // 表格先解除旧页脚，再将它嵌入占位容器，避免 UIKit 换页脚时摘掉已移入的旧视图。
        table.tableFooterView = nil;
        if (original) [footer addSubview:original];
        objc_setAssociatedObject(page, &kDKSearchFooterKey, footer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat width = CGRectGetWidth(table.bounds);
    CGFloat originalHeight = CGRectGetHeight(original.frame);
    CGRect frame = CGRectMake(0.0, 0.0, width, originalHeight + reserved);
    if (table.tableFooterView == footer && CGRectEqualToRect(footer.frame, frame)) return;
    if (original) original.frame = CGRectMake(0.0, 0.0, width, originalHeight);
    footer.frame = frame;
    table.tableFooterView = footer;
}
