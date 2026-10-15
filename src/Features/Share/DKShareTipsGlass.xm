//
//  DKShareTipsGlass.xm
//  分享成功提示液态玻璃：把「已私信给 xxx」那张白卡片换成系统液态玻璃。
//  头像不接管；黑系文字按材质与系统深浅改色，彩色文字不动。
//  与分享面板共用材质设置（DYKillerSharePanelGlass / DYKillerSharePanelGlassClear）。
//

#import "DouyinHeaders.h"
#import "DKGlassFlexView.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKUtils.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static const NSTimeInterval kDKTipsGlassAnimation = 0.25;
static const CGFloat kDKTipsRadiusFloor = 12.0;

static char kFillColorKey;
static char kFillOpaqueKey;
static char kSlotGlassKey;
static char kShareViewKey;
static char kGlassClearKey;
static char kGlassStyleKey;
static char kGlassMaterializingKey;

static NSHashTable *gGlassCarriers;
static NSHashTable<AWEIMBottomTipsContainerView *> *gContainers;
static BOOL gEverAttached = NO;
static __weak UIWindowScene *gObservedScene = nil;
static UIUserInterfaceStyle gGlassStyle = UIUserInterfaceStyleUnspecified;

#pragma mark - 开关与材质

static BOOL DKTipsEnabled(void) {
    return DKGlassOSAvailable() && DKPrefBool(DKKeySharePanelGlass);
}

static BOOL DKTipsUsesClear(void) {
    return DKGlassOSAvailable() && DKPrefBool(DKKeySharePanelGlassClear);
}

static BOOL DKTipsColorOpaque(UIColor *color) {
    return color && CGColorGetAlpha(color.CGColor) >= 0.99;
}

static UIUserInterfaceStyle DKTipsStyleForView(UIView *view) {
    UIUserInterfaceStyle style = view.window.windowScene.traitCollection.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified) style = gGlassStyle;
    if (style == UIUserInterfaceStyleUnspecified) style = view.traitCollection.userInterfaceStyle;
    return style == UIUserInterfaceStyleUnspecified ? UIUserInterfaceStyleLight : style;
}

static UIUserInterfaceStyle DKTipsOverrideStyle(BOOL clear, UIUserInterfaceStyle style) {
    return clear ? UIUserInterfaceStyleUnspecified : style;
}

static UIColor *DKTipsTint(BOOL clear, UIUserInterfaceStyle style) {
    return clear ? DKGlassTintForStyle(style) : nil;
}

static UIGlassEffect *DKTipsMakeEffect(BOOL clear, UIUserInterfaceStyle style)
    API_AVAILABLE(ios(26.0)) {
    UIGlassEffect *effect = [UIGlassEffect effectWithStyle:
        clear ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular];
    effect.tintColor = DKTipsTint(clear, style);
    effect.interactive = YES;
    return effect;
}

static void DKTipsRunAnimation(BOOL animated, void (^changes)(void)) {
    if (!changes) return;
    if (!animated || UIAccessibilityIsReduceMotionEnabled()) {
        [UIView performWithoutAnimation:changes];
        return;
    }
    [UIView animateWithDuration:kDKTipsGlassAnimation
                          delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState
                              | UIViewAnimationOptionAllowUserInteraction
                              | UIViewAnimationOptionCurveEaseInOut
                     animations:changes
                     completion:nil];
}

static void DKTipsInstallEffect(UIVisualEffectView *glass, BOOL clear, UIUserInterfaceStyle style)
    API_AVAILABLE(ios(26.0)) {
    glass.effect = DKTipsMakeEffect(clear, style);
    objc_setAssociatedObject(glass, &kGlassClearKey, @(clear), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(glass, &kGlassStyleKey, @(style), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL DKTipsGlassNeedsUpdate(UIVisualEffectView *glass, BOOL clear, UIUserInterfaceStyle style)
    API_AVAILABLE(ios(26.0)) {
    if (glass.overrideUserInterfaceStyle != DKTipsOverrideStyle(clear, style)) return YES;
    UIGlassEffect *current = [glass.effect isKindOfClass:UIGlassEffect.class]
        ? (UIGlassEffect *)glass.effect : nil;
    if (!current) return glass.effect != nil;
    NSNumber *installedClear = objc_getAssociatedObject(glass, &kGlassClearKey);
    NSNumber *installedStyle = objc_getAssociatedObject(glass, &kGlassStyleKey);
    if (!installedClear || installedClear.boolValue != clear) return YES;
    if (!installedStyle || installedStyle.integerValue != style) return YES;
    if (!current.interactive) return YES;
    UIColor *want = DKTipsTint(clear, style);
    return !((current.tintColor == want) || [current.tintColor isEqual:want]);
}

static void DKTipsApplyStyle(UIUserInterfaceStyle style, BOOL animated) API_AVAILABLE(ios(26.0)) {
    if (style == UIUserInterfaceStyleUnspecified) return;
    gGlassStyle = style;
    // 场景 trait 回调在关开关后仍会来，这里不能再往回写。
    if (!DKTipsEnabled()) return;
    BOOL clear = DKTipsUsesClear();

    for (AWEIMBottomTipsContainerView *container in gContainers.allObjects) {
        DKGlassApplyInkText(objc_getAssociatedObject(container, &kShareViewKey), clear, style);
    }

    BOOL needs = NO;
    for (UIVisualEffectView *glass in gGlassCarriers.allObjects) {
        if (DKTipsGlassNeedsUpdate(glass, clear, style)) {
            needs = YES;
            break;
        }
    }
    if (!needs) return;

    DKTipsRunAnimation(animated, ^{
        for (UIVisualEffectView *glass in gGlassCarriers.allObjects) {
            glass.overrideUserInterfaceStyle = DKTipsOverrideStyle(clear, style);
            if (!glass.effect || !DKTipsGlassNeedsUpdate(glass, clear, style)) continue;
            DKTipsInstallEffect(glass, clear, style);
        }
    });
}

static void DKTipsObserveStyle(UIView *host) API_AVAILABLE(ios(26.0)) {
    UIWindowScene *scene = host.window.windowScene;
    if (!scene || scene == gObservedScene) return;
    gObservedScene = scene;
    [scene registerForTraitChanges:@[ UITraitUserInterfaceStyle.class ]
                       withHandler:^(UIWindowScene *changed, __unused UITraitCollection *previous) {
        DKTipsApplyStyle(changed.traitCollection.userInterfaceStyle, YES);
    }];
}

static UIVisualEffectView *DKTipsMakeShell(void) API_AVAILABLE(ios(26.0)) {
    DKGlassFlexView *glass = [[DKGlassFlexView alloc] initWithEffect:nil];
    glass.userInteractionEnabled = NO;
    glass.alpha = 1.0;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    return glass;
}

static BOOL DKTipsRectUsable(CGRect rect) {
    return CGRectGetWidth(rect) >= 8.0 && CGRectGetHeight(rect) >= 8.0;
}

// 0 尺寸写入 UIGlassEffect 不会建材质层，之后只改 frame 补不回来。
static void DKTipsPlaceGlass(UIVisualEffectView *glass, UIView *slot) {
    if (!glass || !slot) return;
    BOOL wasEmpty = !DKTipsRectUsable(glass.bounds);
    if (!CGRectEqualToRect(glass.frame, slot.bounds)) glass.frame = slot.bounds;
    if (slot.subviews.firstObject != glass) [slot insertSubview:glass atIndex:0];
    if (wasEmpty && DKTipsRectUsable(glass.bounds) && glass.effect) {
        glass.effect = nil;
        objc_setAssociatedObject(glass, &kGlassMaterializingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void DKTipsMaterialize(UIVisualEffectView *glass) API_AVAILABLE(ios(26.0)) {
    if (!glass || !DKTipsRectUsable(glass.bounds) || glass.effect
        || [objc_getAssociatedObject(glass, &kGlassMaterializingKey) boolValue]) {
        return;
    }
    objc_setAssociatedObject(glass, &kGlassMaterializingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKTipsRunAnimation(YES, ^{
        if (!glass.superview || !DKTipsEnabled()) {
            objc_setAssociatedObject(glass, &kGlassMaterializingKey,
                                     nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }
        UIUserInterfaceStyle style = gGlassStyle;
        if (style == UIUserInterfaceStyleUnspecified) style = DKTipsStyleForView(glass);
        BOOL clear = DKTipsUsesClear();
        glass.overrideUserInterfaceStyle = DKTipsOverrideStyle(clear, style);
        DKTipsInstallEffect(glass, clear, style);
        objc_setAssociatedObject(glass, &kGlassMaterializingKey,
                                 nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

#pragma mark - 作用域

// AWEIMBottomTipsContainerView 是 IM 通用底部提示壳，只有装着分享提示时才接管。
static UIView *DKTipsShareViewIn(AWEIMBottomTipsContainerView *container) {
    Class shareClass = %c(AWEIMBottomShareTipsView);
    if (!shareClass) return nil;
    if ([container respondsToSelector:@selector(contentView)]
        && [container.contentView isKindOfClass:shareClass]) {
        return container.contentView;
    }
    for (UIView *child in container.subviews) {
        if ([child isKindOfClass:shareClass]) return child;
    }
    return nil;
}

static AWEIMBottomTipsContainerView *DKTipsContainerOf(UIView *view) {
    while (view) {
        if ([view isKindOfClass:%c(AWEIMBottomTipsContainerView)]) {
            return (AWEIMBottomTipsContainerView *)view;
        }
        view = view.superview;
    }
    return nil;
}

#pragma mark - 底色

// 不透明底清成透明时必须一并清 opaque，否则该区域的渲染结果未定义。
static void DKTipsClearFill(UIView *view) {
    if (!view || !DKTipsColorOpaque(view.backgroundColor)) return;
    if (!objc_getAssociatedObject(view, &kFillColorKey)) {
        objc_setAssociatedObject(view, &kFillColorKey,
                                 view.backgroundColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &kFillOpaqueKey,
                                 @(view.opaque), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    view.backgroundColor = UIColor.clearColor;
    view.opaque = NO;
    gEverAttached = YES;
}

static void DKTipsRestoreFill(UIView *view) {
    UIColor *color = objc_getAssociatedObject(view, &kFillColorKey);
    if (!color) return;
    NSNumber *opaque = objc_getAssociatedObject(view, &kFillOpaqueKey);
    view.backgroundColor = color;
    if (opaque) view.opaque = opaque.boolValue;
    objc_setAssociatedObject(view, &kFillColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kFillOpaqueKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - 卡片

static UICornerConfiguration *DKTipsCornerConfig(UIView *container, UIView *shareView)
    API_AVAILABLE(ios(26.0)) {
    CGFloat radius = container.layer.cornerRadius;
    if (radius <= 0.0) radius = shareView.layer.cornerRadius;
    if (radius <= 0.0) radius = kDKTipsRadiusFloor;
    return [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius fixedRadius:radius]];
}

static UIVisualEffectView *DKTipsAttachCard(AWEIMBottomTipsContainerView *container,
                                            UIView *shareView)
    API_AVAILABLE(ios(26.0)) {
    DKTipsClearFill(container);
    DKTipsClearFill(shareView);
    if (!objc_getAssociatedObject(container, &kFillColorKey)
        && !objc_getAssociatedObject(shareView, &kFillColorKey)) {
        return nil;
    }

    UIVisualEffectView *glass = objc_getAssociatedObject(container, &kSlotGlassKey);
    if (!glass) {
        if ([container.subviews.firstObject isKindOfClass:UIVisualEffectView.class]) return nil;
        glass = DKTipsMakeShell();
        ((DKGlassFlexView *)glass).flexSourceView = container;
        objc_setAssociatedObject(container, &kSlotGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gGlassCarriers addObject:glass];
        gEverAttached = YES;
    }
    glass.cornerConfiguration = DKTipsCornerConfig(container, shareView);
    DKTipsPlaceGlass(glass, container);
    return glass;
}

static void DKTipsDetachCard(AWEIMBottomTipsContainerView *container, UIView *shareView) {
    UIView *glass = objc_getAssociatedObject(container, &kSlotGlassKey);
    [gGlassCarriers removeObject:glass];
    [glass removeFromSuperview];
    objc_setAssociatedObject(container, &kSlotGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKTipsRestoreFill(container);
    DKTipsRestoreFill(shareView);
}

#pragma mark - 同步

static void DKTipsRestore(AWEIMBottomTipsContainerView *container) {
    if (!container) return;
    UIView *shareView = objc_getAssociatedObject(container, &kShareViewKey)
        ?: DKTipsShareViewIn(container);
    DKGlassRestoreInkText(shareView);
    DKTipsDetachCard(container, shareView);
    objc_setAssociatedObject(container, &kShareViewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gContainers removeObject:container];
}

static void DKTipsSync(AWEIMBottomTipsContainerView *container) API_AVAILABLE(ios(26.0)) {
    if (!container) return;
    BOOL enabled = DKTipsEnabled();
    if (!enabled && !gEverAttached) return;
    if (!enabled) {
        DKTipsRestore(container);
        return;
    }

    UIView *shareView = DKTipsShareViewIn(container);
    if (!shareView) return;

    [gContainers addObject:container];
    objc_setAssociatedObject(container, &kShareViewKey, shareView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKTipsObserveStyle(container);

    UIUserInterfaceStyle style = DKTipsStyleForView(container);
    BOOL clear = DKTipsUsesClear();

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    UIVisualEffectView *card = DKTipsAttachCard(container, shareView);
    DKGlassApplyInkText(shareView, clear, style);
    [CATransaction commit];

    if (card) {
        DKTipsApplyStyle(style, YES);
        DKTipsMaterialize(card);
    }
}

#pragma mark - Hook

%group DKShareTipsGlassHooks

%hook AWEIMBottomTipsContainerView

- (void)show {
    %orig;
    if (@available(iOS 26.0, *)) DKTipsSync(self);
}

- (void)layoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) DKTipsSync(self);
}

%end

%hook AWEIMBottomShareTipsView

- (void)layoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) DKTipsSync(DKTipsContainerOf(self));
}

- (void)updateTipsLabelWithText:(id)text {
    %orig;
    if (@available(iOS 26.0, *)) DKTipsSync(DKTipsContainerOf(self));
}

%end

%end

%ctor {
    gGlassCarriers = [NSHashTable weakObjectsHashTable];
    gContainers = [NSHashTable weakObjectsHashTable];

    if (DKGlassOSAvailable()) {
        %init(DKShareTipsGlassHooks);
    }
}
