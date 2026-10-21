// 收藏成功与取消收藏提示共用的玻璃底板，保留原生内容、按钮和展示时序。
#import "DouyinHeaders.h"
#import "DKGlassFlexView.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import <objc/runtime.h>

@interface DKTipsGlassState : NSObject
@property (nonatomic, weak) UIView *plate;
@property (nonatomic, strong) DKGlassFlexView *glass;
@property (nonatomic, strong) UIColor *hostColor;
@property (nonatomic, strong) UIColor *plateColor;
@property (nonatomic) BOOL hostOpaque;
@property (nonatomic) BOOL plateOpaque;
@property (nonatomic) CGFloat borderWidth;
@property (nonatomic) CGFloat radius;
@property (nonatomic) BOOL clear;
@property (nonatomic) UIUserInterfaceStyle style;
@end
@implementation DKTipsGlassState
@end

static char kDKTipsGlassStateKey;
static NSHashTable<UIView *> *gDKTipsGlassHosts;
static NSHashTable<UIWindowScene *> *gDKTipsGlassScenes;

static BOOL DKTipsGlassEnabled(void) {
    return DKGlassOSAvailable() && DKPrefBool(DKKeyTipsGlass);
}

// 各提示只登记业务身份与底板，材质及恢复由同一条路径处理。
static UIView *DKTipsGlassPlate(UIView *host) {
    if ([host isKindOfClass:NSClassFromString(@"AFDSnackBar")]) {
        AFDSnackBar *bar = (AFDSnackBar *)host;
        if ([bar.delegate isKindOfClass:NSClassFromString(@"AWEFavoriteNoticeView")]
            && [bar.bodyView isKindOfClass:NSClassFromString(@"AFDSnackBarCustomView")]) {
            return bar.bodyView;
        }
    } else if ([host isKindOfClass:NSClassFromString(@"AWEPlayInteractionSnackBar")]) {
        AWEPlayInteractionSnackBar *bar = (AWEPlayInteractionSnackBar *)host;
        if ([bar.snakeBarConfig.identifier isEqualToString:@"ios_unfavorite_bottom_notification"]) {
            return host;
        }
    }
    return nil;
}

static void DKTipsGlassRestore(UIView *host) {
    DKTipsGlassState *state = objc_getAssociatedObject(host, &kDKTipsGlassStateKey);
    if (!state) return;
    UIView *plate = state.plate;
    [state.glass removeFromSuperview];
    DKGlassRestoreInkText(plate);
    if ([host.backgroundColor isEqual:UIColor.clearColor]) host.backgroundColor = state.hostColor;
    if ([plate.backgroundColor isEqual:UIColor.clearColor]) plate.backgroundColor = state.plateColor;
    if (!host.opaque) host.opaque = state.hostOpaque;
    if (!plate.opaque) plate.opaque = state.plateOpaque;
    if (plate.layer.borderWidth == 0.0) {
        plate.layer.borderWidth = state.borderWidth;
    }
    objc_setAssociatedObject(host, &kDKTipsGlassStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DKTipsGlassRefresh(void);

static void DKTipsGlassSync(UIView *host) API_AVAILABLE(ios(26.0)) {
    if (!host) return;
    UIView *plate = DKTipsGlassPlate(host);
    if (plate) [gDKTipsGlassHosts addObject:host];
    else [gDKTipsGlassHosts removeObject:host];

    DKTipsGlassState *state = objc_getAssociatedObject(host, &kDKTipsGlassStateKey);
    if (state && state.plate != plate) {
        DKTipsGlassRestore(host);
        state = nil;
    }
    if (!DKTipsGlassEnabled() || !plate || CGRectIsEmpty(plate.bounds)) {
        DKTipsGlassRestore(host);
        return;
    }

    UIWindowScene *scene = host.window.windowScene;
    if (scene && ![gDKTipsGlassScenes containsObject:scene]) {
        [gDKTipsGlassScenes addObject:scene];
        [scene registerForTraitChanges:@[ UITraitUserInterfaceStyle.class ]
                          withHandler:^(__unused UIWindowScene *changed, __unused UITraitCollection *previous) {
            DKTipsGlassRefresh();
        }];
    }
    UIUserInterfaceStyle style = scene.traitCollection.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified) style = host.traitCollection.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified) style = UIUserInterfaceStyleLight;
    BOOL clear = DKPrefBool(DKKeyTipsGlassClear);
    BOOL fresh = state == nil;
    if (fresh) {
        state = [DKTipsGlassState new];
        state.plate = plate;
        state.hostColor = host.backgroundColor;
        state.plateColor = plate.backgroundColor;
        state.hostOpaque = host.opaque;
        state.plateOpaque = plate.opaque;
        state.borderWidth = plate.layer.borderWidth;
        state.glass = [[DKGlassFlexView alloc] initWithFrame:plate.bounds];
        state.glass.userInteractionEnabled = NO;
        state.glass.flexSourceView = host;
        objc_setAssociatedObject(host, &kDKTipsGlassStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    // 原生重新配置过的底色、边框成为新的恢复值。
    if (![host.backgroundColor isEqual:UIColor.clearColor]) state.hostColor = host.backgroundColor;
    if (![plate.backgroundColor isEqual:UIColor.clearColor]) state.plateColor = plate.backgroundColor;
    if (plate.layer.borderWidth != 0.0) {
        state.borderWidth = plate.layer.borderWidth;
    }
    host.backgroundColor = UIColor.clearColor;
    plate.backgroundColor = UIColor.clearColor;
    host.opaque = NO;
    plate.opaque = NO;
    plate.layer.borderWidth = 0.0;
    if (plate.subviews.firstObject != state.glass) [plate insertSubview:state.glass atIndex:0];
    if (!CGRectEqualToRect(state.glass.frame, plate.bounds)) state.glass.frame = plate.bounds;
    CGFloat radius = plate.layer.cornerRadius;
    if (fresh || state.radius != radius) {
        state.radius = radius;
        state.glass.cornerConfiguration = [UICornerConfiguration configurationWithUniformRadius:
            [UICornerRadius fixedRadius:radius]];
    }
    if (fresh || state.clear != clear || state.style != style) {
        state.clear = clear;
        state.style = style;
        state.glass.overrideUserInterfaceStyle = clear ? UIUserInterfaceStyleUnspecified : style;
        UIGlassEffect *effect = [UIGlassEffect effectWithStyle:
            clear ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular];
        if (clear) effect.tintColor = DKGlassTintForStyle(style);
        effect.interactive = YES;
        state.glass.effect = effect;
    }
    DKGlassApplyInkText(plate, clear, style);
    [CATransaction commit];
}

static void DKTipsGlassRefresh(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKTipsGlassRefresh(); });
        return;
    }
    if (@available(iOS 26.0, *)) {
        for (UIView *host in gDKTipsGlassHosts.allObjects) DKTipsGlassSync(host);
    }
}

%group DKTipsGlassHooks

%hook AFDSnackBar
- (void)showWithBodyView:(UIView *)bodyView {
    %orig;
    if (@available(iOS 26.0, *)) DKTipsGlassSync(self);
}
- (void)layoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) DKTipsGlassSync(self);
}
%end

%hook AFDSnackBarCustomView
- (void)layoutSubviews {
    %orig;
    UIView *host = self.superview;
    if ([host isKindOfClass:NSClassFromString(@"AFDSnackBar")]) {
        if (@available(iOS 26.0, *)) DKTipsGlassSync(host);
    }
}
%end

%hook AWEPlayInteractionSnackBar
- (void)showOnView:(UIView *)view bottomOffset:(double)offset {
    %orig;
    if (@available(iOS 26.0, *)) DKTipsGlassSync(self);
}
- (void)layoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) DKTipsGlassSync(self);
}
%end

%end

%ctor {
    gDKTipsGlassHosts = [NSHashTable weakObjectsHashTable];
    gDKTipsGlassScenes = [NSHashTable weakObjectsHashTable];
    DKSettingsRegister(DKKeyTipsGlass, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeGlassChoice(DKKeyTipsGlass, DKKeyTipsGlassClear,
            @"提示信息液态玻璃", ^{ DKTipsGlassRefresh(); });
        return DKSettingsWithInfo(item,
            @"收藏成功与取消收藏提示的材质：关闭时保持抖音原生样式；模糊玻璃使用系统 Regular；清透玻璃显示更多背后画面细节。保留提示中的原生操作按钮。");
    });
    if (DKGlassOSAvailable()) {
        %init(DKTipsGlassHooks);
    }
}
