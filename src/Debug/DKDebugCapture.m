//
//  DKDebugCapture.m
//  DYKiller
//
//  只读地遍历 UIKit/CoreAnimation 安全字段 + 收集本页类，产出 DKDebugExportContext。
//  不递归读任意对象的 ivar 值。
//

#import "DKDebugCapture.h"
#import "DKKeys.h"
#import "DKClassDump.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@implementation DKDebugExportContext
@end

#pragma mark - 小型格式化工具

static NSString *DKStringFromPointer(const void *pointer) {
    return [NSString stringWithFormat:@"%p", pointer];
}

static NSString *DKClassName(id object) {
    return object ? NSStringFromClass([object class]) : @"";
}

static NSString *DKObjectDesc(id object) {
    if (!object) return @"";
    @try {
        return [object description] ?: @"";
    } @catch (__unused NSException *exception) {
        return @"<description threw>";
    }
}

static NSNumber *DKNum(double value) {
    return @(isfinite(value) ? value : 0);
}

static NSString *DKStringFromColor(UIColor *color) {
    if (!color) return @"";
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if ([color getRed:&r green:&g blue:&b alpha:&a]) {
        return [NSString stringWithFormat:@"rgba(%.4f, %.4f, %.4f, %.4f)", r, g, b, a];
    }
    return DKObjectDesc(color);
}

static NSDictionary *DKRectDict(CGRect rect) {
    return @{
        @"x": DKNum(rect.origin.x),
        @"y": DKNum(rect.origin.y),
        @"width": DKNum(rect.size.width),
        @"height": DKNum(rect.size.height),
        @"string": NSStringFromCGRect(rect)
    };
}

static NSDictionary *DKPointDict(CGPoint point) {
    return @{ @"x": DKNum(point.x), @"y": DKNum(point.y), @"string": NSStringFromCGPoint(point) };
}

static NSDictionary *DKSizeDict(CGSize size) {
    return @{ @"width": DKNum(size.width), @"height": DKNum(size.height), @"string": NSStringFromCGSize(size) };
}

static NSDictionary *DKAffineDict(CGAffineTransform t) {
    return @{
        @"a": DKNum(t.a), @"b": DKNum(t.b), @"c": DKNum(t.c),
        @"d": DKNum(t.d), @"tx": DKNum(t.tx), @"ty": DKNum(t.ty)
    };
}

static NSDictionary *DKTransform3DDict(CATransform3D t) {
    return @{
        @"m11": DKNum(t.m11), @"m12": DKNum(t.m12), @"m13": DKNum(t.m13), @"m14": DKNum(t.m14),
        @"m21": DKNum(t.m21), @"m22": DKNum(t.m22), @"m23": DKNum(t.m23), @"m24": DKNum(t.m24),
        @"m31": DKNum(t.m31), @"m32": DKNum(t.m32), @"m33": DKNum(t.m33), @"m34": DKNum(t.m34),
        @"m41": DKNum(t.m41), @"m42": DKNum(t.m42), @"m43": DKNum(t.m43), @"m44": DKNum(t.m44)
    };
}

#pragma mark - 窗口与控制器工具

static BOOL DKIsDebugWindow(UIWindow *window) {
    NSString *cls = DKClassName(window);
    return [cls hasPrefix:@"DKDebug"] || [cls hasPrefix:@"FLEX"];
}

static NSArray<UIWindow *> *DKActiveWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (!window || DKIsDebugWindow(window)) continue;
                if (window.hidden || window.alpha <= 0.01) continue;
                [windows addObject:window];
            }
        }
    }
    if (windows.count == 0) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            if (!window || DKIsDebugWindow(window)) continue;
            if (window.hidden || window.alpha <= 0.01) continue;
            [windows addObject:window];
        }
#pragma clang diagnostic pop
    }
    return windows;
}

UIWindow *DKDebugTargetWindow(void) {
    NSArray<UIWindow *> *windows = DKActiveWindows();
    for (UIWindow *window in windows) if (window.isKeyWindow) return window;
    return windows.firstObject;
}

static UIViewController *DKViewControllerForView(UIView *view) {
    UIResponder *responder = view;
    for (NSUInteger i = 0; responder && i < 80; i++) {
        responder = responder.nextResponder;
        if ([responder isKindOfClass:[UIViewController class]]) return (UIViewController *)responder;
    }
    return nil;
}

static UIViewController *DKTopViewControllerFrom(UIViewController *vc) {
    for (NSUInteger i = 0; vc && i < 80; i++) {
        if (vc.presentedViewController) {
            vc = vc.presentedViewController;
        } else if ([vc isKindOfClass:[UINavigationController class]]) {
            UIViewController *visible = ((UINavigationController *)vc).visibleViewController;
            if (!visible || visible == vc) break;
            vc = visible;
        } else if ([vc isKindOfClass:[UITabBarController class]]) {
            UIViewController *selected = ((UITabBarController *)vc).selectedViewController;
            if (!selected || selected == vc) break;
            vc = selected;
        } else {
            break;
        }
    }
    return vc;
}

UIViewController *DKDebugTopPresenter(UIWindow *window) {
    return DKTopViewControllerFrom(window.rootViewController);
}

#pragma mark - 页面快照

static NSDictionary *DKLayerInfo(CALayer *layer) {
    if (!layer) return @{};
    return @{
        @"class": DKClassName(layer),
        @"address": DKStringFromPointer((__bridge const void *)layer),
        @"bounds": DKRectDict(layer.bounds),
        @"position": DKPointDict(layer.position),
        @"anchorPoint": DKPointDict(layer.anchorPoint),
        @"zPosition": DKNum(layer.zPosition),
        @"opacity": DKNum(layer.opacity),
        @"hidden": @(layer.hidden),
        @"masksToBounds": @(layer.masksToBounds),
        @"cornerRadius": DKNum(layer.cornerRadius),
        @"sublayerCount": @(layer.sublayers.count),
        @"transform": DKTransform3DDict(layer.transform),
        @"mask": layer.mask ? @{
            @"class": DKClassName(layer.mask),
            @"address": DKStringFromPointer((__bridge const void *)layer.mask),
            @"bounds": DKRectDict(layer.mask.bounds)
        } : @{}
    };
}

static NSMutableDictionary *DKBaseViewInfo(UIView *view, NSUInteger depth) {
    UIViewController *nearestVC = DKViewControllerForView(view);
    NSMutableDictionary *info = [@{
        @"class": DKClassName(view),
        @"address": DKStringFromPointer((__bridge const void *)view),
        @"depth": @(depth),
        @"frame": DKRectDict(view.frame),
        @"bounds": DKRectDict(view.bounds),
        @"center": DKPointDict(view.center),
        @"alpha": DKNum(view.alpha),
        @"hidden": @(view.hidden),
        @"opaque": @(view.opaque),
        @"clipsToBounds": @(view.clipsToBounds),
        @"userInteractionEnabled": @(view.userInteractionEnabled),
        @"multipleTouchEnabled": @(view.multipleTouchEnabled),
        @"contentMode": @(view.contentMode),
        @"tag": @(view.tag),
        @"autoresizingMask": @(view.autoresizingMask),
        @"autoresizesSubviews": @(view.autoresizesSubviews),
        @"transform": DKAffineDict(view.transform),
        @"backgroundColor": DKStringFromColor(view.backgroundColor),
        @"tintColor": DKStringFromColor(view.tintColor),
        @"accessibilityIdentifier": view.accessibilityIdentifier ?: @"",
        @"accessibilityLabel": view.accessibilityLabel ?: @"",
        @"nearestViewController": nearestVC ? @{
            @"class": DKClassName(nearestVC),
            @"address": DKStringFromPointer((__bridge const void *)nearestVC)
        } : @{},
        @"layer": DKLayerInfo(view.layer),
        @"subviewCount": @(view.subviews.count)
    } mutableCopy];

    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        info[@"label"] = @{
            @"text": label.text ?: @"",
            @"attributedText": label.attributedText.string ?: @"",
            @"font": DKObjectDesc(label.font),
            @"textColor": DKStringFromColor(label.textColor),
            @"numberOfLines": @(label.numberOfLines),
            @"textAlignment": @(label.textAlignment)
        };
    }
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *button = (UIButton *)view;
        info[@"button"] = @{
            @"currentTitle": [button titleForState:UIControlStateNormal] ?: (button.currentTitle ?: @""),
            @"currentAttributedTitle": button.currentAttributedTitle.string ?: @"",
            @"enabled": @(button.enabled),
            @"selected": @(button.selected),
            @"highlighted": @(button.highlighted)
        };
    }
    if ([view isKindOfClass:[UIImageView class]]) {
        UIImageView *imageView = (UIImageView *)view;
        info[@"imageView"] = @{
            @"imageSize": imageView.image ? DKSizeDict(imageView.image.size) : @{},
            @"highlighted": @(imageView.highlighted)
        };
    }
    if ([view isKindOfClass:[UIControl class]]) {
        UIControl *control = (UIControl *)view;
        info[@"control"] = @{
            @"enabled": @(control.enabled),
            @"selected": @(control.selected),
            @"highlighted": @(control.highlighted),
            @"state": @(control.state)
        };
    }
    if ([view isKindOfClass:[UIScrollView class]]) {
        UIScrollView *scroll = (UIScrollView *)view;
        info[@"scrollView"] = @{
            @"contentOffset": DKPointDict(scroll.contentOffset),
            @"contentSize": DKSizeDict(scroll.contentSize),
            @"contentInset": NSStringFromUIEdgeInsets(scroll.contentInset),
            @"adjustedContentInset": NSStringFromUIEdgeInsets(scroll.adjustedContentInset),
            @"zoomScale": DKNum(scroll.zoomScale),
            @"minimumZoomScale": DKNum(scroll.minimumZoomScale),
            @"maximumZoomScale": DKNum(scroll.maximumZoomScale),
            @"pagingEnabled": @(scroll.pagingEnabled),
            @"scrollEnabled": @(scroll.scrollEnabled),
            @"dragging": @(scroll.dragging),
            @"tracking": @(scroll.tracking),
            @"decelerating": @(scroll.decelerating)
        };
    }
    if ([view isKindOfClass:[UIVisualEffectView class]]) {
        info[@"visualEffectView"] = @{ @"effect": DKObjectDesc(((UIVisualEffectView *)view).effect) };
    }
    return info;
}

static NSDictionary *DKViewTreeJSON(UIView *view, NSUInteger depth, NSMutableArray *layers) {
    NSMutableDictionary *info = DKBaseViewInfo(view, depth);
    [layers addObject:@{
        @"viewClass": info[@"class"],
        @"viewAddress": info[@"address"],
        @"nearestViewController": info[@"nearestViewController"],
        @"layer": info[@"layer"]
    }];

    NSMutableArray *children = [NSMutableArray arrayWithCapacity:view.subviews.count];
    for (UIView *subview in view.subviews) {
        [children addObject:DKViewTreeJSON(subview, depth + 1, layers)];
    }
    info[@"children"] = children;
    return info;
}

static void DKAppendViewTreeText(UIView *view, NSUInteger depth, NSMutableString *out) {
    NSMutableString *indent = [NSMutableString string];
    for (NSUInteger i = 0; i < depth; i++) [indent appendString:@"  "];
    UIViewController *vc = DKViewControllerForView(view);
    [out appendFormat:@"%@%@ %@ frame=%@ bounds=%@ vc=%@ %@ hidden=%d alpha=%.3f clips=%d user=%d layer=%@\n",
     indent,
     DKClassName(view),
     DKStringFromPointer((__bridge const void *)view),
     NSStringFromCGRect(view.frame),
     NSStringFromCGRect(view.bounds),
     vc ? DKClassName(vc) : @"",
     vc ? DKStringFromPointer((__bridge const void *)vc) : @"",
     view.hidden,
     view.alpha,
     view.clipsToBounds,
     view.userInteractionEnabled,
     DKClassName(view.layer)];
    for (UIView *subview in view.subviews) DKAppendViewTreeText(subview, depth + 1, out);
}

static NSDictionary *DKWindowJSON(UIWindow *window) {
    return @{
        @"class": DKClassName(window),
        @"address": DKStringFromPointer((__bridge const void *)window),
        @"frame": DKRectDict(window.frame),
        @"bounds": DKRectDict(window.bounds),
        @"windowLevel": DKNum(window.windowLevel),
        @"hidden": @(window.hidden),
        @"alpha": DKNum(window.alpha),
        @"keyWindow": @(window.isKeyWindow),
        @"rootViewController": window.rootViewController ? @{
            @"class": DKClassName(window.rootViewController),
            @"address": DKStringFromPointer((__bridge const void *)window.rootViewController)
        } : @{}
    };
}

static NSArray *DKAncestorChain(UIView *view) {
    NSMutableArray *chain = [NSMutableArray array];
    UIView *v = view;
    for (NSUInteger depth = 0; v && depth < 120; depth++, v = v.superview) {
        [chain addObject:DKBaseViewInfo(v, depth)];
    }
    return chain;
}

static void DKAppendVCText(UIViewController *vc, NSUInteger depth, NSMutableString *out, NSHashTable *seen) {
    if (!vc || [seen containsObject:vc]) return;
    [seen addObject:vc];
    NSMutableString *indent = [NSMutableString string];
    for (NSUInteger i = 0; i < depth; i++) [indent appendString:@"  "];
    [out appendFormat:@"%@%@ %@ view=%@ %@ frame=%@\n",
     indent,
     DKClassName(vc),
     DKStringFromPointer((__bridge const void *)vc),
     DKClassName(vc.view),
     vc.view ? DKStringFromPointer((__bridge const void *)vc.view) : @"",
     vc.view ? NSStringFromCGRect(vc.view.frame) : @"null"];

    if ([vc isKindOfClass:[UINavigationController class]]) {
        UINavigationController *nav = (UINavigationController *)vc;
        [out appendFormat:@"%@  nav.top=%@ nav.visible=%@\n", indent, DKClassName(nav.topViewController), DKClassName(nav.visibleViewController)];
    }
    if ([vc isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tab = (UITabBarController *)vc;
        [out appendFormat:@"%@  tab.selected=%@\n", indent, DKClassName(tab.selectedViewController)];
    }
    for (UIViewController *child in vc.childViewControllers) DKAppendVCText(child, depth + 1, out, seen);
    if (vc.presentedViewController) {
        [out appendFormat:@"%@  presented:\n", indent];
        DKAppendVCText(vc.presentedViewController, depth + 1, out, seen);
    }
}

static NSData *DKScreenshotPNG(UIWindow *window) {
    if (!window) return NSData.data;
    UIGraphicsBeginImageContextWithOptions(window.bounds.size, NO, 0);
    BOOL drew = [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:NO];
    if (!drew) [window.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image ? UIImagePNGRepresentation(image) : NSData.data;
}

#pragma mark - 页面类收集

// 收集一个类及其整条继承链的类名：跳过运行时生成子类噪声，但继续上溯 → 自动收到真实基类。
static void DKCollectClassAndSupers(Class cls, NSMutableSet<NSString *> *names) {
    for (int i = 0; cls && i < 50; i++) {
        if (!DKClassIsSafe(cls)) break;
        NSString *name = NSStringFromClass(cls);
        if (name.length && !DKClassNameIsRuntimeGenerated(name)) [names addObject:name];
        cls = class_getSuperclass(cls);
    }
}

// 递归收集视图子树里每个 view 及其 layer 的类（含继承链）。
static void DKCollectPageClassesFromView(UIView *view, NSMutableSet<NSString *> *names) {
    if (!view) return;
    DKCollectClassAndSupers(object_getClass(view), names);
    DKCollectClassAndSupers(object_getClass(view.layer), names);
    for (UIView *sub in view.subviews) DKCollectPageClassesFromView(sub, names);
}

// 递归收集 VC 树（child + presented）里每个 VC 及其已加载 view 的类（含继承链）。
static void DKCollectPageClassesFromVC(UIViewController *vc, NSMutableSet<NSString *> *names, NSHashTable *seen) {
    if (!vc || [seen containsObject:vc]) return;
    [seen addObject:vc];
    DKCollectClassAndSupers(object_getClass(vc), names);
    if (vc.isViewLoaded) DKCollectClassAndSupers(object_getClass(vc.view), names);
    for (UIViewController *child in vc.childViewControllers) DKCollectPageClassesFromVC(child, names, seen);
    if (vc.presentedViewController) DKCollectPageClassesFromVC(vc.presentedViewController, names, seen);
}

DKDebugExportContext *DKDebugCaptureContext(UIWindow *targetWindow, CGPoint point, UIView *selectedView) {
    DKDebugExportContext *context = [DKDebugExportContext new];
    NSArray<UIWindow *> *windows = DKActiveWindows();
    NSMutableArray *windowsJSON = [NSMutableArray array];
    NSMutableArray *treeJSON = [NSMutableArray array];
    NSMutableArray *layersJSON = [NSMutableArray array];
    NSMutableString *treeText = [NSMutableString string];
    NSMutableString *vcText = [NSMutableString string];
    NSHashTable *seenVCs = [NSHashTable weakObjectsHashTable];
    NSMutableSet<NSString *> *pageClasses = [NSMutableSet set];
    NSHashTable *seenClassVCs = [NSHashTable weakObjectsHashTable];

    for (UIWindow *window in windows) {
        [windowsJSON addObject:DKWindowJSON(window)];
        [treeJSON addObject:DKViewTreeJSON(window, 0, layersJSON)];
        DKAppendViewTreeText(window, 0, treeText);
        DKCollectPageClassesFromView(window, pageClasses);
        DKCollectPageClassesFromVC(window.rootViewController, pageClasses, seenClassVCs);
        if (window.rootViewController) {
            [vcText appendFormat:@"Window %@ %@\n", DKClassName(window), DKStringFromPointer((__bridge const void *)window)];
            DKAppendVCText(window.rootViewController, 1, vcText, seenVCs);
        }
    }

    UIViewController *nearestVC = DKViewControllerForView(selectedView);
    NSDictionary *selected = @{
        @"tapPointInWindow": DKPointDict(point),
        @"hitView": DKBaseViewInfo(selectedView ?: targetWindow, 0),
        @"nearestViewController": nearestVC ? @{
            @"class": DKClassName(nearestVC),
            @"address": DKStringFromPointer((__bridge const void *)nearestVC)
        } : @{},
        @"ancestorChain": selectedView ? DKAncestorChain(selectedView) : @[]
    };

    NSDictionary *metadata = @{
        @"generatedAt": DKObjectDesc(NSDate.date),
        @"dykillerVersion": DK_VERSION,
        @"bundleIdentifier": NSBundle.mainBundle.bundleIdentifier ?: @"",
        @"bundleName": NSBundle.mainBundle.infoDictionary[@"CFBundleName"] ?: @"",
        @"appVersion": NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"",
        @"buildVersion": NSBundle.mainBundle.infoDictionary[(NSString *)kCFBundleVersionKey] ?: @"",
        @"systemName": UIDevice.currentDevice.systemName ?: @"",
        @"systemVersion": UIDevice.currentDevice.systemVersion ?: @"",
        @"deviceModel": UIDevice.currentDevice.model ?: @"",
        @"screenBounds": DKRectDict(UIScreen.mainScreen.bounds),
        @"tapPointInTargetWindow": DKPointDict(point),
        @"targetWindow": targetWindow ? DKWindowJSON(targetWindow) : @{}
    };

    NSString *summary = [NSString stringWithFormat:
                         @"Hit: %@ %@\nFrame: %@\nBounds: %@\nNearest VC: %@ %@\nWindows: %lu\nSubviews: %lu",
                         DKClassName(selectedView),
                         DKStringFromPointer((__bridge const void *)selectedView),
                         selectedView ? NSStringFromCGRect(selectedView.frame) : @"",
                         selectedView ? NSStringFromCGRect(selectedView.bounds) : @"",
                         nearestVC ? DKClassName(nearestVC) : @"",
                         nearestVC ? DKStringFromPointer((__bridge const void *)nearestVC) : @"",
                         (unsigned long)windows.count,
                         (unsigned long)selectedView.subviews.count];

    context.metadata = metadata;
    context.windowsJSON = windowsJSON;
    context.viewTreeJSON = treeJSON;
    context.viewTreeText = treeText;
    context.selectedViewJSON = selected;
    context.viewControllersText = vcText;
    context.layersJSON = layersJSON;
    context.screenshotPNG = DKScreenshotPNG(targetWindow);
    context.summary = summary;
    context.pageClassNames = pageClasses.allObjects;
    context.sourceView = targetWindow;
    context.presenter = DKDebugTopPresenter(targetWindow);
    return context;
}
