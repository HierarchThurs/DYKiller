//
//  DKUtils.m
//  作为普通 .m 编译一次、被各功能文件链接复用。
//

#import "DKUtils.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DouyinHeaders.h"

#import <objc/runtime.h>

BOOL DKPrefBool(NSString *key) {
    if (DKGlassIsGatedKey(key) && !DKGlassOSAvailable()) return NO;
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

NSInteger DKPrefInteger(NSString *key) {
    if (DKGlassIsGatedKey(key) && !DKGlassOSAvailable()) return 0;
    return [[NSUserDefaults standardUserDefaults] integerForKey:key];
}

BOOL DKAudioSamplingWanted(void) {
    return DKPrefBool(DKKeyDebugInspectorEnabled) || DKPrefInteger(DKKeyAudioVizPosition) != 0;
}

#pragma mark - 控制器查找

static UIViewController *DKSearchChildController(UIViewController *controller, NSString *className, NSUInteger depth) {
    if (!controller || depth > 12) return nil;
    for (UIViewController *child in controller.childViewControllers) {
        if ([NSStringFromClass(child.class) isEqualToString:className]) return child;
        UIViewController *match = DKSearchChildController(child, className, depth + 1);
        if (match) return match;
    }
    return nil;
}

UIViewController *DKChildControllerNamed(UIViewController *controller, NSString *className) {
    return DKSearchChildController(controller, className, 0);
}

#pragma mark - 颜色

BOOL DKColorIsOpaqueBlack(UIColor *color) {
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

#pragma mark - 液态玻璃染色

// 深色档的黑色染色强度：实测评论面板亮度比 0.90、底栏 platter 中位亮度 136.6 → 99.8，
// 两处都明确是深色玻璃且背后细节完整。
static const CGFloat kDKGlassDarkTintAlpha = 0.30;

UIColor *DKGlassTintForStyle(UIUserInterfaceStyle style) {
    if (style != UIUserInterfaceStyleDark) return nil;
    return [UIColor colorWithWhite:0.0 alpha:kDKGlassDarkTintAlpha];
}

#pragma mark - 玻璃上的文字

// 黑系判据的两个阈值：抖音标题色 #161823 明度 0.137、饱和度 0.37；
// 同处的蓝色 #04498D 明度 0.553、粉色 #FE2C55 明度 0.996，按明度就能分开。
static const CGFloat kDKGlassInkBrightness = 0.35;
static const CGFloat kDKGlassInkSaturation = 0.50;

// 遍历深度：通知横幅最深处是白槽 → 栈 → CommonView → 容器 → 栈 → 栈 → 标题项 → 文字，
// 展开态还会更深，留出余量。
static const NSUInteger kDKGlassInkDepth = 10;

static char kDKInkOriginalKey;
static char kDKInkAppliedKey;

BOOL DKGlassColorIsInk(UIColor *color) {
    if (!color) return NO;

    CGFloat hue = 0.0;
    CGFloat saturation = 0.0;
    CGFloat brightness = 0.0;
    CGFloat alpha = 0.0;
    if (![color getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha]) {
        CGFloat white = 0.0;
        if (![color getWhite:&white alpha:&alpha]) return NO;
        saturation = 0.0;
        brightness = white;
    }
    return alpha >= 0.5
        && brightness <= kDKGlassInkBrightness
        && saturation <= kDKGlassInkSaturation;
}

// 先按目标外观解析再判定：宿主那个色是静态还是动态都能得到正确结果。
UIColor *DKGlassInkTextColor(UIColor *original, BOOL clear, UIUserInterfaceStyle style) {
    if (!original) return nil;
    UITraitCollection *traits = [UITraitCollection traitCollectionWithUserInterfaceStyle:style];
    UIColor *resolved = [original resolvedColorWithTraitCollection:traits];
    if (!DKGlassColorIsInk(resolved)) return original;
    if (!clear && style != UIUserInterfaceStyleDark) return original;
    return [UIColor colorWithWhite:1.0 alpha:CGColorGetAlpha(resolved.CGColor)];
}

static void DKGlassWalkLabels(UIView *view, NSUInteger depth, void (^block)(UILabel *label)) {
    if (!view || depth > kDKGlassInkDepth) return;
    if ([view isKindOfClass:[UIControl class]]) return;
    if ([view isKindOfClass:[UILabel class]]) block((UILabel *)view);
    for (UIView *child in view.subviews) DKGlassWalkLabels(child, depth + 1, block);
}

void DKGlassApplyInkText(UIView *root, BOOL clear, UIUserInterfaceStyle style) {
    DKGlassWalkLabels(root, 0, ^(UILabel *label) {
        UIColor *current = label.textColor;
        UIColor *original = objc_getAssociatedObject(label, &kDKInkOriginalKey);
        UIColor *applied = objc_getAssociatedObject(label, &kDKInkAppliedKey);
        // 当前色既不是原色也不是我们写进去的，说明宿主改写过，重新记原色。
        if (!original || (![current isEqual:original] && ![current isEqual:applied])) {
            original = current;
            objc_setAssociatedObject(label, &kDKInkOriginalKey,
                                     original, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        UIColor *want = DKGlassInkTextColor(original, clear, style);
        if (want && ![current isEqual:want]) label.textColor = want;
        objc_setAssociatedObject(label, &kDKInkAppliedKey, want, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

void DKGlassRestoreInkText(UIView *root) {
    DKGlassWalkLabels(root, 0, ^(UILabel *label) {
        UIColor *original = objc_getAssociatedObject(label, &kDKInkOriginalKey);
        if (!original) return;
        label.textColor = original;
        objc_setAssociatedObject(label, &kDKInkOriginalKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(label, &kDKInkAppliedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

#pragma mark - Cell 几何

UIView *DKCellContentView(UIView *view) {
    static Class contentCls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ contentCls = NSClassFromString(@"UITableViewCellContentView"); });
    if (!contentCls) return nil;

    for (NSUInteger i = 0; view && i < 12; i++) {
        if ([view isKindOfClass:contentCls]) return view;
        view = view.superview;
    }
    return nil;
}

CGFloat DKFullCellHeight(UIView *view) {
    UIView *contentView = DKCellContentView(view.superview);
    return contentView ? CGRectGetHeight(contentView.bounds) : 0.0;
}
