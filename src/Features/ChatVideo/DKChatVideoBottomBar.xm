//
//  DKChatVideoBottomBar.xm
//  功能：作品详情页固定底栏移除，以及聊天页全屏时的快捷回复栏透明化。
//
//  固定底栏移除通过抖音原生状态接口实现，不改底栏子视图和页面布局。
//

#import "DouyinHeaders.h"
#import "DKUtils.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import <objc/runtime.h>

static char kBarOrigBGKey;   // 底栏原始背景色缓存，便于关闭时还原
static char kBarOrigOpaqueKey;

static BOOL DKShouldHideDetailBottomBar(void) {
    return DKPrefBool(DKKeyDetailHideBottomBar);
}

static AWEAwemeIMDetailTableViewController *DKFindIMDetailController(UIViewController *vc) {
    static Class imDetailCls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        imDetailCls = NSClassFromString(@"AWEAwemeIMDetailTableViewController");
    });
    for (int i = 0; vc && i < 10; i++) {
        if (imDetailCls && [vc isKindOfClass:imDetailCls]) return (AWEAwemeIMDetailTableViewController *)vc;
        vc = vc.parentViewController;
    }
    return nil;
}

static void DKApplyBarBackground(UIView *view, BOOL clear) {
    if (!view) return;
    id orig = objc_getAssociatedObject(view, &kBarOrigBGKey);

    if (clear) {
        if (!orig) {
            objc_setAssociatedObject(view, &kBarOrigBGKey,
                                     view.backgroundColor ?: (id)[NSNull null],
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(view, &kBarOrigOpaqueKey,
                                     @(view.opaque),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        view.backgroundColor = [UIColor clearColor];
        view.opaque = NO;
        return;
    }

    if (orig) {
        view.backgroundColor = (orig == [NSNull null]) ? nil : (UIColor *)orig;
        NSNumber *opaque = objc_getAssociatedObject(view, &kBarOrigOpaqueKey);
        if (opaque) view.opaque = opaque.boolValue;
        objc_setAssociatedObject(view, &kBarOrigBGKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &kBarOrigOpaqueKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%hook AWEAwemeDetailTableViewController

- (BOOL)canShowFixedBottomBar {
    if (DKShouldHideDetailBottomBar()) return NO;
    return %orig;
}

- (void)setBottomBarHidden:(BOOL)hidden {
    if (DKShouldHideDetailBottomBar()) hidden = YES;
    %orig(hidden);
}

%end

%hook AWEAwemeIMDetailTableViewController

- (void)setBottomBarHidden:(BOOL)hidden {
    if (DKShouldHideDetailBottomBar()) hidden = YES;
    %orig(hidden);
}

%end

%hook AWEIMFeedVideoQuickReplayInputViewController

- (void)viewDidLayoutSubviews {
    %orig;

    BOOL clear = DKPrefBool(DKKeyChatVideoFullscreen) || DKShouldHideDetailBottomBar();
    DKApplyBarBackground(self.view, clear);

    if (DKShouldHideDetailBottomBar()) {
        AWEAwemeIMDetailTableViewController *detail = DKFindIMDetailController(self);
        if (detail) [detail setBottomBarHidden:YES];
    }
}

%end

#pragma mark - 设置项注册

%ctor {
    DKSettingsRegisterItem(@"播放体验", ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyDetailHideBottomBar, @"移除作品详情页底栏", @"隐藏详情页底部快捷评论栏并禁止点击");
    });
}
