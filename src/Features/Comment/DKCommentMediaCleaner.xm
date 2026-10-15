//
//  DKCommentMediaCleaner.xm
//  功能：清理评论图片大图页底栏、返回键与渐变，并让图片在完整窗口内按原比例居中显示。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import <math.h>
#import <objc/runtime.h>

static NSString *const kDKMediaInputClass =
    @"AWECommentInputViewSwiftImpl.CommentInputContainerView";
static NSString *const kDKMediaCommonControllerClass =
    @"AWECommentMediaFeedSwfitImpl.CommentMediaFeedCommonImageCellViewController";
static NSString *const kDKMediaInteractionControllerClass =
    @"AWECommentMediaFeedSwfitImpl.CommentMediaFeedPlayInteractionViewController";
static NSString *const kDKMediaInteractionViewClass =
    @"AWECommentMediaFeedSwfitImpl.CommentMediaFeedPlayInteractionView";
static NSString *const kDKMediaUserNameViewClass =
    @"AWECommentMediaFeedSwfitImpl.CommentMediaFeedUserNameContainerView";
static NSString *const kDKMediaInteractionTagClass =
    @"AWECommentMediaFeedSwfitImpl.CommentMediaFeedPlayInteractionTag";
static NSString *const kDKMediaPreviewClass =
    @"AWECommentMediaFeedSwfitImpl.CommentMediaFeedImagePreviewView";
static NSString *const kDKMediaBackButtonIdentifier = @"CommentMediaFeedBackButton";

static char kDKMediaVisibilityManagedKey;
static char kDKMediaOriginalAlphaKey;
static char kDKMediaOriginalHiddenKey;
static char kDKMediaOriginalInteractionKey;
static char kDKMediaOriginalAccessibilityKey;
static char kDKMediaOriginalContentModeKey;
static char kDKMediaCollectionExpandedKey;
static char kDKMediaCollectionSizeKey;
static char kDKMediaNativeReanchorKey;
static char kDKMediaPendingReanchorKey;

static NSHashTable<UIView *> *gDKMediaManagedViews;
static NSHashTable<AWECommentMediaFeedViewController *> *gDKMediaControllers;

// 本功能开启时，大图页 viewDidLayoutSubviews 期间为 YES：抖音的自适应窗口布局会把集合视图 frame
// 重设回自己的口径并回卷位置，与整窗 frame 互相覆盖。只在主线程读写。
static BOOL gDKMediaSuppressAdaptiveLayout;

static BOOL DKCommentMediaCleanerEnabled(void) {
    return DKPrefBool(DKKeyCommentMediaCleanBottomBar);
}

#pragma mark - 可逆视图状态

static void DKMediaRememberVisibility(UIView *view) {
    if (!view || [objc_getAssociatedObject(view, &kDKMediaVisibilityManagedKey) boolValue]) return;

    objc_setAssociatedObject(view, &kDKMediaOriginalAlphaKey,
                             @(view.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kDKMediaOriginalHiddenKey,
                             @(view.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kDKMediaOriginalInteractionKey,
                             @(view.userInteractionEnabled), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kDKMediaOriginalAccessibilityKey,
                             @(view.accessibilityElementsHidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kDKMediaVisibilityManagedKey,
                             @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gDKMediaManagedViews addObject:view];
}

static void DKMediaSuppressView(UIView *view) {
    if (!view) return;
    DKMediaRememberVisibility(view);

    if (view.alpha != 0.0) view.alpha = 0.0;
    if (!view.hidden) view.hidden = YES;
    if (view.userInteractionEnabled) view.userInteractionEnabled = NO;
    if (!view.accessibilityElementsHidden) view.accessibilityElementsHidden = YES;
}

static void DKMediaApplyAspectFit(UIView *view) {
    if (!view) return;
    if (!objc_getAssociatedObject(view, &kDKMediaOriginalContentModeKey)) {
        objc_setAssociatedObject(view, &kDKMediaOriginalContentModeKey,
                                 @(view.contentMode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gDKMediaManagedViews addObject:view];
    }
    if (view.contentMode != UIViewContentModeScaleAspectFit) {
        view.contentMode = UIViewContentModeScaleAspectFit;
    }
}

static void DKMediaRestoreView(UIView *view) {
    if (!view) return;

    if ([objc_getAssociatedObject(view, &kDKMediaVisibilityManagedKey) boolValue]) {
        NSNumber *alpha = objc_getAssociatedObject(view, &kDKMediaOriginalAlphaKey);
        NSNumber *hidden = objc_getAssociatedObject(view, &kDKMediaOriginalHiddenKey);
        NSNumber *interaction = objc_getAssociatedObject(view, &kDKMediaOriginalInteractionKey);
        NSNumber *accessibility = objc_getAssociatedObject(view, &kDKMediaOriginalAccessibilityKey);
        if (alpha) view.alpha = alpha.doubleValue;
        if (hidden) view.hidden = hidden.boolValue;
        if (interaction) view.userInteractionEnabled = interaction.boolValue;
        if (accessibility) view.accessibilityElementsHidden = accessibility.boolValue;

        objc_setAssociatedObject(view, &kDKMediaVisibilityManagedKey,
                                 nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &kDKMediaOriginalAlphaKey,
                                 nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &kDKMediaOriginalHiddenKey,
                                 nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &kDKMediaOriginalInteractionKey,
                                 nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &kDKMediaOriginalAccessibilityKey,
                                 nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    NSNumber *contentMode = objc_getAssociatedObject(view, &kDKMediaOriginalContentModeKey);
    if (contentMode) {
        view.contentMode = (UIViewContentMode)contentMode.integerValue;
        objc_setAssociatedObject(view, &kDKMediaOriginalContentModeKey,
                                 nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    [gDKMediaManagedViews removeObject:view];
}

static void DKMediaRestoreViewsUnderRoot(UIView *root) {
    if (!root) return;
    for (UIView *view in gDKMediaManagedViews.allObjects) {
        if (view == root || [view isDescendantOfView:root]) DKMediaRestoreView(view);
    }
}

static void DKMediaRestoreAllViews(void) {
    for (UIView *view in gDKMediaManagedViews.allObjects) DKMediaRestoreView(view);
}

#pragma mark - 结构匹配

static Class DKMediaInputClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(kDKMediaInputClass); });
    return cls;
}

static BOOL DKMediaViewContainsClass(UIView *view, NSString *className, NSUInteger depth) {
    if (!view || depth > 12) return NO;
    if ([NSStringFromClass(view.class) isEqualToString:className]) return YES;
    for (UIView *subview in view.subviews) {
        if (DKMediaViewContainsClass(subview, className, depth + 1)) return YES;
    }
    return NO;
}

static UIView *DKMediaDescendantNamed(UIView *view, NSString *className, NSUInteger depth) {
    if (!view || depth > 12) return nil;
    if ([NSStringFromClass(view.class) isEqualToString:className]) return view;
    for (UIView *subview in view.subviews) {
        UIView *match = DKMediaDescendantNamed(subview, className, depth + 1);
        if (match) return match;
    }
    return nil;
}

static void DKMediaCollectControllersNamed(UIViewController *controller,
                                           NSString *className,
                                           NSMutableArray<UIViewController *> *output,
                                           NSUInteger depth) {
    if (!controller || depth > 12) return;
    for (UIViewController *child in controller.childViewControllers) {
        if ([NSStringFromClass(child.class) isEqualToString:className]) [output addObject:child];
        DKMediaCollectControllersNamed(child, className, output, depth + 1);
    }
}

static NSArray<UIViewController *> *DKMediaControllersNamed(UIViewController *controller,
                                                             NSString *className) {
    NSMutableArray<UIViewController *> *result = [NSMutableArray array];
    DKMediaCollectControllersNamed(controller, className, result, 0);
    return result;
}

static UICollectionView *DKMediaPageCollection(AWECommentMediaFeedViewController *controller) {
    if (!controller.isViewLoaded) return nil;
    UICollectionView *fallback = nil;
    for (UIView *subview in controller.view.subviews) {
        if (![subview isKindOfClass:UICollectionView.class]) continue;
        UICollectionView *collection = (UICollectionView *)subview;
        if (!fallback) fallback = collection;
        if (collection.delegate == (id<UICollectionViewDelegate>)controller
            || collection.dataSource == (id<UICollectionViewDataSource>)controller) {
            return collection;
        }
    }
    return fallback;
}

static UIView *DKMediaInputView(AWECommentMediaFeedViewController *controller) {
    Class inputClass = DKMediaInputClass();
    if (!inputClass || !controller.isViewLoaded) return nil;
    for (UIView *subview in controller.view.subviews) {
        if ([subview isKindOfClass:inputClass]) return subview;
    }
    return nil;
}

static BOOL DKMediaButtonHasAction(UIButton *button, SEL action) {
    if (!button || !action) return NO;
    for (id target in button.allTargets) {
        NSArray<NSString *> *actions =
            [button actionsForTarget:target forControlEvent:UIControlEventTouchUpInside];
        if ([actions containsObject:NSStringFromSelector(action)]) return YES;
    }
    return NO;
}

// 返回键是根视图直属 UIButton。优先取控制器的 backButton，其次认
// CommentMediaFeedBackButton，再认 previewDismissByClickBackBtn。不碰删除键。
static UIView *DKMediaBackButton(AWECommentMediaFeedViewController *controller) {
    if (!controller.isViewLoaded) return nil;

    if ([controller respondsToSelector:@selector(backButton)]) {
        UIView *button = controller.backButton;
        if (button) return button;
    }

    SEL action = @selector(previewDismissByClickBackBtn);
    for (UIView *subview in controller.view.subviews) {
        if (![subview isKindOfClass:UIButton.class]) continue;
        UIButton *button = (UIButton *)subview;
        if ([button.accessibilityIdentifier isEqualToString:kDKMediaBackButtonIdentifier]
            || DKMediaButtonHasAction(button, action)) {
            return button;
        }
    }
    return nil;
}

#pragma mark - 页面控件

static void DKMediaApplyInteractionControls(AWECommentMediaFeedViewController *controller) {
    for (UIViewController *interaction in
         DKMediaControllersNamed(controller, kDKMediaInteractionControllerClass)) {
        UIView *root = interaction.viewIfLoaded;
        for (UIView *container in root.subviews) {
            BOOL containsLike =
                DKMediaViewContainsClass(container, kDKMediaInteractionViewClass, 0);
            BOOL containsInfo =
                DKMediaViewContainsClass(container, kDKMediaUserNameViewClass, 0)
                || DKMediaViewContainsClass(container, kDKMediaInteractionTagClass, 0);
            if (containsLike || containsInfo) {
                DKMediaSuppressView(container);
            } else {
                DKMediaRestoreView(container);
            }
        }
    }
}

static BOOL DKMediaGradientMatchesEdge(UIView *view, BOOL top) {
    if (![NSStringFromClass(view.class) isEqualToString:@"AWEGradientView"]) return NO;
    UIView *parent = view.superview;
    if (!parent) return NO;

    CGRect frame = [view convertRect:view.bounds toView:parent];
    CGRect bounds = parent.bounds;
    CGFloat tolerance = MAX(1.0 / UIScreen.mainScreen.scale, 0.5);
    BOOL fullWidth = fabs(CGRectGetMinX(frame) - CGRectGetMinX(bounds)) <= tolerance
        && fabs(CGRectGetWidth(frame) - CGRectGetWidth(bounds)) <= tolerance;
    if (!fullWidth) return NO;

    if (top) {
        return fabs(CGRectGetMinY(frame) - CGRectGetMinY(bounds)) <= tolerance
            && CGRectGetMaxY(frame) < CGRectGetMaxY(bounds) - tolerance;
    }
    return fabs(CGRectGetMaxY(frame) - CGRectGetMaxY(bounds)) <= tolerance
        && CGRectGetMinY(frame) > CGRectGetMinY(bounds) + tolerance;
}

static void DKMediaApplyChromeGradients(UIView *view) {
    if (!view) return;
    for (UIView *subview in view.subviews) {
        if ([NSStringFromClass(subview.class) isEqualToString:@"AWEGradientView"]) {
            if (DKMediaGradientMatchesEdge(subview, YES) || DKMediaGradientMatchesEdge(subview, NO)) {
                DKMediaSuppressView(subview);
            } else {
                DKMediaRestoreView(subview);
            }
            continue;
        }
        DKMediaApplyChromeGradients(subview);
    }
}

static void DKMediaApplyCommonCellChrome(AWECommentMediaFeedViewController *controller) {
    for (UIViewController *common in
         DKMediaControllersNamed(controller, kDKMediaCommonControllerClass)) {
        DKMediaApplyChromeGradients(common.viewIfLoaded);
    }
}

// 输入栏上沿的分割线是根视图的直属子层，不是 CommentInputContainerView 的后代。
// 判据：普通 UIView、无子视图、全宽、高度不超过 1pt。不写死 y 或底栏高度。
static BOOL DKMediaIsHairlineSeparator(UIView *view, UIView *root) {
    if (!view || !root || view.class != UIView.class || view.subviews.count > 0) return NO;

    CGFloat height = CGRectGetHeight(view.frame);
    if (height <= 0.0 || height > 1.0) return NO;

    CGFloat tolerance = MAX(1.0 / UIScreen.mainScreen.scale, 0.5);
    return fabs(CGRectGetMinX(view.frame) - CGRectGetMinX(root.bounds)) <= tolerance
        && fabs(CGRectGetWidth(view.frame) - CGRectGetWidth(root.bounds)) <= tolerance;
}

static void DKMediaApplyHairlineSeparators(AWECommentMediaFeedViewController *controller) {
    UIView *root = controller.viewIfLoaded;
    if (!root) return;
    for (UIView *subview in root.subviews) {
        if (DKMediaIsHairlineSeparator(subview, root)) DKMediaSuppressView(subview);
    }
}

#pragma mark - 全窗口分页几何

static BOOL DKMediaSizesClose(CGSize lhs, CGSize rhs) {
    return fabs(lhs.width - rhs.width) <= 0.5 && fabs(lhs.height - rhs.height) <= 0.5;
}

static BOOL DKMediaRectsClose(CGRect lhs, CGRect rhs) {
    return fabs(CGRectGetMinX(lhs) - CGRectGetMinX(rhs)) <= 0.5
        && fabs(CGRectGetMinY(lhs) - CGRectGetMinY(rhs)) <= 0.5
        && DKMediaSizesClose(lhs.size, rhs.size);
}

// 目标页还没有数据时返回 NO，由调用方在后续布局里再试。
static BOOL DKMediaReanchorCurrentItem(AWECommentMediaFeedViewController *controller,
                                       UICollectionView *collection) {
    NSInteger index = (NSInteger)controller.currentIndex;
    if (index < 0 || collection.numberOfSections == 0
        || index >= [collection numberOfItemsInSection:0]) {
        return NO;
    }

    NSIndexPath *path = [NSIndexPath indexPathForItem:index inSection:0];
    [collection scrollToItemAtIndexPath:path
                       atScrollPosition:UICollectionViewScrollPositionCenteredVertically
                               animated:NO];
    return YES;
}

static void DKMediaResetCollectionState(AWECommentMediaFeedViewController *controller) {
    UICollectionView *collection = DKMediaPageCollection(controller);
    if (!collection || ![objc_getAssociatedObject(collection, &kDKMediaCollectionExpandedKey) boolValue]) {
        return;
    }

    objc_setAssociatedObject(collection, &kDKMediaCollectionExpandedKey,
                             nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(collection, &kDKMediaCollectionSizeKey,
                             nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller, &kDKMediaPendingReanchorKey,
                             nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller, &kDKMediaNativeReanchorKey,
                             @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [collection.collectionViewLayout invalidateLayout];
    [controller.view setNeedsLayout];
}

static void DKMediaApplyCollectionState(AWECommentMediaFeedViewController *controller, BOOL enabled) {
    UICollectionView *collection = DKMediaPageCollection(controller);
    if (!collection) return;

    if (!enabled) {
        DKMediaResetCollectionState(controller);
        if ([objc_getAssociatedObject(controller, &kDKMediaNativeReanchorKey) boolValue]) {
            [UIView performWithoutAnimation:^{
                [collection.collectionViewLayout invalidateLayout];
                [collection layoutIfNeeded];
                DKMediaReanchorCurrentItem(controller, collection);
            }];
            objc_setAssociatedObject(controller, &kDKMediaNativeReanchorKey,
                                     nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }

    CGFloat width = CGRectGetWidth(controller.view.bounds);
    CGFloat height = CGRectGetHeight(controller.view.bounds);
    if (width <= 0.0 || height <= 0.0) return;

    CGSize targetSize = CGSizeMake(width, height);
    CGRect targetFrame = CGRectMake(0.0, 0.0, width, height);
    BOOL wasExpanded =
        [objc_getAssociatedObject(collection, &kDKMediaCollectionExpandedKey) boolValue];
    NSValue *lastSizeValue = objc_getAssociatedObject(collection, &kDKMediaCollectionSizeKey);
    BOOL sizeChanged = !wasExpanded || !lastSizeValue
        || !DKMediaSizesClose(lastSizeValue.CGSizeValue, targetSize);

    objc_setAssociatedObject(collection, &kDKMediaCollectionExpandedKey,
                             @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(collection, &kDKMediaCollectionSizeKey,
                             [NSValue valueWithCGSize:targetSize], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller, &kDKMediaNativeReanchorKey,
                             nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // 尺寸变化后回卷到 currentIndex；目标页尚无数据时保留标记，下次布局再试，成功即清除。
    if (sizeChanged) {
        objc_setAssociatedObject(controller, &kDKMediaPendingReanchorKey,
                                 @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL pendingReanchor = [objc_getAssociatedObject(controller, &kDKMediaPendingReanchorKey) boolValue];

    [UIView performWithoutAnimation:^{
        if (!DKMediaRectsClose(collection.frame, targetFrame)) collection.frame = targetFrame;
        if (sizeChanged) {
            [collection.collectionViewLayout invalidateLayout];
            [collection layoutIfNeeded];
        }
        if (pendingReanchor && DKMediaReanchorCurrentItem(controller, collection)) {
            objc_setAssociatedObject(controller, &kDKMediaPendingReanchorKey,
                                     nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }];
}

static void DKMediaApplyControllerState(AWECommentMediaFeedViewController *controller) {
    if (!controller || !controller.isViewLoaded) return;
    BOOL enabled = DKCommentMediaCleanerEnabled();

    if (!enabled) {
        DKMediaRestoreViewsUnderRoot(controller.view);
        DKMediaApplyCollectionState(controller, NO);
        return;
    }

    DKMediaApplyCollectionState(controller, YES);
    DKMediaSuppressView(DKMediaInputView(controller));
    DKMediaSuppressView(DKMediaBackButton(controller));
    DKMediaApplyHairlineSeparators(controller);
    DKMediaApplyInteractionControls(controller);
    DKMediaApplyCommonCellChrome(controller);
}

#pragma mark - 图片显示模式

static BOOL DKMediaIsPreviewCarrier(UIView *view) {
    if ([view isKindOfClass:UIImageView.class]) return YES;
    return [NSStringFromClass(view.class) isEqualToString:@"PHLivePhotoView"];
}

static void DKMediaApplyImageCellState(AWECommentMediaFeedImageCell *cell) {
    UIView *mediaRoot = nil;
    if ([cell respondsToSelector:@selector(mediaContainerView)]) mediaRoot = [cell mediaContainerView];
    UIView *preview = DKMediaDescendantNamed(mediaRoot ?: cell, kDKMediaPreviewClass, 0);
    if (!preview && mediaRoot != cell) {
        preview = DKMediaDescendantNamed(cell, kDKMediaPreviewClass, 0);
    }
    if (!preview) return;

    BOOL enabled = DKCommentMediaCleanerEnabled() && cell.window;
    for (UIView *carrier in preview.subviews) {
        if (!DKMediaIsPreviewCarrier(carrier)) continue;
        if (enabled) {
            DKMediaApplyAspectFit(carrier);
        } else {
            DKMediaRestoreView(carrier);
        }
    }
}

#pragma mark - 钩子

%hook AWECommentMediaFeedViewController

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGSize size = %orig;
    if (!DKCommentMediaCleanerEnabled() || collectionView != DKMediaPageCollection(self)) return size;

    CGSize target = self.view.bounds.size;
    return target.width > 0.0 && target.height > 0.0 ? target : size;
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [gDKMediaControllers addObject:self];
    [self.view setNeedsLayout];
}

- (void)viewDidLayoutSubviews {
    BOOL outerSuppress = gDKMediaSuppressAdaptiveLayout;
    gDKMediaSuppressAdaptiveLayout = DKCommentMediaCleanerEnabled();
    %orig;
    gDKMediaSuppressAdaptiveLayout = outerSuppress;
    [gDKMediaControllers addObject:self];
    DKMediaApplyControllerState(self);
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (self.viewIfLoaded.window) return;
    DKMediaRestoreViewsUnderRoot(self.viewIfLoaded);
    DKMediaResetCollectionState(self);
    [gDKMediaControllers removeObject:self];
}

%end

%hook AWECommentMediaFeedImageCell

- (void)layoutSubviews {
    %orig;
    DKMediaApplyImageCellState(self);
}

- (void)didMoveToWindow {
    %orig;
    DKMediaApplyImageCellState(self);
}

%end

// 只在本功能接管的大图页布局期间关掉自适应窗口布局，其他调用方照常读实验位。
%group DKMediaAdaptiveLayoutHook

%hook AWECommentABTestSettings

+ (BOOL)enableCommentAdaptiveWindowResponsiveLayout {
    if (gDKMediaSuppressAdaptiveLayout) return NO;
    return %orig;
}

%end

%end

#pragma mark - 设置

%ctor {
    gDKMediaManagedViews = [NSHashTable weakObjectsHashTable];
    gDKMediaControllers = [NSHashTable weakObjectsHashTable];

    %init;
    // 实验位方法不在时不装：内部 generator 对不存在的方法会新增实现，%orig 无处可调。
    Class abTest = NSClassFromString(@"AWECommentABTestSettings");
    if ([abTest respondsToSelector:@selector(enableCommentAdaptiveWindowResponsiveLayout)]) {
        %init(DKMediaAdaptiveLayoutHook);
    }

    DKSettingsRegister(DKKeyCommentMediaCleanBottomBar, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(
            DKKeyCommentMediaCleanBottomBar,
            @"评论区图片清理底栏",
            @"隐藏图片页底栏、返回键与底部交互，图片完整居中显示"
        );
        void (^origBlock)(void) = [item.switchChangedBlock copy];
        item.switchChangedBlock = ^{
            if (origBlock) origBlock();
            void (^refresh)(void) = ^{
                BOOL enabled = DKCommentMediaCleanerEnabled();
                if (!enabled) DKMediaRestoreAllViews();
                for (AWECommentMediaFeedViewController *controller in
                     gDKMediaControllers.allObjects) {
                    if (!enabled) DKMediaResetCollectionState(controller);
                    [controller.viewIfLoaded setNeedsLayout];
                }
            };
            if (NSThread.isMainThread) refresh();
            else dispatch_async(dispatch_get_main_queue(), refresh);
        };
        return item;
    });
}
