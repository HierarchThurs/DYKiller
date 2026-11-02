//
//  DKTopBarGlass.xm
//  功能：顶栏液态玻璃 —— 左侧栏与搜索入口改为圆钮，频道条放进长胶囊。
//
//  实现：
//   - 几何走原生配置：槽位内边距写进 AWEHPTopTabCTAItemLayoutConfig 后调 updateConfig:，
//     由原生约束排出槽位，频道条随之收窄并按内容居中；关闭时写回原值。
//   - 玻璃都是对应原生视图的子视图，hidden / alpha / 隐藏移除的 mask 沿视图树继承。
//   - 亮度跟 isLightTheme：频道文字与图标由抖音按页面底色决定，玻璃取相同明暗保证可读。
//   - 频道胶囊与手势见 DKTopChannelCapsule。
//

#import "DKTopBarGlass.h"

#import "DKGlassGuard.h"
#import "DKAdjustRange.h"
#import "DKKeys.h"
#import "DKTopBarGlassMetrics.h"
#import "DKTopChannelCapsule.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"
#import "DouyinHeaders.h"
#import <objc/runtime.h>

static char kDKTopBarGlassStateKey;
static char kDKTopBarGlassCapsuleKey;
static char kDKTopBarGlassCircleKey;
static char kDKTopBarGlassConfigOriginalKey;
static char kDKTopBarGlassCopyKey;

static const CGFloat kDKTopBarGlassCircleHitOutset = 4.0;

static NSHashTable<AWEFeedTopBarContainer *> *gDKTopBarGlassContainers;

static BOOL DKTopBarGlassEnabled(void) {
    return DKGlassOSAvailable() && DKPrefBool(DKKeyTopBarGlass);
}

static CGFloat DKTopBarGlassScale(NSString *key) {
    return DKAdjustValue(key) / 100.0;
}

#pragma mark - 槽位配置

static void DKTopBarGlassSetConfig(AWEHPTopTabCTAItemLayoutConfig *config, const CGFloat values[4]) {
    config.leftMargin = values[0];
    config.leftPadding = values[1];
    config.rightPadding = values[2];
    config.rightMargin = values[3];
}

// 原值只在首次接管时记下；抖音换了配置对象时，新对象重新记录。
static void DKTopBarGlassApplySlot(AWEHPTopBarCTAItemView *item, CGFloat leftPadding, CGFloat rightPadding, CGFloat rightMargin) {
    AWEHPTopTabCTAItemLayoutConfig *config = item.config;
    if (!config) return;
    if (!objc_getAssociatedObject(config, &kDKTopBarGlassConfigOriginalKey)) {
        NSArray *original = @[ @(config.leftMargin), @(config.leftPadding), @(config.rightPadding), @(config.rightMargin) ];
        objc_setAssociatedObject(config, &kDKTopBarGlassConfigOriginalKey, original, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    const CGFloat values[4] = { 0.0, leftPadding, rightPadding, rightMargin };
    if (fabs(config.leftMargin - values[0]) < 0.01 && fabs(config.leftPadding - values[1]) < 0.01
        && fabs(config.rightPadding - values[2]) < 0.01 && fabs(config.rightMargin - values[3]) < 0.01) return;
    DKTopBarGlassSetConfig(config, values);
    [item updateConfig:config];
}

static void DKTopBarGlassRestoreSlot(AWEHPTopBarCTAItemView *item) {
    AWEHPTopTabCTAItemLayoutConfig *config = item.config;
    NSArray<NSNumber *> *original = config ? objc_getAssociatedObject(config, &kDKTopBarGlassConfigOriginalKey) : nil;
    if (!original) return;
    const CGFloat values[4] = { original[0].doubleValue, original[1].doubleValue, original[2].doubleValue, original[3].doubleValue };
    DKTopBarGlassSetConfig(config, values);
    objc_setAssociatedObject(config, &kDKTopBarGlassConfigOriginalKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [item updateConfig:config];
}

#pragma mark - 圆钮

static void DKTopBarGlassPlaceCircle(AWEHPTopBarCTAItemView *item, CGFloat centerX, CGFloat diameter,
                                     DKTopBarGlassMaterial material) API_AVAILABLE(ios(26.0)) {
    UIVisualEffectView *circle = objc_getAssociatedObject(item, &kDKTopBarGlassCircleKey);
    if (!circle) {
        circle = DKTopBarGlassMakeView(item);
        objc_setAssociatedObject(item, &kDKTopBarGlassCircleKey, circle, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [item insertSubview:circle atIndex:0];
    }
    CGRect frame = CGRectMake(centerX - diameter / 2.0, CGRectGetMidY(item.bounds) - diameter / 2.0, diameter, diameter);
    if (!CGRectEqualToRect(circle.frame, frame)) circle.frame = frame;
    DKTopBarGlassApplyMaterial(circle, material, nil, YES);
    DKAdjustTransform(item.customView, CGAffineTransformMakeScale(diameter / kDKTopBarGlassBaseHeight,
                                                                  diameter / kDKTopBarGlassBaseHeight));
}

static void DKTopBarGlassRemoveCircle(AWEHPTopBarCTAItemView *item) {
    UIView *circle = objc_getAssociatedObject(item, &kDKTopBarGlassCircleKey);
    if (!circle) return;
    [circle removeFromSuperview];
    objc_setAssociatedObject(item, &kDKTopBarGlassCircleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKAdjustTransform(item.customView, CGAffineTransformIdentity);
}

BOOL DKTopBarGlassSlotRejectsPoint(UIView *item, CGPoint point) {
    UIView *circle = objc_getAssociatedObject(item, &kDKTopBarGlassCircleKey);
    return circle && !CGRectContainsPoint(CGRectInset(circle.frame, -kDKTopBarGlassCircleHitOutset,
                                                      -kDKTopBarGlassCircleHitOutset), point);
}

#pragma mark - 同步

static AWEHPTopBarCTAItemView *DKTopBarGlassSearchItem(AWEFeedTopBarContainer *container) {
    UIView *item = container.discoverEntranceContentView;
    return [item isKindOfClass:%c(AWEHPTopBarCTAItemView)] ? (AWEHPTopBarCTAItemView *)item : nil;
}

static AWEHPTopBarCTAItemView *DKTopBarGlassSideBarItem(AWEFeedTopBarContainer *container) {
    UIView *item = container.leftContentView;
    return [item isKindOfClass:%c(AWEHPTopBarCTAItemView)] ? (AWEHPTopBarCTAItemView *)item : nil;
}

static DKTopChannelCapsule *DKTopBarGlassCapsule(UIView *control) API_AVAILABLE(ios(26.0)) {
    return objc_getAssociatedObject(control, &kDKTopBarGlassCapsuleKey);
}

static void DKTopBarGlassTeardown(AWEFeedTopBarContainer *container) API_AVAILABLE(ios(26.0)) {
    // 写回配置可能同步触发布局，先清状态，重入时直接返回。
    objc_setAssociatedObject(container, &kDKTopBarGlassStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    AWEFeedMultiTabSegmentedControl *control = container.segmentControlView;
    [DKTopBarGlassCapsule(control) invalidate];
    objc_setAssociatedObject(control, &kDKTopBarGlassCapsuleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    AWEHPTopBarCTAItemView *left = DKTopBarGlassSideBarItem(container);
    AWEHPTopBarCTAItemView *right = DKTopBarGlassSearchItem(container);
    DKTopBarGlassRemoveCircle(left);
    DKTopBarGlassRestoreSlot(left);
    DKTopBarGlassRemoveCircle(right);
    DKTopBarGlassRestoreSlot(right);
}

static void DKTopBarGlassSync(AWEFeedTopBarContainer *container) API_AVAILABLE(ios(26.0)) {
    if (!container) return;
    if (!DKTopBarGlassEnabled()) {
        if (objc_getAssociatedObject(container, &kDKTopBarGlassStateKey)) DKTopBarGlassTeardown(container);
        return;
    }
    // 下面的布局与 updateConfig: 可能同步回到这里，重入时由外层这一轮收尾。
    NSNumber *syncing = objc_getAssociatedObject(container, &kDKTopBarGlassStateKey);
    if (syncing.boolValue) return;
    AWEFeedMultiTabSegmentedControl *control = container.segmentControlView;
    UIScrollView *scrollView = control.multiTabSegmentedControlScollWrapperView;
    if (!control || !scrollView) return;
    objc_setAssociatedObject(container, &kDKTopBarGlassStateKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 布局由外向内，此时内容宽度与频道条 frame 可能还是旧值。
    [control layoutIfNeeded];
    [scrollView layoutIfNeeded];

    if (!gDKTopBarGlassContainers) gDKTopBarGlassContainers = [NSHashTable weakObjectsHashTable];
    [gDKTopBarGlassContainers addObject:container];

    DKTopChannelCapsule *capsule = DKTopBarGlassCapsule(control);
    if (!capsule) {
        capsule = [[DKTopChannelCapsule alloc] initWithControl:control];
        objc_setAssociatedObject(control, &kDKTopBarGlassCapsuleKey, capsule, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    AWEHPTopBarCTAItemView *left = DKTopBarGlassSideBarItem(container);
    AWEHPTopBarCTAItemView *right = DKTopBarGlassSearchItem(container);
    DKTopBarGlassMetrics metrics = DKTopBarGlassComputeMetrics((DKTopBarGlassInput){
        .containerWidth = CGRectGetWidth(container.bounds),
        .contentWidth = scrollView.contentSize.width,
        .heightScale = DKTopBarGlassScale(DKKeyTopBarGlassHeight),
        .lengthScale = DKTopBarGlassScale(DKKeyTopBarGlassLength),
    });
    DKTopBarGlassMaterial material = { DKPrefBool(DKKeyTopBarGlassClear), control.isLightTheme };

    // 入口图标靠内边距定位到圆钮中心，其余宽度补给槽位，两侧槽位等宽保持频道条居中。
    if (left) {
        CGFloat icon = CGRectGetWidth(left.customView.bounds);
        CGFloat leftPadding = metrics.leftCenterX - icon / 2.0;
        DKTopBarGlassApplySlot(left, leftPadding, 0.0, metrics.slotWidth - leftPadding - icon);
        DKTopBarGlassPlaceCircle(left, metrics.leftCenterX, metrics.height, material);
    }
    if (right) {
        CGFloat icon = CGRectGetWidth(right.customView.bounds);
        CGFloat leftPadding = metrics.rightCenterX - icon / 2.0;
        DKTopBarGlassApplySlot(right, leftPadding, metrics.slotWidth - leftPadding - icon, 0.0);
        DKTopBarGlassPlaceCircle(right, metrics.rightCenterX, metrics.height, material);
    }

    // 这一轮改了槽位时频道条 frame 还是旧值，约束变化会再来一轮布局，同一帧内收敛。
    CGRect strip = [scrollView.superview convertRect:scrollView.frame toView:control];
    CGRect capsuleFrame = CGRectMake(CGRectGetMinX(strip) - kDKTopBarGlassCapsuleInset,
                                     CGRectGetMidY(strip) - metrics.height / 2.0,
                                     CGRectGetWidth(strip) + kDKTopBarGlassCapsuleInset * 2.0, metrics.height);
    [capsule applyMaterial:material];
    [capsule layoutCapsuleFrame:capsuleFrame pillHeight:metrics.height - kDKTopBarGlassCapsuleInset * 2.0];

    objc_setAssociatedObject(container, &kDKTopBarGlassStateKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void DKTopBarGlassRefresh(void) {
    if (@available(iOS 26.0, *)) {
        for (AWEFeedTopBarContainer *container in gDKTopBarGlassContainers.allObjects) {
            DKTopBarGlassSync(container);
            [container setNeedsLayout];
        }
    }
}

#pragma mark - 评论区搜索图标副本

void DKTopBarGlassApplySearchCopy(UIView *copy, BOOL visible) {
    if (@available(iOS 26.0, *)) {
        UIVisualEffectView *circle = objc_getAssociatedObject(copy, &kDKTopBarGlassCopyKey);
        CGFloat diameter = DKTopBarGlassComputeMetrics((DKTopBarGlassInput){
            .heightScale = DKTopBarGlassScale(DKKeyTopBarGlassHeight) }).height;
        CGFloat scale = diameter / kDKTopBarGlassBaseHeight;
        if (!visible || !DKTopBarGlassEnabled()) {
            [circle removeFromSuperview];
            objc_setAssociatedObject(copy, &kDKTopBarGlassCopyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            for (UIView *sub in copy.subviews) DKAdjustTransform(sub, CGAffineTransformIdentity);
            return;
        }
        if (!circle) {
            circle = DKTopBarGlassMakeView(copy);
            objc_setAssociatedObject(copy, &kDKTopBarGlassCopyKey, circle, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [copy insertSubview:circle atIndex:0];
        }
        CGRect bounds = copy.bounds;
        circle.frame = CGRectMake(CGRectGetMidX(bounds) - diameter / 2.0, CGRectGetMidY(bounds) - diameter / 2.0, diameter, diameter);
        DKTopBarGlassMaterial material = { DKPrefBool(DKKeyTopBarGlassClear), NO };
        DKTopBarGlassApplyMaterial(circle, material, nil, YES);
        for (UIView *sub in copy.subviews) {
            if (sub != circle) DKAdjustTransform(sub, CGAffineTransformMakeScale(scale, scale));
        }
    }
}

#pragma mark - 诊断

NSString *DKTopBarGlassStatus(void) {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"开关=%d 清透=%d 高度=%ld%% 长度=%ld%% 系统可用=%d\n",
        DKPrefBool(DKKeyTopBarGlass), DKPrefBool(DKKeyTopBarGlassClear),
        (long)DKAdjustValue(DKKeyTopBarGlassHeight), (long)DKAdjustValue(DKKeyTopBarGlassLength),
        DKGlassOSAvailable()];
    if (@available(iOS 26.0, *)) {
        for (AWEFeedTopBarContainer *container in gDKTopBarGlassContainers.allObjects) {
            AWEFeedMultiTabSegmentedControl *control = container.segmentControlView;
            UIScrollView *scrollView = control.multiTabSegmentedControlScollWrapperView;
            UIView *left = objc_getAssociatedObject(DKTopBarGlassSideBarItem(container), &kDKTopBarGlassCircleKey);
            UIView *right = objc_getAssociatedObject(DKTopBarGlassSearchItem(container), &kDKTopBarGlassCircleKey);
            UIView *pill = DKTopBarGlassCapsule(control).pillView;
            [out appendFormat:@"  容器=%@ 频道条=%@ 内容宽=%.1f 偏移=%.1f 选中=%lld 浅色页=%d\n",
                NSStringFromCGRect(container.frame), NSStringFromCGRect(control.frame), scrollView.contentSize.width,
                scrollView.contentOffset.x, control.selectedIndex, control.isLightTheme];
            [out appendFormat:@"  左圆钮=%@ 右圆钮=%@ 选中块=%@ 隐藏=%d\n",
                left ? NSStringFromCGRect(left.frame) : @"无", right ? NSStringFromCGRect(right.frame) : @"无",
                pill ? NSStringFromCGRect(pill.frame) : @"无", pill.isHidden];
        }
    }
    return out;
}

%group DKTopBarGlassHooks

%hook AWEFeedTopBarContainer

- (void)layoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) DKTopBarGlassSync(self);
}

- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;
    if (@available(iOS 26.0, *)) DKTopBarGlassSync(self);
}

%end

%hook AWEFeedMultiTabSegmentedControl

// 频道增减或改名后内容宽度变化，按新内容重排整组。
- (void)layoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) {
        if (!DKTopBarGlassCapsule(self)) return;
        UIView *container = self.superview.superview;
        if ([container isKindOfClass:%c(AWEFeedTopBarContainer)]) DKTopBarGlassSync((AWEFeedTopBarContainer *)container);
    }
}

- (void)layoutSelectedLineViewWithIndex:(long long)index {
    %orig;
    if (@available(iOS 26.0, *)) [DKTopBarGlassCapsule(self) selectionDidChange];
}

- (void)updateSelectedLineWhenSlidingDidScroll:(id)scrollView isFigureDragging:(BOOL)dragging {
    %orig;
    if (@available(iOS 26.0, *)) [DKTopBarGlassCapsule(self) selectionLineDidMove];
}

- (void)scrollViewDidScroll:(id)scrollView {
    %orig;
    if (@available(iOS 26.0, *)) [DKTopBarGlassCapsule(self) channelsDidScroll];
}

- (void)scrollViewWillBeginDragging:(id)scrollView {
    %orig;
    if (@available(iOS 26.0, *)) [DKTopBarGlassCapsule(self) channelsWillBeginDragging];
}

// 原生每帧都写，只在明暗变化时重配材质。
- (void)setIsLightTheme:(BOOL)isLightTheme {
    BOOL changed = self.isLightTheme != isLightTheme;
    %orig;
    if (!changed) return;
    if (@available(iOS 26.0, *)) {
        if (!DKTopBarGlassCapsule(self)) return;
        UIView *container = self.superview.superview;
        if ([container isKindOfClass:%c(AWEFeedTopBarContainer)]) DKTopBarGlassSync((AWEFeedTopBarContainer *)container);
    }
}

%end

%hook AWEMultiTabNavigationArrowView

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    BOOL handled = NO;
    BOOL inside = DKTopChannelArrowContainsPoint(self, point, &handled);
    return handled ? inside : %orig;
}

%end

// 长按拖选期间不打开原生的频道排序面板。
%hook AWEFeedContainerViewController

- (void)topBarContainerLongPress:(id)gesture {
    if (@available(iOS 26.0, *)) {
        if (DKTopChannelCapsule.dragging) return;
    }
    %orig;
}

%end

%end

%ctor {
    if (DKGlassOSAvailable()) {
        %init(DKTopBarGlassHooks);
    }
}
