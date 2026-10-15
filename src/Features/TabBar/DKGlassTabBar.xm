//
//  DKGlassTabBar.xm
//  自建 UITabBar（4 个 tab 的玻璃胶囊）+ 右侧独立玻璃圆键（拍摄），顶替抖音自绘底栏。
//  内容全部镜像自抖音自己的按钮：标题、顺序、拍摄图标、未读角标，抖音改什么这里跟着变。
//
//  两条不可回退的结论：
//
//  · 不能复活抖音自带的 AWEFakeTabBar。它与自建 UITabBar 的 appearance、platter 子树、
//    layer 属性完全一致，却只有自建的渲染出玻璃——它自创建起即隐藏，UIKit 从未为它建过
//    玻璃背景层，事后改可见性不会补建。
//
//  · 两块玻璃都做成抖音底栏的【子视图】。显隐、透明度、位置、生命周期由 UIKit 沿视图树
//    继承，无需任何同步代码，也就不会出现「抖音不布局就不更新」。驱动点放在抖音底栏自己的
//    layoutSubviews，冷启动首帧即可挂上。唯一继承不到的是深浅色，见 DKGlassApplyStyle。
//

#import "DKGlassTabBar.h"
#import "DKAudioVisualizer.h"
#import "DKPlusIcon.h"
#import "DKTabBarRemoval.h"
#import "DouyinHeaders.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"

#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>

// 依赖的抖音/UIKit 私有符号集中在此，抖音改名时只改这里。
static NSString *const kDKBadgeContainerClass = @"AWENormalModeTabBarBadgeContainerView";
static NSString *const kDKBadgeClass = @"DUXBadge";
static NSString *const kDKPlatterClass = @"_UITabBarItemPlatterView";
static NSString *const kDKTabButtonClass = @"_UITabButton";
static NSString *const kDKPlusClickSelector = @"plusTabBarButtonDidClick:";
static NSString *const kDKTabClickSelector = @"tabBarButtonDidTouchUpInside:gestureRecognizer:";

// 抖音按钮的 type：拍摄入口。它不是页面，不参与 selectedIndex，单独做成右侧圆键。
static const long long kDKPlusButtonType = 2;
// 标题字号。抖音原生底栏是 10pt——那是留给「图标在上、10pt 标签在下」的层叠布局的，
// 标题独占整个按钮后 10pt 会显得空落，故按纯文字胶囊的比例取值。
static const CGFloat kDKTitleFontSize = 15.0;
// 胶囊与拍摄键之间的间距。
static const CGFloat kDKPlusKeyGap = 12.0;
// 拍摄图标在圆键内的四周留白。
static const CGFloat kDKPlusIconInset = 14.0;
// 自定义图标本身就是一枚圆，只留一圈窄边把它嵌进圆键，不需要给字形留呼吸空间。
static const CGFloat kDKPlusIconCustomInset = 7.0;
// platter 还没建起来时的兜底几何（beta7 实测值），量到真实值后即被取代。
static const CGFloat kDKPlatterFallbackHeight = 62.0;
static const CGFloat kDKPlatterFallbackInset = 21.0;
// 胶囊里每颗 _UITabButton 的宽与首颗距胶囊左缘的距离（0.6.1-beta1 实测值），用法同上。
static const CGFloat kDKTabButtonFallbackWidth = 94.0;
static const CGFloat kDKTabButtonFallbackPad = 4.0;

#pragma mark - 状态

static UITabBar *gBar = nil;
static id gProxy = nil;
// 每个 item 对应的 tab 序号（validIndex）。与 items 同序等长。
static NSArray<NSNumber *> *gItemKinds = nil;
// 每个 item 对应的抖音按钮，转发点击与读取角标都用它。与 items 同序等长。
static NSArray *gItemButtons = nil;
// 上次构建 items 用的签名，变了才重建，避免每次布局都换 items。
static NSString *gSignature = nil;
// 最近一次见到的抖音底栏，供开关变化时立即生效。
static __weak AWENormalModeTabBar *gDouyinBar = nil;
// 已挂上深浅色监听的场景，避免重复注册。
static __weak UIWindowScene *gObservedScene = nil;

// 拍摄圆键及其内容。
static UIVisualEffectView *gPlusKey = nil;
static UIImageView *gPlusIcon = nil;
static UIButton *gPlusHit = nil;
// 抖音的拍摄按钮；被其他插件移除时为 nil，圆键随之隐藏。
static __weak UIView *gPlusButton = nil;
// 上次裁过的图标源图，按指针比对，变了才重裁。
static UIImage *gPlusSourceIcon = nil;

UITabBar *DKGlassTabBarCurrent(void) {
    return gBar;
}

UIVisualEffectView *DKGlassPlusKeyCurrent(void) {
    return gPlusKey;
}

// 每次布局由 DKGlassLayoutGlass 刷新。弱引用：UIKit 换掉 platter 时这里自动变 nil。
static __weak UIView *gPlatter = nil;

UIView *DKGlassPlatterCurrent(void) {
    return gPlatter;
}

#pragma mark - 小工具

static id DKGlassValue(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *DKGlassButtonTitle(id button) {
    id inner = DKGlassValue(button, @"innerView");
    NSString *text = DKGlassValue(DKGlassValue(inner, @"label"), @"text");
    if (text.length > 0) return text;

    NSString *current = DKGlassValue(inner, @"currentTitleText");
    if (current.length > 0) return current;

    NSString *label = [button isKindOfClass:UIView.class] ? [(UIView *)button accessibilityLabel] : nil;
    return label.length > 0 ? label : nil;
}

static UITabBarController *DKGlassControllerForView(UIView *view) {
    for (UIResponder *responder = view.nextResponder; responder; responder = responder.nextResponder) {
        if ([responder isKindOfClass:UITabBarController.class]) return (UITabBarController *)responder;
    }
    return nil;
}

#pragma mark - 开关

static BOOL DKGlassTabBarEnabled(void) {
    return DKGlassOSAvailable() && DKPrefBool(DKKeyGlassTabBar);
}

static BOOL DKGlassTabBarUsesClear(void) {
    return DKGlassOSAvailable() && DKPrefBool(DKKeyGlassTabBarClear);
}

#pragma mark - 材质

// 胶囊与拍摄圆键共用。档位跟「清透玻璃」开关走：关＝系统默认磨砂，开＝Clear。
//
// 深色档两种材质认的不是同一条：Clear 对 overrideUserInterfaceStyle 不敏感、只认染色
// （实测中位亮度 136.6 → 99.8；改用 override 是 157.9，等于没压暗），Regular 归 override 管，
// 再叠一层染色会压暗两次。所以染色只给 Clear。
static UIGlassEffect *DKGlassMakeGlassEffect(UIUserInterfaceStyle style, BOOL interactive)
    API_AVAILABLE(ios(26.0)) {
    BOOL clear = DKGlassTabBarUsesClear();
    UIGlassEffect *effect = [UIGlassEffect effectWithStyle:
        clear ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular];
    if (clear) effect.tintColor = DKGlassTintForStyle(style);
    effect.interactive = interactive;
    return effect;
}

// 悬浮胶囊的材质由 _UITabBarItemPlatterView 自己持有的 glassEffect 决定——
// UITabBarAppearance.backgroundEffect 是悬浮布局之前的旧 API，floating provider 根本不读它
// （实测出厂态 / Regular / Clear 三者渲染逐像素相同，均为 9.x% 细节保留）。改写这个属性才
// 拿得到清透，且原生透镜、长按拖动、角标完全不受影响：细节保留 5.9% → 26.8%，
// 与自建 Clear（31.4%）、Apple 的 clearGlassButtonConfiguration（29.8%）同档。
//
// 两条纪律：
// · glassEffect 是 UIKit 内部属性，iOS 大版本可能改名。首次读不到就永久放弃，此后整段不进入
//   （逐帧路径上反复 @try/@catch 既慢又吵），底栏保持系统默认磨砂，功能不受影响。
// · 只还原自己改过的：首次接管前把原厂那只存在 platter 上，关开关时原样放回。
static NSString *const kDKPlatterGlassKey = @"glassEffect";
static char kDKPlatterOriginalGlassKey;
static BOOL gPlatterGlassProbed = NO;
static BOOL gPlatterGlassSupported = NO;
// glassEffect 是 copy 属性（实测回读指针 != 写入指针），所以记的是 platter 存下的那只【副本】。
// 弱引用：platter 换掉它、或 platter 本身销毁，这里都会变，正好当作「需要重装」的信号。
static __weak id gPlatterGlassInstalled = nil;
static UIUserInterfaceStyle gPlatterGlassStyle = UIUserInterfaceStyleUnspecified;

static void DKGlassApplyPlatterGlass(UIView *platter, UIUserInterfaceStyle style)
    API_AVAILABLE(ios(26.0)) {
    if (!platter || (gPlatterGlassProbed && !gPlatterGlassSupported)) return;

    id current = nil;
    @try {
        current = [platter valueForKey:kDKPlatterGlassKey];
    } @catch (__unused NSException *exception) {
        gPlatterGlassProbed = YES;      // 属性不在，永久放弃
        gPlatterGlassSupported = NO;
        return;
    }
    gPlatterGlassProbed = YES;
    gPlatterGlassSupported = YES;

    BOOL patched = current && current == gPlatterGlassInstalled;

    if (!DKGlassTabBarUsesClear()) {
        if (!patched) return;                       // 没接管过，无需还原
        id original = objc_getAssociatedObject(platter, &kDKPlatterOriginalGlassKey);
        @try {
            [platter setValue:(original == NSNull.null ? nil : original)
                       forKey:kDKPlatterGlassKey];
        } @catch (__unused NSException *exception) {}
        gPlatterGlassInstalled = nil;
        gPlatterGlassStyle = UIUserInterfaceStyleUnspecified;
        [platter setNeedsLayout];
        return;
    }

    // 装的还是我们那只、档位也没变，就什么都不做。逐帧无脑重写会打断系统的呈现过渡。
    if (patched && style == gPlatterGlassStyle) return;

    if (!objc_getAssociatedObject(platter, &kDKPlatterOriginalGlassKey)) {
        objc_setAssociatedObject(platter, &kDKPlatterOriginalGlassKey, current ?: NSNull.null,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // interactive 照抄现有那只。UIKit 给 platter 的原厂配置就是 interactive=YES，整块胶囊的
    // 按压/触摸/高亮动效全从它来；写死 NO 会把这些动效一并抹掉（beta23 踩过）。
    BOOL interactive = [current isKindOfClass:UIGlassEffect.class]
        ? ((UIGlassEffect *)current).interactive : YES;
    @try {
        [platter setValue:DKGlassMakeGlassEffect(style, interactive) forKey:kDKPlatterGlassKey];
        gPlatterGlassInstalled = [platter valueForKey:kDKPlatterGlassKey];
    } @catch (__unused NSException *exception) {
        gPlatterGlassSupported = NO;
        return;
    }
    gPlatterGlassStyle = style;
    [platter setNeedsLayout];
}

NSString *DKGlassPlatterGlassStatus(void) {
    if (!gPlatterGlassProbed) return @"未尝试（功能关闭或 platter 尚未建立）";
    if (!gPlatterGlassSupported) return @"属性不存在，已放弃——保持系统默认磨砂";
    if (!DKGlassTabBarUsesClear()) return @"清透开关关闭 · 系统默认磨砂";
    id installed = gPlatterGlassInstalled;
    if (!installed) return @"清透开关开启但尚未装上，下一次布局补";
    UIColor *tint = DKGlassTintForStyle(gPlatterGlassStyle);
    BOOL interactive = [installed isKindOfClass:UIGlassEffect.class]
        && ((UIGlassEffect *)installed).interactive;
    return [NSString stringWithFormat:@"已改写 · Clear · interactive=%@ · 染色 %@",
            interactive ? @"YES" : @"NO", tint ? tint.description : @"(nil，浅色档)"];
}

#pragma mark - 深浅色

// 深浅色是唯一不能靠继承拿到的东西：抖音把 window.overrideUserInterfaceStyle 钉死为浅色
// （beta3 探针逐级实证），它的深色模式是自己换肤画出来的，压根不进 UIKit 的 trait，
// 所以沿视图树继承到的永远是浅色。
//
// UIWindowScene 的 trait 由系统直接下发，而 overrideUserInterfaceStyle 只存在于
// UIView / UIViewController / UIWindow 上——抖音没有 API 能盖住场景那一层，取它即得真值。
//
// 评论面板的玻璃同源，见 DKCommentGlass.xm 的 DKApplyGlassStyle。
//
// override 与染色分工明确：override 只管内容着色（标题模板图、拍摄图标靠 trait 取色），
// 玻璃材质归染色管——Clear 对 override 不敏感，实测给 platter 加 override 深色后中位亮度
// 157.9，等于没压暗；换成染色黑 30% 才是 99.8。
static UIUserInterfaceStyle gGlassStyle = UIUserInterfaceStyleUnspecified;

static void DKGlassApplyStyle(UIUserInterfaceStyle style) API_AVAILABLE(ios(26.0)) {
    if (style == UIUserInterfaceStyleUnspecified || style == gGlassStyle) return;
    gGlassStyle = style;

    if (gBar) gBar.overrideUserInterfaceStyle = style;
    if (gPlusKey) {
        gPlusKey.overrideUserInterfaceStyle = style;
        gPlusKey.effect = DKGlassMakeGlassEffect(style, YES);
    }
    // platter 的玻璃在下一次布局里跟着重写；trait 变化未必伴随布局，主动踢一次。
    [gDouyinBar setNeedsLayout];
}

// 挂在场景上监听，系统一切深浅色即刻改；否则只能等抖音下次布局，就是 beta3 那种「切一下页才变」。
static void DKGlassObserveStyle(UIView *host) API_AVAILABLE(ios(26.0)) {
    UIWindowScene *scene = host.window.windowScene;
    if (!scene || scene == gObservedScene) return;
    gObservedScene = scene;
    [scene registerForTraitChanges:@[ UITraitUserInterfaceStyle.class ]
                       withHandler:^(UIWindowScene *changed, __unused UITraitCollection *previous) {
        if (gBar) DKGlassApplyStyle(changed.traitCollection.userInterfaceStyle);
    }];
}

#pragma mark - 内容取色

// 内容的黑白极性跟【底色】走，不跟深浅色模式走：抖音首页在浅色模式下也是黑视频，消息页在
// 深色模式下是黑底——模式说不清底色。选中/未选中的区别交给浓度（100% / 60%），这样两种极性
// 下都保留切换指示，而不像出厂那样把「选中/未选中」当成「白/黑」两极用。
//
// 出厂两个色的来源（0.5.7-beta2 导出实证，见 docs/tab-bar-liquid-glass.md）：
// · SelectedContentView 里那份 _UITabButton 的 tintColor 是白——UIKit 没写它，沿视图树继承
//   到了 AWENormalModeTabBar.tintColor（抖音设的白），所以选中恒白、与深浅色无关。
// · ContentView 里那份是纯黑——UIKit 按我们下发的 override trait 取。
// 于是浅色模式下同一块玻璃上同时出现两种极性，深色模式下两者塌成同一个色。
//
// 选中透镜（_UITabSelectionView，CABackdropLayer）只取样背后内容（黑底页实测 #000000、
// 白底页浅灰），不提供任何对比度保证，指望它兜底是错的。
//
// 两个色最终由标题图自己携带（见 DKGlassTitleImage）：beta3 实测 tint 那条路走不通。
// 只管内容色。材质档（override 与 Clear 染色）仍归 DKGlassApplyStyle 按场景 trait 管。
static UIImage *DKGlassTitleImage(NSString *title, UIColor *color);

static UIUserInterfaceStyle gInkStyle = UIUserInterfaceStyleUnspecified;
// 上一次分类过的宿主文字色，按指针比对做缓存——这是逐帧路径，指针没变就不必再解析一次。
static UIColor *gInkHostColor = nil;
static BOOL gInkHostIsLight = NO;
// 判定用到的宿主色描述，只给探针看。
static NSString *gInkSource = nil;
// 事件计数，只给探针看。beta3 就是因为只有快照没有事件，才要交叉比对两行才看出样本是过期的。
static NSUInteger gInkResolveCount = 0;    // 真正重新解析过宿主色的次数
static NSUInteger gInkApplyCount = 0;      // 档位真的变了、重渲染过标题图的次数
static NSUInteger gInkColorHits = 0;       // textColorChangedWithSelectedStatus: 命中次数
static NSUInteger gInkStatusHits = 0;      // tabbarStatusDidChanged:animated: 命中次数
// 已经写给拍摄图标的档位。按档位比对而不是按颜色比对：那是逐帧路径，UIColor 的相等性
// 一旦对不上就会每帧重写 tintColor，白白触发 tintColorDidChange。
static UIUserInterfaceStyle gPlusIconInkStyle = UIUserInterfaceStyleUnspecified;

// 未选中的浓度。实测：50% 在亮底只有 3.94:1 不达 AA、55% 是 4.68:1 卡线，
// 60% 两侧分别 6.69 / 5.59。不用系统 secondaryLabel——它浅色档是 #3C3C43 而非纯黑，
// 压在白页上只有 3.4:1。保留 alpha、底色取纯黑白，与 DKGlassInkTextColor 同一口径。
static const CGFloat kDKInkSecondaryAlpha = 0.60;

static UIColor *DKGlassInkColor(BOOL selected) {
    CGFloat white = (gInkStyle == UIUserInterfaceStyleDark) ? 1.0 : 0.0;
    return [UIColor colorWithWhite:white alpha:(selected ? 1.0 : kDKInkSecondaryAlpha)];
}

// 按当前极性重渲染每个 item 的两张标题图。就地改 image / selectedImage，不重建 items——
// 极性变化和切页是同一时刻，重建 items 会打断系统正在跑的透镜位移动画。
static void DKGlassApplyItemImages(void) {
    if (!gBar) return;
    UIColor *selected = DKGlassInkColor(YES);
    UIColor *normal = DKGlassInkColor(NO);
    for (UITabBarItem *item in gBar.items) {
        // 标题不另存一份：建 item 时就写进 accessibilityLabel 了，跟着 item 走不会失配。
        NSString *title = item.accessibilityLabel;
        if (title.length == 0) continue;
        item.image = DKGlassTitleImage(title, normal);
        item.selectedImage = DKGlassTitleImage(title, selected);
    }
}

// 底色明暗只有抖音自己知道：它每页都重算自绘按钮的文字色（首页白、浅色消息 #161823、
// 深色消息白），那就是「这一页底色是什么」的现成答案，而且是抖音自己保证读得清的答案。
// 这条判据还能修一个 trait 修不了的偏差：抖音把 window 的 override 钉死为浅色、深色模式是
// 自己换肤画的、不进 UIKit trait，跟场景 trait 等于跟系统，抖音单独锁深色时会取错。
//
// 只取【选中】那颗按钮：未选中那颗可能是中灰或半透明，按明度分类会判错。
// 直接从抖音的按钮数组里找，不依赖 gItemButtons——那样取色就得排在 DKGlassSyncItems 之后，
// 而标题图要按极性渲染，必须先定极性。拍摄按钮的 validIndex 同样是 0，按 type 排除掉。
static UIColor *DKGlassHostTitleColor(NSArray *buttons, NSInteger selectedIndex) {
    for (id button in buttons) {
        UIView *view = [button isKindOfClass:UIView.class] ? button : nil;
        if (!view || view.isHidden || !view.superview) continue;
        if ([DKGlassValue(button, @"type") longLongValue] == kDKPlusButtonType) continue;
        if ([DKGlassValue(button, @"validIndex") integerValue] != selectedIndex) continue;
        id inner = DKGlassValue(button, @"innerView");
        return DKGlassValue(DKGlassValue(inner, @"label"), @"textColor");
    }
    return nil;
}

static UIUserInterfaceStyle DKGlassInkStyleFor(NSArray *buttons, NSInteger selectedIndex,
                                               UIUserInterfaceStyle fallback) {
    UIColor *host = DKGlassHostTitleColor(buttons, selectedIndex);
    if (!host) {
        gInkSource = @"宿主文字色取不到，回落场景 trait";
        return gInkStyle != UIUserInterfaceStyleUnspecified ? gInkStyle : fallback;
    }
    if (host == gInkHostColor) return gInkHostIsLight ? UIUserInterfaceStyleLight
                                                      : UIUserInterfaceStyleDark;

    // 宿主给的可能是动态色，按当前场景解析后才是真值。
    UIColor *resolved = [host resolvedColorWithTraitCollection:
        [UITraitCollection traitCollectionWithUserInterfaceStyle:fallback]];
    // 切页过渡里抖音会把文字整体淡出，那一帧的色不能用来判极性，保持上一次的结论。
    if (CGColorGetAlpha(resolved.CGColor) < 0.5) {
        gInkSource = [NSString stringWithFormat:@"样本 alpha 过低（%@），保持上次结论", resolved];
        return gInkStyle != UIUserInterfaceStyleUnspecified ? gInkStyle : fallback;
    }

    // 宿主用黑系文字 → 这一页底色偏亮 → 我们也用黑系。
    gInkHostColor = host;
    gInkHostIsLight = DKGlassColorIsInk(resolved);
    gInkSource = [NSString stringWithFormat:@"宿主文字色 %@", resolved];
    gInkResolveCount++;
    return gInkHostIsLight ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark;
}

// 与 DKGlassApplyStyle 同样的纪律：档位没变就什么都不做。
// 不写 tintColor / unselectedItemTintColor：0.5.7-beta4 导出实证前者对 AlwaysOriginal 的
// 标题图无效（浅色模式首页那份里未选中副本的 tintColor 是 trait 推出的黑，字却按我们烤进
// 图里的白 60% 渲染，实测 RGB 166 = 0.6×255 + 0.4×32），后者根本不被悬浮 provider 采纳。
static void DKGlassApplyInk(UIUserInterfaceStyle style) {
    // gBar 的判定放在记录档位之前：没底栏可写就不能把档位记下来，否则下次同档会被跳过。
    if (style == UIUserInterfaceStyleUnspecified || !gBar || style == gInkStyle) return;
    gInkStyle = style;
    gInkApplyCount++;
    DKGlassApplyItemImages();
}

NSString *DKGlassInkStatus(void) {
    if (gInkStyle == UIUserInterfaceStyleUnspecified) return @"未判定（功能关闭或尚未布局）";
    return [NSString stringWithFormat:
            @"底色%@ · 选中 %@ · 未选中 %@\n"
            @"                       依据：%@\n"
            @"                       事件：写色 %lu · 状态变 %lu · 重新解析 %lu · 改档 %lu",
            gInkStyle == UIUserInterfaceStyleDark ? @"偏暗（内容用白）" : @"偏亮（内容用黑）",
            DKGlassInkColor(YES), DKGlassInkColor(NO), gInkSource ?: @"(无)",
            (unsigned long)gInkColorHits, (unsigned long)gInkStatusHits,
            (unsigned long)gInkResolveCount, (unsigned long)gInkApplyCount];
}

#pragma mark - 标题图

// iOS 26 悬浮底栏按「图标在上、标签在下」排版，只给标题时图标槽空着、标题落到按钮底部；
// titlePositionAdjustment 属于旧版层叠布局，悬浮 provider 完全忽略（实测给到 -168 仍纹丝
// 不动）。故把标题渲染成模板图当图标用、标题置空，由系统把它当图标居中。
// 颜色直接烤进图里、走 AlwaysOriginal，不留给任何 tint API 决定：0.5.7-beta3 实测
// `unselectedItemTintColor` 不被悬浮 provider 采纳（截图逐像素量到未选中字仍是纯白
// L=0.965，而白 60% 压在 L=0.019 的胶囊上应为 L≈0.32），选中与未选中因此毫无区别。
// 两张图字形与字号完全相同，只有颜色和浓度不同，所以尺寸一致、胶囊宽度不会跳。
// 字重取 Semibold：玻璃胶囊上压着的内容要够重，太细在半透明底上会发糊。
static UIImage *DKGlassTitleImage(NSString *title, UIColor *color) {
    NSDictionary *attributes = @{
        NSFontAttributeName: [UIFont systemFontOfSize:kDKTitleFontSize weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: color
    };
    CGSize size = [title sizeWithAttributes:attributes];
    size.width = ceil(size.width);
    size.height = ceil(size.height);

    UIGraphicsImageRendererFormat *format = UIGraphicsImageRendererFormat.preferredFormat;
    format.opaque = NO;
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format]
        imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
            [title drawAtPoint:CGPointZero withAttributes:attributes];
        }];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

#pragma mark - 拍摄图标

// 取抖音当前真实显示的拍摄图标。别的插件替换图标改的正是这个 image view，故天然跟随
//（UIButton 自己的 state image 也经 imageView 渲染，同样命中）。
static UIImage *DKGlassPlusSourceIcon(UIView *button) {
    for (UIView *subview in button.subviews) {
        if (![subview isKindOfClass:UIImageView.class]) continue;
        UIImage *image = ((UIImageView *)subview).image;
        if (image) return image;
    }
    return nil;
}

// 按 alpha 裁掉四周透明留白。抖音给的图是 75×49 而字形只有约 33×30，直接缩进圆键会小到看不清；
// 裁完再排版，换了图标也自适应，不必写死内缩。
static UIImage *DKGlassTrimTransparent(UIImage *image) {
    CGImageRef source = image.CGImage;
    if (!source) return image;

    size_t width = CGImageGetWidth(source);
    size_t height = CGImageGetHeight(source);
    if (width == 0 || height == 0) return image;

    uint8_t *alpha = (uint8_t *)calloc(width * height, sizeof(uint8_t));
    if (!alpha) return image;

    CGContextRef context = CGBitmapContextCreate(alpha, width, height, 8, width, NULL,
                                                 (CGBitmapInfo)kCGImageAlphaOnly);
    if (!context) {
        free(alpha);
        return image;
    }
    CGContextDrawImage(context, CGRectMake(0.0, 0.0, width, height), source);
    CGContextRelease(context);

    size_t minX = width, minY = height, maxX = 0, maxY = 0;
    for (size_t y = 0; y < height; y++) {
        for (size_t x = 0; x < width; x++) {
            if (alpha[y * width + x] == 0) continue;
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
        }
    }
    free(alpha);
    if (minX > maxX || minY > maxY) return image;   // 整张全透明，原样返回

    CGImageRef cropped = CGImageCreateWithImageInRect(
        source, CGRectMake(minX, minY, maxX - minX + 1, maxY - minY + 1));
    if (!cropped) return image;

    UIImage *result = [UIImage imageWithCGImage:cropped
                                          scale:image.scale
                                    orientation:image.imageOrientation];
    CGImageRelease(cropped);
    return result;
}

// 图标同样走模板图：抖音会随页面在白/黑两版图标间切换，只取 alpha 则两版形状一致，
// 着色跟内容极性走（见「内容取色」），黑视频上不会出现看不见的黑图标。
CGFloat DKGlassPlusIconInset(void) {
    return DKPlusIconCustom() ? kDKPlusIconCustomInset : kDKPlusIconInset;
}

static void DKGlassSyncPlusIcon(UIView *button) {
    // 自定义图标是用户选的照片，两道加工都要跳过：模板化只取 alpha，会把彩色抹成单色块；
    // 圆形 alpha 已在裁剪时烘进图内，再裁一次透明包围盒会毁掉 3pt 均匀留边的前提。
    UIImage *custom = DKPlusIconCustom();
    if (custom) {
        if (custom == gPlusSourceIcon) return;
        gPlusSourceIcon = custom;
        gPlusIcon.image = custom;
        // 自定义图标保持用户选的原色，一律不着色。档位复位是为了用户清掉它之后，
        // 下一次布局能把模板图的着色补回来。
        gPlusIconInkStyle = UIUserInterfaceStyleUnspecified;
        return;
    }

    // 着色写在这里而不是 DKGlassApplyInk：这个函数每次布局都跑，图源没变也会走到，
    // 用户清掉自定义图标后不必等极性变化就能补上。
    if (gPlusIconInkStyle != gInkStyle) {
        gPlusIconInkStyle = gInkStyle;
        gPlusIcon.tintColor = DKGlassInkColor(YES);
    }

    UIImage *source = DKGlassPlusSourceIcon(button);
    if (!source || source == gPlusSourceIcon) return;
    gPlusSourceIcon = source;
    gPlusIcon.image = [DKGlassTrimTransparent(source)
        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

#pragma mark - 点击转发

@interface DKGlassTabBarProxy : NSObject <UITabBarDelegate>
- (void)plusKeyDidTap;
@end

@implementation DKGlassTabBarProxy

// 拍摄不是页面，走抖音自己的拍摄回调，传它自己的按钮。
- (void)plusKeyDidTap {
    UITabBarController *controller = DKGlassControllerForView(gPlusKey);
    SEL selector = NSSelectorFromString(kDKPlusClickSelector);
    if (controller && gPlusButton && [controller respondsToSelector:selector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(controller, selector, gPlusButton);
    }
}

- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item {
    UITabBarController *controller = DKGlassControllerForView(tabBar);
    NSUInteger index = [tabBar.items indexOfObjectIdenticalTo:item];
    if (!controller || index == NSNotFound || index >= gItemButtons.count) return;

    id button = gItemButtons[index];
    // 切页必须走抖音自己的按钮点击回调。直接写 selectedIndex 会被它的 override 吞掉——
    // 实测底栏选中态变了、抖音的 selectedIndex 仍是 0、页面也没换，只是「看着切了」。
    // 连手势一并原样回传，抖音据此构造点击上下文，与真实点按走完全相同的路径。
    SEL selector = NSSelectorFromString(kDKTabClickSelector);
    if ([controller respondsToSelector:selector]) {
        ((void (*)(id, SEL, id, id))objc_msgSend)(controller, selector, button,
                                                  DKGlassValue(button, @"singleTapGes"));
    }
}

@end

#pragma mark - 未读角标镜像

// 读抖音按钮当前的角标。走子视图扫描而不是 badge / badgeContainerView 属性：那两个 getter
// 可能懒建对象，而这里是逐帧路径，只读不建才安全。
static NSString *DKGlassBadgeValue(id button) {
    if (![button isKindOfClass:UIView.class]) return nil;

    UIView *badge = nil;
    for (UIView *container in ((UIView *)button).subviews) {
        if (![NSStringFromClass(container.class) isEqualToString:kDKBadgeContainerClass]
            || container.isHidden || container.alpha < 0.01) {
            continue;
        }
        for (UIView *candidate in container.subviews) {
            // 尺寸也要判：抖音会把角标留在树里收成零尺寸，那不算「有角标」。
            if ([NSStringFromClass(candidate.class) isEqualToString:kDKBadgeClass]
                && !candidate.isHidden && candidate.alpha >= 0.01
                && !CGRectIsEmpty(candidate.bounds)) {
                badge = candidate;
                break;
            }
        }
        if (badge) break;
    }
    if (!badge) return nil;

    NSString *text = DKGlassValue(badge, @"badgeText");
    if (text.length > 0) return text;                      // 抖音自己给的文案，如 "99+"
    unsigned long long count = [DKGlassValue(badge, @"badgeNumber") unsignedLongLongValue];
    if (count > 0) return @(count).stringValue;
    return @"";                                            // 有角标但无数字 → 纯红点
}

// badgeValue 交给系统渲染即得 iOS 26 悬浮胶囊里的原生红点，badgeColor 留 nil 用系统默认色。
static void DKGlassSyncBadges(void) {
    NSUInteger count = MIN(gItemButtons.count, gBar.items.count);
    for (NSUInteger i = 0; i < count; i++) {
        UITabBarItem *item = gBar.items[i];
        NSString *value = DKGlassBadgeValue(gItemButtons[i]);
        NSString *current = item.badgeValue;
        if (current != value && ![current isEqualToString:value]) item.badgeValue = value;
    }
}

#pragma mark - 内容镜像

// 抖音的按钮数组本身就是视觉顺序，直接照抄；拍摄入口按 type 认出来单独交给圆键，
// 其余按 validIndex 映射到 tab。
//
// 分两段走：先用一轮廉价循环算出内容签名，签名没变就不碰 items。渲染标题图并不便宜，
// 而这个函数每次底栏布局都会跑一遍。返回值表示 items 是否真的重建过。
static BOOL DKGlassSyncItems(UITabBarController *controller, NSArray *buttons) {
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    NSMutableArray<NSNumber *> *kinds = [NSMutableArray array];
    NSMutableArray *mirrored = [NSMutableArray array];
    NSMutableString *signature = [NSMutableString string];
    UIView *plus = nil;

    for (id button in buttons) {
        UIView *view = [button isKindOfClass:UIView.class] ? button : nil;
        // 源按钮的 opacity 会被本功能置零，不能作为存在性信号；显隐与父视图关系保留原始语义。
        if (!view || view.isHidden || !view.superview) continue;

        if ([DKGlassValue(button, @"type") longLongValue] == kDKPlusButtonType) {
            plus = view;
            continue;                  // 拍摄不进胶囊，见 DKGlassMakePlusKey
        }

        NSString *title = DKGlassButtonTitle(button);
        if (title.length == 0) continue;

        NSInteger kind = [DKGlassValue(button, @"validIndex") integerValue];
        [titles addObject:title];
        [kinds addObject:@(kind)];
        [mirrored addObject:button];
        [signature appendFormat:@"%@:%ld|", title, (long)kind];
    }

    gPlusButton = plus;

    if (mirrored.count == 0) return NO;
    // 按钮引用每次都刷新：抖音可能重建出标题相同的新按钮，签名察觉不到，
    // 拿着旧对象转发点击就会落空。items 与它同序等长，只在签名变化时才重建。
    gItemButtons = mirrored;

    BOOL rebuilt = ![signature isEqualToString:gSignature];
    if (rebuilt) {
        NSMutableArray<UITabBarItem *> *items = [NSMutableArray arrayWithCapacity:titles.count];
        [titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger index, __unused BOOL *stop) {
            // 标题走 image 槽（见 DKGlassTitleImage），title 置空，否则系统还会再排一行标签。
            // 图交给 DKGlassApplyItemImages 按极性统一渲染，选中与未选中各一张。
            UITabBarItem *item = [[UITabBarItem alloc] initWithTitle:nil image:nil
                                                                 tag:(NSInteger)index];
            item.accessibilityLabel = title;   // 标题不再是文字，旁白与探针都靠它认人
            [items addObject:item];
        }];
        gBar.items = items;
        gItemKinds = kinds;
        gSignature = [signature copy];
        DKGlassApplyItemImages();
    }

    NSUInteger current = [gItemKinds indexOfObject:@((NSInteger)controller.selectedIndex)];
    if (current != NSNotFound && current < gBar.items.count) {
        UITabBarItem *item = gBar.items[current];
        if (gBar.selectedItem != item) gBar.selectedItem = item;
    }

    DKGlassSyncBadges();
    return rebuilt;
}

// 其他插件（DYYY 等）改标题、隐红点都发生在按钮的子视图里，而 UIKit 的布局遍历是父先子后，
// 抖音底栏那一轮读到的必然是它们改写前的旧值；改标题本身又不会让底栏重新布局，不补这一次
// 就会一直停在旧内容。
//
// 延到主队列再读，而不是在子视图的 hook 里直接读：谁的 hook 在外层取决于插件加载顺序，
// 只有等整轮布局结束才保证读到最终值。gPendingMirror 让一轮布局最多排一次。
static BOOL gPendingMirror = NO;

static void DKGlassScheduleMirror(void) {
    if (gPendingMirror || !gBar) return;
    gPendingMirror = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        gPendingMirror = NO;
        AWENormalModeTabBar *bar = gDouyinBar;
        UITabBarController *controller = bar ? DKGlassControllerForView(bar) : nil;
        if (!gBar || !controller) return;
        // 内容没变时纯空转；变了才重建 items，并要求底栏重排一次几何——胶囊宽度归 UIKit 算，
        // 圆键位置得跟着它走。签名收敛后不再标脏，不会形成布局环。
        // 取色排在同步之前：标题图要按极性渲染，极性得先定下来。
        NSArray *buttons = DKGlassValue(bar, @"tabBarButtons");
        DKGlassApplyInk(DKGlassInkStyleFor(buttons, (NSInteger)controller.selectedIndex,
                                           gGlassStyle));
        if (DKGlassSyncItems(controller, buttons)) [bar setNeedsLayout];
    });
}

#pragma mark - 拍摄圆键

// interactive 是 iOS 26 玻璃自带的触摸反馈（按压形变），不需要我们画任何东西；
// capsuleConfiguration 作用在正方形 frame 上即为正圆。
// 触发用铺满的透明 UIButton：touchUpInside 同时满足「轻点触发」与「长按后松手仍触发」。
// 材质与胶囊同为 Clear（见 DKGlassMakeGlassEffect）——胶囊清透了圆键必须跟上，
// 否则又是「胶囊清透、圆键磨砂」的割裂。
static UIVisualEffectView *DKGlassMakePlusKey(id target) API_AVAILABLE(ios(26.0)) {
    UIVisualEffectView *key =
        [[UIVisualEffectView alloc] initWithEffect:DKGlassMakeGlassEffect(gGlassStyle, YES)];
    key.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];

    gPlusIcon = [[UIImageView alloc] init];
    gPlusIcon.contentMode = UIViewContentModeScaleAspectFit;
    [key.contentView addSubview:gPlusIcon];

    gPlusHit = [UIButton buttonWithType:UIButtonTypeCustom];
    [gPlusHit addTarget:target action:@selector(plusKeyDidTap)
       forControlEvents:UIControlEventTouchUpInside];
    [key.contentView addSubview:gPlusHit];
    return key;
}

static UIView *DKGlassFindPlatter(UIView *root) {
    for (UIView *subview in root.subviews) {
        if ([NSStringFromClass(subview.class) containsString:kDKPlatterClass]) return subview;
        UIView *found = DKGlassFindPlatter(subview);
        if (found) return found;
    }
    return nil;
}

#pragma mark - 几何

// 悬浮胶囊的几何口径（40.7.0 / iOS 27 实测，见 docs/tab-bar-removal.md）：
// · 胶囊宽 = min(自然宽, UITabBar 宽 − 2×内缩)，在 UITabBar 内居中。内缩是 UIKit 内部常量，没有 API。
// · 每颗 _UITabButton 宽 b、首颗距胶囊左缘 pad；自然排布时相邻间距为 b − 2·pad，压缩时间距线性收窄。
// 这些量都从实物上量，量到之前用兜底值。
typedef struct {
    CGFloat buttonWidth;   // b
    CGFloat buttonPad;     // pad
    CGFloat height;        // 胶囊高，即圆键直径
    CGFloat top;           // 胶囊在 UITabBar 内的 y
    CGFloat inset;         // UITabBar 左右到胶囊的内缩
} DKGlassMetrics;

static const DKGlassMetrics kDKGlassFallbackMetrics = {
    kDKTabButtonFallbackWidth, kDKTabButtonFallbackPad, kDKPlatterFallbackHeight, 0.0, kDKPlatterFallbackInset
};
static DKGlassMetrics gMetrics = kDKGlassFallbackMetrics;
// 量这些值时抖音底栏的宽度；宽度变了全部作废，重新量。
static CGFloat gMetricsBarWidth = 0.0;
// 最近一次布局的读数，只给探针看。
static NSUInteger gGeometryCount = 0;
static NSUInteger gGeometryReference = 0;
static CGFloat gGeometryTarget = 0.0;
static CGFloat gGeometryMeasured = 0.0;
static BOOL gInsetMeasured = NO;

static void DKGlassCollectTabButtons(UIView *root, NSMutableArray<UIView *> *result) {
    for (UIView *subview in root.subviews) {
        if ([NSStringFromClass(subview.class) isEqualToString:kDKTabButtonClass]) [result addObject:subview];
        else DKGlassCollectTabButtons(subview, result);
    }
}

static BOOL DKGlassMetricChanged(CGFloat a, CGFloat b) {
    return fabs(a - b) > 0.5;
}

// 从 platter 实物量出各项；返回 YES 表示有量变了，需要按新值重算一轮。
// 胶囊里每颗按钮画两份（选中 / 未选中），frame 相同，取 minX 最小与次小的两个不同值即可。
// 内缩只在压缩态量：此时胶囊两侧各让出一个内缩；自然态胶囊比可用宽度窄，读数偏大不可信。
static BOOL DKGlassMeasure(UIView *platter, NSUInteger count) {
    if (!platter || CGRectGetHeight(platter.bounds) <= 0.0) return NO;
    CGRect frame = [platter convertRect:platter.bounds toView:gBar];
    DKGlassMetrics metrics = gMetrics;
    metrics.height = CGRectGetHeight(frame);
    metrics.top = CGRectGetMinY(frame);

    NSMutableArray<UIView *> *buttons = [NSMutableArray array];
    DKGlassCollectTabButtons(platter, buttons);
    CGFloat first = CGFLOAT_MAX, second = CGFLOAT_MAX, width = 0.0;
    for (UIView *button in buttons) {
        CGRect rect = [button convertRect:button.bounds toView:platter];
        CGFloat x = CGRectGetMinX(rect);
        if (x < first - 0.5) {
            if (first < CGFLOAT_MAX) second = first;
            first = x;
            width = CGRectGetWidth(rect);
        } else if (x > first + 0.5 && x < second - 0.5) {
            second = x;
        }
    }
    if (first < CGFLOAT_MAX && width > 0.0) {
        metrics.buttonPad = first;
        metrics.buttonWidth = width;
    }
    CGFloat naturalPitch = metrics.buttonWidth - 2.0 * metrics.buttonPad;
    if (count >= 2 && second < CGFLOAT_MAX && second - first < naturalPitch - 0.5) {
        metrics.inset = (CGRectGetWidth(gBar.bounds) - CGRectGetWidth(frame)) / 2.0;
        gInsetMeasured = YES;
    }

    BOOL changed = DKGlassMetricChanged(metrics.buttonWidth, gMetrics.buttonWidth) ||
                   DKGlassMetricChanged(metrics.buttonPad, gMetrics.buttonPad) ||
                   DKGlassMetricChanged(metrics.height, gMetrics.height) ||
                   DKGlassMetricChanged(metrics.inset, gMetrics.inset);
    gMetrics = metrics;
    return changed;
}

// 胶囊宽度跟着 4+1 参考态走：参考态是 reference 个项目、右侧有拍摄圆键、整组占满底栏两侧内缩之间。
// 由参考态得出相邻间距，少几项就少几个间距——每项的大小与位置间隔都与参考态相同，不拉长。
static CGFloat DKGlassCapsuleWidth(NSUInteger count, NSUInteger reference, CGFloat barWidth) {
    CGFloat single = gMetrics.buttonWidth + 2.0 * gMetrics.buttonPad;
    CGFloat naturalPitch = MAX(gMetrics.buttonWidth - 2.0 * gMetrics.buttonPad, 0.0);
    reference = MAX(reference, count);
    if (count <= 1 || reference <= 1) return single;

    CGFloat available = barWidth - gMetrics.height - kDKPlusKeyGap - 2.0 * gMetrics.inset;
    CGFloat referenceWidth = MIN(available, single + (reference - 1) * naturalPitch);
    CGFloat pitch = MIN(MAX((referenceWidth - single) / (reference - 1), 0.0), naturalPitch);
    return single + (count - 1) * pitch;
}

NSString *DKGlassGeometryStatus(void) {
    if (!gBar) return @"未建立（功能关闭或尚未布局）";
    return [NSString stringWithFormat:
            @"项目 %lu / 参考 %lu · 胶囊目标 %.1f 实测 %.1f · 按钮宽 %.1f 首距 %.1f 高 %.1f · 内缩 %.1f（%@）",
            (unsigned long)gGeometryCount, (unsigned long)gGeometryReference, gGeometryTarget, gGeometryMeasured,
            gMetrics.buttonWidth, gMetrics.buttonPad, gMetrics.height, gMetrics.inset,
            gInsetMeasured ? @"实测" : @"兜底"];
}

// 胶囊与拍摄圆键作为一组在抖音底栏内水平居中，项目少了只缩短胶囊、不拉长。
// UITabBar 宽度按目标胶囊宽 + 两侧内缩写入后立即布局再量；量到的值变了就按新值再来一轮，首帧也一次到位。
// 定位用实测胶囊宽，靠平移 UITabBar 让胶囊落到位——平移不改宽度，不会再触发重排。
// 写入先比较，不会形成布局环。
static void DKGlassLayoutGlass(AWENormalModeTabBar *douyinBar, NSUInteger reference) API_AVAILABLE(ios(26.0)) {
    CGSize size = douyinBar.bounds.size;
    if (DKGlassMetricChanged(size.width, gMetricsBarWidth)) {
        gMetrics = kDKGlassFallbackMetrics;
        gMetricsBarWidth = size.width;
        gInsetMeasured = NO;
    }

    // 拍摄按钮被移除时圆键一并隐藏。
    BOOL available = gPlusButton != nil;
    if (gPlusKey.isHidden == available) gPlusKey.hidden = !available;

    NSUInteger count = gBar.items.count;
    UIView *platterView = nil;
    for (NSUInteger pass = 0; pass < 2; pass++) {
        gGeometryTarget = DKGlassCapsuleWidth(count, reference, size.width);
        CGFloat barWidth = gGeometryTarget + 2.0 * gMetrics.inset;
        CGRect frame = gBar.frame;
        if (fabs(CGRectGetWidth(frame) - barWidth) > 0.01 || CGRectGetHeight(frame) != size.height) {
            gBar.frame = CGRectMake(CGRectGetMinX(frame), 0.0, barWidth, size.height);
        }
        [gBar layoutIfNeeded];
        platterView = DKGlassFindPlatter(gBar);
        if (!DKGlassMeasure(platterView, count)) break;
    }
    gGeometryCount = count;
    gGeometryReference = reference;
    gPlatter = platterView;
    // 找到 platter 就顺手把它的玻璃换成 Clear。放在所有提前 return 之前：
    // 拍摄按钮被移除时下面会早退，但胶囊材质照样要生效。
    DKGlassApplyPlatterGlass(platterView, gGlassStyle);

    CGRect platter = platterView ? [platterView convertRect:platterView.bounds toView:gBar] : CGRectZero;
    BOOL measured = CGRectGetWidth(platter) > 0.0;
    CGFloat capsule = measured ? CGRectGetWidth(platter) : gGeometryTarget;
    CGFloat capsuleX = measured ? CGRectGetMinX(platter) : gMetrics.inset;
    CGFloat diameter = gMetrics.height;
    gGeometryMeasured = capsule;

    CGFloat group = capsule + (available ? kDKPlusKeyGap + diameter : 0.0);
    CGFloat left = (size.width - group) / 2.0;
    CGRect barFrame = gBar.frame;
    barFrame.origin.x = left - capsuleX;
    if (!CGRectEqualToRect(gBar.frame, barFrame)) gBar.frame = barFrame;
    if (!available) return;

    CGRect keyFrame = CGRectMake(left + capsule + kDKPlusKeyGap, gMetrics.top, diameter, diameter);
    if (!CGRectEqualToRect(gPlusKey.frame, keyFrame)) gPlusKey.frame = keyFrame;

    CGRect bounds = gPlusKey.bounds;
    CGFloat iconInset = DKGlassPlusIconInset();
    CGRect iconFrame = CGRectInset(bounds, iconInset, iconInset);
    if (!CGRectEqualToRect(gPlusIcon.frame, iconFrame)) gPlusIcon.frame = iconFrame;
    if (!CGRectEqualToRect(gPlusHit.frame, bounds)) gPlusHit.frame = bounds;

    DKGlassSyncPlusIcon(gPlusButton);
}

// 抖音自绘底栏的内容隐去：背景层与按钮都不可见、不接收触摸，交互交给覆盖其上的玻璃底栏。
// 只动内容，不动底栏自身的 hidden/alpha——那是抖音的显隐状态，玻璃底栏靠继承跟随它。
//
// 驱动点是抖音底栏的 layoutSubviews，每帧都会走到这里，因此所有写入都必须先比较：
// 值没变还照写会让 UITabBar 反复重新布局，把系统的选中状态与长按拖动手势冲掉。
static void DKGlassSetDouyinContentVisible(AWENormalModeTabBar *douyinBar, NSArray *buttons, BOOL visible) {
    float opacity = visible ? 1.0f : 0.0f;
    NSArray *backdrops = @[ DKGlassValue(douyinBar, @"backgroundView") ?: NSNull.null,
                            DKGlassValue(douyinBar, @"awe_blurView") ?: NSNull.null,
                            DKGlassValue(douyinBar, @"separatorLine") ?: NSNull.null,
                            DKGlassValue(douyinBar, @"skinContainerView") ?: NSNull.null ];
    for (id backdrop in backdrops) {
        if (![backdrop isKindOfClass:UIView.class]) continue;
        CALayer *layer = ((UIView *)backdrop).layer;
        if (layer.opacity != opacity) layer.opacity = opacity;
    }
    for (id button in buttons) {
        if (![button isKindOfClass:UIView.class]) continue;
        UIView *view = button;
        if (view.layer.opacity != opacity) view.layer.opacity = opacity;
        if (view.userInteractionEnabled != visible) view.userInteractionEnabled = visible;
    }
}

// 4+1 参考态里胶囊的项目数：当前在镜像的项目，加上被「移除底栏项目」隐藏的。
// 抖音或其他插件自己藏起的按钮不算，那不是参考态的一部分。
static NSUInteger DKGlassReferenceCount(NSArray *buttons) {
    NSUInteger count = 0;
    for (id button in buttons) {
        UIView *view = [button isKindOfClass:UIView.class] ? button : nil;
        if (!view.superview) continue;
        if ([DKGlassValue(button, @"type") longLongValue] == kDKPlusButtonType) continue;
        if (!view.isHidden || DKTabBarRemovalHides(view)) count++;
    }
    return count;
}

#pragma mark - 挂载与拆除

// 整个功能只在 iOS 26 及以上成立——低版本没有 UIGlassEffect，装上去只是一条没有玻璃的
// UITabBar 盖住抖音底栏，比原生还差。故在此一处挡住，各 helper 用 API_AVAILABLE 标注。
static void DKGlassUpdate(AWENormalModeTabBar *douyinBar) API_AVAILABLE(ios(26.0)) {
    // 抖音换过底栏实例时，先把旧那条的内容还原——玻璃底栏只会跟着新实例走，
    // 旧实例的按钮若停在 opacity=0，它再次出现时就是一条空底栏。
    AWENormalModeTabBar *previousBar = gDouyinBar;
    if (previousBar && previousBar != douyinBar && gBar) {
        DKGlassSetDouyinContentVisible(
            previousBar, DKGlassValue(previousBar, @"tabBarButtons"), YES);
    }
    gDouyinBar = douyinBar;

    NSArray *buttons = DKGlassValue(douyinBar, @"tabBarButtons");
    if (!DKGlassTabBarEnabled()) {
        if (!gBar) return;
        DKGlassSetDouyinContentVisible(douyinBar, buttons, YES);
        [gBar removeFromSuperview];
        [gPlusKey removeFromSuperview];
        gBar = nil;
        gPlusKey = nil;
        gPlusIcon = nil;
        gPlusHit = nil;
        gPlusButton = nil;
        gPlusSourceIcon = nil;
        gProxy = nil;
        gItemKinds = nil;
        gItemButtons = nil;
        gSignature = nil;
        // 重新开启时材质与 platter 玻璃都要能重新装上；探测结果不复位，那是设备能力，一次为准。
        gGlassStyle = UIUserInterfaceStyleUnspecified;
        gInkStyle = UIUserInterfaceStyleUnspecified;
        gInkHostColor = nil;
        gPlusIconInkStyle = UIUserInterfaceStyleUnspecified;
        gPlatterGlassStyle = UIUserInterfaceStyleUnspecified;
        gPlatterGlassInstalled = nil;
        // 玻璃底栏是可视化的落位基准，它一撤可视化必须跟着撤，否则会留下一层孤儿视图。
        DKAudioVisualizerLayout(douyinBar);
        return;
    }
    // 场景监听不撤：handler 只在 gBar 存在时才动手，重新开启开关后照旧生效。

    UITabBarController *controller = DKGlassControllerForView(douyinBar);
    if (!controller) return;

    if (!gBar) {
        gProxy = [[DKGlassTabBarProxy alloc] init];
        // 不碰 appearance：实测出厂态与装了 Regular backgroundEffect 渲染逐像素相同，
        // 悬浮 provider 不读这个旧 API。材质统一由 DKGlassApplyPlatterGlass 决定。
        gBar = [[UITabBar alloc] initWithFrame:douyinBar.bounds];
        gBar.delegate = gProxy;
        gPlusKey = DKGlassMakePlusKey(gProxy);
    }

    // 作为子视图挂在抖音底栏内：显隐/透明度/位置全部随父视图继承。
    if (gBar.superview != douyinBar) [douyinBar addSubview:gBar];
    if (gPlusKey.superview != douyinBar) [douyinBar addSubview:gPlusKey];
    // 置顶兜底——其他插件遍历底栏子视图后可能改动层级。圆键在胶囊之上。
    if (douyinBar.subviews.lastObject != gPlusKey) {
        [douyinBar bringSubviewToFront:gBar];
        [douyinBar bringSubviewToFront:gPlusKey];
    }

    DKGlassObserveStyle(douyinBar);
    // 监听之外再逐帧比对一次：冷启动首帧与刚挂上时都没有 trait 变化事件可等。
    DKGlassApplyStyle(douyinBar.window.windowScene.traitCollection.userInterfaceStyle);
    // 取色排在最前：标题图按极性渲染，拍摄图标着色也要用这一步定下的极性。
    DKGlassApplyInk(DKGlassInkStyleFor(buttons, (NSInteger)controller.selectedIndex, gGlassStyle));
    DKGlassSyncItems(controller, buttons);
    DKGlassLayoutGlass(douyinBar, DKGlassReferenceCount(buttons));
    DKGlassSetDouyinContentVisible(douyinBar, buttons, NO);
    // 放在最后：可视化的环绕轮廓要用 DKGlassLayoutGlass 刚算完的胶囊与圆键几何。
    DKAudioVisualizerLayout(douyinBar);
}

void DKGlassTabBarRefresh(void) {
    AWENormalModeTabBar *bar = gDouyinBar;
    if (!bar) return;
    if (@available(iOS 26.0, *)) DKGlassUpdate(bar);
}

#pragma mark - Hook

%group DKGlassTabBarHooks

%hook AWENormalModeTabBar

- (void)layoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) DKGlassUpdate(self);
}

%end

// 角标变化不一定伴随底栏重新布局（收到推送时就不会），故在抖音写入角标的两个入口上
// 立即重跑一次同步。逐帧同步只兜稳态。
%hook AWENormalModeTabBarGeneralButton

- (id)p_showBadgeWithStyle:(unsigned long long)style count:(long long)count text:(id)text config:(id)config {
    id result = %orig;
    if (gBar) DKGlassSyncBadges();
    return result;
}

- (void)hideBadge {
    %orig;
    if (gBar) DKGlassSyncBadges();
}

%end

// 这两个子视图是其他插件改底栏内容的落点：DYYY 在 TextView 里写 label.text 改标题，
// 在 BadgeContainerView 里把 DUXBadge 隐掉。见 DKGlassScheduleMirror。
%hook AWENormalModeTabBarTextView

- (void)layoutSubviews {
    %orig;
    DKGlassScheduleMirror();
}

// 抖音写文字色的两个入口（类信息实证；首页那颗的 AWENormalModeTabBarFeedView 继承本类、
// 不重写这两个方法，所以一处覆盖全部四颗）。挂布局读到的必然是写入之前的旧值——写色本身
// 不触发布局，beta3 首页因此一直停在上一页的样本上。%orig 之后排一次补读，合并调度保证
// 一轮最多跑一趟。两处各自记数：若某一个长期为 0，说明它是多余的，可以删。
- (void)textColorChangedWithSelectedStatus:(BOOL)selected {
    %orig;
    gInkColorHits++;
    DKGlassScheduleMirror();
}

- (void)tabbarStatusDidChanged:(long long)status animated:(BOOL)animated {
    %orig;
    gInkStatusHits++;
    DKGlassScheduleMirror();
}

%end

%hook AWENormalModeTabBarBadgeContainerView

- (void)layoutSubviews {
    %orig;
    DKGlassScheduleMirror();
}

%end

%end

#pragma mark - 设置项注册

%ctor {
    DKSettingsRegister(DKKeyGlassTabBar, ^AWESettingItemModel *{
        // 选定后立刻生效，不必等抖音下一次布局。
        AWESettingItemModel *item = DKMakeGlassChoice(DKKeyGlassTabBar, DKKeyGlassTabBarClear, @"悬浮玻璃底栏", ^{
            AWENormalModeTabBar *bar = gDouyinBar;
            if (@available(iOS 26.0, *)) {
                if (!bar) return;
                // 材质变了但深浅色没变，DKGlassApplyStyle 会因档位相同而空转；
                // 复位它，让拍摄圆键的 effect 也跟着重建。
                gGlassStyle = UIUserInterfaceStyleUnspecified;
                DKGlassUpdate(bar);
            }
        });
        return DKSettingsWithInfo(item,
            @"悬浮底栏的材质：关闭时不显示悬浮玻璃底栏；模糊玻璃使用系统 Regular；清透玻璃显示更多背后视频细节。");
    });

    if (DKGlassOSAvailable()) {
        %init(DKGlassTabBarHooks);
    }
}
