// 清屏按钮与长按倍速提示的玻璃外观，保留原生内容和触摸入口。
#import "DKPlaybackOverlay.h"
#import "DKGlassTabBar.h"
#import "DKGlassGuard.h"
#import "DKGlassFlexView.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import <objc/runtime.h>
#import <math.h>

@interface DKPlaybackGlassState : NSObject
@property (nonatomic, strong) DKGlassFlexView *glass;
@property (nonatomic) BOOL originalClips;
@property (nonatomic) BOOL clear;
@property (nonatomic) UIUserInterfaceStyle style;
@end
@implementation DKPlaybackGlassState
@end

static char kDKPlaybackGlassKey;
static NSHashTable<UIView *> *gDKPlaybackGlassHosts;
static NSHashTable<UIWindowScene *> *gDKPlaybackGlassScenes;

static BOOL DKPlaybackGlassEnabled(void) {
    return DKGlassOSAvailable() && DKGlassTabBarActive();
}

static void DKPlaybackGlassSync(UIView *host, CGRect frame, BOOL enabled, BOOL interactive)
    API_AVAILABLE(ios(26.0)) {
    [gDKPlaybackGlassHosts addObject:host];
    DKPlaybackGlassState *state = objc_getAssociatedObject(host, &kDKPlaybackGlassKey);
    if (!enabled || CGRectIsEmpty(frame) || CGRectIsNull(frame)
        || !isfinite(frame.origin.x) || !isfinite(frame.origin.y)
        || !isfinite(frame.size.width) || !isfinite(frame.size.height)) {
        if (state) {
            [state.glass removeFromSuperview];
            if (!host.clipsToBounds) host.clipsToBounds = state.originalClips;
            objc_setAssociatedObject(host, &kDKPlaybackGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    UIWindowScene *scene = host.window.windowScene;
    if (scene && ![gDKPlaybackGlassScenes containsObject:scene]) {
        [gDKPlaybackGlassScenes addObject:scene];
        [scene registerForTraitChanges:@[ UITraitUserInterfaceStyle.class ]
                          withHandler:^(__unused UIWindowScene *changed, __unused UITraitCollection *previous) {
            DKPlaybackOverlayGlassRefresh();
        }];
    }
    UIUserInterfaceStyle style = scene.traitCollection.userInterfaceStyle;
    BOOL clear = DKPrefBool(DKKeyGlassTabBarClear);
    BOOL fresh = state == nil;
    if (fresh) {
        state = [DKPlaybackGlassState new];
        state.originalClips = host.clipsToBounds;
        state.glass = [[DKGlassFlexView alloc] initWithFrame:frame];
        state.glass.userInteractionEnabled = NO;
        state.glass.flexSourceView = interactive ? host : nil;
        state.glass.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];
        objc_setAssociatedObject(host, &kDKPlaybackGlassKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // 宿主重建子视图时可能连同玻璃一起移除，玻璃始终挂回原生内容下方。
    if (state.glass.superview != host) [host insertSubview:state.glass atIndex:0];
    host.clipsToBounds = NO;
    if (!CGRectEqualToRect(state.glass.frame, frame)) state.glass.frame = frame;
    if (fresh || state.clear != clear || state.style != style) {
        state.clear = clear;
        state.style = style;
        state.glass.overrideUserInterfaceStyle = style;
        UIGlassEffect *effect = [UIGlassEffect effectWithStyle:
            clear ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular];
        if (clear) effect.tintColor = DKGlassTintForStyle(style);
        effect.interactive = interactive;
        state.glass.effect = effect;
    }
}

static void DKPureGlassSync(AFDRoundRectangleBoxView *box) API_AVAILABLE(ios(26.0)) {
    BOOL enabled = DKPlaybackGlassEnabled() && DKPlaybackOverlayIsPureControl(box);
    // 原生盒子分别为退出单键与暂停 / 倍速双键，正方形自然形成圆形。
    DKPlaybackGlassSync(box, box.bounds, enabled, YES);
}

static void DKPureTransportGlassSync(UIView *toolbar) API_AVAILABLE(ios(26.0)) {
    BOOL enabled = DKPlaybackGlassEnabled() && DKPlaybackOverlayIsPureControl(toolbar)
        && !toolbar.hidden && toolbar.alpha > 0.01;
    CGRect content = CGRectNull;
    CGFloat height = 0.0;
    if (enabled) {
        Class buttonClass = NSClassFromString(@"AFDRoundRectangleButton");
        Class boxClass = NSClassFromString(@"AFDRoundRectangleBoxView");
        // 原生盒子内的退出 / 倍速单独保留；直属按钮构成中间播放控制组。
        for (UIView *item in toolbar.subviews) {
            if (item.hidden || item.alpha <= 0.01 || CGRectIsEmpty(item.bounds)) continue;
            if ([item isKindOfClass:boxClass]) height = MAX(height, CGRectGetHeight(item.bounds));
            if ([item isKindOfClass:buttonClass]) {
                content = CGRectUnion(content, [item convertRect:item.bounds toView:toolbar]);
            }
        }
    }
    CGRect frame = CGRectNull;
    if (!CGRectIsNull(content)) {
        height = MAX(height, CGRectGetHeight(content));
        frame = CGRectIntersection(toolbar.bounds,
            CGRectInset(content, -height / 2.0, -(height - CGRectGetHeight(content)) / 2.0));
    }
    // 胶囊只提供材质，三个按钮沿用各自的原生按压反馈和触摸路径。
    DKPlaybackGlassSync(toolbar, frame, enabled, NO);
}

// 清屏工具条是清屏页根视图的直属子视图；按钮直接挂在工具条上，或在工具条的原生盒子里。
static UIView *DKPureToolbarForButton(UIView *button) {
    UIView *toolbar = button.superview;
    if ([toolbar isKindOfClass:NSClassFromString(@"AFDRoundRectangleBoxView")]) toolbar = toolbar.superview;
    UIResponder *page = toolbar.superview.nextResponder;
    return [page isKindOfClass:NSClassFromString(@"AFDPureModePageContainerViewController")] ? toolbar : nil;
}

static void DKPureGlassLayoutPage(UIViewController *page) API_AVAILABLE(ios(26.0)) {
    Class boxClass = NSClassFromString(@"AFDRoundRectangleBoxView");
    for (UIView *toolbar in page.viewIfLoaded.subviews) {
        for (UIView *item in toolbar.subviews) {
            if (![item isKindOfClass:boxClass]) continue;
            DKPureTransportGlassSync(toolbar);
            break;
        }
    }
}

static CGRect DKSpeedHintFrame(AFDFastSpeedView *view) {
    CGRect content = CGRectNull;
    for (UIView *item in @[ view.bottomTextView ?: NSNull.null,
                            view.bottomSpeedTextView ?: NSNull.null,
                            view.drageToPureModeTextView ?: NSNull.null,
                            view.bottomArrowView ?: NSNull.null,
                            view.downLockArrowView ?: NSNull.null ]) {
        if (![item isKindOfClass:UIView.class] || item.hidden || item.alpha <= 0.01
            || item.superview != view || CGRectIsEmpty(item.bounds)) continue;
        content = CGRectUnion(content, [item convertRect:item.bounds toView:view]);
    }
    if (CGRectIsNull(content)) return CGRectNull;
    CGFloat height = CGRectGetHeight(content);
    // 留白按实际文字 / 箭头高度计算，胶囊始终包住可见内容。
    return CGRectIntersection(view.bounds, CGRectInset(content, -height * 0.55, -height * 0.35));
}

static void DKSpeedGlassSync(AFDFastSpeedView *view) API_AVAILABLE(ios(26.0)) {
    BOOL enabled = DKPlaybackGlassEnabled();
    DKPlaybackGlassSync(view, enabled ? DKSpeedHintFrame(view) : CGRectNull, enabled, NO);
}

void DKPlaybackOverlayGlassRefresh(void) {
    if (!DKGlassOSAvailable()) return;
    if (@available(iOS 26.0, *)) {
        Class speedClass = NSClassFromString(@"AFDFastSpeedView");
        Class boxClass = NSClassFromString(@"AFDRoundRectangleBoxView");
        for (UIView *host in gDKPlaybackGlassHosts.allObjects) {
            if ([host isKindOfClass:speedClass]) DKSpeedGlassSync((AFDFastSpeedView *)host);
            else if ([host isKindOfClass:boxClass]) DKPureGlassSync((AFDRoundRectangleBoxView *)host);
            else DKPureTransportGlassSync(host);
        }
    }
}

%group DKPlaybackGlass
%hook AFDPureModePageContainerViewController
- (void)viewDidLayoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) DKPureGlassLayoutPage(self);
}
%end

%hook AFDRoundRectangleBoxView
- (void)layoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) DKPureGlassSync(self);
}
- (void)didMoveToWindow {
    %orig;
    if (@available(iOS 26.0, *)) DKPureGlassSync(self);
}
%end

%hook AFDRoundRectangleButton
// 换作品重建工具条时，清屏页布局早于工具条为新按钮落位；按钮布局时按最终位置重算胶囊。
- (void)layoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) {
        UIView *toolbar = DKPureToolbarForButton(self);
        if (toolbar) DKPureTransportGlassSync(toolbar);
    }
}
%end

%hook AFDFastSpeedView
- (void)layoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) DKSpeedGlassSync(self);
}
- (void)didMoveToWindow {
    %orig;
    if (@available(iOS 26.0, *)) DKSpeedGlassSync(self);
}
%end
%end

%ctor {
    gDKPlaybackGlassHosts = [NSHashTable weakObjectsHashTable];
    gDKPlaybackGlassScenes = [NSHashTable weakObjectsHashTable];
    if (DKGlassOSAvailable()) { %init(DKPlaybackGlass); }
}
