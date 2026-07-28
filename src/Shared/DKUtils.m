//
//  DKUtils.m
//  作为普通 .m 编译一次、被各功能文件链接复用。
//

#import "DKUtils.h"
#import "DKKeys.h"
#import "DouyinHeaders.h"
#import <objc/message.h>
#import <objc/runtime.h>

BOOL DKPrefBool(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

#pragma mark - 详情页作用域

static NSString *DKStringBySelector(id object, SEL selector) {
    if (![object respondsToSelector:selector]) return nil;
    id value = ((id (*)(id, SEL))objc_msgSend)(object, selector);
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static BOOL DKIsSearchReferString(NSString *referString) {
    if (referString.length == 0) return NO;

    static NSSet<NSString *> *referStrings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        referStrings = [NSSet setWithArray:@[
            @"general_search",
            @"search_result",
            @"search_ecommerce",
            @"general_search_scan",
        ]];
    });
    return [referStrings containsObject:referString];
}

// AWESearchViewController 属于按需 dlopen 的 AWESearchFramework，启动早期取不到；
// 只在取到时缓存，避免把 nil 永久记下来。
static Class DKSearchViewControllerClass(void) {
    static Class cls;
    if (!cls) cls = NSClassFromString(@"AWESearchViewController");
    return cls;
}

// referString 尚未传递到详情页控制器时，以紧邻的搜索页导航来源兜底。
static BOOL DKDetailComesFromSearch(UIViewController *detail) {
    Class searchCls = DKSearchViewControllerClass();
    NSArray<UIViewController *> *stack = detail.navigationController.viewControllers;
    NSUInteger index = [stack indexOfObjectIdenticalTo:detail];
    if (!searchCls || index == NSNotFound || index == 0) return NO;
    return [stack[index - 1] isKindOfClass:searchCls];
}

// 页面归属是「页面」的属性，不能取决于从哪个视图开始解析：Merge 自带 referString 一查即中，
// 底栏这类分支的 responder 链上没有它。故解析成功后记在详情页控制器上供其余入口复用。
static char kDKDetailPageKey;

static DKDetailPage DKResolveDetailPage(UIViewController *detail, BOOL sawSearchRefer) {
    static Class imDetailCls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        imDetailCls = NSClassFromString(@"AWEAwemeIMDetailTableViewController");
    });
    if (imDetailCls && [detail isKindOfClass:imDetailCls]) return DKDetailPageChat;

    NSNumber *memo = objc_getAssociatedObject(detail, &kDKDetailPageKey);
    if (memo) return (DKDetailPage)memo.unsignedIntegerValue;

    BOOL fromSearch = sawSearchRefer
        || DKIsSearchReferString(DKStringBySelector(detail, @selector(referString)))
        || DKIsSearchReferString(DKStringBySelector(detail, @selector(realReferString)))
        || DKDetailComesFromSearch(detail);
    // 判不出来不记忆，留给之后带 referString 的入口再定；否则会把 None 钉死。
    if (!fromSearch) return DKDetailPageNone;

    objc_setAssociatedObject(detail, &kDKDetailPageKey, @(DKDetailPageSearch),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return DKDetailPageSearch;
}

DKDetailPage DKDetailPageForResponder(UIResponder *responder) {
    static Class detailCls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        detailCls = NSClassFromString(@"AWEAwemeDetailTableViewController");
    });
    if (!detailCls) return DKDetailPageNone;

    // 途中的 Merge / HUD 控制器先于详情页拿到 referString，作为判定的优先来源。
    BOOL sawSearchRefer = NO;
    for (NSUInteger i = 0; responder && i < 40; i++) {
        if ([responder isKindOfClass:[UIWindow class]]) break;

        if ([responder isKindOfClass:detailCls]) {
            return DKResolveDetailPage((UIViewController *)responder, sawSearchRefer);
        }
        if (!sawSearchRefer && [responder isKindOfClass:[UIViewController class]]) {
            sawSearchRefer = DKIsSearchReferString(DKStringBySelector(responder, @selector(referString)));
        }
        responder = responder.nextResponder;
    }
    return DKDetailPageNone;
}

BOOL DKDetailPageFullscreenOn(DKDetailPage page) {
    switch (page) {
        case DKDetailPageChat:   return DKPrefBool(DKKeyChatVideoFullscreen);
        case DKDetailPageSearch: return DKPrefBool(DKKeySearchVideoFullscreen);
        case DKDetailPageNone:   return NO;
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
