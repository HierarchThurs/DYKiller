//
//  DKTabBarBackdrop.xm
//  功能：视频全屏 —— 底栏背景让位。视频全屏开启、悬浮玻璃底栏关闭时，抖音自绘底栏的背景在所有底栏页面透明，
//  按钮与外观覆盖层保持不透明，悬浮在页面内容上。
//
//  实现：
//   - 背景层直读 ivar（_backgroundView / _awe_blurView / _skinContainerView / _separatorLine），不经 getter：
//     separatorLine 的 getter 会懒加载创建分隔线。遮挡视频的是 blur 层的不透明背景色。
//   - 透明靠挂自有的透明 mask，不改 alpha / hidden；抖音切页时只改 blur 层背景色，不会冲掉它。
//   - 判据只看两个开关：视频全屏开启、玻璃底栏未开启。mask 挂在背景层上，切页时不需要重判。
//   - 触发：底栏 layoutSubviews，以及两个开关改动时的 DKTabBarBackdropSetNeedsUpdate。
//   - 玻璃底栏开启时背景归玻璃底栏管（它写 opacity），本模块摘掉自己的 mask。
//

#import "DKTabBarBackdrop.h"
#import "DKGlassTabBar.h"
#import "DKVideoFullscreen.h"
#import "DKViewAdjust.h"
#import "DouyinHeaders.h"

#import <objc/runtime.h>

static const char *const kDKBackdropIvars[] = {
    "_backgroundView", "_awe_blurView", "_skinContainerView", "_separatorLine",
};
static const NSUInteger kDKBackdropIvarCount = sizeof(kDKBackdropIvars) / sizeof(kDKBackdropIvars[0]);

static __weak AWENormalModeTabBar *gBackdropBar;
static BOOL gBackdropScheduled;

static UIView *DKBackdropView(id object, const char *name) {
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    if (!type || type[0] != '@') return nil;
    id value = object_getIvar(object, ivar);
    return [value isKindOfClass:UIView.class] ? value : nil;
}

static BOOL DKBackdropShouldHide(void) {
    return !DKGlassTabBarActive() && DKVideoFullscreenOn();
}

static void DKBackdropApply(AWENormalModeTabBar *bar) {
    if (!bar) return;
    gBackdropBar = bar;
    CGFloat factor = DKBackdropShouldHide() ? 0.0 : 1.0;
    for (NSUInteger i = 0; i < kDKBackdropIvarCount; i++) {
        UIView *view = DKBackdropView(bar, kDKBackdropIvars[i]);
        DKAdjustFade(view, factor, view.bounds.size);
    }
}

void DKTabBarBackdropSetNeedsUpdate(void) {
    if (gBackdropScheduled) return;
    gBackdropScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        gBackdropScheduled = NO;
        DKBackdropApply(gBackdropBar);
    });
}

NSString *DKTabBarBackdropStatus(void) {
    AWENormalModeTabBar *bar = gBackdropBar;
    NSMutableString *out = [NSMutableString string];
    if (!bar) {
        [out appendString:@"还没有见到抖音底栏\n"];
        return out;
    }
    BOOL glass = DKGlassTabBarActive();
    BOOL fullscreen = DKVideoFullscreenOn();
    id progress = nil;
    @try {
        progress = [bar valueForKey:@"awe_lightModeProgress"];
    } @catch (__unused NSException *exception) {
    }
    [out appendFormat:@"玻璃底栏=%@ 视频全屏=%@ → 背景=%@  明暗进度=%@\n",
        glass ? @"开" : @"关", fullscreen ? @"开" : @"关",
        glass ? @"玻璃接管" : (DKBackdropShouldHide() ? @"透明" : @"原生"), progress ?: @"-"];
    for (NSUInteger i = 0; i < kDKBackdropIvarCount; i++) {
        UIView *view = DKBackdropView(bar, kDKBackdropIvars[i]);
        if (!view) {
            [out appendFormat:@"  %s = nil\n", kDKBackdropIvars[i]];
            continue;
        }
        [out appendFormat:@"  %s = %@ alpha=%.2f hidden=%d 本模块透明=%@ 背景色=%@\n", kDKBackdropIvars[i],
            NSStringFromClass(view.class), view.alpha, view.isHidden,
            DKAdjustFadeFactor(view) < 0.5 ? @"是" : @"否", view.backgroundColor ?: @"nil"];
    }
    return out;
}

%hook AWENormalModeTabBar

- (void)layoutSubviews {
    %orig;
    DKBackdropApply(self);
}

%end
