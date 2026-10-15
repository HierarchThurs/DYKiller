//
//  DKInnerNotificationGlass.xm
//  应用内通知横幅：白卡片换成系统液态玻璃，回复键走官方玻璃按钮，角标改成正圆玻璃。
//  只藏私信副标题里的「私信了你:」；其它文字不接管。
//

#import "DouyinHeaders.h"
#import "DKGlassFlexView.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"

#import <objc/runtime.h>

static const NSTimeInterval kDKNotiGlassAnimation = 0.25;
static const CGFloat kDKNotiNativeCorner = 12.0;
static const NSInteger kDKNotiCornerDefault = 100;
static NSString *const kDKNotiHintPrefix = @"私信了你";

static char kSlotColorKey;
static char kSlotGlassKey;
static char kSlotMarkedKey;
static char kGlassClearKey;
static char kGlassStyleKey;
static char kGlassMaterializingKey;
static char kCornerRadiusKey;
static char kCornerConfigKey;
static char kActionConfigKey;
static char kActionColorKey;
static char kActionTitleKey;
static char kActionAttrTitleKey;
static char kActionForegroundKey;
static char kActionClearKey;
static char kBadgeColorKey;
static char kBadgeGlassKey;
static char kHintHiddenKey;

static NSHashTable *gGlassCarriers;
static NSHashTable<AWEInnerNotificationContainerView *> *gContainers;
static NSHashTable<AWEInnerPushCommonView *> *gCommonViews;
static BOOL gEverAttached = NO;
// 我们自己写 textColor 会再次触发 setTextColor: 钩子，用它挡住重入。
static BOOL gInkReapplying = NO;
static __weak UIWindowScene *gObservedScene = nil;
static UIUserInterfaceStyle gGlassStyle = UIUserInterfaceStyleUnspecified;

#pragma mark - 开关与材质

static BOOL DKNotiEnabled(void) {
    return DKGlassOSAvailable() && DKPrefBool(DKKeyInnerNotiGlass);
}

static BOOL DKNotiUsesClear(void) {
    return DKGlassOSAvailable() && DKPrefBool(DKKeyInnerNotiGlassClear);
}

// 未写过键时保持胶囊（100），与 beta7 观感一致。
static CGFloat DKNotiCornerProgress(void) {
    NSNumber *stored = [NSUserDefaults.standardUserDefaults objectForKey:DKKeyInnerNotiCorner];
    NSInteger percent = stored ? stored.integerValue : kDKNotiCornerDefault;
    if (percent < 0) percent = 0;
    if (percent > 100) percent = 100;
    return percent / 100.0;
}

static BOOL DKNotiColorOpaque(UIColor *color) {
    return color && CGColorGetAlpha(color.CGColor) >= 0.99;
}

static UIUserInterfaceStyle DKNotiStyleForView(UIView *view) {
    UIUserInterfaceStyle style = view.window.windowScene.traitCollection.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified) style = gGlassStyle;
    if (style == UIUserInterfaceStyleUnspecified) style = view.traitCollection.userInterfaceStyle;
    return style == UIUserInterfaceStyleUnspecified ? UIUserInterfaceStyleLight : style;
}

static UIUserInterfaceStyle DKNotiOverrideStyle(BOOL clear, UIUserInterfaceStyle style) {
    return clear ? UIUserInterfaceStyleUnspecified : style;
}

static UIColor *DKNotiTint(BOOL clear, UIUserInterfaceStyle style) {
    return clear ? DKGlassTintForStyle(style) : nil;
}

static UIGlassEffect *DKNotiMakeEffect(BOOL clear, UIUserInterfaceStyle style)
    API_AVAILABLE(ios(26.0)) {
    UIGlassEffect *effect = [UIGlassEffect effectWithStyle:
        clear ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular];
    effect.tintColor = DKNotiTint(clear, style);
    effect.interactive = YES;
    return effect;
}

static void DKNotiRunAnimation(BOOL animated, void (^changes)(void)) {
    if (!changes) return;
    if (!animated || UIAccessibilityIsReduceMotionEnabled()) {
        [UIView performWithoutAnimation:changes];
        return;
    }
    [UIView animateWithDuration:kDKNotiGlassAnimation
                          delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState
                              | UIViewAnimationOptionAllowUserInteraction
                              | UIViewAnimationOptionCurveEaseInOut
                     animations:changes
                     completion:nil];
}

static void DKNotiInstallEffect(UIVisualEffectView *glass, BOOL clear, UIUserInterfaceStyle style)
    API_AVAILABLE(ios(26.0)) {
    glass.effect = DKNotiMakeEffect(clear, style);
    objc_setAssociatedObject(glass, &kGlassClearKey, @(clear), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(glass, &kGlassStyleKey, @(style), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL DKNotiGlassNeedsUpdate(UIVisualEffectView *glass, BOOL clear, UIUserInterfaceStyle style)
    API_AVAILABLE(ios(26.0)) {
    if (glass.overrideUserInterfaceStyle != DKNotiOverrideStyle(clear, style)) return YES;
    UIGlassEffect *current = [glass.effect isKindOfClass:UIGlassEffect.class]
        ? (UIGlassEffect *)glass.effect : nil;
    if (!current) return glass.effect != nil;
    NSNumber *installedClear = objc_getAssociatedObject(glass, &kGlassClearKey);
    NSNumber *installedStyle = objc_getAssociatedObject(glass, &kGlassStyleKey);
    if (!installedClear || installedClear.boolValue != clear) return YES;
    if (!installedStyle || installedStyle.integerValue != style) return YES;
    if (!current.interactive) return YES;
    UIColor *want = DKNotiTint(clear, style);
    return !((current.tintColor == want) || [current.tintColor isEqual:want]);
}

static UIView *DKNotiSlot(AWEInnerNotificationContainerView *container);

static void DKNotiApplyStyle(UIUserInterfaceStyle style, BOOL animated) API_AVAILABLE(ios(26.0)) {
    if (style == UIUserInterfaceStyleUnspecified) return;
    gGlassStyle = style;
    // 场景 trait 回调在关开关后仍会来，这里不能再往回写。
    if (!DKNotiEnabled()) return;
    BOOL clear = DKNotiUsesClear();

    // 深浅切换时横幅可能正在场，文字要跟着材质一起换。
    for (AWEInnerPushCommonView *common in gCommonViews.allObjects) {
        DKGlassApplyInkText(common, clear, style);
    }
    for (AWEInnerNotificationContainerView *container in gContainers.allObjects) {
        DKGlassApplyInkText(DKNotiSlot(container), clear, style);
    }

    BOOL needs = NO;
    for (UIVisualEffectView *glass in gGlassCarriers.allObjects) {
        if (DKNotiGlassNeedsUpdate(glass, clear, style)) {
            needs = YES;
            break;
        }
    }
    if (!needs) return;

    DKNotiRunAnimation(animated, ^{
        for (UIVisualEffectView *glass in gGlassCarriers.allObjects) {
            glass.overrideUserInterfaceStyle = DKNotiOverrideStyle(clear, style);
            if (!glass.effect || !DKNotiGlassNeedsUpdate(glass, clear, style)) continue;
            DKNotiInstallEffect(glass, clear, style);
        }
    });
}

static void DKNotiObserveStyle(UIView *host) API_AVAILABLE(ios(26.0)) {
    UIWindowScene *scene = host.window.windowScene;
    if (!scene || scene == gObservedScene) return;
    gObservedScene = scene;
    [scene registerForTraitChanges:@[ UITraitUserInterfaceStyle.class ]
                       withHandler:^(UIWindowScene *changed, __unused UITraitCollection *previous) {
        DKNotiApplyStyle(changed.traitCollection.userInterfaceStyle, YES);
    }];
}

static UIVisualEffectView *DKNotiMakeShell(void) API_AVAILABLE(ios(26.0)) {
    DKGlassFlexView *glass = [[DKGlassFlexView alloc] initWithEffect:nil];
    glass.userInteractionEnabled = NO;
    glass.alpha = 1.0;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    return glass;
}

static BOOL DKNotiRectUsable(CGRect rect) {
    return CGRectGetWidth(rect) >= 8.0 && CGRectGetHeight(rect) >= 8.0;
}

static void DKNotiEnsureBackmost(UIView *slot, UIView *glass) {
    if (slot.subviews.firstObject == glass) return;
    [slot insertSubview:glass atIndex:0];
}

// 0 尺寸写入 UIGlassEffect 不会建材质层，之后只改 frame 补不回来。
static void DKNotiPlaceGlass(UIVisualEffectView *glass, UIView *slot) {
    if (!glass || !slot) return;
    BOOL wasEmpty = !DKNotiRectUsable(glass.bounds);
    if (!CGRectEqualToRect(glass.frame, slot.bounds)) glass.frame = slot.bounds;
    DKNotiEnsureBackmost(slot, glass);
    if (wasEmpty && DKNotiRectUsable(glass.bounds) && glass.effect) {
        glass.effect = nil;
        objc_setAssociatedObject(glass, &kGlassMaterializingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void DKNotiMaterialize(UIVisualEffectView *glass) API_AVAILABLE(ios(26.0)) {
    if (!glass || !DKNotiRectUsable(glass.bounds) || glass.effect
        || [objc_getAssociatedObject(glass, &kGlassMaterializingKey) boolValue]) {
        return;
    }
    objc_setAssociatedObject(glass, &kGlassMaterializingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKNotiRunAnimation(YES, ^{
        if (!glass.superview || !DKNotiEnabled()) {
            objc_setAssociatedObject(glass, &kGlassMaterializingKey,
                                     nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }
        UIUserInterfaceStyle style = gGlassStyle;
        if (style == UIUserInterfaceStyleUnspecified) style = DKNotiStyleForView(glass);
        BOOL clear = DKNotiUsesClear();
        glass.overrideUserInterfaceStyle = DKNotiOverrideStyle(clear, style);
        DKNotiInstallEffect(glass, clear, style);
        objc_setAssociatedObject(glass, &kGlassMaterializingKey,
                                 nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

#pragma mark - 圆角

static void DKNotiRememberCorners(UIView *view) {
    if (!view || objc_getAssociatedObject(view, &kCornerRadiusKey)) return;
    objc_setAssociatedObject(view, &kCornerRadiusKey,
                             @(view.layer.cornerRadius), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if ([view respondsToSelector:@selector(cornerConfiguration)]) {
        objc_setAssociatedObject(view, &kCornerConfigKey,
                                 view.cornerConfiguration, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static UICornerConfiguration *DKNotiCardCornerConfig(UIView *view) API_AVAILABLE(ios(26.0)) {
    DKNotiRememberCorners(view);
    CGFloat native = kDKNotiNativeCorner;
    NSNumber *remembered = objc_getAssociatedObject(view, &kCornerRadiusKey);
    if (remembered && remembered.doubleValue > 0.0) native = remembered.doubleValue;
    CGFloat capsule = MIN(CGRectGetWidth(view.bounds), CGRectGetHeight(view.bounds)) * 0.5;
    if (capsule < native) capsule = native;
    CGFloat radius = native + (capsule - native) * DKNotiCornerProgress();
    view.layer.cornerRadius = radius;
    return [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius fixedRadius:radius]];
}

static void DKNotiApplyCardShape(UIView *view, UIVisualEffectView *glass) API_AVAILABLE(ios(26.0)) {
    if (!view) return;
    UICornerConfiguration *config = DKNotiCardCornerConfig(view);
    if ([view respondsToSelector:@selector(setCornerConfiguration:)]) {
        view.cornerConfiguration = config;
    }
    if (glass && [glass respondsToSelector:@selector(setCornerConfiguration:)]) {
        glass.cornerConfiguration = config;
    }
}

static void DKNotiApplyCapsule(UIView *view) API_AVAILABLE(ios(26.0)) {
    if (!view) return;
    DKNotiRememberCorners(view);
    if ([view respondsToSelector:@selector(setCornerConfiguration:)]) {
        view.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];
    }
    CGFloat height = CGRectGetHeight(view.bounds);
    if (height >= 1.0) view.layer.cornerRadius = height * 0.5;
}

static void DKNotiRestoreCorners(UIView *view) {
    NSNumber *radius = objc_getAssociatedObject(view, &kCornerRadiusKey);
    if (!view || !radius) return;
    if ([view respondsToSelector:@selector(setCornerConfiguration:)]) {
        view.cornerConfiguration = objc_getAssociatedObject(view, &kCornerConfigKey);
    }
    view.layer.cornerRadius = radius.doubleValue;
    objc_setAssociatedObject(view, &kCornerRadiusKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kCornerConfigKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - 查找

static AWEInnerNotificationContainerView *DKNotiContainerOf(UIView *view) {
    while (view) {
        if ([view isKindOfClass:%c(AWEInnerNotificationContainerView)]) {
            return (AWEInnerNotificationContainerView *)view;
        }
        view = view.superview;
    }
    return nil;
}

static UIView *DKNotiSlot(AWEInnerNotificationContainerView *container) {
    UIView *marked = objc_getAssociatedObject(container, &kSlotMarkedKey);
    if (marked.superview == container) return marked;

    if ([container respondsToSelector:@selector(containerView)]) {
        UIView *candidate = container.containerView;
        if (candidate.superview == container
            && (DKNotiColorOpaque(candidate.backgroundColor)
                || objc_getAssociatedObject(candidate, &kSlotColorKey))) {
            return candidate;
        }
    }
    for (UIView *child in container.subviews) {
        if (child.hidden) continue;
        if (DKNotiColorOpaque(child.backgroundColor)
            || objc_getAssociatedObject(child, &kSlotColorKey)) {
            return child;
        }
    }
    return nil;
}

static AWEInnerPushCommonView *DKNotiCommonIn(UIView *view, NSUInteger depth) {
    if (!view || depth > 6) return nil;
    if ([view isKindOfClass:%c(AWEInnerPushCommonView)]) return (AWEInnerPushCommonView *)view;
    for (UIView *child in view.subviews) {
        AWEInnerPushCommonView *found = DKNotiCommonIn(child, depth + 1);
        if (found) return found;
    }
    return nil;
}

#pragma mark - 卡片

static BOOL DKNotiClearSlot(UIView *slot) {
    UIColor *current = slot.backgroundColor;
    if (DKNotiColorOpaque(current)) {
        if (!objc_getAssociatedObject(slot, &kSlotColorKey)) {
            objc_setAssociatedObject(slot, &kSlotColorKey, current, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        slot.backgroundColor = UIColor.clearColor;
        gEverAttached = YES;
        return YES;
    }
    return objc_getAssociatedObject(slot, &kSlotColorKey) != nil;
}

static UIVisualEffectView *DKNotiAttachCard(AWEInnerNotificationContainerView *container,
                                            UIView *slot)
    API_AVAILABLE(ios(26.0)) {
    if (!DKNotiClearSlot(slot)) return nil;

    UIVisualEffectView *glass = objc_getAssociatedObject(slot, &kSlotGlassKey);
    if (!glass) {
        UIView *first = slot.subviews.firstObject;
        if ([first isKindOfClass:UIVisualEffectView.class]
            && first != objc_getAssociatedObject(slot, &kSlotGlassKey)) {
            return nil;
        }
        glass = DKNotiMakeShell();
        ((DKGlassFlexView *)glass).flexSourceView = container;
        objc_setAssociatedObject(slot, &kSlotGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(container, &kSlotMarkedKey, slot, OBJC_ASSOCIATION_ASSIGN);
        [gGlassCarriers addObject:glass];
        gEverAttached = YES;
    }

    DKNotiApplyCardShape(container, glass);
    DKNotiApplyCardShape(slot, glass);
    DKNotiPlaceGlass(glass, slot);
    return glass;
}

static void DKNotiDetachCard(AWEInnerNotificationContainerView *container) {
    UIView *slot = DKNotiSlot(container);
    if (!slot) return;
    DKGlassRestoreInkText(slot);
    UIView *glass = objc_getAssociatedObject(slot, &kSlotGlassKey);
    [gGlassCarriers removeObject:glass];
    [glass removeFromSuperview];
    UIColor *original = objc_getAssociatedObject(slot, &kSlotColorKey);
    if (original) slot.backgroundColor = original;
    DKNotiRestoreCorners(slot);
    DKNotiRestoreCorners(container);
    objc_setAssociatedObject(slot, &kSlotColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(slot, &kSlotGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(container, &kSlotMarkedKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

#pragma mark - 回复键

static BOOL DKNotiActionHasGlass(UIButton *button) {
    return button.configuration && objc_getAssociatedObject(button, &kActionClearKey);
}

static void DKNotiRememberAction(UIButton *button) {
    if (!button || DKNotiActionHasGlass(button)) return;
    if (button.configuration && !objc_getAssociatedObject(button, &kActionConfigKey)) {
        objc_setAssociatedObject(button, &kActionConfigKey,
                                 button.configuration, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (button.backgroundColor) {
        objc_setAssociatedObject(button, &kActionColorKey,
                                 button.backgroundColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSAttributedString *attributed = button.currentAttributedTitle;
    if (attributed.length) {
        objc_setAssociatedObject(button, &kActionAttrTitleKey,
                                 attributed, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    NSString *title = button.currentTitle.length ? button.currentTitle : attributed.string;
    if (title.length) {
        objc_setAssociatedObject(button, &kActionTitleKey,
                                 title, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    UIColor *foreground = nil;
    if (attributed.length) {
        foreground = [attributed attribute:NSForegroundColorAttributeName
                                   atIndex:0
                            effectiveRange:NULL];
    }
    if (!foreground) foreground = [button titleColorForState:UIControlStateNormal];
    if (foreground) {
        objc_setAssociatedObject(button, &kActionForegroundKey,
                                 foreground, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static UIButtonConfiguration *DKNotiMakeActionConfig(BOOL clear) API_AVAILABLE(ios(26.0)) {
    UIButtonConfiguration *config = nil;
    if (clear && [UIButtonConfiguration respondsToSelector:@selector(clearGlassButtonConfiguration)]) {
        config = [UIButtonConfiguration clearGlassButtonConfiguration];
    } else if ([UIButtonConfiguration respondsToSelector:@selector(glassButtonConfiguration)]) {
        config = [UIButtonConfiguration glassButtonConfiguration];
    }
    if (!config) return nil;
    config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    return config;
}

static void DKNotiWriteActionTitle(UIButton *button, UIButtonConfiguration *config) {
    NSAttributedString *attributed = objc_getAssociatedObject(button, &kActionAttrTitleKey);
    NSString *title = objc_getAssociatedObject(button, &kActionTitleKey);
    UIColor *foreground = objc_getAssociatedObject(button, &kActionForegroundKey);
    if (attributed.length) {
        config.attributedTitle = attributed;
    } else if (title.length) {
        config.title = title;
    }
    if (foreground) config.baseForegroundColor = foreground;
}

static void DKNotiRestoreAction(UIButton *button) {
    if (!button || !objc_getAssociatedObject(button, &kActionForegroundKey)) return;
    UIButtonConfiguration *original = objc_getAssociatedObject(button, &kActionConfigKey);
    button.configuration = original;
    UIColor *color = objc_getAssociatedObject(button, &kActionColorKey);
    if (color) button.backgroundColor = color;
    if (!original) {
        NSAttributedString *attributed = objc_getAssociatedObject(button, &kActionAttrTitleKey);
        NSString *title = objc_getAssociatedObject(button, &kActionTitleKey);
        UIColor *foreground = objc_getAssociatedObject(button, &kActionForegroundKey);
        if (attributed) {
            [button setAttributedTitle:attributed forState:UIControlStateNormal];
        } else if (title) {
            [button setTitle:title forState:UIControlStateNormal];
        }
        if (foreground) [button setTitleColor:foreground forState:UIControlStateNormal];
    }
    objc_setAssociatedObject(button, &kActionConfigKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, &kActionColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, &kActionTitleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, &kActionAttrTitleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, &kActionForegroundKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, &kActionClearKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DKNotiApplyAction(UIButton *button) API_AVAILABLE(ios(26.0)) {
    if (!button || button.hidden || button.alpha < 0.01) {
        if (button) DKNotiRestoreAction(button);
        return;
    }

    DKNotiRememberAction(button);
    if (objc_getAssociatedObject(button, &kActionColorKey)) {
        button.backgroundColor = UIColor.clearColor;
    }

    BOOL clear = DKNotiUsesClear();
    NSNumber *installed = objc_getAssociatedObject(button, &kActionClearKey);
    if (DKNotiActionHasGlass(button) && installed.boolValue == clear) return;

    UIButtonConfiguration *config = DKNotiMakeActionConfig(clear);
    if (!config) return;
    DKNotiWriteActionTitle(button, config);
    button.configuration = config;
    objc_setAssociatedObject(button, &kActionClearKey, @(clear), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    gEverAttached = YES;
}

#pragma mark - 角标

static void DKNotiRestoreBadge(UIView *badge) {
    if (!badge) return;
    UIView *glass = objc_getAssociatedObject(badge, &kBadgeGlassKey);
    [gGlassCarriers removeObject:glass];
    [glass removeFromSuperview];
    UIColor *original = objc_getAssociatedObject(badge, &kBadgeColorKey);
    if (original) badge.backgroundColor = original;
    DKNotiRestoreCorners(badge);
    objc_setAssociatedObject(badge, &kBadgeColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(badge, &kBadgeGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DKNotiApplyBadge(UIView *badge) API_AVAILABLE(ios(26.0)) {
    if (!badge || badge.hidden || badge.alpha < 0.01) {
        if (badge) DKNotiRestoreBadge(badge);
        return;
    }

    UIColor *current = badge.backgroundColor;
    if (DKNotiColorOpaque(current)) {
        if (!objc_getAssociatedObject(badge, &kBadgeColorKey)) {
            objc_setAssociatedObject(badge, &kBadgeColorKey, current, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        badge.backgroundColor = UIColor.clearColor;
    } else if (!objc_getAssociatedObject(badge, &kBadgeColorKey)) {
        return;
    }

    UIVisualEffectView *glass = objc_getAssociatedObject(badge, &kBadgeGlassKey);
    if (!glass) {
        glass = DKNotiMakeShell();
        glass.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];
        ((DKGlassFlexView *)glass).flexSourceView = badge;
        objc_setAssociatedObject(badge, &kBadgeGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gGlassCarriers addObject:glass];
        gEverAttached = YES;
    }
    DKNotiApplyCapsule(badge);
    DKNotiPlaceGlass(glass, badge);
    DKNotiMaterialize(glass);
}

#pragma mark - 「私信了你」

static BOOL DKNotiIsHintText(NSString *text) {
    if (text.length < kDKNotiHintPrefix.length) return NO;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![trimmed hasPrefix:kDKNotiHintPrefix]) return NO;
    NSString *rest = [trimmed substringFromIndex:kDKNotiHintPrefix.length];
    static NSCharacterSet *junk;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        junk = [NSCharacterSet characterSetWithCharactersInString:@":： "];
    });
    return [rest stringByTrimmingCharactersInSet:junk].length == 0;
}

static void DKNotiWalkLabels(UIView *view, NSUInteger depth, void (^block)(UILabel *label)) {
    if (!view || depth > 8 || !block) return;
    if ([view isKindOfClass:UILabel.class]) block((UILabel *)view);
    for (UIView *child in view.subviews) DKNotiWalkLabels(child, depth + 1, block);
}

static void DKNotiRestoreHint(AWEInnerPushCommonView *common) {
    UIView *root = ([common respondsToSelector:@selector(middleContentTextStackView)]
                    && common.middleContentTextStackView)
        ? common.middleContentTextStackView : common;
    DKNotiWalkLabels(root, 0, ^(UILabel *label) {
        NSNumber *hidden = objc_getAssociatedObject(label, &kHintHiddenKey);
        if (!hidden) return;
        label.hidden = hidden.boolValue;
        objc_setAssociatedObject(label, &kHintHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

static AWEInnerPushCommonView *DKNotiCommonOf(UIView *view) {
    while (view) {
        if ([view isKindOfClass:%c(AWEInnerPushCommonView)]) return (AWEInnerPushCommonView *)view;
        view = view.superview;
    }
    return nil;
}

static void DKNotiHideHintLabel(UILabel *label) {
    if (!label) return;
    if (!objc_getAssociatedObject(label, &kHintHiddenKey)) {
        objc_setAssociatedObject(label, &kHintHiddenKey,
                                 @(label.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!label.hidden) label.hidden = YES;
    gEverAttached = YES;
}

#pragma mark - 迟到的文字色

// 副标题的文案和色值在同步之后才写进去：横幅首帧只有用户名变了色，正文要拖一下
// （拖动触发 layout 才重新扫）才跟上。这里在写入点当场补，不等下一次布局。
// 全应用的 UILabel 都会走到：横幅住在自己那个 999 窗口里，一次 window 判定就挡掉绝大多数；
// 还没挂进窗口的横幅取不到 window，退回「当前有没有横幅在场」再细查。
static void DKNotiReapplyInk(UILabel *label) {
    if (gInkReapplying) return;
    if (![label.window isKindOfClass:%c(AWEInnerNotificationWindow)]
        && gContainers.count == 0 && gCommonViews.count == 0) {
        return;
    }
    if (!DKNotiEnabled()) return;

    for (UIView *node = label; node; node = node.superview) {
        // 按钮标题由 UIButtonConfiguration 管，写 textColor 会被配置刷掉，两边打架。
        if ([node isKindOfClass:UIControl.class]) return;
        if (![node isKindOfClass:%c(AWEInnerNotificationContainerView)]) continue;
        gInkReapplying = YES;
        DKGlassApplyInkText(label, DKNotiUsesClear(), DKNotiStyleForView(label));
        gInkReapplying = NO;
        return;
    }
}

static void DKNotiApplyHint(AWEInnerPushCommonView *common) {
    UIView *root = ([common respondsToSelector:@selector(middleContentTextStackView)]
                    && common.middleContentTextStackView)
        ? common.middleContentTextStackView : common;
    DKNotiWalkLabels(root, 0, ^(UILabel *label) {
        NSString *text = label.text.length ? label.text : label.attributedText.string;
        BOOL hint = DKNotiIsHintText(text);
        NSNumber *marked = objc_getAssociatedObject(label, &kHintHiddenKey);
        if (hint) {
            DKNotiHideHintLabel(label);
        } else if (marked) {
            label.hidden = marked.boolValue;
            objc_setAssociatedObject(label, &kHintHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    });
}

#pragma mark - 同步

static void DKNotiRestoreCommon(AWEInnerPushCommonView *common) {
    if ([common respondsToSelector:@selector(rightActionButton)]) {
        DKNotiRestoreAction(common.rightActionButton);
    }
    if ([common respondsToSelector:@selector(leftExtraIconBackgroundView)]) {
        DKNotiRestoreBadge(common.leftExtraIconBackgroundView);
    }
    DKNotiRestoreHint(common);
    DKGlassRestoreInkText(common);
    [gCommonViews removeObject:common];
}

static void DKNotiRestoreContainer(AWEInnerNotificationContainerView *container) {
    AWEInnerPushCommonView *common = DKNotiCommonIn(container, 0);
    if (common) DKNotiRestoreCommon(common);
    DKNotiDetachCard(container);
    [gContainers removeObject:container];
}

static void DKNotiRestoreAll(void) {
    for (AWEInnerPushCommonView *common in gCommonViews.allObjects) {
        DKNotiRestoreCommon(common);
    }
    for (AWEInnerNotificationContainerView *container in gContainers.allObjects) {
        DKNotiDetachCard(container);
    }
    [gContainers removeAllObjects];
}

static void DKNotiSyncCommon(AWEInnerPushCommonView *common) API_AVAILABLE(ios(26.0)) {
    if (!common) return;
    BOOL enabled = DKNotiEnabled();
    if (!enabled && !gEverAttached) return;
    if (!enabled) {
        DKNotiRestoreCommon(common);
        return;
    }

    [gCommonViews addObject:common];
    DKNotiApplyHint(common);
    DKGlassApplyInkText(common, DKNotiUsesClear(), DKNotiStyleForView(common));
    if ([common respondsToSelector:@selector(rightActionButton)]) {
        DKNotiApplyAction(common.rightActionButton);
    }
    if ([common respondsToSelector:@selector(leftExtraIconBackgroundView)]) {
        DKNotiApplyBadge(common.leftExtraIconBackgroundView);
    }
}

static void DKNotiSyncContainer(AWEInnerNotificationContainerView *container)
    API_AVAILABLE(ios(26.0)) {
    if (!container) return;
    BOOL enabled = DKNotiEnabled();
    if (!enabled && !gEverAttached) return;
    if (!enabled) {
        DKNotiRestoreContainer(container);
        return;
    }

    UIView *slot = DKNotiSlot(container);
    if (!slot) return;

    [gContainers addObject:container];
    DKNotiObserveStyle(container);
    UIUserInterfaceStyle style = DKNotiStyleForView(container);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    UIVisualEffectView *card = DKNotiAttachCard(container, slot);
    DKNotiSyncCommon(DKNotiCommonIn(container, 0));
    // 从白槽起走一遍：点赞、评论、直播这类不带 AWEInnerPushCommonView 的横幅也覆盖到。
    DKGlassApplyInkText(slot, DKNotiUsesClear(), style);
    [CATransaction commit];

    if (card) {
        DKNotiApplyStyle(style, YES);
        DKNotiMaterialize(card);
    }
}

static void DKNotiRefreshVisible(void) {
    BOOL enabled = DKNotiEnabled();
    if (!enabled) {
        DKNotiRestoreAll();
        return;
    }
    if (@available(iOS 26.0, *)) {
        for (AWEInnerNotificationContainerView *container in gContainers.allObjects) {
            DKNotiSyncContainer(container);
        }
        for (AWEInnerPushCommonView *common in gCommonViews.allObjects) {
            DKNotiSyncCommon(common);
        }
    }
}

#pragma mark - Hook

%group DKInnerNotificationGlassHooks

%hook AWEInnerNotificationContainerView

- (void)renderModel:(id)model context:(id)context {
    %orig;
    if (@available(iOS 26.0, *)) DKNotiSyncContainer(self);
}

- (void)layoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) DKNotiSyncContainer(self);
}

- (void)viewDidDisappear:(BOOL)animated reason:(long long)reason {
    %orig;
    if (self.window) return;
    DKNotiRestoreContainer(self);
}

%end

%hook AWEInnerPushCommonView

- (void)updateViewWithRequest:(id)request notificationContent:(id)content viewModel:(id)viewModel {
    %orig;
    if (@available(iOS 26.0, *)) {
        DKNotiSyncCommon(self);
        AWEInnerNotificationContainerView *container = DKNotiContainerOf(self);
        if (container) DKNotiSyncContainer(container);
    }
}

- (void)layoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) DKNotiSyncCommon(self);
}

%end

// 文案在布局之后才写入；只靠 layoutSubviews 会首帧漏藏，拖一下才消失。
%hook UILabel

- (void)setText:(NSString *)text {
    %orig;
    if (DKNotiEnabled() && DKNotiIsHintText(text) && DKNotiCommonOf(self)) {
        DKNotiHideHintLabel(self);
    }
    DKNotiReapplyInk(self);
}

- (void)setAttributedText:(NSAttributedString *)text {
    %orig;
    if (DKNotiEnabled() && DKNotiIsHintText(text.string) && DKNotiCommonOf(self)) {
        DKNotiHideHintLabel(self);
    }
    DKNotiReapplyInk(self);
}

- (void)setTextColor:(UIColor *)color {
    %orig;
    DKNotiReapplyInk(self);
}

- (void)setHidden:(BOOL)hidden {
    if (!hidden && DKNotiEnabled() && objc_getAssociatedObject(self, &kHintHiddenKey)) {
        NSString *text = self.text.length ? self.text : self.attributedText.string;
        if (DKNotiIsHintText(text)) {
            %orig(YES);
            return;
        }
    }
    %orig;
}

%end

%end

#pragma mark - 设置

%ctor {
    gGlassCarriers = [NSHashTable weakObjectsHashTable];
    gContainers = [NSHashTable weakObjectsHashTable];
    gCommonViews = [NSHashTable weakObjectsHashTable];

    DKSettingsRegister(DKKeyInnerNotiGlass, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeGlassChoice(DKKeyInnerNotiGlass, DKKeyInnerNotiGlassClear, @"消息通知液态玻璃", ^{
            void (^refresh)(void) = ^{
                if (@available(iOS 26.0, *)) {
                    UIUserInterfaceStyle style = gGlassStyle;
                    if (style == UIUserInterfaceStyleUnspecified) {
                        style = UIScreen.mainScreen.traitCollection.userInterfaceStyle;
                    }
                    DKNotiApplyStyle(style, YES);
                    DKNotiRefreshVisible();
                }
            };
            if (NSThread.isMainThread) refresh();
            else dispatch_async(dispatch_get_main_queue(), refresh);
        });
        return DKSettingsWithInfo(item,
            @"应用内通知横幅的材质：关闭时保持抖音原生样式；模糊玻璃使用系统 Regular；清透玻璃显示更多背后视频细节。");
    });

    DKSettingsRegister(DKKeyInnerNotiCorner, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakePercentSlider(
            DKKeyInnerNotiCorner,
            @"通知圆角",
            @"左侧为抖音默认圆角，右侧为胶囊圆角",
            kDKNotiCornerDefault,
            ^(__unused NSInteger percent) {
                if (@available(iOS 26.0, *)) DKNotiRefreshVisible();
            }
        );
        return DKSettingsWithInfo(item, @"应用内通知玻璃横幅的圆角大小：0% 为抖音默认圆角，100% 为胶囊形。");
    });

    if (DKGlassOSAvailable()) {
        %init(DKInnerNotificationGlassHooks);
    }
}
