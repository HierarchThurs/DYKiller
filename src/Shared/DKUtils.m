//
//  DKUtils.m
//  作为普通 .m 编译一次、被各功能文件链接复用。
//

#import "DKUtils.h"
#import "DKKeys.h"
#import "DouyinHeaders.h"

BOOL DKPrefBool(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
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
