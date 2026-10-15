//
//  DKCommentGlass.xm
//  用 iOS 26 系统液态玻璃替换评论面板与输入框的不透明底色。
//  默认使用自适应的 Regular，用户可切换为 Clear；两种材质都不接管文字渲染。
//
//  实现约束：
//
//  · 槽位判据是「子树里唯一不透明的背景色」——面板在 CommentContainerInnerViewController.view，
//    输入栏与输入框各一处。不写死 frame / 层级；其他形态找不到槽位时自动不生效。
//
//  · Regular 不叠加任何 tint，通过玻璃视图的 overrideUserInterfaceStyle 跟随真实场景外观。
//    Clear 浅色不染色，深色沿用 DKGlassTintForStyle 的黑色 30% 染色。
//
//  · 玻璃自身必须有有效圆角，宿主 masksToBounds 只是硬裁、不会给玻璃折射与高光。
//    顶部半径取槽位实时 layer.cornerRadius 作为同心圆角下限；输入框直接取槽位半径。
//
//  · 新建时 effect=nil 挂载，再在转场协调器或短动画中写入 effect，走系统 materialize；
//    禁止用 alpha 淡入（UIVisualEffectView 文档：alpha < 1 会失真甚至不显示）。
//
//  · 整个输入区共用一块玻璃，挂在 CommentInputContainerView 自己身上——容器才是「输入区」这个
//    语义单位，抖音在里面怎么挪槽位（拉起艾特面板时底色槽整体下移、腾出顶上 120pt）都不影响
//    覆盖范围。容器内的不透明底（底色槽、艾特面板、表情面板及其 tab 条）统一按满幅清扫清掉。
//
//  · 主面板玻璃让位到输入区顶边——两块上下拼接、互不重叠。回复态输入栏跳到面板中段、与评论
//    列表整段重叠，只清成透明会直接看见评论行；而玻璃叠玻璃是一整块肉眼可见的亮度台阶
//    （实测见 docs/comment-panel-liquid-glass.md）。让位只让「能证明被盖住」的那一段，
//    判据不成立一律回满幅，不会留洞；输入区盖到槽位顶边之上时主面板玻璃整块隐藏。
//    输入框保持独立一块，不使用 UIGlassContainerEffect（嵌套会被合并成同一形状）。
//
//  · 小表情栏住在 UITextEffectsWindow 里，够不着也不必够——它的矩形正好落在输入区玻璃之内，
//    只清掉自己的不透明底色，透出来的就是同一块玻璃。
//
//  · 热更新的「不透明绘制优化」从抖音自己的 AB 网关关掉，等于把收到热更新的设备退回没收到的
//    那个状态。不碰文字颜色、字形、图层与 opaque。
//
//  · 深浅色从 UIWindowScene 的 trait 取：抖音把 window override 钉死为浅色。
//  · interactive 恒为 YES；玻璃不参与 hit-test，触摸源重定向到对应槽位及其子树。
//  · 主面板若已有其他插件的 effect view，整项让行，只移除自身创建的视图。
//

#import "DouyinHeaders.h"
#import "DKCommentGlass.h"
#import "DKGlassFlexView.h"
#import "DKGlassGuard.h"
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
static NSString *const kDKFoldDisplayClass =
    @"AWECommentPanelListSwiftImpl.CommentFoldDisplayView";

// 输入栏底色槽的尺寸比对容差。
static const CGFloat kDKSlotSizeTolerance = 0.5;
// 槽位尚未写入圆角时的顶部半径下限，保证玻璃有效半径 > 0。
static const CGFloat kDKTopRadiusFloor = 8.0;
// 没有可复用的页面转场时，材质更换使用这个短动画。
static const NSTimeInterval kDKGlassAnimationDuration = 0.25;
// 满幅底色清扫的深度上限：主面板要一路走到 Cell 里（第 12 层左右）；输入栏容器最深只到表情
// 面板的 tab 条（第 6 层），收窄一点也把表情面板展开时的遍历成本关住。判据见 DKIsCoverCandidate。
static const NSUInteger kDKPanelCoverWalkDepth = 14;
static const NSUInteger kDKInputCoverWalkDepth = 8;
static const CGFloat kDKCoverMinHeight = 8.0;

#pragma mark - 状态（全部挂在被改动的视图上，多个评论面板并存也互不干扰）

static char kSlotOriginalColorKey;     // 槽位：抖音写的底色
static char kSlotGlassKey;             // 槽位：我们插的玻璃层
static char kCoverOriginalColorKey;    // 遮盖层：抖音写的底色
static char kGlassClearModeKey;         // 玻璃：当前 effect 是否按 Clear 构造
static char kGlassMaterializingKey;     // 玻璃：已排入 materialize，防止重复排队
static char kFoldMaskedHiddenKey;       // 被折叠条盖住的兄弟：抖音原本的 hidden

// 本次会话是否接管过槽位。开关一直关着的用户不必为每帧的查找与还原付出代价。
static BOOL gEverAttached = NO;
// 所有在场的玻璃层，供深浅色切换时统一更新。
static NSHashTable *gGlassCarriers = nil;
// 已清过底色的满幅遮盖层，关开关时还原。
static NSHashTable *gClearedCovers = nil;
// 被折叠提示条盖住、由我们代抖音藏起来的兄弟视图，关开关时还原。
static NSHashTable *gFoldMaskedViews = nil;
// 已挂上深浅色监听的场景，避免重复注册。
static __weak UIWindowScene *gObservedScene = nil;
// 拦下「不透明绘制优化」网关的次数，只给调试探针读。
static NSUInteger gRenderOptimizeBlocks = 0;
// 最近接管的面板槽位与输入框槽位，只给调试探针读。
static __weak UIView *gLastPanelSlot = nil;
static __weak UIView *gLastFieldSlot = nil;
// 最近接管的输入栏容器。主面板玻璃的让位判据、小表情栏的清色判据都以它那块玻璃为准。
static __weak UIView *gLastInputContainer = nil;
// 在场的小表情栏。它随键盘来去，玻璃可能比它后到，同步时补清一次。
static __weak UIView *gEmoticonPanel = nil;
// 最近同步过的评论控制器，供小表情栏那条补救路径回调同步（见 DKCommentEmoticonHook）。
static __weak UIViewController *gLastController = nil;

UIView *DKCommentGlassCurrentSlot(void) {
    return gLastPanelSlot;
}

UIView *DKCommentGlassCurrentField(void) {
    return gLastFieldSlot;
}

UIView *DKCommentGlassCurrentInputContainer(void) {
    return gLastInputContainer;
}

UIView *DKCommentGlassCurrentEmoticonPanel(void) {
    return gEmoticonPanel;
}

NSUInteger DKCommentGlassRenderOptimizeBlocks(void) {
    return gRenderOptimizeBlocks;
}

#pragma mark - 小工具

static BOOL DKColorIsOpaque(UIColor *color) {
    return color && CGColorGetAlpha(color.CGColor) >= 0.99;
}

static BOOL DKViewIsVisible(UIView *view) {
    return view && !view.hidden && view.alpha >= 0.01;
}

// 视图自己连同每一级祖先都可见。「移除评论区底栏」把整个输入栏容器压成 alpha 0，
// 玻璃作为它的后代跟着看不见——只看玻璃自己会判成还在盖着。
static BOOL DKViewChainVisible(UIView *view) {
    for (UIView *node = view; node; node = node.superview) {
        if (!DKViewIsVisible(node)) return NO;
    }
    return YES;
}

#pragma mark - 材质与外观

// 抖音的 window override 恒为浅色，真实系统外观从 UIWindowScene 取。
static UIUserInterfaceStyle gGlassStyle = UIUserInterfaceStyleUnspecified;

static BOOL DKColorsEqual(UIColor *lhs, UIColor *rhs) {
    return lhs == rhs || [lhs isEqual:rhs];
}

static UIUserInterfaceStyle DKGlassStyleForView(UIView *view) {
    UIUserInterfaceStyle style = view.window.windowScene.traitCollection.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified) style = gGlassStyle;
    if (style == UIUserInterfaceStyleUnspecified) style = view.traitCollection.userInterfaceStyle;
    return style == UIUserInterfaceStyleUnspecified ? UIUserInterfaceStyleLight : style;
}

static BOOL DKCommentGlassEnabled(void) {
    return DKGlassOSAvailable() && DKPrefBool(DKKeyCommentGlass);
}

static BOOL DKCommentGlassUsesClearMaterial(void) {
    return DKGlassOSAvailable() && DKPrefBool(DKKeyCommentGlassClear);
}

static UIUserInterfaceStyle DKGlassOverrideStyle(BOOL clear, UIUserInterfaceStyle style) {
    return clear ? UIUserInterfaceStyleUnspecified : style;
}

static UIColor *DKCommentGlassTint(BOOL clear, UIUserInterfaceStyle style) {
    return clear ? DKGlassTintForStyle(style) : nil;
}

static UIGlassEffect *DKMakeCommentGlassEffect(BOOL clear, UIUserInterfaceStyle style)
    API_AVAILABLE(ios(26.0)) {
    UIGlassEffect *effect = [UIGlassEffect effectWithStyle:
        clear ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular];
    effect.tintColor = DKCommentGlassTint(clear, style);
    effect.interactive = YES;
    return effect;
}

static void DKRunGlassAnimation(UIViewController *controller, BOOL animated, void (^changes)(void)) {
    if (!changes) return;
    if (!animated || UIAccessibilityIsReduceMotionEnabled()) {
        [UIView performWithoutAnimation:changes];
        return;
    }

    id<UIViewControllerTransitionCoordinator> coordinator = controller.transitionCoordinator;
    if (coordinator && coordinator.isAnimated) {
        BOOL accepted = [coordinator
            animateAlongsideTransition:^(__unused id<UIViewControllerTransitionCoordinatorContext> context) {
                changes();
            }
            completion:nil];
        if (accepted) return;
    }

    [UIView animateWithDuration:kDKGlassAnimationDuration
                          delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState
                              | UIViewAnimationOptionAllowUserInteraction
                              | UIViewAnimationOptionCurveEaseInOut
                     animations:changes
                     completion:nil];
}

static void DKInstallGlassEffect(UIVisualEffectView *glass, UIGlassEffect *effect, BOOL clear)
    API_AVAILABLE(ios(26.0)) {
    glass.effect = effect;
    objc_setAssociatedObject(glass, &kGlassClearModeKey, @(clear), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// 判据只看真正进入 effect 的三样：Regular/Clear 档位、tint、interactive。**场景外观不在其中**
// ——Regular 的 tint 恒为 nil，换外观时 DKMakeCommentGlassEffect 造出来的 effect 与在用的
// 逐字段相同，0.5.5 把外观也算进判据，于是每次切深浅色都拿一份一模一样的 effect 去换掉活着的
// 材质。外观现在只走 overrideUserInterfaceStyle。纯粹是省掉一次无谓的材质重建：
// 「换 effect 会打死材质」在 iOS 26.5 模拟器上没能复现（探针见
// debug/details/0.5.6/glass-restyle-probe/，swap / override / reparent 三条路径读数一致），
// 全屏切外观那条最后查明是全屏容器底色被重刷，与材质无关。
static BOOL DKGlassNeedsAppearance(UIVisualEffectView *glass, BOOL clear, UIUserInterfaceStyle style)
    API_AVAILABLE(ios(26.0)) {
    UIGlassEffect *current = [glass.effect isKindOfClass:UIGlassEffect.class]
        ? (UIGlassEffect *)glass.effect : nil;
    if (!current) return glass.effect != nil;

    NSNumber *installedClear = objc_getAssociatedObject(glass, &kGlassClearModeKey);
    if (!installedClear || installedClear.boolValue != clear) return YES;
    if (!current.interactive) return YES;
    return !DKColorsEqual(current.tintColor, DKCommentGlassTint(clear, style));
}

// 外观切换只改 overrideUserInterfaceStyle；只有 Regular/Clear 档位或 tint 真的变了才重建 effect。
static void DKApplyGlassStyle(UIUserInterfaceStyle style, BOOL animated) API_AVAILABLE(ios(26.0)) {
    if (style == UIUserInterfaceStyleUnspecified) return;
    gGlassStyle = style;

    BOOL clear = DKCommentGlassUsesClearMaterial();
    NSArray<UIVisualEffectView *> *carriers = gGlassCarriers.allObjects;
    UIUserInterfaceStyle override = DKGlassOverrideStyle(clear, style);

    NSMutableArray<UIVisualEffectView *> *restyle = [NSMutableArray array];
    for (UIVisualEffectView *glass in carriers) {
        if (glass.overrideUserInterfaceStyle != override) {
            glass.overrideUserInterfaceStyle = override;
        }
        if (glass.effect && DKGlassNeedsAppearance(glass, clear, style)) [restyle addObject:glass];
    }
    if (restyle.count == 0) return;

    DKRunGlassAnimation(nil, animated, ^{
        for (UIVisualEffectView *glass in restyle) {
            DKInstallGlassEffect(glass, DKMakeCommentGlassEffect(clear, style), clear);
        }
    });
}

// 挂在场景上监听，系统一切深浅色即刻改；否则只能等抖音下次布局。
static void DKObserveGlassStyle(UIView *host) API_AVAILABLE(ios(26.0)) {
    UIWindowScene *scene = host.window.windowScene;
    if (!scene || scene == gObservedScene) return;
    gObservedScene = scene;
    [scene registerForTraitChanges:@[ UITraitUserInterfaceStyle.class ]
                       withHandler:^(UIWindowScene *changed, __unused UITraitCollection *previous) {
        DKApplyGlassStyle(changed.traitCollection.userInterfaceStyle, YES);
    }];
}

#pragma mark - 槽位

// 槽位候选：当前带不透明底色，或底色已被我们清掉但记忆还在。
static BOOL DKIsSlotCandidate(UIView *view) {
    return objc_getAssociatedObject(view, &kSlotOriginalColorKey) != nil
        || DKColorIsOpaque(view.backgroundColor);
}

// 整棵跳过 effect view：底色槽接管之后玻璃就挂在它里面，UIKit 那套内部视图里既有满幅的、
// 也有带圆角的，扫进来会被当成第二个槽位。别的插件的 effect 同理，也不该往里认。
static void DKCollectSlotCandidates(UIView *view, NSUInteger depth, NSMutableArray<UIView *> *candidates) {
    if (depth > 4) return;
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:UIVisualEffectView.class]) continue;
        if (DKIsSlotCandidate(subview)) [candidates addObject:subview];
        DKCollectSlotCandidates(subview, depth + 1, candidates);
    }
}

// 半屏与全屏复用同一个评论控制器；槽位按结构解析，认不出时不接管。
static UIView *DKPanelSlot(UIViewController *controller) {
    UIViewController *inner = DKChildControllerNamed(controller, kDKInnerControllerClass);
    return inner.isViewLoaded ? inner.view : nil;
}

static UIView *DKInputContainer(UIViewController *controller) {
    Class containerClass = NSClassFromString(kDKInputContainerClass);
    if (!containerClass || !controller.isViewLoaded) return nil;
    for (UIView *subview in controller.view.subviews) {
        if ([subview isKindOfClass:containerClass]) return subview;
    }
    return nil;
}

// 输入栏里只剩一个要单独接管的槽位：输入框那枚圆角胶囊。
// 整个输入区的底（底色槽、艾特面板、表情面板）由容器那一块玻璃统一垫，见 DKSyncInputGlass。
static UIView *DKInputFieldSlot(UIView *container) {
    if (!container) return nil;

    NSMutableArray<UIView *> *candidates = [NSMutableArray array];
    DKCollectSlotCandidates(container, 0, candidates);

    CGSize size = container.bounds.size;
    for (UIView *candidate in candidates) {
        // 铺满容器的是底色槽、艾特面板或表情面板，都不是胶囊——它们由容器那块玻璃统一垫。
        CGSize candidateSize = candidate.bounds.size;
        if (fabs(candidateSize.width - size.width) <= kDKSlotSizeTolerance) continue;
        // 发送键之类的圆角控件也有底色，胶囊本身从来不是控件。
        if ([candidate isKindOfClass:UIControl.class]) continue;
        if (candidate.layer.cornerRadius > 0.0) return candidate;
    }
    return nil;
}

#pragma mark - 玻璃层

// 玻璃要垫在抖音内容之下。其他插件遍历子视图后可能改动层级，每轮校验一次，顺序对就不动。
static void DKEnsureBackmost(UIView *slot, UIView *glass) {
    if (slot.subviews.firstObject == glass) return;
    [slot insertSubview:glass atIndex:0];
}

typedef NS_ENUM(NSUInteger, DKGlassShape) {
    // 上圆下方：主面板；顶部半径跟槽位实时 cornerRadius。
    DKGlassShapeTopRounded = 0,
    // 跟随槽位实时 cornerRadius：输入框那枚控件。常驻态它的半径正好是半高，本来就是胶囊。
    DKGlassShapeField,
    // 输入栏容器，平角：它与主面板玻璃上下拼接，顶边给圆角会在两角露出原始视频。
    DKGlassShapeBarFlat,
    // 输入栏容器，上圆下方：艾特 / 表情面板把输入区顶出主面板之后，顶边成了露在视频上的自由边，
    // 原生那条盖条就是 8pt 圆角。
    DKGlassShapeBarRounded,
};

static BOOL DKGlassShapeIsBar(DKGlassShape shape) {
    return shape == DKGlassShapeBarFlat || shape == DKGlassShapeBarRounded;
}

static void DKSyncPanelGlassHeight(void);
static void DKClearCoverLayers(UIView *slot, NSUInteger maxDepth);

// 输入栏那块玻璃。它带 FlexibleWidth|FlexibleHeight，输入栏容器在常驻态与回复态之间
// 改尺寸（82 ↔ 545）时 UIKit 会跟着改它的 bounds，于是本回调必然被调用一次。
// 主面板玻璃的让位高度就在这里重算：改输入栏几何的那次布局与重算主面板的那次是同一次，
// 结构上无法失步——这正是「主面板截到输入栏顶边」这条路以前会留洞的原因。
// 这里改的是另一棵子树里的视图（主面板玻璃），不改自身 frame，不会形成布局环。
@interface DKCommentBarGlassView : DKGlassFlexView {
    CGSize _dkSweptSize;   // 上次补扫时的容器尺寸，只在形态真的变了时再扫
}
@end

@implementation DKCommentBarGlassView

- (void)layoutSubviews {
    [super layoutSubviews];
    DKSyncPanelGlassHeight();

    // 尺寸变了 = 输入区换了形态（艾特面板 / 表情面板出现或收起）。新露出来的那一块若在玻璃
    // 出现**之前**就被抖音画过底色，取色口那道拦截赶不上，按形态变化补扫一次。
    // 只认尺寸变化：layoutSubviews 本身可能被调很多次，而形态切换一共就那么几次。
    CGSize size = self.bounds.size;
    if (CGSizeEqualToSize(size, _dkSweptSize)) return;
    _dkSweptSize = size;
    DKClearCoverLayers(self.superview, kDKInputCoverWalkDepth);
}

@end

// 先以 nil effect 建好视图；挂上视图树并完成几何后再走系统 materialize。
// 用 DKGlassFlexView 而不是裸 UIVisualEffectView：它多一条触摸源重定向，除此之外行为一致。
static UIVisualEffectView *DKMakeGlassShell(DKGlassShape shape) API_AVAILABLE(ios(26.0)) {
    Class shellClass = DKGlassShapeIsBar(shape) ? DKCommentBarGlassView.class : DKGlassFlexView.class;
    DKGlassFlexView *glass = [[shellClass alloc] initWithEffect:nil];
    glass.userInteractionEnabled = NO;
    glass.alpha = 1.0;
    // 输入框与输入栏都会在常驻态与回复态之间改变尺寸；交给 UIKit 按槽位 bounds 自动跟随。
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    return glass;
}

// 顶部：同心圆角 + 槽位实时半径作下限，保证折射与高光所需的有效圆角。
// 胶囊：系统 capsuleConfiguration，正方形/扁矩形上都保证有效圆角 > 0。
static void DKApplyGlassShape(UIVisualEffectView *glass, UIView *slot, DKGlassShape shape)
    API_AVAILABLE(ios(26.0)) {
    // cornerConfiguration 是 nonnull，且形状会在 BarFlat / BarRounded 之间来回切，
    // 必须显式写回 0 半径，不能留着上一次的圆角。
    if (shape == DKGlassShapeBarFlat) {
        glass.cornerConfiguration =
            [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius fixedRadius:0.0]];
        return;
    }
    // 输入框：跟随抖音写在槽位上的圆角，不写死 capsule。抖音恒写 18——常驻 36pt 高时它等于半高、
    // 观感就是胶囊；加图或多行涨到 124pt 时它是圆角矩形。而文字与图片缩略图是槽位的**兄弟视图**，
    // 画在玻璃上面、不受槽位裁剪，写死 capsule 会把两侧收进 62pt，把它们甩到玻璃外面。
    if (shape == DKGlassShapeField) {
        CGFloat radius = slot.layer.cornerRadius;
        glass.cornerConfiguration = radius > 0.0
            ? [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius fixedRadius:radius]]
            : [UICornerConfiguration capsuleConfiguration];
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

// 仅在 effect 仍为 nil 时写入，让系统 materialize 动画跑一次。
static void DKMaterializeGlass(UIVisualEffectView *glass, UIViewController *controller)
    API_AVAILABLE(ios(26.0)) {
    if (!glass || glass.effect || [objc_getAssociatedObject(glass, &kGlassMaterializingKey) boolValue]) return;
    objc_setAssociatedObject(glass, &kGlassMaterializingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    DKRunGlassAnimation(controller, YES, ^{
        if (!glass.superview || !DKCommentGlassEnabled()) {
            objc_setAssociatedObject(glass, &kGlassMaterializingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }

        UIUserInterfaceStyle style = gGlassStyle;
        if (style == UIUserInterfaceStyleUnspecified) style = DKGlassStyleForView(glass);
        BOOL clear = DKCommentGlassUsesClearMaterial();
        glass.overrideUserInterfaceStyle = DKGlassOverrideStyle(clear, style);
        DKInstallGlassEffect(glass, DKMakeCommentGlassEffect(clear, style), clear);
        objc_setAssociatedObject(glass, &kGlassMaterializingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // 让位判据要求输入栏玻璃已写入 effect，而 effect 是在几何之后才写的（转场协调器那条路
        // 还会推迟到转场里）。这里补算一次，主面板才不会一直停在满幅、与输入栏叠成一块台阶。
        DKSyncPanelGlassHeight();
    });
}

// 记下并清掉槽位的不透明底色。返回 NO 表示这个槽位不该接管——它本来就没有底色。
static BOOL DKClearSlotColor(UIView *slot) {
    if (objc_getAssociatedObject(slot, &kSlotOriginalColorKey)) {
        if (DKColorIsOpaque(slot.backgroundColor)) slot.backgroundColor = UIColor.clearColor;
        return YES;
    }
    UIColor *current = slot.backgroundColor;
    if (!DKColorIsOpaque(current)) return NO;
    objc_setAssociatedObject(slot, &kSlotOriginalColorKey, current, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    slot.backgroundColor = UIColor.clearColor;
    gEverAttached = YES;
    return YES;
}

// 铺满槽位的不透明容器会盖住垫在最底层的玻璃。只动满幅容器，不动文字/按钮/图片。
//
// 热更新那一套「不透明绘制优化」刷出来的底色**不归这里管**，由 AB 网关在源头关掉
// （见文件末尾 DKCommentRenderOptimizeHook）。beta1 曾在这里加过一整套按面板底色匹配、
// 连 UILabel 一起清的逻辑，热更设备 8 份导出实测**一次都没触发过**（网关挡住了绘制，
// 列表与 label 根本没被刷色），已整层删除。
//
// 这条结构判据仍然要留：未热更设备上抖音会在列表内容底边放一块满幅不透明垫底块
// （实测 428×200 纯黑、无子视图，挂在 clipsToBounds 的 tab 内容列表里），
// 不清的话往下拉过头会露出一条黑带，与热更新无关，网关管不到。
static Class DKFoldDisplayClass(void) {
    static Class cls = Nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(kDKFoldDisplayClass); });
    return cls;
}

static BOOL DKIsCoverCandidate(UIView *view, UIView *slot) {
    if (!view || view == slot) return NO;
    if (view.hidden || view.alpha < 0.01) return NO;
    if ([view isKindOfClass:UILabel.class]
        || [view isKindOfClass:UIControl.class]
        || [view isKindOfClass:UIImageView.class]) {
        return NO;
    }
    if (!DKColorIsOpaque(view.backgroundColor)) return NO;
    if (fabs(CGRectGetWidth(view.bounds) - CGRectGetWidth(slot.bounds)) > 1.0) return NO;
    return CGRectGetHeight(view.bounds) >= kDKCoverMinHeight;
}

static void DKClearCoverColor(UIView *view) {
    if (objc_getAssociatedObject(view, &kCoverOriginalColorKey)) {
        if (DKColorIsOpaque(view.backgroundColor)) view.backgroundColor = UIColor.clearColor;
        return;
    }
    if (!DKColorIsOpaque(view.backgroundColor)) return;
    objc_setAssociatedObject(view, &kCoverOriginalColorKey,
                             view.backgroundColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gClearedCovers addObject:view];
    view.backgroundColor = UIColor.clearColor;
}

static void DKWalkClearCovers(UIView *view, UIView *slot, NSUInteger depth, NSUInteger maxDepth) {
    if (depth > maxDepth) return;
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:UIVisualEffectView.class]) continue;
        if (DKIsCoverCandidate(sub, slot)) DKClearCoverColor(sub);
        if ([sub isKindOfClass:UILabel.class] || [sub isKindOfClass:UIImageView.class]) continue;
        DKWalkClearCovers(sub, slot, depth + 1, maxDepth);
    }
}

static void DKClearCoverLayers(UIView *slot, NSUInteger maxDepth) {
    if (!slot) return;
    DKWalkClearCovers(slot, slot, 0, maxDepth);
}

static void DKRestoreCoverColor(UIView *view) {
    UIColor *original = objc_getAssociatedObject(view, &kCoverOriginalColorKey);
    if (!original) return;
    objc_setAssociatedObject(view, &kCoverOriginalColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.backgroundColor = original;
}

static void DKRestoreAllCovers(void) {
    NSArray<UIView *> *views = gClearedCovers.allObjects;
    [gClearedCovers removeAllObjects];
    for (UIView *view in views) DKRestoreCoverColor(view);
}

// 接管一个槽位：清掉它的不透明底色，在最底层插一层玻璃壳。
// requireOpaque：输入框胶囊必须本来有底色；主面板槽位按类名认定，底色透明也要挂。
// 返回 nil 表示这个槽位不该接管——已被别的插件插了玻璃，或（输入框）没有底色。
static UIView *DKAttachGlass(UIView *slot, DKGlassShape shape, BOOL requireOpaque)
    API_AVAILABLE(ios(26.0)) {
    UIView *glass = objc_getAssociatedObject(slot, &kSlotGlassKey);
    // 退让只在尚未接管时判定；接管之后层级由 DKEnsureBackmost 维持，不能再据此退出。
    if (!glass && [slot.subviews.firstObject isKindOfClass:UIVisualEffectView.class]) return nil;

    BOOL cleared = DKClearSlotColor(slot);
    if (requireOpaque && !cleared) return nil;

    if (!glass) {
        glass = DKMakeGlassShell(shape);
        objc_setAssociatedObject(slot, &kSlotGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gGlassCarriers addObject:glass];
        gEverAttached = YES;
    }

    // 槽位作为触摸源时包含它的整棵子树，面板列表与输入控件都不必单独枚举。
    ((DKGlassFlexView *)glass).flexSourceView = slot;
    DKApplyGlassShape((UIVisualEffectView *)glass, slot, shape);
    return glass;
}

static void DKDetachGlass(UIView *slot) {
    UIView *glass = objc_getAssociatedObject(slot, &kSlotGlassKey);
    UIColor *original = objc_getAssociatedObject(slot, &kSlotOriginalColorKey);
    if (!glass && !original) return;

    [glass removeFromSuperview];
    if (original) slot.backgroundColor = original;

    objc_setAssociatedObject(slot, &kSlotOriginalColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(slot, &kSlotGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - 让位

// 输入栏那块玻璃在不在场、是不是真的在渲染。effect 是几何之后才写的，所以没写入就还不算数。
static UIVisualEffectView *DKUsableInputGlass(void) {
    UIVisualEffectView *glass = objc_getAssociatedObject(gLastInputContainer, &kSlotGlassKey);
    if (!glass || !glass.effect || !glass.window || !DKViewChainVisible(glass)) return nil;
    return glass;
}

// 输入栏那块玻璃是否**确实**盖住了槽位某条横线以下的整段。除了「在渲染」，还要与槽位同属一个
// 评论控制器、同窗口、满宽、底边到槽位底边。任一条不成立就当没盖住。
// gLastInputContainer 是「最近一个」，同源判定挡住另一个面板的残留。
static BOOL DKInputGlassCoverage(UIView *slot, CGFloat *coverTop) {
    UIVisualEffectView *glass = DKUsableInputGlass();
    if (!glass || !slot.window || glass.window != slot.window) return NO;
    if (!slot.superview || ![gLastInputContainer isDescendantOfView:slot.superview]) return NO;

    CGRect cover = [glass convertRect:glass.bounds toView:slot];
    CGSize size = slot.bounds.size;
    if (CGRectGetMinX(cover) > 0.5 || CGRectGetMaxX(cover) < size.width - 0.5) return NO;
    if (CGRectGetMaxY(cover) < size.height - 0.5) return NO;

    // 可以是负的：艾特 / 表情面板把输入区顶出主面板之后，容器顶边高过槽位顶边，
    // 等于整个槽位都被盖住。调用方据此把主面板玻璃整块收起来。
    *coverTop = CGRectGetMinY(cover);
    return YES;
}

// 主面板玻璃的几何：槽位满幅，减去输入栏玻璃能证明盖住的那一段。两块上下拼接、互不重叠。
// 判据不成立一律回满幅——重叠只是一块亮度台阶，留空却是面板中间一条原始视频。
//
// 调用点有两个：DKCommentGlassSync（包在 CATransaction 里，瞬时生效），以及输入栏玻璃自己的
// layoutSubviews（不包，让高度变化继承键盘动画的环境上下文，与输入栏一起动）。
static void DKSyncPanelGlassHeight(void) {
    UIView *slot = gLastPanelSlot;
    UIVisualEffectView *glass = objc_getAssociatedObject(slot, &kSlotGlassKey);
    if (!glass || !DKCommentGlassEnabled()) return;

    CGFloat coverTop = 0.0;
    BOOL covered = DKInputGlassCoverage(slot, &coverTop);
    // 输入区盖到了槽位顶边之上（艾特 / 表情面板那种形态）：整块收起来。用 hidden 而不是把高度
    // 压成 0——零尺寸的 UIGlassEffect 建不出材质层，之后再撑大也补不回来
    // （见 docs/share-panel-liquid-glass.md 的 beta4 一节）。
    BOOL entirelyCovered = covered && coverTop <= 0.5;
    if (glass.hidden != entirelyCovered) glass.hidden = entirelyCovered;
    if (entirelyCovered) return;

    CGRect target = slot.bounds;
    if (covered) target.size.height = coverTop;
    if (!CGRectEqualToRect(glass.frame, target)) glass.frame = target;
}

#pragma mark - 折叠提示条

// 对某条评论点「不喜欢」后，抖音把这条 Cell 压矮并亮出「① 该评论被折叠」提示条。
//
// **那块不透明底不是同色隐形块，是抖音的功能性遮罩**：折叠时它并不隐藏旧的时间 / 回复 label，
// 而是拿提示条这块不透明色盖住它们（实测提示条 {60,30,276.05,18} 正好罩住时间 {60,31,93,16}
// 与回复 {169,31,26,16}）。所以只清底色会让两层文字叠在一起，必须同时替抖音把被罩住的那几个
// 兄弟藏起来——0.5.6-beta4 只清不藏，就是「缩放后折叠评论很错乱」。
//
// 提示条在每个 Cell 里都预先存在（alpha=0、底色 clear），折叠时抖音只改 alpha 与底色，
// **没有任何视图新增**，所以挂在「Cell 上屏」上的钩子对原地折叠永远不响。
// 判据全部现取现算、不存状态机：每次收敛都按提示条此刻的状态决定藏还是放。
static const NSUInteger kDKFoldWalkDepth = 3;

static BOOL DKFoldRowActive(UIView *fold) {
    if (!DKViewIsVisible(fold)) return NO;
    // 底色被我们清过之后就只剩记忆可认，两者取其一。
    return DKColorIsOpaque(fold.backgroundColor)
        || objc_getAssociatedObject(fold, &kCoverOriginalColorKey) != nil;
}

static void DKUnmaskFoldSibling(UIView *view) {
    NSNumber *original = objc_getAssociatedObject(view, &kFoldMaskedHiddenKey);
    if (!original) return;
    objc_setAssociatedObject(view, &kFoldMaskedHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gFoldMaskedViews removeObject:view];
    view.hidden = original.boolValue;
}

static void DKRestoreAllFoldMasks(void) {
    NSArray<UIView *> *views = gFoldMaskedViews.allObjects;
    for (UIView *view in views) DKUnmaskFoldSibling(view);
    [gFoldMaskedViews removeAllObjects];
}

// 收敛一条折叠提示条：亮着就清底色 + 藏被它完整罩住的可见兄弟，灭了就原样放回去。
// 「完整罩住」而不是「相交」——头像在左、点赞与不喜欢在右、昵称在上、正文比它宽，都不会命中。
static void DKSyncFoldRow(UIView *fold) {
    UIView *parent = fold.superview;
    if (!parent) return;

    if (!DKFoldRowActive(fold)) {
        // 只放兄弟，**不把底色还回去**。取消不喜欢时抖音是用动画把提示条 alpha 收到 0 的，
        // 而 view.alpha 读的是 model 值——动画一开始它就是 0 了，presentation 还整整齐齐在屏上。
        // 这时候写回不透明白色，就是那一下「展开前闪一块折叠底色」。
        // 也不存在「没还原」的问题：抖音自己的未折叠态本来就是 alpha 0 + 底色 clear
        // （原始评论导出实测），留着 clear 正是它该有的样子；记忆留着还能顺带挡住抖音在
        // 这段动画里的回写，下次再折叠时也不会先闪一下白。关开关走 DKRestoreAllCovers() 还原。
        for (UIView *sibling in parent.subviews) DKUnmaskFoldSibling(sibling);
        return;
    }

    DKClearCoverColor(fold);
    CGRect covered = fold.frame;
    for (UIView *sibling in parent.subviews) {
        if (sibling == fold) continue;
        if (objc_getAssociatedObject(sibling, &kFoldMaskedHiddenKey)) continue;
        if (sibling.hidden || !CGRectContainsRect(covered, sibling.frame)) continue;
        objc_setAssociatedObject(sibling, &kFoldMaskedHiddenKey, @(sibling.hidden),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gFoldMaskedViews addObject:sibling];
        sibling.hidden = YES;
    }
}

static void DKSyncFoldRowsIn(UIView *view, Class foldClass, NSUInteger depth) {
    if (depth > kDKFoldWalkDepth) return;
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:foldClass]) {
            DKSyncFoldRow(sub);
            continue;
        }
        if ([sub isKindOfClass:UILabel.class] || [sub isKindOfClass:UIImageView.class]) continue;
        DKSyncFoldRowsIn(sub, foldClass, depth + 1);
    }
}

#pragma mark - 小表情栏

// 小表情栏是键盘的输入附件，住在 UITextEffectsWindow 里，不在评论控制器的视图树内。
// 它上面那条窗口链（UITextEffectsWindow / UITrackingWindowView / UIKeyboardItemContainerView）
// 底色全为 nil，只有它自己是不透明的；而它的矩形恒落在输入栏容器之内（容器高 = 输入栏高 +
// 键盘高）。所以清掉这一块底色，透出来的就是输入栏那块玻璃本身——同一块玻璃，天生同档、不叠加。
//
// 只在能证明「输入栏玻璃就在它背后」时才清，证明不了就保留抖音原样，不留一条没有玻璃的横条。
static void DKApplyEmoticonPanel(void) {
    UIView *panel = gEmoticonPanel;
    if (!panel || !panel.window || !DKCommentGlassEnabled()) return;

    UIVisualEffectView *glass = DKUsableInputGlass();
    if (!glass) return;

    // 两个窗口都是满屏同原点，各自的窗口坐标可以直接比。
    CGRect panelRect = [panel convertRect:panel.bounds toView:nil];
    CGRect glassRect = [glass convertRect:glass.bounds toView:nil];
    if (!CGRectContainsRect(CGRectInset(glassRect, -0.5, -0.5), panelRect)) return;

    DKClearCoverColor(panel);
}

#pragma mark - 同步

// 输入栏在「移除评论区底栏」开启时被压成 alpha 0，此时整段不做；它的显隐 owner 是
// DKCommentBottomBar，这里只读不写。只挂壳与几何，effect 由调用方在 CATransaction 外 materialize。
//
// 玻璃挂在**容器**上而不是里面的底色槽上：容器才是「整个输入区」这个语义单位。拉起艾特面板时
// 抖音把底色槽整体下移、腾出顶上 120pt 给艾特面板，玻璃跟着底色槽走就够不到那一块；
// 挂在容器上则不管抖音在里面怎么挪槽位，覆盖范围都等于输入区本身。
// 容器里各种不透明底（底色槽、艾特面板、表情面板及其 tab 条）统一交给满幅清扫。
static void DKSyncInputGlass(UIView *container) API_AVAILABLE(ios(26.0)) {
    if (!DKViewIsVisible(container)) return;

    // 顶边露在主面板槽位之上时它是压在视频上的自由边，按原生那条盖条给 8pt 圆角；
    // 贴着主面板玻璃时必须平角——给了圆角会在两角露出原始视频。
    UIView *panel = gLastPanelSlot;
    BOOL freeTopEdge = panel.window == container.window
        && [container convertPoint:CGPointZero toView:panel].y < -0.5;
    DKGlassShape shape = freeTopEdge ? DKGlassShapeBarRounded : DKGlassShapeBarFlat;

    UIVisualEffectView *barGlass = (UIVisualEffectView *)DKAttachGlass(container, shape, NO);
    if (barGlass) {
        gLastInputContainer = container;
        // 触摸源取容器自己：工具栏按钮、发送键、艾特头像都在它的子树里。
        ((DKGlassFlexView *)barGlass).flexSourceView = container;
        if (!CGRectEqualToRect(barGlass.frame, container.bounds)) {
            barGlass.frame = container.bounds;
        }
        DKEnsureBackmost(container, barGlass);
        DKClearCoverLayers(container, kDKInputCoverWalkDepth);
    }

    UIView *field = DKInputFieldSlot(container);
    if (!field) return;

    // 输入框不用 UIGlassContainerEffect：嵌套会被合并成同一形状。
    UIVisualEffectView *glass = (UIVisualEffectView *)DKAttachGlass(field, DKGlassShapeField, YES);
    if (!glass) return;
    gLastFieldSlot = field;
    if (!CGRectEqualToRect(glass.frame, field.bounds)) glass.frame = field.bounds;
    DKEnsureBackmost(field, glass);
}

static void DKMaterializeSlotGlass(UIView *slot, UIViewController *controller) API_AVAILABLE(ios(26.0)) {
    if (!slot) return;
    UIVisualEffectView *glass = objc_getAssociatedObject(slot, &kSlotGlassKey);
    if (glass) DKMaterializeGlass(glass, controller);
}

static void DKCommentGlassSync(UIViewController *controller) API_AVAILABLE(ios(26.0)) {
    BOOL enabled = DKCommentGlassEnabled();
    if (!enabled && !gEverAttached) return;

    UIView *panel = DKPanelSlot(controller);
    if (!panel) return;

    UIView *inputContainer = DKInputContainer(controller);

    if (!enabled) {
        // 还原一次即收敛：槽位记忆清空后，后续布局只剩几次空查找。
        // 玻璃可能正处在「整块被盖住」的隐藏态，DKDetachGlass 直接把它摘掉，不必先复位。
        DKDetachGlass(panel);
        DKDetachGlass(inputContainer);
        DKDetachGlass(DKInputFieldSlot(inputContainer));
        DKRestoreAllCovers();
        DKRestoreAllFoldMasks();
        return;
    }

    DKObserveGlassStyle(panel);
    UIUserInterfaceStyle style = DKGlassStyleForView(panel);

    // 本函数可能落在抖音的布局或键盘动画里，隐式动画会让玻璃几何拖在内容后面。
    // materialize 在几何就位后单独执行，不受这个 CATransaction 影响。
    UIVisualEffectView *panelGlass = nil;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    panelGlass = (UIVisualEffectView *)DKAttachGlass(panel, DKGlassShapeTopRounded, NO);
    if (panelGlass) {
        gLastPanelSlot = panel;
        gLastController = controller;

        DKEnsureBackmost(panel, panelGlass);
        DKClearCoverLayers(panel, kDKPanelCoverWalkDepth);

        // 先摆输入栏，再按它实际盖住的那一段给主面板玻璃定高。
        DKSyncInputGlass(inputContainer);
        DKSyncPanelGlassHeight();
    }

    [CATransaction commit];

    // 几何就位后统一更新已存在的材质，再让新玻璃从 nil → effect materialize。
    if (panelGlass) {
        DKApplyGlassStyle(style, YES);
        DKMaterializeGlass(panelGlass, controller);
        if (DKViewIsVisible(inputContainer)) {
            DKMaterializeSlotGlass(inputContainer, controller);
            DKMaterializeSlotGlass(DKInputFieldSlot(inputContainer), controller);
        }
        DKApplyEmoticonPanel();
    }
}

#pragma mark - Hook

// DKCommentBottomBar.xm 也在这两个方法上挂了一层（底栏抑制），两处分属两个功能、各有各的开关，
// 本文件这一层还整体受 iOS 26 可用性约束。多层 %hook 会正常串联，两条同时生效。
%group DKCommentGlassHooks

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

%hook UIView

- (void)setBackgroundColor:(UIColor *)color {
    if ((objc_getAssociatedObject(self, &kCoverOriginalColorKey)
         || objc_getAssociatedObject(self, &kSlotOriginalColorKey))
        && DKColorIsOpaque(color)) {
        %orig(UIColor.clearColor);
        return;
    }
    %orig;
}

%end

%end

// 小表情栏随键盘来去，且不在评论控制器的视图树里——遍历找不到它，只能按类名挂钩。
// 玻璃可能比它后到，所以 DKCommentGlassSync 末尾也补一次（弱引用记住这一块）。
%group DKCommentEmoticonHook

%hook AWECommentMiniEmoticonPanelView

- (void)layoutSubviews {
    %orig;
    gEmoticonPanel = self;
    if (@available(iOS 26.0, *)) {
        DKApplyEmoticonPanel();
        // 小表情栏在屏 = 回复输入区已就位。此时若还没有可用的输入栏玻璃，说明抖音把输入栏从
        // 常驻态挪上来那一下没走评论控制器的布局回调（「移除评论区底栏」开着时常驻态整条被压成
        // alpha 0，那之前也没机会挂）。这是回复态确定会走到的时机，补一次同步；
        // 玻璃就位后本判据即不成立，不会反复进来。
        if (!DKUsableInputGlass() && gLastController) DKCommentGlassSync(gLastController);
    }
}

%end

%end

// 折叠提示条的收敛必须在布局落定之后算（判据是矩形包含），而折叠这件事本身就会把 Cell 从
// 86 压到 58、**必然触发列表重新布局**——触发条件与要修的现象是同一件事，不存在错过。
// 复用、滚动、缩放全屏半屏走的也是这一条；收敛幂等，来回切自愈。
%group DKCommentFoldHook

%hook AWEListKitMagicCollectionView

- (void)layoutSubviews {
    %orig;
    if (!DKCommentGlassEnabled()) return;
    Class foldClass = DKFoldDisplayClass();
    if (!foldClass) return;
    DKSyncFoldRowsIn(self, foldClass, 0);
}

%end

%end

// 艾特面板（点工具栏「@」拉起）的底色**唯一**来自 obtainPanelColor：39.9.0 反汇编实测本类内
// 5 处引用，5 处的返回值都直接进 setBackgroundColor:（横排头像的 collection view、headerView、
// 搜索结果表、两个 footer 与出错页），没有一处当文字色用。
//
// 从取色口返回透明，等于抖音无论什么时候画、画在哪个视图、画几次，拿到的都是透明色——
// 不存在「我们扫完它才画」的时序洞，也不用为没见过的形态（搜索结果 / 加载 / 出错）补扫描。
// 与 enableCommentRenderingOptimize: 同一种手法：只改纯取色方法的返回值，不吞有副作用的调用。
%group DKCommentSearchPanelHook

%hook AWECommentSearchViewController

- (id)obtainPanelColor {
    // 判据只问「输入区玻璃此刻在不在屏」，**不问自己在不在那棵树里**：这几个取色点是懒加载
    // getter，第一次调用时 view 还没挂进输入容器，用层级判定会在冷启动首次原样返回白色，
    // 正是要修的那个洞。艾特面板只为评论输入而生，输入区玻璃亮着时它就是被我们垫着的那块。
    return DKCommentGlassEnabled() && DKUsableInputGlass() ? UIColor.clearColor : %orig;
}

%end

%end

// 热更新（AB 实验位 AWERenderingOptimize4）打开的评论区「不透明绘制优化」：抖音把面板底色写进
// 列表容器与每一个 UIKit 文字视图的 backgroundColor。原版不透明面板上它们与面板同色、完全
// 看不见，玻璃一挂就是「文字带底色块 + 整块面板变色」。从这个网关关掉，等于把收到热更新的设备
// 退回没收到的那个状态——那个状态的渲染已由未热更设备的四份导出验证正确。
//
// 这是热更设备唯一的防线：beta1 曾同时上过一套按面板底色的清扫，8 份导出实测一次都没触发过
// （网关挡在绘制之前），已删。抖音改名或删掉这个方法时本组不安装，观感退回热更原样——
// 探针的「残留面板底色」会立刻从 0 变正数，据此判断要不要把那一层捡回来。
%group DKCommentRenderOptimizeHook

%hook AWECommentABTestSettings

+ (BOOL)enableCommentRenderingOptimize:(id)context {
    if (DKCommentGlassEnabled()) {
        gRenderOptimizeBlocks++;
        return NO;
    }
    return %orig;
}

%end

%end

#pragma mark - 设置项注册

%ctor {
    gGlassCarriers = [NSHashTable weakObjectsHashTable];
    gClearedCovers = [NSHashTable weakObjectsHashTable];
    gFoldMaskedViews = [NSHashTable weakObjectsHashTable];

    DKSettingsRegister(DKKeyCommentGlass, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeGlassChoice(DKKeyCommentGlass, DKKeyCommentGlassClear, @"评论区液态玻璃", ^{
            void (^refresh)(void) = ^{
                UIView *slot = gLastPanelSlot;
                UIUserInterfaceStyle current = gGlassStyle;
                if (slot.window.windowScene) current = DKGlassStyleForView(slot);
                else if (current == UIUserInterfaceStyleUnspecified && slot) current = DKGlassStyleForView(slot);
                if (@available(iOS 26.0, *)) DKApplyGlassStyle(current, YES);
            };
            if ([NSThread isMainThread]) refresh();
            else dispatch_async(dispatch_get_main_queue(), refresh);
        });
        return DKSettingsWithInfo(item,
            @"评论面板与输入框的材质：关闭时保持抖音原生样式；模糊玻璃使用系统 Regular；清透玻璃显示更多背后视频细节。");
    });

    if (DKGlassOSAvailable()) {
        %init(DKCommentGlassHooks);

        if (NSClassFromString(@"AWECommentMiniEmoticonPanelView")) {
            %init(DKCommentEmoticonHook);
        }

        if (NSClassFromString(@"AWEListKitMagicCollectionView") && DKFoldDisplayClass()) {
            %init(DKCommentFoldHook);
        }

        Class searchPanel = NSClassFromString(@"AWECommentSearchViewController");
        if ([searchPanel instancesRespondToSelector:@selector(obtainPanelColor)]) {
            %init(DKCommentSearchPanelHook);
        }

        // 类或方法任一不在就不装：内部 generator 对不存在的方法会「新增」而不是「钩住」，
        // 那样 %orig 会调进空实现。
        Class abTest = NSClassFromString(@"AWECommentABTestSettings");
        if ([abTest respondsToSelector:@selector(enableCommentRenderingOptimize:)]) {
            %init(DKCommentRenderOptimizeHook);
        }
    }
}
