//
//  DKFeedMenuGlass.xm
//  长按菜单：作品长按菜单液态玻璃 —— 面板外壳的模糊换成一层 Regular / Clear 玻璃。
//
//  实现：
//   - 面板外壳是 DUX 弹层的 DUXVisualEffectView（20pt 顶圆角、UIBlurEffect）；只处理装着
//     AWEVideoLongPressPanelViewController 的那一个，其余 DUX 弹层不动。
//   - 外壳 effect 记下后清空，contentView 最底层挂一块玻璃，满幅的面板底色视图隐藏；原生行的卡片常态底色去掉，
//     与玻璃融为一体，按下态保持原生高亮。
//   - 抖音给弹层与外壳 contentView 设了深色主题偏好；接管时取消偏好、之后的深色偏好也拦下，
//     菜单跟随抖音全局主题：浅色时文字与图标为黑色，深色时为白色。
//   - 玻璃深浅按菜单文字色判定：浅色文字（深色菜单）用深色玻璃。
//   - 抖音主题刷新会给 contentView 里的 effect view 重写一个 Regular 玻璃，玻璃上的 effect 写入一律换回当前材质；
//     外壳后续再写 effect 时也拦下。关闭开关后还原 effect、底色视图与深色偏好，并拿掉玻璃。
//

#import "DouyinHeaders.h"
#import "DKGlassFlexView.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKLongPressMenu.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const kDKFeedShellClass = @"DUXVisualEffectView";
static const CGFloat kDKFeedShellRadiusFloor = 20.0;

static char kDKShellEffectKey;     // 外壳原 effect（NSNull 表示原本就是 nil）
static char kDKShellGlassKey;      // 外壳上挂的玻璃
static char kDKShellPlateKey;      // 外壳里被隐藏的面板底色视图
static char kDKGlassStateKey;      // 玻璃当前材质「清透|外观」
static char kDKGlassEffectKey;     // 玻璃当前 effect；其它写入换回它
static char kDKThemeFollowKey;     // 该视图的深色主题偏好已改为跟随全局主题

static NSHashTable<UIVisualEffectView *> *gShells;
static NSString *gLastStatus = @"未接管";

static BOOL DKFeedGlassEnabled(void) {
    return DKGlassOSAvailable() && DKPrefBool(DKKeyFeedMenuGlass);
}

static UIVisualEffectView *DKFeedShell(UIView *view) {
    Class cls = NSClassFromString(kDKFeedShellClass);
    for (UIView *current = view.superview; cls && current; current = current.superview) {
        if ([current isKindOfClass:cls]) return (UIVisualEffectView *)current;
    }
    return nil;
}

// 菜单文字色是浅色时菜单是深色外观。
static UIUserInterfaceStyle DKFeedPanelStyle(UIView *view) {
    Class config = NSClassFromString(@"AWEModernLongPressPanelUIConfig");
    id color = [config respondsToSelector:@selector(itemTitleColor)]
        ? ((id (*)(id, SEL))objc_msgSend)(config, @selector(itemTitleColor)) : nil;
    if ([color isKindOfClass:UIColor.class]) {
        UIColor *resolved = [(UIColor *)color resolvedColorWithTraitCollection:view.traitCollection];
        CGFloat white = 0, alpha = 0;
        if ([resolved getWhite:&white alpha:&alpha]) {
            return white > 0.5 ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
        }
    }
    UIUserInterfaceStyle style = view.traitCollection.userInterfaceStyle;
    return style == UIUserInterfaceStyleUnspecified ? UIUserInterfaceStyleDark : style;
}

// 面板底色视图：contentView 里与它等大、没有子视图的普通 UIView（深色主题白 3%，浅色主题不透明浅灰）。
static UIView *DKFeedPlate(UIView *host, UIView *glass) {
    for (UIView *subview in host.subviews) {
        if (subview == glass || subview.subviews.count || ![subview isMemberOfClass:UIView.class]) continue;
        if (CGSizeEqualToSize(subview.bounds.size, host.bounds.size)) return subview;
    }
    return nil;
}

static BOOL DKFeedCanFollowTheme(UIView *view) {
    return [view respondsToSelector:@selector(awe_cancelPreferredTheme)]
        && [view respondsToSelector:@selector(awe_hasPreferredTheme)]
        && [view respondsToSelector:@selector(awe_preferDarkTheme)];
}

static void DKFeedFollowTheme(UIView *view) {
    if (!DKFeedCanFollowTheme(view)) return;
    if (!objc_getAssociatedObject(view, &kDKThemeFollowKey)) {
        objc_setAssociatedObject(view, &kDKThemeFollowKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if ([view awe_hasPreferredTheme]) [view awe_cancelPreferredTheme];
}

// 还原为抖音给这个菜单设的深色偏好。
static void DKFeedRestoreTheme(UIView *view) {
    if (!view || !objc_getAssociatedObject(view, &kDKThemeFollowKey)) return;
    objc_setAssociatedObject(view, &kDKThemeFollowKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [view awe_preferDarkTheme];
}

static BOOL DKFeedInGlassShell(UIView *view) {
    UIVisualEffectView *shell = DKFeedShell(view);
    return shell && objc_getAssociatedObject(shell, &kDKShellGlassKey) != nil;
}

// 卡片在接管前就可能取过底色：对面板里可见的原生行按当前状态重取一次。
static void DKFeedRefreshCards(UIView *root) {
    Class cellClass = NSClassFromString(@"AWELongPressPanelSettingCell");
    if (!cellClass || !root) return;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (![view isKindOfClass:UITableView.class]) {
            [queue addObjectsFromArray:view.subviews];
            continue;
        }
        for (UITableViewCell *cell in ((UITableView *)view).visibleCells) {
            if (![cell isKindOfClass:cellClass]) continue;
            AWELongPressPanelSettingCell *row = (AWELongPressPanelSettingCell *)cell;
            UIView *card = row.sectionBackgroundView;
            UIColor *color = [row sectionBackgroundColorForHighlighted:row.isHighlighted];
            if ([card isKindOfClass:UIView.class] && color && ![card.backgroundColor isEqual:color]) card.backgroundColor = color;
        }
    }
}

static void DKFeedRestoreShell(UIVisualEffectView *shell) {
    id original = objc_getAssociatedObject(shell, &kDKShellEffectKey);
    if (!original) return;
    UIView *glass = objc_getAssociatedObject(shell, &kDKShellGlassKey);
    [glass removeFromSuperview];
    objc_setAssociatedObject(shell, &kDKShellGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(shell, &kDKShellEffectKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *plate = objc_getAssociatedObject(shell, &kDKShellPlateKey);
    plate.hidden = NO;
    objc_setAssociatedObject(shell, &kDKShellPlateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKFeedRestoreTheme(shell.contentView);
    DKFeedRestoreTheme(shell.superview);
    shell.effect = original == NSNull.null ? nil : original;
    DKFeedRefreshCards(shell.contentView);
    [gShells removeObject:shell];
    gLastStatus = @"已还原";
}

static void DKFeedApplyGlass(UIVisualEffectView *shell, UIView *anchor) API_AVAILABLE(ios(26.0)) {
    UIView *host = shell.contentView;
    if (CGRectGetWidth(host.bounds) < 8.0 || CGRectGetHeight(host.bounds) < 8.0) return;

    if (!objc_getAssociatedObject(shell, &kDKShellEffectKey)) {
        objc_setAssociatedObject(shell, &kDKShellEffectKey, shell.effect ?: (id)NSNull.null,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gShells addObject:shell];
    }
    if (shell.effect) shell.effect = nil;

    BOOL clear = DKPrefBool(DKKeyFeedMenuGlassClear);
    UIUserInterfaceStyle style = DKFeedPanelStyle(anchor);
    DKGlassFlexView *glass = objc_getAssociatedObject(shell, &kDKShellGlassKey);
    BOOL fresh = glass == nil;
    if (fresh) {
        glass = [[DKGlassFlexView alloc] initWithEffect:nil];
        glass.userInteractionEnabled = NO;
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        CGFloat radius = MAX(shell.layer.cornerRadius, kDKFeedShellRadiusFloor);
        UICornerRadius *top = [UICornerRadius containerConcentricRadiusWithMinimum:radius];
        glass.cornerConfiguration = [UICornerConfiguration configurationWithUniformTopRadius:top
                                                                            bottomLeftRadius:nil
                                                                           bottomRightRadius:nil];
        glass.flexSourceView = host;
        objc_setAssociatedObject(shell, &kDKShellGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!CGRectEqualToRect(glass.frame, host.bounds)) glass.frame = host.bounds;
    if (host.subviews.firstObject != glass) [host insertSubview:glass atIndex:0];

    UIView *plate = objc_getAssociatedObject(shell, &kDKShellPlateKey) ?: DKFeedPlate(host, glass);
    if (plate) {
        objc_setAssociatedObject(shell, &kDKShellPlateKey, plate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!plate.hidden) plate.hidden = YES;
    }
    DKFeedFollowTheme(shell.superview);
    DKFeedFollowTheme(host);
    DKFeedRefreshCards(anchor);

    UIUserInterfaceStyle override = clear ? UIUserInterfaceStyleUnspecified : style;
    if (glass.overrideUserInterfaceStyle != override) glass.overrideUserInterfaceStyle = override;
    UIGlassEffect *current = [glass.effect isKindOfClass:UIGlassEffect.class] ? (UIGlassEffect *)glass.effect : nil;
    NSString *want = [NSString stringWithFormat:@"%d|%ld", clear, (long)style];
    if (!current || ![objc_getAssociatedObject(glass, &kDKGlassStateKey) isEqualToString:want]) {
        UIGlassEffect *effect = [UIGlassEffect effectWithStyle:clear ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular];
        effect.tintColor = clear ? DKGlassTintForStyle(style) : nil;
        effect.interactive = YES;
        void (^install)(void) = ^{
            objc_setAssociatedObject(glass, &kDKGlassEffectKey, effect, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            glass.effect = effect;
        };
        if (fresh) [UIView animateWithDuration:0.25 animations:install];
        else install();
        objc_setAssociatedObject(glass, &kDKGlassStateKey, want, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    BOOL themed = DKFeedCanFollowTheme(host) && ![host awe_hasPreferredTheme];
    gLastStatus = [NSString stringWithFormat:@"已接管  %@  %@  外壳 %@  底色%@  主题%@", clear ? @"清透" : @"模糊",
                   style == UIUserInterfaceStyleDark ? @"深色" : @"浅色", NSStringFromCGRect(shell.frame),
                   plate ? @"已隐藏" : @"未找到", themed ? @"跟随全局" : @"未跟随"];
}

static void DKFeedSyncGlass(UIViewController *panel) {
    if (!panel.isViewLoaded) return;
    UIVisualEffectView *shell = DKFeedShell(panel.view);
    if (!shell) return;
    if (!DKFeedGlassEnabled()) {
        DKFeedRestoreShell(shell);
        return;
    }
    if (@available(iOS 26.0, *)) DKFeedApplyGlass(shell, panel.view);
}

NSString *DKFeedMenuGlassStatus(void) {
    if (!DKGlassOSAvailable()) return @"系统低于 iOS 26，不安装";
    NSString *setting = !DKPrefBool(DKKeyFeedMenuGlass) ? @"关闭"
                      : (DKPrefBool(DKKeyFeedMenuGlassClear) ? @"清透玻璃" : @"模糊玻璃");
    return [NSString stringWithFormat:@"设置 %@  在场外壳 %lu  %@", setting,
            (unsigned long)gShells.allObjects.count, gLastStatus];
}

%group DKFeedMenuGlassHooks

%hook AWEVideoLongPressPanelViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    DKFeedSyncGlass(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    DKFeedSyncGlass(self);
}

%end

%hook AWELongPressPanelSettingCell

// 接管中的菜单里，卡片的常态底色去掉；按下态保持原生。
- (UIColor *)sectionBackgroundColorForHighlighted:(BOOL)highlighted {
    UIColor *color = %orig;
    if (highlighted || !DKFeedGlassEnabled() || !DKFeedInGlassShell(self)) return color;
    return UIColor.clearColor;
}

%end

%hook UIVisualEffectView

// 玻璃上的其它 effect 写入换回当前材质；接管中的外壳再被写回模糊时，记为新的原 effect，外壳保持无 effect。
- (void)setEffect:(UIVisualEffect *)effect {
    if (DKFeedGlassEnabled()) {
        UIVisualEffect *locked = objc_getAssociatedObject(self, &kDKGlassEffectKey);
        if (locked && effect != locked) {
            %orig(locked);
            return;
        }
        if (effect && objc_getAssociatedObject(self, &kDKShellEffectKey)) {
            objc_setAssociatedObject(self, &kDKShellEffectKey, effect, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            %orig(nil);
            return;
        }
    }
    %orig;
}

%end

%end

%group DKFeedMenuThemeHooks

%hook UIView

// 接管中的弹层与外壳 contentView 再被设深色偏好时，保持跟随全局主题。
- (void)awe_preferDarkTheme {
    if (objc_getAssociatedObject(self, &kDKThemeFollowKey) && DKFeedGlassEnabled()) {
        if ([self awe_hasPreferredTheme]) [self awe_cancelPreferredTheme];
        return;
    }
    %orig;
}

%end

%end

%ctor {
    gShells = [NSHashTable weakObjectsHashTable];
    DKSettingsRegister(DKKeyFeedMenuGlass, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeGlassChoice(DKKeyFeedMenuGlass, DKKeyFeedMenuGlassClear, @"长按菜单液态玻璃", nil);
        return DKSettingsWithInfo(item,
            @"视频与图文长按菜单的材质：关闭时保持抖音原生样式；模糊玻璃使用系统 Regular；清透玻璃显示更多背后视频细节。"
            @"开启后菜单文字与图标跟随抖音的深浅色：浅色模式为黑色，深色模式为白色。"
            @"下次打开长按菜单时生效。评论的长按菜单跟随「分享面板液态玻璃」。");
    });
    if (!DKGlassOSAvailable()) return;
    %init(DKFeedMenuGlassHooks);
    if ([UIView instancesRespondToSelector:@selector(awe_preferDarkTheme)]
        && [UIView instancesRespondToSelector:@selector(awe_cancelPreferredTheme)]
        && [UIView instancesRespondToSelector:@selector(awe_hasPreferredTheme)]) {
        %init(DKFeedMenuThemeHooks);
    }
}
