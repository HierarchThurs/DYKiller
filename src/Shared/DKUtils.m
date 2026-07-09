//
//  DKUtils.m
//  作为普通 .m 编译一次、被各功能文件链接复用。
//  用带缓存的 NSClassFromString 获取私有类。
//

#import "DKUtils.h"

BOOL DKPrefBool(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

BOOL DKVCInIMDetail(UIViewController *vc) {
    static Class imDetailCls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ imDetailCls = NSClassFromString(@"AWEAwemeIMDetailTableViewController"); });
    for (int i = 0; vc && i < 10; i++) {
        if (imDetailCls && [vc isKindOfClass:imDetailCls]) return YES;
        vc = vc.parentViewController;
    }
    return NO;
}

BOOL DKViewInIMDetail(UIView *view) {
    UIResponder *r = view.nextResponder;
    for (int i = 0; r && i < 40; i++) {
        if ([r isKindOfClass:[UIViewController class]]) {
            return DKVCInIMDetail((UIViewController *)r);
        }
        r = r.nextResponder;
    }
    return NO;
}

CGFloat DKFullCellHeight(UIView *view) {
    static Class contentCls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ contentCls = NSClassFromString(@"UITableViewCellContentView"); });
    UIView *v = view.superview;
    for (int i = 0; v && i < 12; i++) {
        if (contentCls && [v isKindOfClass:contentCls]) return v.bounds.size.height;
        v = v.superview;
    }
    return 0;
}
