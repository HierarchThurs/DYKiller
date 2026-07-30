//
//  DKCommentGlass.xm
//  把抖音原生评论面板换成系统 Clear 液态玻璃：主面板、输入栏底色与输入框胶囊各一层
//  UIGlassEffectStyleClear。深浅色、材质、染色全部交给系统；本文件不压 alpha、不加 tint、
//  不做自绘模糊 / 压暗 / 调色。
//
//  实现约束（beta6）：
//
//  · 槽位判据仍是「子树里唯一不透明的背景色」——面板在 CommentContainerInnerViewController.view，
//    输入栏与输入框各一处。不写死 frame / 层级；其他形态找不到槽位时自动不生效。
//
//  · 大尺寸媒体背景必须用 Clear：Regular 会主动模糊并增强不透明度，面板越大越厚。
//    Apple Materials / WWDC25 UIKit 明确把 Clear 留给媒体背景。
//
//  · Clear 不随深浅色变化：iOS 26.5 实测，场景浅色 / 场景深色 / override 浅色 / override 深色
//    四种组合逐像素相同（亮度比同为 1.21，面板尺寸复测 1.17 / 1.15）。所以深色玻璃不能靠
//    overrideUserInterfaceStyle，只能用原生 UIGlassEffect.tintColor 染色——它在保留折射与
//    视频细节的前提下把玻璃压暗（黑 15% / 30% / 50% 对应 1.04 / 0.90 / 0.71）。
//
//  · 玻璃自身必须有有效圆角，宿主 masksToBounds 只是硬裁、不会给玻璃折射与高光。
//    顶部半径取槽位实时 layer.cornerRadius 作为同心圆角下限；输入框用 capsule。
//
//  · 新建时 effect=nil 挂载，再在现有呈现过渡中写入 effect，走系统 materialize；
//    禁止用 alpha 淡入（UIVisualEffectView 文档：alpha < 1 会失真甚至不显示）。
//
//  · 主面板玻璃恒为槽位满幅。输入栏容器是面板槽位的兄弟且落在它的矩形之内，所以铺满就已经
//    盖住输入区——输入栏底色槽只清成透明让它透上来，不再单独挂一块玻璃。beta2 给底色槽也挂
//    玻璃、主面板则截到输入栏顶边让位，空评论态下底色槽认不出来，那 82pt 就两块玻璃都没有。
//    输入框保持独立胶囊，不使用 UIGlassContainerEffect（嵌套会被合并成同一形状）。
//
//  · 深浅色从 UIWindowScene 的 trait 取：抖音把 window override 钉死为浅色。
//  · 主面板若已有其他插件的 effect view，整项让行，只移除自身创建的视图。
//

#import "DouyinHeaders.h"
#import "DKCommentGlass.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"

#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import <objc/runtime.h>

// 依赖的抖音类名集中在此，抖音改名时只改这里。
static NSString *const kDKInnerControllerClass =
    @"AWECommentPanelContainerSwiftImpl.CommentContainerInnerViewController";
static NSString *const kDKInputContainerClass =
    @"AWECommentInputViewSwiftImpl.CommentInputContainerView";

// 输入栏底色槽的尺寸比对容差。
static const CGFloat kDKSlotSizeTolerance = 0.5;
// 槽位尚未写入圆角时的顶部半径下限，保证玻璃有效半径 > 0。
static const CGFloat kDKTopRadiusFloor = 8.0;
// 深色档的黑色染色强度：实测亮度比 0.90，明确是深色玻璃且视频细节完整。
static const CGFloat kDKDarkTintAlpha = 0.30;

#pragma mark - 状态（全部挂在被改动的视图上，多个评论面板并存也互不干扰）

static char kSlotOriginalColorKey;     // 槽位：抖音写的底色
static char kSlotGlassKey;             // 槽位：我们插的玻璃层

// 本次会话是否接管过槽位。开关一直关着的用户不必为每帧的查找与还原付出代价。
static BOOL gEverAttached = NO;
// 所有在场的玻璃层，供深浅色切换时统一更新。
static NSHashTable *gGlassCarriers = nil;
// 已挂上深浅色监听的场景，避免重复注册。
static __weak UIWindowScene *gObservedScene = nil;
// 最近接管的面板槽位，只给调试探针读。
static __weak UIView *gLastPanelSlot = nil;

UIView *DKCommentGlassCurrentSlot(void) {
    return gLastPanelSlot;
}

#pragma mark - 小工具

static BOOL DKColorIsOpaque(UIColor *color) {
    return color && CGColorGetAlpha(color.CGColor) >= 0.99;
}

static BOOL DKViewIsVisible(UIView *view) {
    return view && !view.hidden && view.alpha >= 0.01;
}

#pragma mark - 深浅色

// 该外观下玻璃应有的染色；浅色档不染色，与参照实现一致。
static UIColor *DKGlassTintForStyle(UIUserInterfaceStyle style) {
    if (style != UIUserInterfaceStyleDark) return nil;
    return [UIColor colorWithWhite:0.0 alpha:kDKDarkTintAlpha];
}

// 当前该用的外观：抖音把 window override 钉死为浅色，UIWindowScene 那一层它盖不住，取它即得系统真值。
static UIUserInterfaceStyle gGlassStyle = UIUserInterfaceStyleUnspecified;

// Clear 对 overrideUserInterfaceStyle 完全不敏感，只能整只 effect 换掉。
// effect 尚未 materialize（仍为 nil）的玻璃跳过，等它自己那一轮补上。
static void DKApplyGlassStyle(UIUserInterfaceStyle style) API_AVAILABLE(ios(26.0)) {
    if (style == UIUserInterfaceStyleUnspecified) return;
    gGlassStyle = style;

    UIColor *tint = DKGlassTintForStyle(style);
    for (UIVisualEffectView *glass in gGlassCarriers.allObjects) {
        UIGlassEffect *current = (UIGlassEffect *)glass.effect;
        if (!current) continue;
        // tintColor 相同就不重建：每帧换 effect 会打断系统的呈现过渡。
        UIColor *existing = [current isKindOfClass:UIGlassEffect.class] ? current.tintColor : nil;
        if (existing == tint || [existing isEqual:tint]) continue;

        UIGlassEffect *effect = [UIGlassEffect effectWithStyle:UIGlassEffectStyleClear];
        effect.tintColor = tint;
        glass.effect = effect;
    }
}

// 挂在场景上监听，系统一切深浅色即刻改；否则只能等抖音下次布局。
static void DKObserveGlassStyle(UIView *host) API_AVAILABLE(ios(26.0)) {
    UIWindowScene *scene = host.window.windowScene;
    if (!scene || scene == gObservedScene) return;
    gObservedScene = scene;
    [scene registerForTraitChanges:@[ UITraitUserInterfaceStyle.class ]
                       withHandler:^(UIWindowScene *changed, __unused UITraitCollection *previous) {
        DKApplyGlassStyle(changed.traitCollection.userInterfaceStyle);
    }];
}

#pragma mark - 槽位

// 槽位候选：当前带不透明底色，或底色已被我们清掉但记忆还在。
static BOOL DKIsSlotCandidate(UIView *view) {
    return objc_getAssociatedObject(view, &kSlotOriginalColorKey) != nil
        || DKColorIsOpaque(view.backgroundColor);
}

static void DKCollectSlotCandidates(UIView *view, NSUInteger depth, NSMutableArray<UIView *> *candidates) {
    if (depth > 4) return;
    for (UIView *subview in view.subviews) {
        if (DKIsSlotCandidate(subview)) [candidates addObject:subview];
        DKCollectSlotCandidates(subview, depth + 1, candidates);
    }
}

static UIView *DKPanelSlot(AWECommentContainerViewController *controller) {
    UIViewController *inner = DKChildControllerNamed(controller, kDKInnerControllerClass);
    return inner.isViewLoaded ? inner.view : nil;
}

static UIView *DKInputContainer(AWECommentContainerViewController *controller) {
    Class containerClass = NSClassFromString(kDKInputContainerClass);
    if (!containerClass || !controller.isViewLoaded) return nil;
    for (UIView *subview in controller.view.subviews) {
        if ([subview isKindOfClass:containerClass]) return subview;
    }
    return nil;
}

// 输入栏有两个槽位：铺满容器的底色槽，以及输入框那枚圆角胶囊。
static void DKResolveInputSlots(UIView *container, UIView **backdrop, UIView **field) {
    *backdrop = nil;
    *field = nil;
    if (!container) return;

    NSMutableArray<UIView *> *candidates = [NSMutableArray array];
    DKCollectSlotCandidates(container, 0, candidates);

    CGSize size = container.bounds.size;
    for (UIView *candidate in candidates) {
        CGSize candidateSize = candidate.bounds.size;
        BOOL fillsContainer = fabs(candidateSize.width - size.width) <= kDKSlotSizeTolerance
            && fabs(candidateSize.height - size.height) <= kDKSlotSizeTolerance;
        if (!*backdrop && fillsContainer) {
            *backdrop = candidate;
        } else if (!*field && candidate.layer.cornerRadius > 0.0) {
            *field = candidate;
        }
    }
}

#pragma mark - 玻璃层

// 玻璃要垫在抖音内容之下。其他插件遍历子视图后可能改动层级，每轮校验一次，顺序对就不动。
static void DKEnsureBackmost(UIView *slot, UIView *glass) {
    if (slot.subviews.firstObject == glass) return;
    [slot insertSubview:glass atIndex:0];
}

typedef NS_ENUM(NSUInteger, DKGlassShape) {
    // 上圆下方：面板与输入栏底色槽；顶部半径跟槽位实时 cornerRadius。
    DKGlassShapeTopRounded = 0,
    // 正圆胶囊：输入框那枚控件。
    DKGlassShapeCapsule,
};

// 先以 nil effect 建好视图；Clear 在挂上视图树后由 DKMaterializeGlass 写入，走系统 materialize。
static UIVisualEffectView *DKMakeGlassShell(void) API_AVAILABLE(ios(26.0)) {
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:nil];
    glass.userInteractionEnabled = NO;
    glass.alpha = 1.0;
    return glass;
}

// 顶部：同心圆角 + 槽位实时半径作下限，避免 beta4 解析成 0 而失去折射/高光。
// 胶囊：系统 capsuleConfiguration，正方形/扁矩形上都保证有效圆角 > 0。
static void DKApplyGlassShape(UIVisualEffectView *glass, UIView *slot, DKGlassShape shape)
    API_AVAILABLE(ios(26.0)) {
    if (shape == DKGlassShapeCapsule) {
        glass.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];
        return;
    }

    CGFloat floor = slot.layer.cornerRadius;
    if (floor <= 0.0) floor = kDKTopRadiusFloor;
    UICornerRadius *top = [UICornerRadius containerConcentricRadiusWithMinimum:floor];
    glass.cornerConfiguration =
        [UICornerConfiguration configurationWithUniformTopRadius:top
                                                bottomLeftRadius:nil
                                               bottomRightRadius:nil];
}

// 仅在 effect 仍为 nil 时写入，让系统 materialize 动画跑一次；后续换档走 DKApplyGlassStyle。
static void DKMaterializeGlass(UIVisualEffectView *glass) API_AVAILABLE(ios(26.0)) {
    if (glass.effect) return;
    UIGlassEffect *effect = [UIGlassEffect effectWithStyle:UIGlassEffectStyleClear];
    effect.tintColor = DKGlassTintForStyle(gGlassStyle);
    glass.effect = effect;
}

// 记下并清掉槽位的不透明底色。返回 NO 表示这个槽位不该接管——它本来就没有底色。
// 输入栏底色槽只做到这一步：它落在主面板槽位的矩形之内，清成透明后主面板玻璃直接透上来，
// 不必也不该再给它单独一块玻璃。
static BOOL DKClearSlotColor(UIView *slot) {
    UIColor *current = slot.backgroundColor;
    if (DKColorIsOpaque(current)) {
        objc_setAssociatedObject(slot, &kSlotOriginalColorKey, current, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        slot.backgroundColor = UIColor.clearColor;
        gEverAttached = YES;
        return YES;
    }
    return objc_getAssociatedObject(slot, &kSlotOriginalColorKey) != nil;
}

// 接管一个槽位：清掉它的不透明底色，在最底层插一层玻璃壳。
// 返回 nil 表示这个槽位不该接管——要么本来就没有底色，要么已被别的插件插了玻璃。
static UIView *DKAttachGlass(UIView *slot, DKGlassShape shape) API_AVAILABLE(ios(26.0)) {
    UIView *glass = objc_getAssociatedObject(slot, &kSlotGlassKey);
    // 退让只在尚未接管时判定；接管之后层级由 DKEnsureBackmost 维持，不能再据此退出。
    if (!glass && [slot.subviews.firstObject isKindOfClass:UIVisualEffectView.class]) return nil;

    if (!DKClearSlotColor(slot)) return nil;

    if (!glass) {
        glass = DKMakeGlassShell();
        objc_setAssociatedObject(slot, &kSlotGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gGlassCarriers addObject:glass];
        gEverAttached = YES;
    }

    DKApplyGlassShape((UIVisualEffectView *)glass, slot, shape);
    return glass;
}

static void DKDetachGlass(UIView *slot) {
    UIColor *original = objc_getAssociatedObject(slot, &kSlotOriginalColorKey);
    if (!original) return;

    [(UIView *)objc_getAssociatedObject(slot, &kSlotGlassKey) removeFromSuperview];
    slot.backgroundColor = original;

    objc_setAssociatedObject(slot, &kSlotOriginalColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(slot, &kSlotGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - 同步

// 输入栏在「移除评论区底栏」开启时被压成 alpha 0，此时整段不做；它的显隐 owner 是
// DKCommentBottomBar，这里只读不写。只挂壳与几何，effect 由调用方在 CATransaction 外 materialize。
//
// 底色槽只清成透明，让主面板玻璃透上来；只有输入框那枚胶囊有自己的玻璃。
// beta2 给底色槽也挂一块玻璃，主面板玻璃就得截到输入栏顶边让位，而空评论态下抖音换了另一套
// 输入区结构、底色槽认不出来，那 82pt 于是两块玻璃都没有，直接露出原始视频。
static void DKSyncInputGlass(UIView *container) API_AVAILABLE(ios(26.0)) {
    if (!DKViewIsVisible(container)) return;

    UIView *backdrop = nil;
    UIView *field = nil;
    DKResolveInputSlots(container, &backdrop, &field);

    if (backdrop) DKClearSlotColor(backdrop);
    if (!field) return;

    // 胶囊不用 UIGlassContainerEffect：嵌套会被合并成同一形状。
    UIVisualEffectView *glass = (UIVisualEffectView *)DKAttachGlass(field, DKGlassShapeCapsule);
    if (!glass) return;
    if (!CGRectEqualToRect(glass.frame, field.bounds)) glass.frame = field.bounds;
    DKEnsureBackmost(field, glass);
}

static void DKMaterializeSlotGlass(UIView *slot) API_AVAILABLE(ios(26.0)) {
    if (!slot) return;
    UIVisualEffectView *glass = objc_getAssociatedObject(slot, &kSlotGlassKey);
    if (glass) DKMaterializeGlass(glass);
}

static void DKCommentGlassSync(AWECommentContainerViewController *controller) API_AVAILABLE(ios(26.0)) {
    BOOL enabled = DKPrefBool(DKKeyCommentGlass);
    if (!enabled && !gEverAttached) return;

    UIView *panel = DKPanelSlot(controller);
    if (!panel) return;

    UIView *inputContainer = DKInputContainer(controller);

    if (!enabled) {
        // 还原一次即收敛：槽位记忆清空后，后续布局只剩几次空查找。
        DKDetachGlass(panel);
        UIView *backdrop = nil;
        UIView *field = nil;
        DKResolveInputSlots(inputContainer, &backdrop, &field);
        DKDetachGlass(backdrop);
        DKDetachGlass(field);
        return;
    }

    // 本函数可能落在抖音的布局或键盘动画里，隐式动画会让玻璃几何拖在内容后面。
    // materialize 单独在 disable 之外写 effect，保留系统呈现过渡。
    UIVisualEffectView *panelGlass = nil;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    panelGlass = (UIVisualEffectView *)DKAttachGlass(panel, DKGlassShapeTopRounded);
    if (panelGlass) {
        gLastPanelSlot = panel;
        DKObserveGlassStyle(panel);
        // 监听之外再逐帧比对一次：冷启动首帧与刚挂上时都没有 trait 变化事件可等。
        DKApplyGlassStyle(panel.window.windowScene.traitCollection.userInterfaceStyle);

        // 恒为槽位满幅：输入栏容器是本槽位的兄弟且落在它的矩形之内，铺满就已经盖住输入区，
        // 不需要给它让位，也就没有「让了位却没人盖」的时序窗口。
        if (!CGRectEqualToRect(panelGlass.frame, panel.bounds)) panelGlass.frame = panel.bounds;
        DKEnsureBackmost(panel, panelGlass);

        DKSyncInputGlass(inputContainer);
    }

    [CATransaction commit];

    // 几何就位后再 materialize：系统 Clear 从 nil → effect 的过渡不走 alpha。
    if (panelGlass) {
        DKMaterializeGlass(panelGlass);
        if (DKViewIsVisible(inputContainer)) {
            UIView *backdrop = nil;
            UIView *field = nil;
            DKResolveInputSlots(inputContainer, &backdrop, &field);
            DKMaterializeSlotGlass(field);
        }
    }
}

#pragma mark - Hook

%hook AWECommentContainerViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (@available(iOS 26.0, *)) DKCommentGlassSync(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) DKCommentGlassSync(self);
}

%end

#pragma mark - 设置项注册

%ctor {
    gGlassCarriers = [NSHashTable weakObjectsHashTable];

    DKSettingsRegisterItem(@"评论区", ^AWESettingItemModel *{
        return DKMakeSwitch(
            DKKeyCommentGlass,
            @"评论区液态玻璃",
            @"把评论面板与输入栏换成 iOS 26 系统 Clear 液态玻璃；面板已被其他插件接管时自动让行"
        );
    });

}
