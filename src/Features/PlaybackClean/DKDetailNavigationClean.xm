// 作品详情顶部返回与搜索的三档显隐；保留导航布局和原生评论开合行为。

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"
#import <objc/runtime.h>

static NSHashTable<UIView *> *gDKDetailNavigationViews;
static char kDKDetailNavigationAppliedKey;
static char kDKDetailNavigationDisabledKey;

static BOOL DKDetailIsKind(id object, NSString *name) {
    Class cls = NSClassFromString(name);
    return cls && [object isKindOfClass:cls];
}

// 直接读取元素引用，不调用可能创建视图的 getter。
static NSString *DKDetailNavigationRowKey(UIView *row) {
    Ivar ivar = class_getInstanceVariable(row.class, "_element");
    id element = ivar ? object_getIvar(row, ivar) : nil;
    if (DKDetailIsKind(element, @"AWEAwemeDetailNaviBarBaseReturnElement")) return DKKeyDetailReturnMode;
    if (DKDetailIsKind(element, @"AWEAwemeDetailNaviBarBaseSearchElement")) return DKKeyDetailSearchMode;
    return nil;
}

static BOOL DKDetailHasDetailParent(UIViewController *controller) {
    for (UIViewController *parent = controller.parentViewController; parent; parent = parent.parentViewController) {
        if (DKDetailIsKind(parent, @"AWEAwemeDetailTableViewController")) return YES;
    }
    return NO;
}

static NSString *DKDetailNavigationKey(UIView *view) {
    if (DKDetailIsKind(view, @"AWEBaseElementView")) return DKDetailNavigationRowKey(view);
    if (!DKDetailIsKind(view, @"AWESearchEntryHalfScreenElement")) return nil;
    for (UIResponder *responder = view.nextResponder; responder; responder = responder.nextResponder) {
        if (DKDetailIsKind(responder, @"AWECommentContainerViewController")) {
            return DKDetailHasDetailParent((UIViewController *)responder) ? DKKeyDetailSearchMode : nil;
        }
    }
    return nil;
}

static void DKDetailNavigationApply(UIView *view) {
    NSString *key = DKDetailNavigationKey(view);
    BOOL applied = objc_getAssociatedObject(view, &kDKDetailNavigationAppliedKey) != nil;
    if (!key && !applied) return;
    if (key) {
        if (!gDKDetailNavigationViews) gDKDetailNavigationViews = [NSHashTable weakObjectsHashTable];
        [gDKDetailNavigationViews addObject:view];
    }
    DKDisplayMode mode = key ? DKPrefDisplayMode(key) : DKDisplayModeShow;
    if (mode != DKDisplayModeShow || applied) {
        DKAdjustFade(view, mode == DKDisplayModeShow ? 1.0 : 0.0, view.bounds.size);
        objc_setAssociatedObject(view, &kDKDetailNavigationAppliedKey,
                                 mode == DKDisplayModeShow ? nil : @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL disabled = objc_getAssociatedObject(view, &kDKDetailNavigationDisabledKey) != nil;
    if (mode == DKDisplayModeRemove) {
        if (view.userInteractionEnabled) {
            view.userInteractionEnabled = NO;
            objc_setAssociatedObject(view, &kDKDetailNavigationDisabledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } else if (disabled) {
        view.userInteractionEnabled = YES;
        objc_setAssociatedObject(view, &kDKDetailNavigationDisabledKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void DKDetailNavigationRefresh(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKDetailNavigationRefresh(); });
        return;
    }
    for (UIView *view in gDKDetailNavigationViews.allObjects) DKDetailNavigationApply(view);
}

%hook AWEBaseElementView

- (void)layoutSubviews {
    %orig;
    DKDetailNavigationApply(self);
}

- (void)didMoveToWindow {
    %orig;
    DKDetailNavigationApply(self);
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    NSString *key = DKDetailNavigationRowKey(self);
    if (key && DKPrefDisplayMode(key) == DKDisplayModeRemove) return nil;
    return %orig;
}

%end

%hook AWECommentContainerViewController

// 半屏搜索类按需加载；在已知的评论容器布局中识别其直接子视图。
- (void)viewDidLayoutSubviews {
    %orig;
    for (UIView *view in self.view.subviews) {
        if (DKDetailIsKind(view, @"AWESearchEntryHalfScreenElement")) DKDetailNavigationApply(view);
    }
}

%end

%ctor {
    %init;
    NSArray *modes = @[ @"显示", @"隐藏", @"移除" ];
    DKSettingsRegister(DKKeyDetailReturnMode, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeChoice(DKKeyDetailReturnMode, @"返回按钮", modes);
        DKSettingsOnChange(item, ^{ DKDetailNavigationRefresh(); });
        return DKSettingsWithInfo(item,
            @"作品详情页左上角的返回按钮。显示：保持抖音原生行为，打开评论区时自然隐藏；隐藏：不显示，原位置仍可点击返回；移除：不显示、不可点击，保留其他控件的位置。");
    });
    DKSettingsRegister(DKKeyDetailSearchMode, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeChoice(DKKeyDetailSearchMode, @"搜索入口", modes);
        DKSettingsOnChange(item, ^{ DKDetailNavigationRefresh(); });
        return DKSettingsWithInfo(item,
            @"统一管理用户主页、喜欢列表、搜索结果和聊天分享等作品详情顶部的搜索栏或搜索图标，以及打开评论区后的搜索图标。视频与图文共用设置。隐藏：不显示，原位置仍可点击搜索；移除：不显示、不可点击，保留其他控件的位置。");
    });
}
