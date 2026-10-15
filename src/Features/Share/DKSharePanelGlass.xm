//
//  DKSharePanelGlass.xm
//  分享面板液态玻璃：卡片底色、关闭键、第三行圆钮，以及点头像后的输入覆盖层、
//  发送按钮和表情栏。分享评论面板（长按评论 → 分享）并入同一开关，复用同一套材质。
//  通讯录头像与输入文字本身不接管。
//

#import "DouyinHeaders.h"
#import "DKGlassFlexView.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKShareSelectionHooks.h"
#import "DKUtils.h"

#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import <objc/runtime.h>

static NSString *const kDKShareEffectClass = @"DUXVisualEffectView";
static NSString *const kDKShareOverlayClass = @"AWEIMShareImpl.ShareAdditionTextView";
static NSString *const kDKShareCommentSheetClass =
    @"AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelSheet";
static NSString *const kDKShareCommentListClass =
    @"AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelCollectionViewController";
static const CGFloat kDKShareRadiusFloor = 20.0;
static const CGFloat kDKShareSendRadiusFloor = 8.0;
// 分享评论面板每行胶囊的上下内缩：相邻两行各缩一次，空隙 = 2 倍。
static const CGFloat kDKShareCardGapInset = 3.0;
static const NSTimeInterval kDKShareGlassAnimation = 0.25;
static const float kDKSharePlateLuma = 0.76f;
static const float kDKSharePlateSat = 0.14f;

static char kSlotColorKey;
static char kSlotGlassKey;
static char kGlassClearKey;
static char kGlassStyleKey;
static char kGlassMaterializingKey;
static char kGlassFixedTintKey;
static char kCloseOriginalConfigKey;
static char kCloseOriginalImageKey;
static char kCloseModeKey;
static char kCloseGlassKey;
static char kCellOriginalImageKey;
static char kCellOriginalColorKey;
static char kCellGlassKey;
static char kDestainedCacheKey;
static char kDestainedFlagKey;
static char kOverlayColorKey;
static char kOverlayEffectKey;
static char kOverlayTakenKey;
static char kOverlayOpaqueKey;
static char kOverlayGlassKey;
static char kOverlayDividerKey;
static char kDividerHiddenKey;
static char kButtonColorKey;
static char kButtonOpaqueKey;
static char kButtonGlassKey;
static char kButtonRadiusKey;
static char kToolbarColorKey;
static char kToolbarOpaqueKey;
static char kToolbarGlassKey;
static char kPlateColorKey;
static char kPlateOpaqueKey;
static char kPlateGlassKey;
static char kCardLayerKey;
static char kCardFillKey;
static char kCardGlassKey;
static char kCardDividerKey;
static char kCardDividerHiddenKey;

static NSHashTable *gGlassCarriers;
static NSHashTable<AWESharePanelContainerViewController *> *gContainers;
static NSHashTable<AWESharePanelFunctionCell *> *gCells;
static NSHashTable<UIViewController *> *gCommentSheets;
static NSHashTable<UICollectionViewCell *> *gCardCells;
static NSHashTable<UIView *> *gSendButtons;
static BOOL gEverAttached = NO;
static __weak UIWindowScene *gObservedScene = nil;
static UIUserInterfaceStyle gGlassStyle = UIUserInterfaceStyleUnspecified;

typedef NS_ENUM(NSInteger, DKShareCloseMode) {
    DKShareCloseModeNone = 0,
    DKShareCloseModeOfficial,
    DKShareCloseModeOverlay,
};

#pragma mark - 开关与材质

static BOOL DKShareEnabled(void) {
    return DKGlassOSAvailable() && DKPrefBool(DKKeySharePanelGlass);
}

static BOOL DKShareUsesClear(void) {
    return DKGlassOSAvailable() && DKPrefBool(DKKeySharePanelGlassClear);
}

static BOOL DKShareColorOpaque(UIColor *color) {
    return color && CGColorGetAlpha(color.CGColor) >= 0.99;
}

// 抖音铺的白 / 近白底板（#FFFFFF、#F3F3F4）：不透明 + 高明度 + 低饱和。
// 与去白底那套用同一对阈值；收 CGColor 是为了同时判 UIColor 与 CALayer 的填充。
static BOOL DKShareCGColorIsPlate(CGColorRef color) {
    if (!color || CGColorGetAlpha(color) < 0.99) return NO;
    size_t count = CGColorGetNumberOfComponents(color);
    const CGFloat *components = CGColorGetComponents(color);
    if (!components) return NO;
    CGFloat red, green, blue;
    if (count >= 4) {
        red = components[0];
        green = components[1];
        blue = components[2];
    } else if (count >= 2) {
        red = green = blue = components[0];
    } else {
        return NO;
    }
    CGFloat maximum = MAX(red, MAX(green, blue));
    CGFloat minimum = MIN(red, MIN(green, blue));
    CGFloat saturation = maximum > 0.001 ? (maximum - minimum) / maximum : 0.0;
    return maximum >= kDKSharePlateLuma && saturation <= kDKSharePlateSat;
}

static UIUserInterfaceStyle DKShareStyleForView(UIView *view) {
    UIUserInterfaceStyle style = view.window.windowScene.traitCollection.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified) style = gGlassStyle;
    if (style == UIUserInterfaceStyleUnspecified) style = view.traitCollection.userInterfaceStyle;
    return style == UIUserInterfaceStyleUnspecified ? UIUserInterfaceStyleLight : style;
}

static UIUserInterfaceStyle DKShareOverrideStyle(BOOL clear, UIUserInterfaceStyle style) {
    return clear ? UIUserInterfaceStyleUnspecified : style;
}

static UIColor *DKShareTint(BOOL clear, UIUserInterfaceStyle style) {
    return clear ? DKGlassTintForStyle(style) : nil;
}

static UIColor *DKShareEffectTint(UIVisualEffectView *glass, BOOL clear, UIUserInterfaceStyle style)
    API_AVAILABLE(ios(26.0)) {
    UIColor *fixed = objc_getAssociatedObject(glass, &kGlassFixedTintKey);
    if (fixed) return fixed;
    return DKShareTint(clear, style);
}

static UIGlassEffect *DKShareMakeEffect(UIVisualEffectView *glass, BOOL clear,
                                        UIUserInterfaceStyle style)
    API_AVAILABLE(ios(26.0)) {
    UIGlassEffect *effect = [UIGlassEffect effectWithStyle:
        clear ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular];
    effect.tintColor = DKShareEffectTint(glass, clear, style);
    effect.interactive = YES;
    return effect;
}

static void DKShareRunAnimation(UIViewController *controller, BOOL animated, void (^changes)(void)) {
    if (!changes) return;
    if (!animated || UIAccessibilityIsReduceMotionEnabled()) {
        [UIView performWithoutAnimation:changes];
        return;
    }
    id<UIViewControllerTransitionCoordinator> coordinator = controller.transitionCoordinator;
    if (coordinator && coordinator.isAnimated) {
        BOOL accepted = [coordinator animateAlongsideTransition:
                         ^(__unused id<UIViewControllerTransitionCoordinatorContext> context) {
            changes();
        } completion:nil];
        if (accepted) return;
    }
    [UIView animateWithDuration:kDKShareGlassAnimation
                          delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState
                              | UIViewAnimationOptionAllowUserInteraction
                              | UIViewAnimationOptionCurveEaseInOut
                     animations:changes
                     completion:nil];
}

static void DKShareInstallEffect(UIVisualEffectView *glass, BOOL clear, UIUserInterfaceStyle style)
    API_AVAILABLE(ios(26.0)) {
    glass.effect = DKShareMakeEffect(glass, clear, style);
    objc_setAssociatedObject(glass, &kGlassClearKey, @(clear), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(glass, &kGlassStyleKey, @(style), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL DKShareGlassNeedsUpdate(UIVisualEffectView *glass, BOOL clear, UIUserInterfaceStyle style)
    API_AVAILABLE(ios(26.0)) {
    if (glass.overrideUserInterfaceStyle != DKShareOverrideStyle(clear, style)) return YES;
    UIGlassEffect *current = [glass.effect isKindOfClass:UIGlassEffect.class]
        ? (UIGlassEffect *)glass.effect : nil;
    if (!current) return glass.effect != nil;
    NSNumber *installedClear = objc_getAssociatedObject(glass, &kGlassClearKey);
    NSNumber *installedStyle = objc_getAssociatedObject(glass, &kGlassStyleKey);
    if (!installedClear || installedClear.boolValue != clear) return YES;
    if (!installedStyle || installedStyle.integerValue != style) return YES;
    if (!current.interactive) return YES;
    UIColor *want = DKShareEffectTint(glass, clear, style);
    return !((current.tintColor == want) || [current.tintColor isEqual:want]);
}

static void DKShareApplyStyle(UIUserInterfaceStyle style, BOOL animated) API_AVAILABLE(ios(26.0)) {
    if (style == UIUserInterfaceStyleUnspecified) return;
    gGlassStyle = style;
    BOOL clear = DKShareUsesClear();
    BOOL needs = NO;
    for (UIVisualEffectView *glass in gGlassCarriers.allObjects) {
        if (DKShareGlassNeedsUpdate(glass, clear, style)) {
            needs = YES;
            break;
        }
    }
    if (!needs) return;

    DKShareRunAnimation(nil, animated, ^{
        for (UIVisualEffectView *glass in gGlassCarriers.allObjects) {
            glass.overrideUserInterfaceStyle = DKShareOverrideStyle(clear, style);
            if (!glass.effect || !DKShareGlassNeedsUpdate(glass, clear, style)) continue;
            DKShareInstallEffect(glass, clear, style);
        }
    });
}

static void DKShareObserveStyle(UIView *host) API_AVAILABLE(ios(26.0)) {
    UIWindowScene *scene = host.window.windowScene;
    if (!scene || scene == gObservedScene) return;
    gObservedScene = scene;
    [scene registerForTraitChanges:@[ UITraitUserInterfaceStyle.class ]
                       withHandler:^(UIWindowScene *changed, __unused UITraitCollection *previous) {
        DKShareApplyStyle(changed.traitCollection.userInterfaceStyle, YES);
    }];
}

static UIVisualEffectView *DKShareMakeShell(void) API_AVAILABLE(ios(26.0)) {
    DKGlassFlexView *glass = [[DKGlassFlexView alloc] initWithEffect:nil];
    glass.userInteractionEnabled = NO;
    glass.alpha = 1.0;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    return glass;
}

static void DKShareEnsureBackmost(UIView *slot, UIView *glass) {
    if (slot.subviews.firstObject == glass) return;
    [slot insertSubview:glass atIndex:0];
}

static BOOL DKShareRectUsable(CGRect rect) {
    return CGRectGetWidth(rect) >= 8.0 && CGRectGetHeight(rect) >= 8.0;
}

// 0 尺寸时写入 UIGlassEffect，系统不会建材质层；之后只改 frame 补不回来。
static void DKSharePlaceGlass(UIVisualEffectView *glass, CGRect frame, UIView *host, UIView *below) {
    if (!glass || !host) return;
    BOOL wasEmpty = !DKShareRectUsable(glass.bounds);
    if (!CGRectEqualToRect(glass.frame, frame)) glass.frame = frame;
    if (below.superview == host) {
        if (glass.superview != host) [host insertSubview:glass belowSubview:below];
    } else if (glass.superview != host) {
        [host insertSubview:glass atIndex:0];
    }
    if (wasEmpty && DKShareRectUsable(glass.bounds) && glass.effect) {
        glass.effect = nil;
        objc_setAssociatedObject(glass, &kGlassMaterializingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void DKShareMaterialize(UIVisualEffectView *glass, UIViewController *controller)
    API_AVAILABLE(ios(26.0)) {
    if (!glass || !DKShareRectUsable(glass.bounds) || glass.effect
        || [objc_getAssociatedObject(glass, &kGlassMaterializingKey) boolValue]) {
        return;
    }
    objc_setAssociatedObject(glass, &kGlassMaterializingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKShareRunAnimation(controller, YES, ^{
        if (!glass.superview || !DKShareEnabled()) {
            objc_setAssociatedObject(glass, &kGlassMaterializingKey,
                                     nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }
        UIUserInterfaceStyle style = gGlassStyle;
        if (style == UIUserInterfaceStyleUnspecified) style = DKShareStyleForView(glass);
        BOOL clear = DKShareUsesClear();
        glass.overrideUserInterfaceStyle = DKShareOverrideStyle(clear, style);
        DKShareInstallEffect(glass, clear, style);
        objc_setAssociatedObject(glass, &kGlassMaterializingKey,
                                 nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

#pragma mark - 去白底

static UIImage *DKShareDestainPlate(UIImage *image) {
    if (!image || [objc_getAssociatedObject(image, &kDestainedFlagKey) boolValue]) return image;
    UIImage *cached = objc_getAssociatedObject(image, &kDestainedCacheKey);
    if (cached) return cached;

    CGImageRef cgImage = image.CGImage;
    if (!cgImage) return image;
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    if (width == 0 || height == 0) return image;

    size_t stride = width * 4;
    uint8_t *pixels = (uint8_t *)calloc(height * stride, 1);
    if (!pixels) return image;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
        pixels, width, height, 8, stride, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) {
        free(pixels);
        return image;
    }
    CGContextDrawImage(context, CGRectMake(0.0, 0.0, width, height), cgImage);

    NSUInteger kept = 0;
    size_t count = width * height;
    for (size_t i = 0; i < count; i++) {
        uint8_t *pixel = pixels + i * 4;
        float red = pixel[0] / 255.0f;
        float green = pixel[1] / 255.0f;
        float blue = pixel[2] / 255.0f;
        float alpha = pixel[3] / 255.0f;
        if (alpha < 0.02f) continue;
        float maximum = fmaxf(red, fmaxf(green, blue));
        float minimum = fminf(red, fminf(green, blue));
        float saturation = maximum > 0.001f ? (maximum - minimum) / maximum : 0.0f;
        if (maximum >= kDKSharePlateLuma && saturation <= kDKSharePlateSat) {
            pixel[0] = pixel[1] = pixel[2] = pixel[3] = 0;
        } else {
            kept += 1;
        }
    }

    UIImage *result = image;
    if (kept > 0) {
        CGImageRef output = CGBitmapContextCreateImage(context);
        if (output) {
            result = [UIImage imageWithCGImage:output
                                         scale:image.scale
                                   orientation:image.imageOrientation];
            CGImageRelease(output);
            objc_setAssociatedObject(result, &kDestainedFlagKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    CGContextRelease(context);
    free(pixels);
    objc_setAssociatedObject(image, &kDestainedCacheKey, result, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return result;
}

#pragma mark - 查找

// 分享面板容器与分享评论面板的外壳都是这个类，取到只为读它的圆角。
static UIView *DKShareEffectView(UIViewController *controller) {
    Class cls = NSClassFromString(kDKShareEffectClass);
    if (!cls || !controller.isViewLoaded) return nil;
    for (UIView *subview in controller.view.subviews) {
        if ([subview isKindOfClass:cls]) return subview;
    }
    return nil;
}

static AWESharePanelViewController *DKShareContentController(UIViewController *controller) {
    if (!controller) return nil;
    if ([controller isKindOfClass:%c(AWESharePanelViewController)]) {
        return (AWESharePanelViewController *)controller;
    }
    if ([controller isKindOfClass:UINavigationController.class]) {
        return DKShareContentController(((UINavigationController *)controller).topViewController);
    }
    for (UIViewController *child in controller.childViewControllers) {
        AWESharePanelViewController *found = DKShareContentController(child);
        if (found) return found;
    }
    return nil;
}

static UIButton *DKShareCloseButton(AWESharePanelViewController *controller) {
    if (!controller.isViewLoaded) return nil;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:controller.view];
    while (stack.count > 0) {
        UIView *view = stack.lastObject;
        [stack removeLastObject];
        if ([view isKindOfClass:UIButton.class]
            && [((UIButton *)view).accessibilityLabel isEqualToString:@"关闭"]) {
            return (UIButton *)view;
        }
        for (UIView *subview in view.subviews) [stack addObject:subview];
    }
    return nil;
}

static UIViewController *DKShareControllerForView(UIView *view) {
    for (UIResponder *responder = view.nextResponder; responder; responder = responder.nextResponder) {
        if ([responder isKindOfClass:UIViewController.class]) return (UIViewController *)responder;
    }
    return nil;
}

// 圆底板：约 56×56、圆角裁成圆。图标可能画在这张图里，也可能只在 smallImageView 上。
static BOOL DKShareIsCirclePlate(UIImageView *imageView) {
    if (!imageView) return NO;
    CGFloat width = CGRectGetWidth(imageView.bounds);
    CGFloat height = CGRectGetHeight(imageView.bounds);
    if (width >= 40.0 && fabs(width - height) <= 1.0) return YES;
    return width < 1.0 && imageView.layer.cornerRadius >= 8.0;
}

static UIImageView *DKShareFindCircleImage(UIView *view, NSUInteger depth) {
    if (!view || depth > 8) return nil;
    if ([view isKindOfClass:UIImageView.class]
        && DKShareIsCirclePlate((UIImageView *)view)) {
        return (UIImageView *)view;
    }
    UIImageView *fallback = nil;
    for (UIView *subview in view.subviews) {
        UIImageView *found = DKShareFindCircleImage(subview, depth + 1);
        if (!found) continue;
        if (CGRectGetWidth(found.bounds) >= 40.0) return found;
        if (!fallback) fallback = found;
    }
    return fallback;
}

static UIImageView *DKShareCircleImageView(AWESharePanelFunctionCell *cell) {
    if ([cell respondsToSelector:@selector(imageView)] && cell.imageView
        && (DKShareIsCirclePlate(cell.imageView)
            || cell.imageView.image
            || DKShareColorOpaque(cell.imageView.backgroundColor))) {
        return cell.imageView;
    }
    return DKShareFindCircleImage(cell, 0);
}

#pragma mark - 面板

static BOOL DKShareClearSlot(UIView *slot) {
    UIColor *current = slot.backgroundColor;
    if (DKShareColorOpaque(current)) {
        if (!objc_getAssociatedObject(slot, &kSlotColorKey)) {
            objc_setAssociatedObject(slot, &kSlotColorKey, current, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        slot.backgroundColor = UIColor.clearColor;
        gEverAttached = YES;
        return YES;
    }
    return objc_getAssociatedObject(slot, &kSlotColorKey) != nil;
}

static UIVisualEffectView *DKShareAttachPanel(UIView *slot, UIView *shell)
    API_AVAILABLE(ios(26.0)) {
    if (!DKShareClearSlot(slot)) return nil;
    UIVisualEffectView *glass = objc_getAssociatedObject(slot, &kSlotGlassKey);
    if (!glass) {
        if ([slot.subviews.firstObject isKindOfClass:UIVisualEffectView.class]) return nil;
        glass = DKShareMakeShell();
        CGFloat radius = shell.layer.cornerRadius;
        if (radius <= 0.0) radius = kDKShareRadiusFloor;
        UICornerRadius *top = [UICornerRadius containerConcentricRadiusWithMinimum:radius];
        glass.cornerConfiguration =
            [UICornerConfiguration configurationWithUniformTopRadius:top
                                                    bottomLeftRadius:nil
                                                   bottomRightRadius:nil];
        ((DKGlassFlexView *)glass).flexSourceView = slot;
        objc_setAssociatedObject(slot, &kSlotGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gGlassCarriers addObject:glass];
        gEverAttached = YES;
    }
    if (!CGRectEqualToRect(glass.frame, slot.bounds)) glass.frame = slot.bounds;
    DKShareEnsureBackmost(slot, glass);
    return glass;
}

static void DKShareDetachPanel(UIView *slot) {
    UIColor *original = objc_getAssociatedObject(slot, &kSlotColorKey);
    if (!original) return;
    [(UIView *)objc_getAssociatedObject(slot, &kSlotGlassKey) removeFromSuperview];
    slot.backgroundColor = original;
    objc_setAssociatedObject(slot, &kSlotColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(slot, &kSlotGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - 关闭键

static void DKShareRememberClose(UIButton *button) {
    if (objc_getAssociatedObject(button, &kCloseOriginalImageKey)
        || objc_getAssociatedObject(button, &kCloseOriginalConfigKey)) {
        return;
    }
    if (button.configuration) {
        objc_setAssociatedObject(button, &kCloseOriginalConfigKey,
                                 button.configuration, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIImage *image = button.currentImage ?: button.imageView.image;
    if (image) {
        objc_setAssociatedObject(button, &kCloseOriginalImageKey,
                                 image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void DKShareRemoveCloseOverlay(UIButton *button) {
    UIView *glass = objc_getAssociatedObject(button, &kCloseGlassKey);
    [glass removeFromSuperview];
    [gGlassCarriers removeObject:glass];
    objc_setAssociatedObject(button, &kCloseGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DKShareRestoreClose(UIButton *button) {
    if (!button) return;
    DKShareRemoveCloseOverlay(button);
    UIButtonConfiguration *config = objc_getAssociatedObject(button, &kCloseOriginalConfigKey);
    UIImage *image = objc_getAssociatedObject(button, &kCloseOriginalImageKey);
    if (config) {
        button.configuration = config;
    } else if (objc_getAssociatedObject(button, &kCloseModeKey)) {
        button.configuration = nil;
        if (image) [button setImage:image forState:UIControlStateNormal];
    }
    objc_setAssociatedObject(button, &kCloseOriginalConfigKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, &kCloseOriginalImageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, &kCloseModeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DKShareApplyCloseOverlay(UIButton *button, UIViewController *controller)
    API_AVAILABLE(ios(26.0)) {
    UIImage *original = objc_getAssociatedObject(button, &kCloseOriginalImageKey);
    if (original) {
        UIImage *icon = DKShareDestainPlate(original);
        if (button.configuration) button.configuration = nil;
        [button setImage:icon forState:UIControlStateNormal];
    }

    UIView *host = button.superview;
    if (!host) return;
    UIVisualEffectView *glass = objc_getAssociatedObject(button, &kCloseGlassKey);
    if (!glass) {
        glass = DKShareMakeShell();
        glass.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];
        ((DKGlassFlexView *)glass).flexSourceView = button;
        objc_setAssociatedObject(button, &kCloseGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gGlassCarriers addObject:glass];
    }
    glass.autoresizingMask = UIViewAutoresizingNone;
    DKSharePlaceGlass(glass, button.frame, host, button);
    objc_setAssociatedObject(button, &kCloseModeKey,
                             @(DKShareCloseModeOverlay), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKShareMaterialize(glass, controller);
}

static BOOL DKShareApplyCloseOfficial(UIButton *button) API_AVAILABLE(ios(26.0)) {
    if (![UIButtonConfiguration respondsToSelector:@selector(glassButtonConfiguration)]) return NO;
    DKShareRemoveCloseOverlay(button);

    UIImage *original = objc_getAssociatedObject(button, &kCloseOriginalImageKey);
    UIButtonConfiguration *config = [UIButtonConfiguration glassButtonConfiguration];
    config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    config.contentInsets = NSDirectionalEdgeInsetsZero;
    if (original) config.image = DKShareDestainPlate(original);
    button.configuration = config;
    objc_setAssociatedObject(button, &kCloseModeKey,
                             @(DKShareCloseModeOfficial), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}

static void DKShareApplyClose(UIButton *button, UIViewController *controller)
    API_AVAILABLE(ios(26.0)) {
    if (!button) return;
    DKShareRememberClose(button);
    if (DKShareUsesClear()) {
        DKShareApplyCloseOverlay(button, controller);
        return;
    }
    if (!DKShareApplyCloseOfficial(button)) DKShareApplyCloseOverlay(button, controller);
}

#pragma mark - 第三行圆钮

static void DKShareRestoreCell(AWESharePanelFunctionCell *cell) {
    UIImageView *imageView = DKShareCircleImageView(cell);
    UIImage *original = objc_getAssociatedObject(cell, &kCellOriginalImageKey);
    UIColor *color = objc_getAssociatedObject(cell, &kCellOriginalColorKey);
    if (imageView && original) imageView.image = original;
    if (imageView && color) imageView.backgroundColor = color;
    UIView *glass = objc_getAssociatedObject(cell, &kCellGlassKey);
    [glass removeFromSuperview];
    [gGlassCarriers removeObject:glass];
    objc_setAssociatedObject(cell, &kCellOriginalImageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(cell, &kCellOriginalColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(cell, &kCellGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gCells removeObject:cell];
}

static void DKShareApplyCell(AWESharePanelFunctionCell *cell, UIViewController *controller)
    API_AVAILABLE(ios(26.0)) {
    UIImageView *imageView = DKShareCircleImageView(cell);
    if (!imageView) return;

    // 底板两种画法：56×56 合成图，或白底 + smallImageView 图标。后一种没有 image。
    if (DKShareColorOpaque(imageView.backgroundColor)) {
        if (!objc_getAssociatedObject(cell, &kCellOriginalColorKey)) {
            objc_setAssociatedObject(cell, &kCellOriginalColorKey,
                                     imageView.backgroundColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        imageView.backgroundColor = UIColor.clearColor;
    }

    UIImage *current = imageView.image;
    if (current && ![objc_getAssociatedObject(current, &kDestainedFlagKey) boolValue]) {
        objc_setAssociatedObject(cell, &kCellOriginalImageKey,
                                 current, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIImage *icon = DKShareDestainPlate(current);
        if (icon != current) imageView.image = icon;
    }

    UIView *host = imageView.superview;
    if (!host) return;
    UIVisualEffectView *glass = objc_getAssociatedObject(cell, &kCellGlassKey);
    if (!glass) {
        glass = DKShareMakeShell();
        glass.autoresizingMask = UIViewAutoresizingNone;
        glass.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];
        ((DKGlassFlexView *)glass).flexSourceView = cell;
        objc_setAssociatedObject(cell, &kCellGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gGlassCarriers addObject:glass];
        [gCells addObject:cell];
        gEverAttached = YES;
    }
    DKSharePlaceGlass(glass, imageView.frame, host, imageView);
    DKShareMaterialize(glass, controller);
}

static void DKShareCollectFunctionCells(UIView *view,
                                        NSMutableArray<AWESharePanelFunctionCell *> *output,
                                        NSUInteger depth) {
    if (!view || depth > 12) return;
    if ([view isKindOfClass:%c(AWESharePanelFunctionCell)]) {
        [output addObject:(AWESharePanelFunctionCell *)view];
        return;
    }
    for (UIView *subview in view.subviews) {
        DKShareCollectFunctionCells(subview, output, depth + 1);
    }
}

static void DKShareApplyVisibleCells(AWESharePanelViewController *controller)
    API_AVAILABLE(ios(26.0)) {
    if (!controller.isViewLoaded) return;
    NSMutableArray<AWESharePanelFunctionCell *> *cells = [NSMutableArray array];
    DKShareCollectFunctionCells(controller.view, cells, 0);
    for (AWESharePanelFunctionCell *cell in cells) DKShareApplyCell(cell, controller);
}

#pragma mark - 输入覆盖层 / 发送按钮 / 表情栏

static Class DKShareOverlayClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(kDKShareOverlayClass); });
    return cls;
}

static UIView *DKShareOverlayHost(UIView *overlay) {
    return [overlay isKindOfClass:UIVisualEffectView.class]
        ? ((UIVisualEffectView *)overlay).contentView : overlay;
}

static UIVisualEffectView *DKShareEnsureGlass(id owner, const void *key, UIView *flexSource)
    API_AVAILABLE(ios(26.0)) {
    UIVisualEffectView *glass = objc_getAssociatedObject(owner, key);
    if (glass) return glass;
    glass = DKShareMakeShell();
    ((DKGlassFlexView *)glass).flexSourceView = flexSource;
    objc_setAssociatedObject(owner, key, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gGlassCarriers addObject:glass];
    gEverAttached = YES;
    return glass;
}

static void DKShareDiscardGlass(id owner, const void *key) {
    UIView *glass = objc_getAssociatedObject(owner, key);
    [glass removeFromSuperview];
    [gGlassCarriers removeObject:glass];
    objc_setAssociatedObject(owner, key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DKShareRememberColor(UIView *view, const void *colorKey, const void *opaqueKey) {
    id existing = objc_getAssociatedObject(view, colorKey);
    UIColor *color = view.backgroundColor;
    if (existing && existing != [NSNull null]) return;
    if (existing == [NSNull null] && (!color || CGColorGetAlpha(color.CGColor) <= 0.01)) return;
    objc_setAssociatedObject(view, colorKey,
                             color ?: (id)[NSNull null], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!objc_getAssociatedObject(view, opaqueKey)) {
        objc_setAssociatedObject(view, opaqueKey, @(view.opaque), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void DKShareRestoreColor(UIView *view, const void *colorKey, const void *opaqueKey) {
    id color = objc_getAssociatedObject(view, colorKey);
    if (!color) return;
    NSNumber *opaque = objc_getAssociatedObject(view, opaqueKey);
    objc_setAssociatedObject(view, colorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, opaqueKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.backgroundColor = (color == [NSNull null]) ? nil : (UIColor *)color;
    if (opaque) view.opaque = opaque.boolValue;
}

static UIView *DKShareFindDivider(UIView *host) {
    for (UIView *sub in host.subviews) {
        CGFloat height = CGRectGetHeight(sub.bounds);
        if (height > 0.1 && height < 1.5
            && CGRectGetWidth(sub.bounds) >= 200.0
            && CGRectGetMinY(sub.frame) < 16.0) {
            return sub;
        }
    }
    return nil;
}

static void DKShareHideDivider(UIView *overlay) {
    UIView *divider = objc_getAssociatedObject(overlay, &kOverlayDividerKey);
    if (!divider) {
        divider = DKShareFindDivider(DKShareOverlayHost(overlay));
        if (!divider) return;
        objc_setAssociatedObject(overlay, &kOverlayDividerKey, divider, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(divider, &kDividerHiddenKey, @(divider.hidden),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    divider.hidden = YES;
}

static void DKShareRestoreDivider(UIView *overlay) {
    UIView *divider = objc_getAssociatedObject(overlay, &kOverlayDividerKey);
    NSNumber *hidden = objc_getAssociatedObject(divider, &kDividerHiddenKey);
    if (divider && hidden) divider.hidden = hidden.boolValue;
    objc_setAssociatedObject(overlay, &kOverlayDividerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(divider, &kDividerHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DKShareRestoreOverlay(UIView *overlay) {
    if (!overlay) return;
    DKShareRestoreDivider(overlay);
    DKShareDiscardGlass(overlay, &kOverlayGlassKey);
    DKShareRestoreColor(overlay, &kOverlayColorKey, &kOverlayOpaqueKey);
    objc_setAssociatedObject(overlay, &kOverlayTakenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIVisualEffect *effect = objc_getAssociatedObject(overlay, &kOverlayEffectKey);
    objc_setAssociatedObject(overlay, &kOverlayEffectKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (effect && [overlay isKindOfClass:UIVisualEffectView.class]) {
        ((UIVisualEffectView *)overlay).effect = effect;
    }
}

// 清底色、摘原生 effect、藏顶部分割线。分享评论面板的覆盖层落在输入区白垫的玻璃上，
// 只做到这一步；分享面板还要接着自己挂一块玻璃。
static void DKShareStripOverlay(UIView *overlay) {
    if (!overlay) return;
    DKShareRememberColor(overlay, &kOverlayColorKey, &kOverlayOpaqueKey);
    if (DKShareColorOpaque(overlay.backgroundColor)) overlay.backgroundColor = UIColor.clearColor;
    overlay.opaque = NO;

    if ([overlay isKindOfClass:UIVisualEffectView.class]) {
        UIVisualEffectView *effectView = (UIVisualEffectView *)overlay;
        if (effectView.effect && !objc_getAssociatedObject(overlay, &kOverlayEffectKey)) {
            objc_setAssociatedObject(overlay, &kOverlayEffectKey,
                                     effectView.effect, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        // 本函数会被覆盖层自己的布局回调反复调用，重复写 effect 会再挑一次布局。
        if (effectView.effect) effectView.effect = nil;
    }
    objc_setAssociatedObject(overlay, &kOverlayTakenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKShareHideDivider(overlay);
    DKShareOverlayHost(overlay).opaque = NO;
}

// 覆盖层叠在第三行功能圆钮上，只能自己挂玻璃，不能只清底色。
static void DKShareApplyOverlay(UIView *overlay, UIViewController *controller)
    API_AVAILABLE(ios(26.0)) {
    if (!overlay) return;
    DKShareStripOverlay(overlay);

    UIView *host = DKShareOverlayHost(overlay);
    if (!host) return;
    UIVisualEffectView *glass = DKShareEnsureGlass(overlay, &kOverlayGlassKey, overlay);
    if (!CGRectEqualToRect(glass.frame, host.bounds)) glass.frame = host.bounds;
    DKShareEnsureBackmost(host, glass);
    DKShareMaterialize(glass, controller);
}

static NSString *DKShareButtonTitle(UIView *button) {
    id object = button;
    NSString *title = [object respondsToSelector:@selector(currentTitle)]
        ? [object currentTitle] : nil;
    if (title.length) return title;
    return [object respondsToSelector:@selector(accessibilityLabel)]
        ? ([object accessibilityLabel] ?: @"") : @"";
}

static BOOL DKShareIsSendButton(UIView *view) {
    if (!view) return NO;
    if (CGRectGetHeight(view.bounds) < 36.0) return NO;

    // 覆盖层内先按语义类名识别，再对其他 UIControl 使用标题判定。
    NSString *className = NSStringFromClass(view.class);
    if ([className containsString:@"ShareAdditionTextButton"]) return YES;
    if (![view isKindOfClass:UIControl.class]) return NO;
    return [DKShareButtonTitle(view) containsString:@"发送"];
}

static void DKShareCollectSendButtons(UIView *view, NSMutableArray<UIView *> *output,
                                      NSUInteger depth) {
    if (!view || depth > 8) return;
    if (DKShareIsSendButton(view)) {
        [output addObject:view];
        return;
    }
    for (UIView *subview in view.subviews) {
        DKShareCollectSendButtons(subview, output, depth + 1);
    }
}

static void DKShareRestoreSendButton(UIView *button) {
    if (!button) return;
    DKShareDiscardGlass(button, &kButtonGlassKey);
    DKShareRestoreColor(button, &kButtonColorKey, &kButtonOpaqueKey);
    objc_setAssociatedObject(button, &kButtonRadiusKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gSendButtons removeObject:button];
}

static void DKShareApplySendButton(UIView *button, UIViewController *controller)
    API_AVAILABLE(ios(26.0)) {
    if (!button) return;
    DKShareRememberColor(button, &kButtonColorKey, &kButtonOpaqueKey);
    UIColor *current = button.backgroundColor;
    if (current && CGColorGetAlpha(current.CGColor) > 0.01) {
        button.backgroundColor = UIColor.clearColor;
    }
    button.opaque = NO;

    // 玻璃挂在按钮内部：随按钮释放，并吃到原生 8pt 裁剪。
    UIVisualEffectView *glass = DKShareEnsureGlass(button, &kButtonGlassKey, button);
    CGFloat radius = button.layer.cornerRadius;
    if (radius <= 0.0) radius = kDKShareSendRadiusFloor;
    NSNumber *installedRadius = objc_getAssociatedObject(button, &kButtonRadiusKey);
    if (!installedRadius || installedRadius.doubleValue != radius) {
        glass.cornerConfiguration =
            [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius fixedRadius:radius]];
        objc_setAssociatedObject(button, &kButtonRadiusKey, @(radius), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [gSendButtons addObject:button];

    id original = objc_getAssociatedObject(button, &kButtonColorKey);
    NSString *title = DKShareButtonTitle(button);
    BOOL primary = ([original isKindOfClass:UIColor.class] && DKShareColorOpaque((UIColor *)original))
        || ([title containsString:@"发送"] && ![title containsString:@"建群"]);
    if (primary) {
        UIColor *tint = ([original isKindOfClass:UIColor.class] && DKShareColorOpaque((UIColor *)original))
            ? (UIColor *)original
            : [UIColor colorWithRed:0.9961 green:0.1725 blue:0.3333 alpha:1.0];
        objc_setAssociatedObject(glass, &kGlassFixedTintKey, tint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (!CGRectEqualToRect(glass.frame, button.bounds)) glass.frame = button.bounds;
    DKShareEnsureBackmost(button, glass);
    DKShareMaterialize(glass, controller);
}

static void DKShareApplySendButtons(UIView *overlay, UIViewController *controller)
    API_AVAILABLE(ios(26.0)) {
    NSMutableArray<UIView *> *buttons = [NSMutableArray array];
    DKShareCollectSendButtons(overlay, buttons, 0);
    for (UIView *button in buttons) DKShareApplySendButton(button, controller);
}

static void DKShareRestoreToolbarFill(UIView *view) {
    DKShareRestoreColor(view, &kToolbarColorKey, &kToolbarOpaqueKey);
}

static void DKShareClearToolbarFills(UIView *view, NSUInteger depth) {
    if (!view || depth > 4) return;
    if ([view isKindOfClass:UIControl.class]
        || [view isKindOfClass:UIImageView.class]
        || [view isKindOfClass:UILabel.class]
        || [view isKindOfClass:UIVisualEffectView.class]) {
        return;
    }
    if (DKShareColorOpaque(view.backgroundColor)) {
        DKShareRememberColor(view, &kToolbarColorKey, &kToolbarOpaqueKey);
        view.backgroundColor = UIColor.clearColor;
        view.opaque = NO;
    }
    for (UIView *subview in view.subviews) DKShareClearToolbarFills(subview, depth + 1);
}

static void DKShareRestoreToolbarFillsUnder(UIView *view, NSUInteger depth) {
    if (!view || depth > 4) return;
    if (objc_getAssociatedObject(view, &kToolbarColorKey)) DKShareRestoreToolbarFill(view);
    for (UIView *subview in view.subviews) DKShareRestoreToolbarFillsUnder(subview, depth + 1);
}

static void DKShareRestoreToolbar(UIView *bar) {
    if (!bar) return;
    DKShareDiscardGlass(bar, &kToolbarGlassKey);
    DKShareRestoreToolbarFillsUnder(bar, 0);
}

static UIView *DKShareToolbarSlot(UIView *bar) {
    if ([bar respondsToSelector:@selector(inputControlBar)]) {
        UIView *slot = ((AWEIMShareInputEmoticonToolBarView *)bar).inputControlBar;
        if (slot) return slot;
    }
    for (UIView *subview in bar.subviews) {
        CGFloat height = CGRectGetHeight(subview.bounds);
        if (height >= 32.0 && height <= 48.0
            && fabs(CGRectGetWidth(subview.bounds) - CGRectGetWidth(bar.bounds)) < 2.0) {
            return subview;
        }
    }
    return nil;
}

static void DKShareApplyToolbar(UIView *bar, UIViewController *controller)
    API_AVAILABLE(ios(26.0)) {
    if (!bar) return;
    DKShareClearToolbarFills(bar, 0);
    UIView *slot = DKShareToolbarSlot(bar);
    if (!slot || !DKShareRectUsable(slot.bounds)) return;
    slot.opaque = NO;
    UIVisualEffectView *glass = DKShareEnsureGlass(bar, &kToolbarGlassKey, slot);
    if (!CGRectEqualToRect(glass.frame, slot.bounds)) glass.frame = slot.bounds;
    DKShareEnsureBackmost(slot, glass);
    DKShareMaterialize(glass, controller);
}

static void DKShareWalkContent(AWESharePanelViewController *content, UIView **overlay, UIView **toolbar) {
    if (overlay) *overlay = nil;
    if (toolbar) *toolbar = nil;
    if (!content.isViewLoaded) return;
    Class overlayClass = DKShareOverlayClass();
    Class toolbarClass = %c(AWEIMShareInputEmoticonToolBarView);
    for (UIView *subview in content.view.subviews) {
        if (overlay && overlayClass && !*overlay && [subview isKindOfClass:overlayClass]) {
            *overlay = subview;
        }
        if (toolbar && toolbarClass && !*toolbar && [subview isKindOfClass:toolbarClass]) {
            *toolbar = subview;
        }
    }
}

static void DKShareSyncInput(AWESharePanelViewController *content)
    API_AVAILABLE(ios(26.0)) {
    UIView *overlay = nil;
    UIView *toolbar = nil;
    DKShareWalkContent(content, &overlay, &toolbar);
    if (overlay && !overlay.hidden) {
        DKShareApplyOverlay(overlay, content);
        DKShareApplySendButtons(overlay, content);
    }
    if (toolbar) DKShareApplyToolbar(toolbar, content);
}

static void DKShareRestoreInput(AWESharePanelViewController *content) {
    UIView *overlay = nil;
    UIView *toolbar = nil;
    DKShareWalkContent(content, &overlay, &toolbar);
    if (overlay) {
        NSMutableArray<UIView *> *buttons = [NSMutableArray array];
        DKShareCollectSendButtons(overlay, buttons, 0);
        for (UIView *button in buttons) DKShareRestoreSendButton(button);
        DKShareRestoreOverlay(overlay);
    }
    if (toolbar) DKShareRestoreToolbar(toolbar);
}

#pragma mark - 分享评论面板

// 不透明浅色底板槽：记原色清透明，最底层挂一块玻璃。
// corners 为 nil 时圆角交给宿主的裁剪，只在新建玻璃时写一次。
static UIVisualEffectView *DKShareApplyPlate(UIView *slot, UICornerConfiguration *corners,
                                             UIViewController *controller)
    API_AVAILABLE(ios(26.0)) {
    if (!slot) return nil;
    BOOL taken = objc_getAssociatedObject(slot, &kPlateColorKey) != nil;
    if (!taken && !DKShareCGColorIsPlate(slot.backgroundColor.CGColor)) return nil;

    DKShareRememberColor(slot, &kPlateColorKey, &kPlateOpaqueKey);
    if (DKShareColorOpaque(slot.backgroundColor)) slot.backgroundColor = UIColor.clearColor;
    slot.opaque = NO;

    BOOL fresh = objc_getAssociatedObject(slot, &kPlateGlassKey) == nil;
    UIVisualEffectView *glass = DKShareEnsureGlass(slot, &kPlateGlassKey, slot);
    if (fresh && corners) glass.cornerConfiguration = corners;
    if (!CGRectEqualToRect(glass.frame, slot.bounds)) glass.frame = slot.bounds;
    DKShareEnsureBackmost(slot, glass);
    DKShareMaterialize(glass, controller);
    return glass;
}

static void DKShareRestorePlate(UIView *slot) {
    if (!slot) return;
    DKShareDiscardGlass(slot, &kPlateGlassKey);
    DKShareRestoreColor(slot, &kPlateColorKey, &kPlateOpaqueKey);
}

// 白卡片底画在行内一层非视图 CALayer 上：CAShapeLayer 看 fillColor、普通层看 backgroundColor。
// 同一行还有一层行间分割线，靠「够不够一块卡片大」把它排除掉。
static CGRect DKShareCardRect(CALayer *layer) {
    if ([layer isKindOfClass:CAShapeLayer.class]) {
        CGPathRef path = ((CAShapeLayer *)layer).path;
        if (path && !CGPathIsEmpty(path)) {
            CGRect box = CGPathGetBoundingBox(path);
            return CGRectOffset(box,
                                CGRectGetMinX(layer.frame) - CGRectGetMinX(layer.bounds),
                                CGRectGetMinY(layer.frame) - CGRectGetMinY(layer.bounds));
        }
    }
    return layer.frame;
}

static CALayer *DKShareCardLayer(UIView *view, NSUInteger depth) {
    if (!view || depth > 3) return nil;
    for (CALayer *layer in view.layer.sublayers) {
        // 视图自带的层由视图那条路处理，只认抖音直接加上来的绘制层。
        if ([layer.delegate isKindOfClass:UIView.class]) continue;
        CGColorRef fill = [layer isKindOfClass:CAShapeLayer.class]
            ? ((CAShapeLayer *)layer).fillColor : layer.backgroundColor;
        if (!DKShareCGColorIsPlate(fill)) continue;
        if (!DKShareRectUsable(DKShareCardRect(layer))) continue;
        return layer;
    }
    for (UIView *subview in view.subviews) {
        CALayer *found = DKShareCardLayer(subview, depth + 1);
        if (found) return found;
    }
    return nil;
}

// 行间分割线与卡片底是同一层视图上的两个非视图 sublayer。每行成了独立胶囊之后那条线会浮在
// 两枚胶囊中间的空隙里，要藏起来。判据与 DKShareFindDivider 同款，只是那条找视图、这条找层：
// 卡片层本身按指针排除，剩下的按「细长」认——卡片有一整行那么高，分割线是亚像素。
// 只接管当前可见的那条：抖音自己就藏起来的（末行、或它另有判断）不必碰，
// 也就不会在还原时把一条本不该出现的线写回去。
// 高度不设下限——描边画的一条线，路径包围盒高度是 0。
static CALayer *DKShareFindCardDivider(UIView *host, CALayer *card) {
    for (CALayer *layer in host.layer.sublayers) {
        if (layer == card || layer.hidden || [layer.delegate isKindOfClass:UIView.class]) continue;
        CGRect rect = DKShareCardRect(layer);
        if (CGRectGetHeight(rect) < 1.5 && CGRectGetWidth(rect) >= 200.0) return layer;
    }
    return nil;
}

// 抖音复用行之后会把 hidden 写回来，每轮布局都重设一次。记着的层脱离层级就重新找。
static void DKShareHideCardDivider(UICollectionViewCell *cell, UIView *host, CALayer *card) {
    CALayer *divider = objc_getAssociatedObject(cell, &kCardDividerKey);
    if (divider && !divider.superlayer) {
        objc_setAssociatedObject(cell, &kCardDividerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell, &kCardDividerHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        divider = nil;
    }
    if (!divider) {
        divider = DKShareFindCardDivider(host, card);
        if (!divider) return;
        // 判据已经排掉了藏着的层，记下的原状态恒为「可见」。
        objc_setAssociatedObject(cell, &kCardDividerKey, divider, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell, &kCardDividerHiddenKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!divider.hidden) divider.hidden = YES;
}

static void DKShareRestoreCardDivider(UICollectionViewCell *cell) {
    CALayer *divider = objc_getAssociatedObject(cell, &kCardDividerKey);
    NSNumber *hidden = objc_getAssociatedObject(cell, &kCardDividerHiddenKey);
    if (divider && hidden) divider.hidden = hidden.boolValue;
    objc_setAssociatedObject(cell, &kCardDividerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(cell, &kCardDividerHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DKShareRestoreCardCell(UICollectionViewCell *cell) {
    CALayer *layer = objc_getAssociatedObject(cell, &kCardLayerKey);
    UIColor *fill = objc_getAssociatedObject(cell, &kCardFillKey);
    if (layer && fill) {
        if ([layer isKindOfClass:CAShapeLayer.class]) ((CAShapeLayer *)layer).fillColor = fill.CGColor;
        else layer.backgroundColor = fill.CGColor;
    }
    DKShareRestoreCardDivider(cell);
    DKShareDiscardGlass(cell, &kCardGlassKey);
    objc_setAssociatedObject(cell, &kCardLayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(cell, &kCardFillKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gCardCells removeObject:cell];
}

// 每行一枚独立胶囊：矩形取抖音那块卡片底的实际几何，上下各内缩 kDKShareCardGapInset 让相邻两行
// 之间露出面板玻璃，圆角交给系统 capsuleConfiguration 按内缩后的高度算，行序与行数都不参与。
// covered：输入区白垫整段罩住了卡片。此时卡片玻璃要藏起来，否则它会从白垫玻璃底下透成
// 一块更亮的矩形（同一处三层玻璃）；填充与分割线仍保持清掉 / 隐藏，写回去会更显眼。
static void DKShareApplyCardCell(UICollectionViewCell *cell, UIViewController *controller,
                                 BOOL covered)
    API_AVAILABLE(ios(26.0)) {
    CALayer *layer = objc_getAssociatedObject(cell, &kCardLayerKey);
    // 抖音换掉绘制层时旧层会脱离层级，记着的那个再清也没用，重新找一次。
    if (layer && !layer.superlayer) {
        objc_setAssociatedObject(cell, &kCardLayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell, &kCardFillKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        layer = nil;
    }
    BOOL taken = layer != nil;
    if (!layer) layer = DKShareCardLayer(cell, 0);
    if (!layer) return;
    UIView *host = [layer.superlayer.delegate isKindOfClass:UIView.class]
        ? (UIView *)layer.superlayer.delegate : nil;
    if (!host) return;

    // 玻璃挂到行最底层，而不是塞进持有卡片底的那层视图：那层里还有别的裸 sublayer，
    // insertSubview:atIndex:0 只在视图之间排序，玻璃会排到裸层之后把它们盖掉。
    CGRect rect = CGRectInset([host convertRect:DKShareCardRect(layer) toView:cell],
                              0.0, kDKShareCardGapInset);
    if (!DKShareRectUsable(rect)) return;

    BOOL shape = [layer isKindOfClass:CAShapeLayer.class];
    if (!taken) {
        CGColorRef fill = shape ? ((CAShapeLayer *)layer).fillColor : layer.backgroundColor;
        objc_setAssociatedObject(cell, &kCardLayerKey, layer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell, &kCardFillKey, [UIColor colorWithCGColor:fill],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gCardCells addObject:cell];
    }
    // 复用后抖音会把填充写回来，每次布局都清一次；行间分割线同理。
    if (shape) ((CAShapeLayer *)layer).fillColor = NULL;
    else layer.backgroundColor = NULL;
    DKShareHideCardDivider(cell, host, layer);

    BOOL fresh = objc_getAssociatedObject(cell, &kCardGlassKey) == nil;
    UIVisualEffectView *glass = DKShareEnsureGlass(cell, &kCardGlassKey, cell);
    glass.autoresizingMask = UIViewAutoresizingNone;
    if (glass.hidden != covered) glass.hidden = covered;
    if (fresh) glass.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];
    DKSharePlaceGlass(glass, rect, cell, nil);
    DKShareMaterialize(glass, controller);
}

static void DKShareCollectCardCells(UIView *view, NSMutableArray<UICollectionViewCell *> *output,
                                    NSUInteger depth) {
    if (!view || depth > 8) return;
    if ([view isKindOfClass:%c(CommentLongPressPanelNormalBaseCell)]) {
        [output addObject:(UICollectionViewCell *)view];
        return;
    }
    for (UIView *subview in view.subviews) DKShareCollectCardCells(subview, output, depth + 1);
}

static BOOL DKShareIsCommentSheet(UIViewController *controller) {
    return [NSStringFromClass(controller.class) isEqualToString:kDKShareCommentSheetClass];
}

// 底色槽只按「画底的普通视图」排除，不按类名精确匹配：
// KVO / 动画会给视图换 isa，object_getClass 拿到的是运行时子类，精确比类会漏判。
static BOOL DKShareCanBePlate(UIView *view) {
    return ![view isKindOfClass:UIScrollView.class]
        && ![view isKindOfClass:UIVisualEffectView.class]
        && ![view isKindOfClass:UIControl.class]
        && ![view isKindOfClass:UIImageView.class]
        && ![view isKindOfClass:UILabel.class];
}

// 面板底色槽：外壳 contentView 里那张满幅不透明浅底。
static UIView *DKShareCommentSlot(UIView *shell) {
    UIView *host = [shell isKindOfClass:UIVisualEffectView.class]
        ? ((UIVisualEffectView *)shell).contentView : shell;
    for (UIView *subview in host.subviews) {
        if (objc_getAssociatedObject(subview, &kPlateColorKey)) return subview;
        if (!DKShareCanBePlate(subview)) continue;
        if (!DKShareCGColorIsPlate(subview.backgroundColor.CGColor)) continue;
        if (fabs(CGRectGetWidth(subview.bounds) - CGRectGetWidth(host.bounds)) > 1.0) continue;
        if (fabs(CGRectGetHeight(subview.bounds) - CGRectGetHeight(host.bounds)) > 1.0) continue;
        return subview;
    }
    return nil;
}

// 输入区白垫盖住列表，且比覆盖层高（还罩着表情面板那一段），玻璃挂它、覆盖层只清底色。
static void DKShareCommentWalk(UIViewController *list, UIView **overlay,
                               UIView **plate, UIView **toolbar) {
    if (overlay) *overlay = nil;
    if (plate) *plate = nil;
    if (toolbar) *toolbar = nil;
    if (!list.isViewLoaded) return;

    Class overlayClass = DKShareOverlayClass();
    Class toolbarClass = %c(AWEIMShareInputEmoticonToolBarView);
    UIView *found = nil;
    for (UIView *subview in list.view.subviews) {
        if (overlayClass && !found && [subview isKindOfClass:overlayClass]) found = subview;
        if (toolbar && toolbarClass && !*toolbar && [subview isKindOfClass:toolbarClass]) {
            *toolbar = subview;
        }
    }
    if (overlay) *overlay = found;
    if (!plate) return;
    for (UIView *subview in list.view.subviews) {
        if (subview == found || (toolbar && subview == *toolbar)) continue;
        if (objc_getAssociatedObject(subview, &kPlateColorKey)) {
            *plate = subview;
            return;
        }
        if (!found || !DKShareCanBePlate(subview)) continue;
        if (!DKShareCGColorIsPlate(subview.backgroundColor.CGColor)) continue;
        // 1pt 余量：白垫和覆盖层顶边对齐，浮点噪声不该判成「没框住」。
        if (CGRectGetMinY(subview.frame) > CGRectGetMinY(found.frame) + 1.0) continue;
        if (CGRectGetMaxY(subview.frame) < CGRectGetMaxY(found.frame) - 1.0) continue;
        if (CGRectGetWidth(subview.frame) < CGRectGetWidth(found.frame) - 1.0) continue;
        *plate = subview;
        return;
    }
}

static UIViewController *DKShareCommentList(UIViewController *sheet) {
    return DKChildControllerNamed(sheet, kDKShareCommentListClass);
}

static void DKShareRestoreCommentSheet(UIViewController *sheet) {
    if (sheet.isViewLoaded) {
        DKShareRestorePlate(DKShareCommentSlot(DKShareEffectView(sheet) ?: sheet.view));
    }
    UIViewController *list = DKShareCommentList(sheet);
    UIView *overlay = nil;
    UIView *plate = nil;
    UIView *toolbar = nil;
    DKShareCommentWalk(list, &overlay, &plate, &toolbar);
    if (overlay) {
        NSMutableArray<UIView *> *buttons = [NSMutableArray array];
        DKShareCollectSendButtons(overlay, buttons, 0);
        for (UIView *button in buttons) DKShareRestoreSendButton(button);
        DKShareRestoreOverlay(overlay);
    }
    if (plate) DKShareRestorePlate(plate);
    if (toolbar) DKShareRestoreToolbar(toolbar);
    for (UICollectionViewCell *cell in gCardCells.allObjects) {
        if (!list.viewIfLoaded || [cell isDescendantOfView:list.view]) DKShareRestoreCardCell(cell);
    }
    [gCommentSheets removeObject:sheet];
}

static void DKShareCommentSync(UIViewController *sheet) API_AVAILABLE(ios(26.0)) {
    if (!sheet.isViewLoaded) return;
    BOOL enabled = DKShareEnabled();
    if (!enabled) {
        if (gEverAttached) DKShareRestoreCommentSheet(sheet);
        return;
    }

    [gCommentSheets addObject:sheet];
    DKShareObserveStyle(sheet.view);
    UIUserInterfaceStyle style = DKShareStyleForView(sheet.view);

    UIView *shell = DKShareEffectView(sheet);
    UIView *slot = DKShareCommentSlot(shell ?: sheet.view);
    UIViewController *list = DKShareCommentList(sheet);
    UIViewController *controller = list ?: sheet;

    UIView *overlay = nil;
    UIView *plate = nil;
    UIView *toolbar = nil;
    DKShareCommentWalk(list, &overlay, &plate, &toolbar);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    UIVisualEffectView *panel = nil;
    if (slot) {
        CGFloat radius = shell ? shell.layer.cornerRadius : 0.0;
        if (radius <= 0.0) radius = kDKShareRadiusFloor;
        UICornerRadius *top = [UICornerRadius containerConcentricRadiusWithMinimum:radius];
        UICornerConfiguration *corners =
            [UICornerConfiguration configurationWithUniformTopRadius:top
                                                    bottomLeftRadius:nil
                                                   bottomRightRadius:nil];
        panel = DKShareApplyPlate(slot, corners, controller);
    }
    BOOL inputUp = overlay && !overlay.hidden;
    if (inputUp) {
        DKShareStripOverlay(overlay);
        DKShareApplySendButtons(overlay, controller);
        if (!DKShareApplyPlate(plate, nil, controller)) plate = nil;
    } else {
        if (overlay) DKShareRestoreOverlay(overlay);
        if (plate) DKShareRestorePlate(plate);
        plate = nil;
    }
    if (toolbar) DKShareApplyToolbar(toolbar, controller);

    NSMutableArray<UICollectionViewCell *> *cells = [NSMutableArray array];
    DKShareCollectCardCells(list.viewIfLoaded, cells, 0);
    BOOL covered = plate != nil && !plate.hidden;
    for (UICollectionViewCell *cell in cells) DKShareApplyCardCell(cell, controller, covered);
    [CATransaction commit];

    if (panel) DKShareApplyStyle(style, YES);
}

// 面板外壳是 Swift 类、布局回调不保证经过被挂钩的基类，行自己也能把整面板的同步带起来。
static UIViewController *DKShareCommentSheetForView(UIView *view) {
    for (UIResponder *responder = view.nextResponder; responder; responder = responder.nextResponder) {
        if ([responder isKindOfClass:UIViewController.class]
            && DKShareIsCommentSheet((UIViewController *)responder)) {
            return (UIViewController *)responder;
        }
    }
    return nil;
}

#pragma mark - 选人状态与发送按钮布局

BOOL DKShareSendButtonDidLayout(UIView *button) {
    if (!NSThread.isMainThread) return NO;
    if (!DKShareEnabled()) {
        if (objc_getAssociatedObject(button, &kButtonGlassKey)) DKShareRestoreSendButton(button);
        return NO;
    }
    UIView *overlay = button.superview;
    Class overlayClass = DKShareOverlayClass();
    for (NSUInteger i = 0; overlay && i < 8; i++, overlay = overlay.superview) {
        if (overlayClass && [overlay isKindOfClass:overlayClass]) break;
    }
    if (!overlay || !overlayClass || ![overlay isKindOfClass:overlayClass]) return NO;
    UIViewController *controller = DKShareControllerForView(overlay);
    if (!DKShareCommentSheetForView(overlay)
        && ![controller isKindOfClass:%c(AWESharePanelViewController)]) return NO;
    if (!DKShareRectUsable(button.bounds)) return NO;
    BOOL fresh = objc_getAssociatedObject(button, &kButtonGlassKey) == nil;
    if (@available(iOS 26.0, *)) DKShareApplySendButton(button, controller);
    return fresh;
}

BOOL DKShareCommentSelectionChanged(id section, UIView *overlay) {
    if (!NSThread.isMainThread) return NO;
    UIViewController *controller = [section respondsToSelector:@selector(viewController)]
        ? [section viewController] : nil;
    if (!overlay) {
        UIView *unusedPlate = nil;
        UIView *unusedToolbar = nil;
        DKShareCommentWalk(controller, &overlay, &unusedPlate, &unusedToolbar);
    }
    if (!overlay) return NO;
    UIViewController *sheet = DKShareCommentSheetForView(overlay);
    if (!sheet) return NO;

    if (@available(iOS 26.0, *)) DKShareCommentSync(sheet);
    return YES;
}

NSString *DKShareSelectionDiagnostics(void) {
    return DKShareSelectionHooksStatus();
}

#pragma mark - 同步

static void DKShareRestoreController(AWESharePanelContainerViewController *container) {
    AWESharePanelViewController *content = DKShareContentController(container);
    if (content.isViewLoaded) {
        DKShareRestoreInput(content);
        DKShareRestoreClose(DKShareCloseButton(content));
        DKShareDetachPanel(content.view);
    }
    for (AWESharePanelFunctionCell *cell in gCells.allObjects) {
        if (!content.view || [cell isDescendantOfView:content.view]) DKShareRestoreCell(cell);
    }
    [gContainers removeObject:container];
}

static void DKShareRestoreAll(void) {
    for (AWESharePanelFunctionCell *cell in gCells.allObjects) DKShareRestoreCell(cell);
    for (AWESharePanelContainerViewController *container in gContainers.allObjects) {
        AWESharePanelViewController *content = DKShareContentController(container);
        if (content.isViewLoaded) {
            DKShareRestoreInput(content);
            DKShareRestoreClose(DKShareCloseButton(content));
            DKShareDetachPanel(content.view);
        }
    }
    [gContainers removeAllObjects];
    for (UIViewController *sheet in gCommentSheets.allObjects) DKShareRestoreCommentSheet(sheet);
    for (UICollectionViewCell *cell in gCardCells.allObjects) DKShareRestoreCardCell(cell);
    [gCommentSheets removeAllObjects];
    for (UIView *button in gSendButtons.allObjects) DKShareRestoreSendButton(button);
}

static void DKShareSync(AWESharePanelContainerViewController *container) API_AVAILABLE(ios(26.0)) {
    if (!container.isViewLoaded) return;
    BOOL enabled = DKShareEnabled();
    if (!enabled && !gEverAttached) return;

    AWESharePanelViewController *content = DKShareContentController(container);
    if (!content.isViewLoaded) return;

    if (!enabled) {
        DKShareRestoreController(container);
        return;
    }

    [gContainers addObject:container];
    DKShareObserveStyle(content.view);
    UIUserInterfaceStyle style = DKShareStyleForView(content.view);
    UIView *shell = DKShareEffectView(container);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    UIVisualEffectView *panel = DKShareAttachPanel(content.view, shell ?: content.view);
    DKShareApplyClose(DKShareCloseButton(content), content);
    DKShareApplyVisibleCells(content);
    DKShareSyncInput(content);
    [CATransaction commit];

    if (panel) {
        DKShareApplyStyle(style, YES);
        DKShareMaterialize(panel, content);
    }
}

static void DKShareRefreshVisible(void) {
    BOOL enabled = DKShareEnabled();
    if (!enabled) DKShareRestoreAll();
    for (AWESharePanelContainerViewController *container in gContainers.allObjects) {
        [container.viewIfLoaded setNeedsLayout];
    }
    for (UIViewController *sheet in gCommentSheets.allObjects) {
        [sheet.viewIfLoaded setNeedsLayout];
    }
    for (AWESharePanelFunctionCell *cell in gCells.allObjects) {
        if (!enabled) continue;
        if (@available(iOS 26.0, *)) DKShareApplyCell(cell, DKShareControllerForView(cell));
    }
}

#pragma mark - Hook

%group DKSharePanelGlassHooks

%hook AWESharePanelContainerViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (@available(iOS 26.0, *)) DKShareSync(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) DKShareSync(self);
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (self.viewIfLoaded.window) return;
    DKShareRestoreController(self);
}

%end

%hook AWESharePanelViewController

- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *parent = self.parentViewController;
    while (parent && ![parent isKindOfClass:%c(AWESharePanelContainerViewController)]) {
        parent = parent.parentViewController;
    }
    if ([parent isKindOfClass:%c(AWESharePanelContainerViewController)]
        && @available(iOS 26.0, *)) {
        DKShareSync((AWESharePanelContainerViewController *)parent);
    }
}

- (void)awe_themeReload {
    %orig;
    UIViewController *parent = self.parentViewController;
    while (parent && ![parent isKindOfClass:%c(AWESharePanelContainerViewController)]) {
        parent = parent.parentViewController;
    }
    if ([parent isKindOfClass:%c(AWESharePanelContainerViewController)]
        && @available(iOS 26.0, *)) {
        DKShareSync((AWESharePanelContainerViewController *)parent);
    }
}

%end

%hook AWESharePanelFunctionCell

- (void)layoutSubviews {
    %orig;
    if (!DKShareEnabled()) {
        if (objc_getAssociatedObject(self, &kCellGlassKey)) DKShareRestoreCell(self);
        return;
    }
    if (@available(iOS 26.0, *)) DKShareApplyCell(self, DKShareControllerForView(self));
}

- (void)updateWithViewModel:(id)viewModel bigFontAdapter:(id)adapter {
    %orig;
    if (!DKShareEnabled()) return;
    if (@available(iOS 26.0, *)) DKShareApplyCell(self, DKShareControllerForView(self));
}

- (void)updateImageViewWithViewModel:(id)viewModel {
    %orig;
    if (!DKShareEnabled()) return;
    if (@available(iOS 26.0, *)) DKShareApplyCell(self, nil);
}

- (void)prepareForReuse {
    %orig;
    if (!DKShareEnabled()) DKShareRestoreCell(self);
}

%end

%hook AWEIMShareInputEmoticonToolBarView

- (void)layoutSubviews {
    %orig;
    if (!DKShareEnabled()) {
        if (objc_getAssociatedObject(self, &kToolbarGlassKey)) DKShareRestoreToolbar(self);
        return;
    }
    if (@available(iOS 26.0, *)) {
        DKShareApplyToolbar(self, DKShareControllerForView(self));
    }
}

- (void)setTabBackgroundColor:(id)color {
    if (DKShareEnabled() && DKShareControllerForView(self)) {
        if ([color isKindOfClass:UIColor.class] && DKShareColorOpaque(color)) {
            DKShareRememberColor(self, &kToolbarColorKey, &kToolbarOpaqueKey);
            %orig(UIColor.clearColor);
            return;
        }
    }
    %orig;
}

%end

// 分享评论面板的外壳，按类名只认这一种 DUX 弹层；分享面板走它自己那条 hook。
%hook DUXContentSheet

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (!DKShareIsCommentSheet(self)) return;
    if (@available(iOS 26.0, *)) DKShareCommentSync(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (!DKShareIsCommentSheet(self)) return;
    if (@available(iOS 26.0, *)) DKShareCommentSync(self);
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (!DKShareIsCommentSheet(self) || self.viewIfLoaded.window) return;
    DKShareRestoreCommentSheet(self);
}

%end

%hook CommentLongPressPanelNormalBaseCell

- (void)layoutSubviews {
    %orig;
    if (!DKShareEnabled()) {
        if (objc_getAssociatedObject(self, &kCardGlassKey)) DKShareRestoreCardCell(self);
        return;
    }
    // 面板外壳是 Swift 类、它的布局回调不保证经过被挂钩的基类，行这一路是同步的主驱动：
    // 白垫是选人之后才加进来的，只有每次列表布局都重扫一遍才接得住。
    if (@available(iOS 26.0, *)) {
        UIViewController *sheet = DKShareCommentSheetForView(self);
        if (sheet) DKShareCommentSync(sheet);
    }
}

- (void)prepareForReuse {
    %orig;
    if (!DKShareEnabled()) DKShareRestoreCardCell(self);
}

%end

%hook UIVisualEffectView

- (void)setEffect:(UIVisualEffect *)effect {
    if (DKShareEnabled() && objc_getAssociatedObject(self, &kOverlayTakenKey) && effect) {
        %orig(nil);
        return;
    }
    %orig;
}

// 单选 ↔ 多选切换只换发送按钮、不改覆盖层高度，面板那层布局回调不一定跑，
// 由被接管的覆盖层自己补一次。判据先看关联对象，未接管的 effect view 直接返回。
// 分享评论面板还要顺带重扫一次白垫——它和覆盖层不是同时到位的。
- (void)layoutSubviews {
    %orig;
    if (!objc_getAssociatedObject(self, &kOverlayTakenKey) || !DKShareEnabled()) return;
    if (@available(iOS 26.0, *)) {
        UIViewController *sheet = DKShareCommentSheetForView(self);
        if (sheet) DKShareCommentSync(sheet);
        else DKShareApplySendButtons(self, DKShareControllerForView(self));
    }
}

%end

%hook UIView

- (void)setBackgroundColor:(UIColor *)color {
    if (DKShareEnabled() && DKShareColorOpaque(color)
        && (objc_getAssociatedObject(self, &kOverlayColorKey)
            || objc_getAssociatedObject(self, &kButtonColorKey)
            || objc_getAssociatedObject(self, &kToolbarColorKey)
            || objc_getAssociatedObject(self, &kPlateColorKey))) {
        %orig(UIColor.clearColor);
        return;
    }
    %orig;
}

%end

%end

#pragma mark - 设置

%ctor {
    gGlassCarriers = [NSHashTable weakObjectsHashTable];
    gContainers = [NSHashTable weakObjectsHashTable];
    gCells = [NSHashTable weakObjectsHashTable];
    gCommentSheets = [NSHashTable weakObjectsHashTable];
    gCardCells = [NSHashTable weakObjectsHashTable];
    gSendButtons = [NSHashTable weakObjectsHashTable];

    DKSettingsRegister(DKKeySharePanelGlass, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeGlassChoice(DKKeySharePanelGlass, DKKeySharePanelGlassClear, @"分享面板液态玻璃", ^{
            void (^refresh)(void) = ^{
                if (@available(iOS 26.0, *)) {
                    UIUserInterfaceStyle style = gGlassStyle;
                    if (style == UIUserInterfaceStyleUnspecified) {
                        style = UIScreen.mainScreen.traitCollection.userInterfaceStyle;
                    }
                    DKShareApplyStyle(style, YES);
                    DKShareRefreshVisible();
                }
            };
            if (NSThread.isMainThread) refresh();
            else dispatch_async(dispatch_get_main_queue(), refresh);
        });
        return DKSettingsWithInfo(item,
            @"分享面板、分享评论面板与分享成功提示的材质：关闭时保持抖音原生样式；模糊玻璃使用系统 Regular；清透玻璃显示更多背后视频细节。");
    });

    if (DKGlassOSAvailable()) {
        %init(DKSharePanelGlassHooks);
    }
}
