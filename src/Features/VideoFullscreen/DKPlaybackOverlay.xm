// 视频全屏与玻璃底栏共用的清屏视口、工具条背景让位。
#import "DKPlaybackOverlay.h"
#import "DKVideoFullscreen.h"
#import "DKGlassTabBar.h"
#import "DKViewAdjust.h"
#import <objc/runtime.h>

static NSHashTable<AFDPureModePageContainerViewController *> *gDKPurePages;
static NSHashTable<AFDFastSpeedView *> *gDKSpeedViews;
static NSHashTable<AFDRoundRectangleBoxView *> *gDKPureControls;
static NSHashTable<UIView *> *gDKPureProgressViews;
static char kDKOverlayColorKey;
static char kDKPureBottomKey;
static char kDKPureInsetKey;

BOOL DKPlaybackOverlayActive(void) {
    return DKVideoFullscreenOn() || DKGlassTabBarActive();
}

static AFDPureModePageContainerViewController *DKPurePageForView(UIView *view) {
    Class pure = NSClassFromString(@"AFDPureModePageContainerViewController");
    for (UIResponder *owner = view.nextResponder; owner; owner = owner.nextResponder) {
        if ([owner isKindOfClass:pure]) return (AFDPureModePageContainerViewController *)owner;
    }
    return nil;
}

BOOL DKPlaybackOverlayIsPureControl(UIView *view) {
    return DKPurePageForView(view) != nil;
}

// 只保存本功能接管的底色；原生再次落色时更新恢复基线。
static void DKOverlayClearColor(UIView *view, BOOL clear) {
    if (!view) return;
    id original = objc_getAssociatedObject(view, &kDKOverlayColorKey);
    if (clear) {
        if (!original || ![view.backgroundColor isEqual:UIColor.clearColor]) {
            objc_setAssociatedObject(view, &kDKOverlayColorKey,
                view.backgroundColor ?: NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (![view.backgroundColor isEqual:UIColor.clearColor]) view.backgroundColor = UIColor.clearColor;
    } else if (original) {
        if ([view.backgroundColor isEqual:UIColor.clearColor]) {
            view.backgroundColor = original == NSNull.null ? nil : original;
        }
        objc_setAssociatedObject(view, &kDKOverlayColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void DKPureSyncPage(AFDPureModePageContainerViewController *page) {
    UIView *root = page.viewIfLoaded;
    if (!root) return;
    [gDKPurePages addObject:page];
    BOOL active = DKPlaybackOverlayActive();
    objc_setAssociatedObject(page, &kDKPureInsetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKOverlayClearColor(root, active);
    Class listClass = NSClassFromString(@"AFDPureModePageListViewController");
    for (UIViewController *child in page.childViewControllers) {
        if (![child isKindOfClass:listClass]) continue;
        UIView *list = child.viewIfLoaded;
        for (NSLayoutConstraint *constraint in root.constraints) {
            if (!constraint.active || constraint.relation != NSLayoutRelationEqual
                || constraint.multiplier != 1.0
                || constraint.firstAttribute != NSLayoutAttributeBottom
                || constraint.secondAttribute != NSLayoutAttributeBottom) continue;
            BOOL direct = constraint.firstItem == list && constraint.secondItem == root;
            BOOL reverse = constraint.firstItem == root && constraint.secondItem == list;
            if (!direct && !reverse) continue;
            NSNumber *original = objc_getAssociatedObject(constraint, &kDKPureBottomKey);
            if (active) {
                if (!original || constraint.constant != 0.0) {
                    objc_setAssociatedObject(constraint, &kDKPureBottomKey, @(constraint.constant),
                        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                if (constraint.constant != 0.0) constraint.constant = 0.0;
                NSNumber *baseline = objc_getAssociatedObject(constraint, &kDKPureBottomKey);
                CGFloat inset = reverse ? baseline.doubleValue : -baseline.doubleValue;
                objc_setAssociatedObject(page, &kDKPureInsetKey, @(MAX(inset, 0.0)),
                    OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            } else if (original) {
                if (constraint.constant == 0.0) constraint.constant = original.doubleValue;
                objc_setAssociatedObject(constraint, &kDKPureBottomKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    }
}

void DKPlaybackOverlayLayoutProgress(UIView *container) {
    AFDPureModePageContainerViewController *page = DKPlaybackOverlayActive()
        ? DKPurePageForView(container) : nil;
    CGFloat inset = [objc_getAssociatedObject(page, &kDKPureInsetKey) doubleValue];
    if (inset <= 0.0 || !container.superview) {
        if ([gDKPureProgressViews containsObject:container]) {
            DKAdjustTransform(container, CGAffineTransformIdentity);
            [gDKPureProgressViews removeObject:container];
        }
        return;
    }
    // 原生约束继续管理尺寸；同一坐标变换同时移动容器内的进度、读数及其触摸范围。
    UIView *parent = container.superview;
    CGPoint origin = [parent convertPoint:CGPointZero fromView:page.viewIfLoaded];
    CGPoint bottom = [parent convertPoint:CGPointMake(0.0, inset) fromView:page.viewIfLoaded];
    DKAdjustTransform(container, CGAffineTransformMakeTranslation(origin.x - bottom.x, origin.y - bottom.y));
    [gDKPureProgressViews addObject:container];
}

static void DKSpeedSyncBackdrop(AFDFastSpeedView *view) {
    [gDKSpeedViews addObject:view];
    BOOL active = DKPlaybackOverlayActive();
    // 三个具名槽位只含原生背景，文字、箭头与手势视图保留。
    for (UIView *background in @[ view.bottomBlackView ?: NSNull.null,
                                  view.bottomBackGroundView ?: NSNull.null,
                                  view.foldableBottomTextBackgroundView ?: NSNull.null ]) {
        if (![background isKindOfClass:UIView.class]) continue;
        DKOverlayClearColor(background, active);
    }
}

static void DKPureSyncControl(AFDRoundRectangleBoxView *box) {
    BOOL active = DKPlaybackOverlayActive() && DKPlaybackOverlayIsPureControl(box);
    if (active) [gDKPureControls addObject:box];
    DKOverlayClearColor(box, active);
    // blurView 不承载按钮内容，透明 mask 保留其原有 hidden / alpha 与布局。
    UIVisualEffectView *blur = box.blurView;
    DKAdjustFade(blur, active ? 0.0 : 1.0, blur.bounds.size);
}

void DKPlaybackOverlayRefresh(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKPlaybackOverlayRefresh(); });
        return;
    }
    for (AFDPureModePageContainerViewController *page in gDKPurePages.allObjects) {
        DKPureSyncPage(page);
        [page.viewIfLoaded setNeedsLayout];
    }
    for (AFDFastSpeedView *view in gDKSpeedViews.allObjects) DKSpeedSyncBackdrop(view);
    for (AFDRoundRectangleBoxView *box in gDKPureControls.allObjects) DKPureSyncControl(box);
    for (UIView *progress in gDKPureProgressViews.allObjects) DKPlaybackOverlayLayoutProgress(progress);
    DKPlaybackOverlayGlassRefresh();
}

%group DKPurePageFullscreen
%hook AFDPureModePageContainerViewController
- (void)viewDidLoad { %orig; DKPureSyncPage(self); }
- (void)viewWillLayoutSubviews { DKPureSyncPage(self); %orig; }
- (CGRect)getPureModeContainerFrame {
    CGRect original = %orig;
    UIView *root = self.viewIfLoaded;
    return DKPlaybackOverlayActive() && !CGRectIsEmpty(root.bounds) ? root.bounds : original;
}
%end
%end

%group DKSpeedBackdrop
%hook AFDFastSpeedView
- (void)layoutSubviews { %orig; DKSpeedSyncBackdrop(self); }
- (void)didMoveToWindow { %orig; DKSpeedSyncBackdrop(self); }
%end
%end

%group DKPureControlBackdrop
%hook AFDRoundRectangleBoxView
- (void)layoutSubviews { %orig; DKPureSyncControl(self); }
- (void)didMoveToWindow { %orig; DKPureSyncControl(self); }
%end
%end

%ctor {
    gDKPurePages = [NSHashTable weakObjectsHashTable];
    gDKSpeedViews = [NSHashTable weakObjectsHashTable];
    gDKPureControls = [NSHashTable weakObjectsHashTable];
    gDKPureProgressViews = [NSHashTable weakObjectsHashTable];
    if (NSClassFromString(@"AFDPureModePageContainerViewController")) { %init(DKPurePageFullscreen); }
    if (NSClassFromString(@"AFDFastSpeedView")) { %init(DKSpeedBackdrop); }
    if (NSClassFromString(@"AFDRoundRectangleBoxView")) { %init(DKPureControlBackdrop); }
}
