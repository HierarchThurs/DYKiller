//
//  DKChatVideoBottomBar.xm
//  功能：聊天页「分享视频」详情页 —— 底部快捷回复栏的透明化 / 移除。
//
//  行为矩阵（与全屏开关联动）：
//   底栏背景透明   = (全屏 || 移除底栏)
//   底栏移除       = 接管抖音自己的固定底栏状态，不改子视图 hidden。
//

#import "DouyinHeaders.h"
#import "DKUtils.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import <objc/runtime.h>

static char kBarOrigBGKey;   // 底栏原始背景色缓存，便于关闭时还原
static char kBarOrigOpaqueKey;

static BOOL DKShouldHideChatBottomBar(void) {
    return DKPrefBool(DKKeyChatVideoHideBottomBar);
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
    if (DKShouldHideChatBottomBar() && DKVCInIMDetail(self)) return NO;
    return %orig;
}

- (void)setBottomBarHidden:(BOOL)hidden {
    if (DKShouldHideChatBottomBar() && DKVCInIMDetail(self)) hidden = YES;
    %orig(hidden);
}

%end

%hook AWEAwemeIMDetailTableViewController

- (void)setBottomBarHidden:(BOOL)hidden {
    if (DKShouldHideChatBottomBar()) hidden = YES;
    %orig(hidden);
}

%end

%hook AWEIMFeedVideoQuickReplayInputViewController

- (void)viewDidLayoutSubviews {
    %orig;

    BOOL clear = DKPrefBool(DKKeyChatVideoFullscreen) || DKShouldHideChatBottomBar();
    DKApplyBarBackground(self.view, clear);

    if (DKShouldHideChatBottomBar()) {
        AWEAwemeIMDetailTableViewController *detail = DKFindIMDetailController(self);
        if (detail) [detail setBottomBarHidden:YES];
    }
}

%end

#pragma mark - 设置项注册

%ctor {
    DKSettingsRegisterItem(@"聊天页", ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyChatVideoHideBottomBar, @"移除聊天页视频底栏", @"隐藏底部快捷回复栏并禁止点击");
    });
}
