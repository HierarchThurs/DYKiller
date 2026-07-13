//
//  DKCommentBottomBar.xm
//  功能：隐藏标准竖屏评论面板常驻输入栏，并在回复编辑期间恢复原生输入界面。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>

static char kViewManagedKey;
static char kViewSuppressedKey;
static char kViewOriginalAlphaKey;
static char kViewOriginalHiddenKey;
static char kViewOriginalInteractionKey;
static char kViewOriginalAccessibilityKey;

static char kCommentEditingKey;
static char kCommentVisibleKey;

static char kListNativeContentInsetKey;
static char kListNativeIndicatorInsetKey;
static char kListApplyingContentInsetKey;
static char kListApplyingIndicatorInsetKey;

static id gTextViewBeginEditingObserver;
static id gTextViewEndEditingObserver;
static NSHashTable *gDetailInputBackgroundViews;

static BOOL DKShouldHideCommentBottomBar(void) {
    return DKPrefBool(DKKeyCommentHideBottomBar);
}

static BOOL DKReadBoolSelector(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
}

static Class DKCommentInputContainerClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cls = NSClassFromString(@"AWECommentInputViewSwiftImpl.CommentInputContainerView");
    });
    return cls;
}

static BOOL DKCommentControllerIsStandard(AWECommentContainerViewController *controller) {
    if (!controller) return NO;
    if (DKReadBoolSelector(controller, NSSelectorFromString(@"isLandscape"))) return NO;
    if (DKReadBoolSelector(controller, NSSelectorFromString(@"isEmbeddedVC"))) return NO;
    if (DKReadBoolSelector(controller, NSSelectorFromString(@"isEmbeddedLandscape"))) return NO;
    return YES;
}

static BOOL DKCommentControllerShouldSuppress(AWECommentContainerViewController *controller) {
    if (!DKShouldHideCommentBottomBar() || !DKCommentControllerIsStandard(controller)) return NO;
    if (![objc_getAssociatedObject(controller, &kCommentVisibleKey) boolValue]) return NO;
    return ![objc_getAssociatedObject(controller, &kCommentEditingKey) boolValue];
}

static AWECommentContainerViewController *DKCommentControllerForView(UIView *view) {
    if (!view) return nil;

    UIResponder *responder = view;
    for (NSUInteger i = 0; responder && i < 40; i++) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            UIViewController *controller = (UIViewController *)responder;
            for (NSUInteger depth = 0; controller && depth < 12; depth++) {
                if ([controller isKindOfClass:%c(AWECommentContainerViewController)]) {
                    return (AWECommentContainerViewController *)controller;
                }
                controller = controller.parentViewController;
            }
        }
        responder = responder.nextResponder;
    }
    return nil;
}

static UIView *DKCommentInputContainer(AWECommentContainerViewController *controller) {
    Class inputClass = DKCommentInputContainerClass();
    if (!controller || !inputClass || !controller.isViewLoaded) return nil;

    for (UIView *subview in controller.view.subviews) {
        if ([subview isKindOfClass:inputClass]) return subview;
    }
    return nil;
}

static BOOL DKViewIsDescendantOfView(UIView *view, UIView *ancestor) {
    for (UIView *candidate = view; candidate; candidate = candidate.superview) {
        if (candidate == ancestor) return YES;
    }
    return NO;
}

#pragma mark - 通用视图状态

static void DKRememberViewState(UIView *view) {
    if (!view || [objc_getAssociatedObject(view, &kViewManagedKey) boolValue]) return;

    objc_setAssociatedObject(view, &kViewOriginalAlphaKey, @(view.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kViewOriginalHiddenKey, @(view.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kViewOriginalInteractionKey, @(view.userInteractionEnabled), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kViewOriginalAccessibilityKey, @(view.accessibilityElementsHidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kViewManagedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DKSuppressView(UIView *view, BOOL setHidden) {
    if (!view) return;
    DKRememberViewState(view);

    if (view.alpha != 0.0) view.alpha = 0.0;
    if (setHidden && !view.hidden) view.hidden = YES;
    if (view.userInteractionEnabled) view.userInteractionEnabled = NO;
    if (!view.accessibilityElementsHidden) view.accessibilityElementsHidden = YES;
    objc_setAssociatedObject(view, &kViewSuppressedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DKRestoreView(UIView *view) {
    if (!view || ![objc_getAssociatedObject(view, &kViewManagedKey) boolValue]) return;

    if ([objc_getAssociatedObject(view, &kViewSuppressedKey) boolValue]) {
        NSNumber *alpha = objc_getAssociatedObject(view, &kViewOriginalAlphaKey);
        NSNumber *hidden = objc_getAssociatedObject(view, &kViewOriginalHiddenKey);
        NSNumber *interaction = objc_getAssociatedObject(view, &kViewOriginalInteractionKey);
        NSNumber *accessibility = objc_getAssociatedObject(view, &kViewOriginalAccessibilityKey);
        if (alpha) view.alpha = alpha.doubleValue;
        if (hidden) view.hidden = hidden.boolValue;
        if (interaction) view.userInteractionEnabled = interaction.boolValue;
        if (accessibility) view.accessibilityElementsHidden = accessibility.boolValue;
    }

    objc_setAssociatedObject(view, &kViewOriginalAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kViewOriginalHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kViewOriginalInteractionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kViewOriginalAccessibilityKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kViewSuppressedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kViewManagedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - 评论列表 inset

static void DKSetListContentInset(AWEListKitMagicCollectionView *collectionView, UIEdgeInsets inset) {
    objc_setAssociatedObject(collectionView, &kListApplyingContentInsetKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    collectionView.contentInset = inset;
    objc_setAssociatedObject(collectionView, &kListApplyingContentInsetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DKSetListIndicatorInset(AWEListKitMagicCollectionView *collectionView, UIEdgeInsets inset) {
    objc_setAssociatedObject(collectionView, &kListApplyingIndicatorInsetKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    collectionView.scrollIndicatorInsets = inset;
    objc_setAssociatedObject(collectionView, &kListApplyingIndicatorInsetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DKApplyCommentListState(AWEListKitMagicCollectionView *collectionView, BOOL forgetState) {
    if (!collectionView) return;

    AWECommentContainerViewController *controller = DKCommentControllerForView(collectionView);
    BOOL suppress = DKCommentControllerShouldSuppress(controller);

    NSValue *nativeContentValue = objc_getAssociatedObject(collectionView, &kListNativeContentInsetKey);
    NSValue *nativeIndicatorValue = objc_getAssociatedObject(collectionView, &kListNativeIndicatorInsetKey);
    if (!nativeContentValue && controller) {
        nativeContentValue = [NSValue valueWithUIEdgeInsets:collectionView.contentInset];
        objc_setAssociatedObject(collectionView, &kListNativeContentInsetKey, nativeContentValue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!nativeIndicatorValue && controller) {
        nativeIndicatorValue = [NSValue valueWithUIEdgeInsets:collectionView.scrollIndicatorInsets];
        objc_setAssociatedObject(collectionView, &kListNativeIndicatorInsetKey, nativeIndicatorValue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (suppress) {
        UIEdgeInsets contentInset = nativeContentValue ? nativeContentValue.UIEdgeInsetsValue : collectionView.contentInset;
        UIEdgeInsets indicatorInset = nativeIndicatorValue ? nativeIndicatorValue.UIEdgeInsetsValue : collectionView.scrollIndicatorInsets;
        contentInset.bottom = 0.0;
        indicatorInset.bottom = 0.0;
        if (!UIEdgeInsetsEqualToEdgeInsets(collectionView.contentInset, contentInset)) {
            DKSetListContentInset(collectionView, contentInset);
        }
        if (!UIEdgeInsetsEqualToEdgeInsets(collectionView.scrollIndicatorInsets, indicatorInset)) {
            DKSetListIndicatorInset(collectionView, indicatorInset);
        }
    } else {
        if (nativeContentValue && !UIEdgeInsetsEqualToEdgeInsets(collectionView.contentInset, nativeContentValue.UIEdgeInsetsValue)) {
            DKSetListContentInset(collectionView, nativeContentValue.UIEdgeInsetsValue);
        }
        if (nativeIndicatorValue && !UIEdgeInsetsEqualToEdgeInsets(collectionView.scrollIndicatorInsets, nativeIndicatorValue.UIEdgeInsetsValue)) {
            DKSetListIndicatorInset(collectionView, nativeIndicatorValue.UIEdgeInsetsValue);
        }
    }

    if (forgetState) {
        objc_setAssociatedObject(collectionView, &kListNativeContentInsetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(collectionView, &kListNativeIndicatorInsetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void DKRefreshCommentListsInView(UIView *view, BOOL forgetState) {
    if (!view) return;
    if ([view isKindOfClass:%c(AWEListKitMagicCollectionView)]) {
        DKApplyCommentListState((AWEListKitMagicCollectionView *)view, forgetState);
    }
    for (UIView *subview in view.subviews) {
        DKRefreshCommentListsInView(subview, forgetState);
    }
}

#pragma mark - 评论底部渐隐层

static UIViewController *DKFindChildControllerNamed(UIViewController *controller, NSString *className, NSUInteger depth) {
    if (!controller || depth > 12) return nil;
    for (UIViewController *child in controller.childViewControllers) {
        if ([NSStringFromClass(child.class) isEqualToString:className]) return child;
        UIViewController *match = DKFindChildControllerNamed(child, className, depth + 1);
        if (match) return match;
    }
    return nil;
}

static BOOL DKIsBottomCommentEdgeEffect(UIView *view, UIView *containerView) {
    if (!view || !containerView) return NO;
    if (![NSStringFromClass(view.class) isEqualToString:@"UIKit.ScrollEdgeEffectView"]) return NO;

    CGRect frame = [view convertRect:view.bounds toView:containerView];
    CGRect bounds = containerView.bounds;
    CGFloat tolerance = MAX(1.0 / UIScreen.mainScreen.scale, 0.5);
    BOOL fullWidth = fabs(CGRectGetMinX(frame) - CGRectGetMinX(bounds)) <= tolerance
        && fabs(CGRectGetWidth(frame) - CGRectGetWidth(bounds)) <= tolerance;
    BOOL bottomAligned = fabs(CGRectGetMaxY(frame) - CGRectGetMaxY(bounds)) <= tolerance;
    return fullWidth && bottomAligned;
}

static void DKApplyCommentEdgeEffectsInView(UIView *view, UIView *containerView, BOOL suppress) {
    if (!view) return;
    if (DKIsBottomCommentEdgeEffect(view, containerView)) {
        if (suppress) {
            DKSuppressView(view, YES);
        } else {
            DKRestoreView(view);
        }
    }
    for (UIView *subview in view.subviews) {
        DKApplyCommentEdgeEffectsInView(subview, containerView, suppress);
    }
}

static void DKApplyCommentEdgeEffectState(AWECommentContainerViewController *controller, BOOL suppress) {
    UIViewController *innerController = DKFindChildControllerNamed(
        controller,
        @"AWECommentPanelContainerSwiftImpl.CommentContainerInnerViewController",
        0
    );
    if (!innerController.isViewLoaded) return;
    DKApplyCommentEdgeEffectsInView(innerController.view, innerController.view, suppress);
}

#pragma mark - 详情页底层输入栏

static AWECommentContainerViewController *DKFindActiveCommentController(UIViewController *controller, UIWindow *window) {
    if (!controller) return nil;

    if ([controller isKindOfClass:%c(AWECommentContainerViewController)]
        && [objc_getAssociatedObject(controller, &kCommentVisibleKey) boolValue]
        && controller.isViewLoaded
        && controller.view.window == window
        && DKCommentControllerIsStandard((AWECommentContainerViewController *)controller)) {
        return (AWECommentContainerViewController *)controller;
    }

    UIViewController *presentedMatch = DKFindActiveCommentController(controller.presentedViewController, window);
    if (presentedMatch) return (AWECommentContainerViewController *)presentedMatch;
    for (UIViewController *child in controller.childViewControllers) {
        AWECommentContainerViewController *match = DKFindActiveCommentController(child, window);
        if (match) return match;
    }
    return nil;
}

static AWECommentContainerViewController *DKActiveCommentControllerInWindow(UIWindow *window) {
    if (!window) return nil;
    return DKFindActiveCommentController(window.rootViewController, window);
}

static BOOL DKShouldSuppressDetailInputBackground(AWECommentInputBackgroundView *backgroundView) {
    AWECommentContainerViewController *controller = DKActiveCommentControllerInWindow(backgroundView.window);
    return DKCommentControllerShouldSuppress(controller);
}

static void DKApplyDetailInputBackgroundState(AWECommentInputBackgroundView *backgroundView) {
    if (!backgroundView) return;
    if (DKShouldSuppressDetailInputBackground(backgroundView)) {
        DKSuppressView(backgroundView, NO);
    } else {
        DKRestoreView(backgroundView);
    }
}

static void DKRefreshDetailInputBackgroundsInWindow(UIWindow *window) {
    for (AWECommentInputBackgroundView *backgroundView in gDetailInputBackgroundViews.allObjects) {
        if (backgroundView.window == window) {
            DKApplyDetailInputBackgroundState(backgroundView);
        }
    }
}

#pragma mark - 评论控制器状态

static void DKApplyCommentControllerState(AWECommentContainerViewController *controller) {
    if (!controller || !controller.isViewLoaded) return;

    BOOL standard = DKCommentControllerIsStandard(controller);
    BOOL enabled = DKShouldHideCommentBottomBar() && standard;
    BOOL suppress = DKCommentControllerShouldSuppress(controller);
    if (!enabled) {
        objc_setAssociatedObject(controller, &kCommentEditingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    UIView *inputView = DKCommentInputContainer(controller);
    if (suppress) {
        DKSuppressView(inputView, NO);
    } else {
        DKRestoreView(inputView);
    }

    DKRefreshCommentListsInView(controller.view, !enabled);
    DKApplyCommentEdgeEffectState(controller, suppress);
    DKRefreshDetailInputBackgroundsInWindow(controller.view.window);
}

static void DKRestoreCommentControllerState(AWECommentContainerViewController *controller) {
    if (!controller || !controller.isViewLoaded) return;

    DKRestoreView(DKCommentInputContainer(controller));
    DKRefreshCommentListsInView(controller.view, YES);
    DKApplyCommentEdgeEffectState(controller, NO);
}

static AWECommentContainerViewController *DKCommentControllerForTextView(UIView *textView) {
    AWECommentContainerViewController *controller = DKCommentControllerForView(textView);
    UIView *inputView = DKCommentInputContainer(controller);
    if (!controller || !inputView || !DKViewIsDescendantOfView(textView, inputView)) return nil;
    return controller;
}

static void DKSetCommentEditing(AWECommentContainerViewController *controller, BOOL editing) {
    if (!controller || !DKShouldHideCommentBottomBar() || !DKCommentControllerIsStandard(controller)) return;

    objc_setAssociatedObject(controller, &kCommentEditingKey, @(editing), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKApplyCommentControllerState(controller);
}

%hook AWECommentContainerViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    objc_setAssociatedObject(self, &kCommentVisibleKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKApplyCommentControllerState(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    DKApplyCommentControllerState(self);
}

- (void)viewWillDisappear:(BOOL)animated {
    UIWindow *window = self.view.window;
    %orig;
    objc_setAssociatedObject(self, &kCommentVisibleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &kCommentEditingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKRestoreCommentControllerState(self);
    DKRefreshDetailInputBackgroundsInWindow(window);
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    objc_setAssociatedObject(self, &kCommentVisibleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &kCommentEditingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%end

%hook AWEListKitMagicCollectionView

- (void)setContentInset:(UIEdgeInsets)contentInset {
    if ([objc_getAssociatedObject(self, &kListApplyingContentInsetKey) boolValue]) {
        %orig(contentInset);
        return;
    }

    AWECommentContainerViewController *controller = DKCommentControllerForView(self);
    if (controller) {
        objc_setAssociatedObject(self, &kListNativeContentInsetKey,
                                 [NSValue valueWithUIEdgeInsets:contentInset],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (DKCommentControllerShouldSuppress(controller)) contentInset.bottom = 0.0;
    }
    %orig(contentInset);
}

- (void)setScrollIndicatorInsets:(UIEdgeInsets)scrollIndicatorInsets {
    if ([objc_getAssociatedObject(self, &kListApplyingIndicatorInsetKey) boolValue]) {
        %orig(scrollIndicatorInsets);
        return;
    }

    AWECommentContainerViewController *controller = DKCommentControllerForView(self);
    if (controller) {
        objc_setAssociatedObject(self, &kListNativeIndicatorInsetKey,
                                 [NSValue valueWithUIEdgeInsets:scrollIndicatorInsets],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (DKCommentControllerShouldSuppress(controller)) scrollIndicatorInsets.bottom = 0.0;
    }
    %orig(scrollIndicatorInsets);
}

- (void)layoutSubviews {
    %orig;
    AWECommentContainerViewController *controller = DKCommentControllerForView(self);
    BOOL forgetState = controller && (!DKShouldHideCommentBottomBar() || !DKCommentControllerIsStandard(controller));
    DKApplyCommentListState(self, forgetState);
}

%end

%hook AWECommentInputBackgroundView

- (void)didMoveToWindow {
    %orig;
    if (self.window) [gDetailInputBackgroundViews addObject:self];
    DKApplyDetailInputBackgroundState(self);
}

- (void)layoutSubviews {
    %orig;
    DKApplyDetailInputBackgroundState(self);
}

%end

#pragma mark - 设置与编辑状态

%ctor {
    gDetailInputBackgroundViews = [NSHashTable weakObjectsHashTable];

    DKSettingsRegisterItem(@"评论区", ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyCommentHideBottomBar, @"移除评论区底栏", @"隐藏常驻输入栏，回复时临时恢复");
    });

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    gTextViewBeginEditingObserver = [center addObserverForName:UITextViewTextDidBeginEditingNotification
                                                       object:nil
                                                        queue:[NSOperationQueue mainQueue]
                                                   usingBlock:^(NSNotification *notification) {
        if (![notification.object isKindOfClass:[UIView class]]) return;
        AWECommentContainerViewController *controller = DKCommentControllerForTextView((UIView *)notification.object);
        DKSetCommentEditing(controller, YES);
    }];
    gTextViewEndEditingObserver = [center addObserverForName:UITextViewTextDidEndEditingNotification
                                                     object:nil
                                                      queue:[NSOperationQueue mainQueue]
                                                 usingBlock:^(NSNotification *notification) {
        if (![notification.object isKindOfClass:[UIView class]]) return;
        AWECommentContainerViewController *controller = DKCommentControllerForTextView((UIView *)notification.object);
        if (!controller) return;
        __weak AWECommentContainerViewController *weakController = controller;
        dispatch_async(dispatch_get_main_queue(), ^{
            DKSetCommentEditing(weakController, NO);
        });
    }];
}
