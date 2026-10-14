//
//  DKTopBarEntrance.xm
//  功能：顶栏入口 —— 左侧栏入口（≡）与搜索图标的隐藏 / 移除。
//
//  实现：
//   - 槽位是 AWEHPTopBarCTAItemView，按子树里的 AWELeftSideBarEntranceView /
//     AWEHPDiscoverFeedEntranceView 判定是哪个入口。
//   - 隐藏：槽位 layer 挂一个空 mask，入口连同红点都不绘制；命中测试不受 mask 影响，点击照常。
//     槽位自身的 hitTest 在 customView 隐藏或近乎透明时返回 nil，故不改 hidden / alpha。
//   - 移除：在隐藏的基础上让槽位 hitTest 返回 nil，触摸交给下层视图。
//   - layoutSubviews / didMoveToWindow 时按当前设置挂上或摘掉自己的 mask，从设置页返回首页即生效。
//   - 评论区打开时的搜索图标副本由 AWEHPTopBarSearchEntranceController 配置，跟随搜索图标设置：
//     隐藏同样挂空 mask；移除另关掉副本的交互，触摸交给下层视图。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import <objc/runtime.h>

typedef NS_ENUM(NSInteger, DKTopBarEntranceKind) {
    DKTopBarEntranceNone = 0,
    DKTopBarEntranceSideBar,
    DKTopBarEntranceSearch,
};

typedef NS_ENUM(NSInteger, DKTopBarEntranceMode) {
    DKTopBarEntranceShown = 0,
    DKTopBarEntranceHidden,
    DKTopBarEntranceRemoved,
};

static char kDKEntranceKindKey;
static char kDKEntranceMaskKey;
static char kDKEntranceInteractionKey;

// 槽位子树只有两三层，按类名找入口视图。
static DKTopBarEntranceKind DKEntranceKindInView(UIView *view, NSInteger depth) {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:%c(AWELeftSideBarEntranceView)]) return DKTopBarEntranceSideBar;
        if ([sub isKindOfClass:%c(AWEHPDiscoverFeedEntranceView)]) return DKTopBarEntranceSearch;
        if (depth > 1) {
            DKTopBarEntranceKind kind = DKEntranceKindInView(sub, depth - 1);
            if (kind != DKTopBarEntranceNone) return kind;
        }
    }
    return DKTopBarEntranceNone;
}

static DKTopBarEntranceMode DKEntranceMode(DKTopBarEntranceKind kind) {
    NSString *key = kind == DKTopBarEntranceSideBar ? DKKeyTopBarSideBarMode
                  : kind == DKTopBarEntranceSearch ? DKKeyTopBarSearchMode : nil;
    if (!key) return DKTopBarEntranceShown;
    NSInteger mode = DKPrefInteger(key);
    if (mode == DKTopBarEntranceHidden) return DKTopBarEntranceHidden;
    if (mode == DKTopBarEntranceRemoved) return DKTopBarEntranceRemoved;
    return DKTopBarEntranceShown;
}

// 槽位类型记在关联对象上，hitTest 直接读，不在每次触摸时遍历子树。
static DKTopBarEntranceKind DKEntranceRefreshKind(UIView *item) {
    DKTopBarEntranceKind kind = DKEntranceKindInView(item, 3);
    objc_setAssociatedObject(item, &kDKEntranceKindKey, kind ? @(kind) : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return kind;
}

static DKTopBarEntranceKind DKEntranceCachedKind(UIView *item) {
    return (DKTopBarEntranceKind)[objc_getAssociatedObject(item, &kDKEntranceKindKey) integerValue];
}

// 挂上或摘掉自己的空 mask；摘时只摘自己挂的，已有的其他 mask 不覆盖。
static void DKEntranceSetMasked(UIView *view, BOOL masked) {
    CALayer *ours = objc_getAssociatedObject(view, &kDKEntranceMaskKey);

    if (!masked) {
        if (!ours) return;
        if (view.layer.mask == ours) view.layer.mask = nil;
        objc_setAssociatedObject(view, &kDKEntranceMaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    if (view.layer.mask && view.layer.mask != ours) return;
    if (!ours) {
        ours = [CALayer layer];
        objc_setAssociatedObject(view, &kDKEntranceMaskKey, ours, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (view.layer.mask != ours) view.layer.mask = ours;
}

static void DKEntranceApply(UIView *item) {
    DKTopBarEntranceMode mode = DKEntranceMode(DKEntranceRefreshKind(item));
    DKEntranceSetMasked(item, mode != DKTopBarEntranceShown);
}

// 移除时关掉副本交互；恢复时只还原自己关掉的。
static void DKEntranceApplySearchCopy(UIView *copy) {
    if (![copy isKindOfClass:UIView.class]) return;
    DKTopBarEntranceMode mode = DKEntranceMode(DKTopBarEntranceSearch);
    DKEntranceSetMasked(copy, mode != DKTopBarEntranceShown);

    BOOL disabledByUs = [objc_getAssociatedObject(copy, &kDKEntranceInteractionKey) boolValue];
    if (mode == DKTopBarEntranceRemoved) {
        if (!copy.userInteractionEnabled) return;
        copy.userInteractionEnabled = NO;
        objc_setAssociatedObject(copy, &kDKEntranceInteractionKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (disabledByUs) {
        copy.userInteractionEnabled = YES;
        objc_setAssociatedObject(copy, &kDKEntranceInteractionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%hook AWEHPTopBarCTAItemView

- (void)layoutSubviews {
    %orig;
    DKEntranceApply(self);
}

- (void)didMoveToWindow {
    %orig;
    if (self.window) DKEntranceApply(self);
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (DKEntranceMode(DKEntranceCachedKind(self)) == DKTopBarEntranceRemoved) return nil;
    return %orig;
}

%end

// 评论区每次打开都会重新配置副本，设置改动在下次打开评论区时生效。
%hook AWEHPTopBarSearchEntranceController

- (void)setupCopyFeedDiscoverEntranceView:(UIView *)view {
    %orig;
    DKEntranceApplySearchCopy(view);
}

%end
