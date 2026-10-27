//
//  DKUnreadBadge.xm
//  功能：未读红点 —— 移除底栏按钮、首页顶栏频道、左侧栏（≡ 入口与侧边栏面板）的点状 / 数字 / 文字红点，
//  三处各一个开关。
//
//  实现：
//   - 三处红点都是 DUXBadge，按所在容器认区域：底栏 AWENormalModeTabBarBadgeContainerView、
//     顶栏频道 AWEHPTopTabItemBadgeContentView、左侧栏入口 AWELeftSideBarEntranceView（首页、消息页、
//     个人主页的 ≡ 同类）、侧边栏面板 AWELeftSideBarBaseCollectionViewCell。
//   - 抖音照常创建、显示与清除红点，本模块只接管显隐写入：开关打开且红点在对应区域时，setHidden: 记下
//     抖音要的值、实际写 YES；挂进父视图或随容器进入窗口时按当前值重写一次（新建的红点不经 setHidden:）。
//     关闭开关后写回记下的值。
//   - 抖音按红点 hidden 判断的状态随之生效：底栏 p_isAvatarBadge 与顶栏 p_enableAvatarBadgeHollowDisplay
//     不再给头像镂空，玻璃底栏的角标镜像跳过隐藏的红点。
//   - 区域内的红点登记到弱引用表，开关切换后即时刷新，并让所在容器重新布局以重算上述状态。
//   - 设置项登记在本文件 %ctor，布局见 DKSettingsLayout.m「界面精简 › 未读红点」。
//

#import "DKUnreadBadge.h"
#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import <objc/runtime.h>

// 抖音写给红点的 hidden：只在本模块接管期间保存，交还时清除。
static char kDKUnreadBadgeHostHiddenKey;
static NSHashTable<DUXBadge *> *gDKUnreadBadges;

static NSString *DKUnreadBadgeKeyForContainer(UIView *view) {
    if ([view isKindOfClass:%c(AWENormalModeTabBarBadgeContainerView)]) return DKKeyTabBarRemoveBadge;
    if ([view isKindOfClass:%c(AWEHPTopTabItemBadgeContentView)]) return DKKeyTopBarRemoveBadge;
    if ([view isKindOfClass:%c(AWELeftSideBarEntranceView)]
        || [view isKindOfClass:%c(AWELeftSideBarBaseCollectionViewCell)]) return DKKeySideBarRemoveBadge;
    return nil;
}

// 沿父视图找红点所在区域的容器，返回该区域的开关键；不在三处区域内返回 nil。
static NSString *DKUnreadBadgeRegion(UIView *badge, UIView **container) {
    for (UIView *view = badge.superview; view; view = view.superview) {
        NSString *key = DKUnreadBadgeKeyForContainer(view);
        if (!key) continue;
        if (container) *container = view;
        return key;
    }
    return nil;
}

// 红点此刻是否由本模块藏起。三个开关都关时不遍历父视图。
static BOOL DKUnreadBadgeRemoved(UIView *badge) {
    if (!DKPrefBool(DKKeyTabBarRemoveBadge) && !DKPrefBool(DKKeyTopBarRemoveBadge)
        && !DKPrefBool(DKKeySideBarRemoveBadge)) {
        return NO;
    }
    NSString *key = DKUnreadBadgeRegion(badge, NULL);
    return key && DKPrefBool(key);
}

// 按开关接管或交还区域内红点的显隐，状态有变时返回所在容器。经 setHidden: 重写一次：接管时写入
// 抖音当前的值（钩子记下后实际写 YES），交还时写回记下的值。
static UIView *DKUnreadBadgeApply(DUXBadge *badge) {
    UIView *container = nil;
    NSString *key = DKUnreadBadgeRegion(badge, &container);
    if (!key) return nil;
    if (!gDKUnreadBadges) gDKUnreadBadges = [NSHashTable weakObjectsHashTable];
    [gDKUnreadBadges addObject:badge];

    NSNumber *hostHidden = objc_getAssociatedObject(badge, &kDKUnreadBadgeHostHiddenKey);
    BOOL removed = DKPrefBool(key);
    if (removed == (hostHidden != nil)) return nil;
    badge.hidden = removed ? badge.isHidden : hostHidden.boolValue;
    return container;
}

static void DKUnreadBadgeRefresh(void) {
    for (DUXBadge *badge in gDKUnreadBadges.allObjects) {
        UIView *container = DKUnreadBadgeApply(badge);
        // 抖音按红点 hidden 重算：底栏按钮布局时的头像镂空、顶栏频道更新约束时的头像镂空、
        // 玻璃底栏在红点容器布局时的角标镜像。
        [container setNeedsLayout];
        [container.superview setNeedsLayout];
        [container.superview setNeedsUpdateConstraints];
    }
}

static NSString *DKUnreadBadgeRegionName(NSString *key) {
    if ([key isEqualToString:DKKeyTabBarRemoveBadge]) return @"底栏";
    if ([key isEqualToString:DKKeyTopBarRemoveBadge]) return @"顶栏";
    return @"左侧栏";
}

NSString *DKUnreadBadgeStatus(void) {
    NSArray<DUXBadge *> *badges = gDKUnreadBadges.allObjects;
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"底栏=%@  顶栏=%@  左侧栏=%@  已登记红点=%lu\n",
        DKPrefBool(DKKeyTabBarRemoveBadge) ? @"移除" : @"显示",
        DKPrefBool(DKKeyTopBarRemoveBadge) ? @"移除" : @"显示",
        DKPrefBool(DKKeySideBarRemoveBadge) ? @"移除" : @"显示", (unsigned long)badges.count];
    for (DUXBadge *badge in badges) {
        UIView *container = nil;
        NSString *key = DKUnreadBadgeRegion(badge, &container);
        if (!key || !badge.window) continue;
        NSNumber *hostHidden = objc_getAssociatedObject(badge, &kDKUnreadBadgeHostHiddenKey);
        [out appendFormat:@"  %@ %@ frame=%@ 文字=%@ 数字=%llu hidden=%d 抖音要的=%@\n",
            DKUnreadBadgeRegionName(key), NSStringFromClass(container.class),
            NSStringFromCGRect([badge convertRect:badge.bounds toView:nil]), badge.badgeText ?: @"",
            badge.badgeNumber, badge.isHidden,
            hostHidden ? (hostHidden.boolValue ? @"隐藏" : @"显示") : @"未接管"];
    }
    return out;
}

%hook DUXBadge

- (void)setHidden:(BOOL)hidden {
    if (DKUnreadBadgeRemoved(self)) {
        objc_setAssociatedObject(self, &kDKUnreadBadgeHostHiddenKey, @(hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        %orig(YES);
        return;
    }
    objc_setAssociatedObject(self, &kDKUnreadBadgeHostHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
}

// 新建的红点不经 setHidden:；挂进区域容器或随容器进入窗口时补一次。
- (void)didMoveToSuperview {
    %orig;
    DKUnreadBadgeApply(self);
}

- (void)didMoveToWindow {
    %orig;
    if (self.window) DKUnreadBadgeApply(self);
}

%end

static AWESettingItemModel *DKUnreadBadgeSwitch(NSString *key, NSString *title, NSString *detail) {
    return DKSettingsOnChange(DKMakeSwitch(key, title, detail), ^{
        DKUnreadBadgeRefresh();
    });
}

%ctor {
    %init;
    DKSettingsRegister(DKKeyTabBarRemoveBadge, ^AWESettingItemModel *{
        return DKUnreadBadgeSwitch(DKKeyTabBarRemoveBadge, @"移除底栏未读红点",
            @"底栏各按钮上的红点、数字与文字角标都不显示，悬浮玻璃底栏一并生效。只是不显示，未读状态不变；关闭后立即恢复。");
    });
    DKSettingsRegister(DKKeyTopBarRemoveBadge, ^AWESettingItemModel *{
        return DKUnreadBadgeSwitch(DKKeyTopBarRemoveBadge, @"移除顶栏未读红点",
            @"首页顶栏各频道上的红点、数字与文字角标（如「关注」右上角的「直播」）都不显示。"
            @"只是不显示，未读状态不变；关闭后立即恢复。");
    });
    DKSettingsRegister(DKKeySideBarRemoveBadge, ^AWESettingItemModel *{
        return DKUnreadBadgeSwitch(DKKeySideBarRemoveBadge, @"移除左侧栏未读红点",
            @"侧边栏入口（≡，首页、消息页与个人主页）与展开后侧边栏里的红点、数字角标都不显示。"
            @"只是不显示，未读状态不变；关闭后立即恢复。");
    });
}
