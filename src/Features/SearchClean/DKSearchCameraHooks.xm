// 搜索框相机入口：隐藏保留命中，移除交由原生显示许可收拢布局。
#import "DKSearchClean.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"
#import <objc/runtime.h>

@interface AWESearchViewController : UIViewController
- (UIButton *)scanButton;
@end

@interface AWESearchTopBarScanElement : NSObject
- (UIButton *)scanButton;
@end

// 布局回调只取已创建的按钮，避免通过 getter 触发懒加载。
static UIView *DKSearchExistingCamera(id owner) {
    Ivar ivar = class_getInstanceVariable([owner class], "_scanButton");
    id view = ivar ? object_getIvar(owner, ivar) : nil;
    return [view isKindOfClass:UIView.class] ? view : nil;
}

static void DKSearchApplyCamera(UIView *view) {
    DKAdjustFade(view, DKPrefDisplayMode(DKKeySearchCameraMode) == DKDisplayModeHide ? 0.0 : 1.0,
                 view.bounds.size);
}

%group DKSearchCameraPermission
%hook AWESearchRootStateContext
- (BOOL)allowShowScanButton {
    if (DKPrefDisplayMode(DKKeySearchCameraMode) == DKDisplayModeRemove) return NO;
    return %orig;
}
%end
%end

%group DKSearchCameraLegacy
%hook AWESearchViewController
- (UIButton *)scanButton {
    UIButton *button = %orig;
    DKSearchApplyCamera(button);
    return button;
}
- (void)viewDidLayoutSubviews {
    %orig;
    DKSearchApplyCamera(DKSearchExistingCamera(self));
}
%end
%end

%group DKSearchCameraTopBar
%hook AWESearchTopBarScanElement
- (UIButton *)scanButton {
    UIButton *button = %orig;
    DKSearchApplyCamera(button);
    return button;
}
- (void)hostViewDidLayoutSubviews {
    %orig;
    DKSearchApplyCamera(DKSearchExistingCamera(self));
}
%end
%end

void DKSearchInstallCameraHooks(void) {
    static BOOL permissionInstalled, legacyInstalled, topBarInstalled;
    Class context = NSClassFromString(@"AWESearchRootStateContext");
    if (!permissionInstalled && class_getInstanceMethod(context, @selector(allowShowScanButton))) {
        %init(DKSearchCameraPermission);
        permissionInstalled = YES;
    }
    Class legacy = NSClassFromString(@"AWESearchViewController");
    if (!legacyInstalled && class_getInstanceMethod(legacy, @selector(scanButton)) &&
        class_getInstanceMethod(legacy, @selector(viewDidLayoutSubviews))) {
        %init(DKSearchCameraLegacy);
        legacyInstalled = YES;
    }
    Class topBar = NSClassFromString(@"AWESearchTopBarScanElement");
    if (!topBarInstalled && class_getInstanceMethod(topBar, @selector(scanButton)) &&
        class_getInstanceMethod(topBar, @selector(hostViewDidLayoutSubviews))) {
        %init(DKSearchCameraTopBar);
        topBarInstalled = YES;
    }
}
