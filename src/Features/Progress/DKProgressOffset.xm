//
//  DKProgressOffset.xm
//  DYKiller
//
//  功能：进度条上移、图片指示器上移。
//
//  实现：
//   - 进度条：feed 布局策略按「容器高 − posAdjustY + sliderYOffset」算常态 / 唤醒 frame 的底边，拖动手势区也按常态 frame 换算。
//     Hook posAdjustY 加上上移量，抖音按新位置写 frame、判手势，时长读数随进度条 frame 摆放；底部背景只用 sliderYOffset，留在原位。
//     本次加上的量记在策略的 edc 上（与总控共用），实测底边时扣掉。
//     改值后对已见进度条的状态机 reapplyCurrentStateAppearance 重新取 frame，当前视频即时生效。
//   - 图片指示器：AWEStoryProgressContainerView 由 Masonry 约束在左侧栈下方，在播放交互层内叠 transform 上移，
//     点按与拖动换图随之移动。清屏页里的剧集分段条由清屏让位管理，这里不处理。
//   - 「位置同图片指示器」：两者都按线条底边到交互层底边的原生距离实测——进度条只取常态 / 唤醒态（两态底边相同）并扣掉
//     本插件的上移，图片指示器取不含 transform 的位置并扣掉底部栈导流条的高度；结果存本机、不进备份。
//     两者最终底边取整后重合时提示。
//   - 左下昵称文案与右侧互动区不跟随。
//   - 设置项登记在本文件 %ctor，布局见 DKSettingsLayout.m「外观定制 › 视频播放」。
//

#import "DKProgressOffset.h"
#import <objc/runtime.h>
#import "DouyinHeaders.h"
#import "DKAdjustRange.h"
#import "DKKeys.h"
#import "DKPlaybackOverlay.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"

static const long long DKProgressStateStable = 1;  // 状态机常态
static const long long DKProgressStateWakeup = 2;  // 状态机唤醒态（暂停、拖动）

// 记在进度条的 edc 上：抖音最近一次取 posAdjustY 时本插件加上的量。
static const void *DKProgressOffsetAppliedKey = &DKProgressOffsetAppliedKey;
static NSHashTable<UIView *> *gDKProgressOffsetContainers;
static NSHashTable<UIView *> *gDKStoryIndicators;

#pragma mark - 本机实测

static BOOL DKProgressOffsetStoredBase(NSString *key, CGFloat *out) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    if (![value isKindOfClass:NSNumber.class]) return NO;
    if (out) *out = [value doubleValue];
    return YES;
}

static void DKProgressOffsetStoreBase(NSString *key, CGFloat base) {
    CGFloat stored = 0;
    if (DKProgressOffsetStoredBase(key, &stored) && fabs(stored - base) < 0.01) return;
    [NSUserDefaults.standardUserDefaults setDouble:base forKey:key];
}

#pragma mark - 进度条

static AWEFeedProgressSlider *DKProgressOffsetSliderIn(UIView *container) {
    Class sliderClass = NSClassFromString(@"AWEFeedProgressSlider");
    for (UIView *subview in container.subviews) {
        if ([subview isKindOfClass:sliderClass]) return (AWEFeedProgressSlider *)subview;
    }
    return nil;
}

static AWEDProgressCoreContainer *DKProgressOffsetCore(AWEFeedProgressSlider *slider) {
    id delegate = slider.progressSliderDelegate;
    return [delegate isKindOfClass:NSClassFromString(@"AWEDProgressCoreContainer")] ? delegate : nil;
}

static AWEDProgressStateChangeContainer *DKProgressOffsetStateOf(AWEDProgressCoreContainer *core) {
    return [core respondsToSelector:@selector(stateChangeContainer)] ? [core stateChangeContainer] : nil;
}

// 抖音最近一次取 posAdjustY 时加上的量；未经 feed 布局策略取过时为 nil。
static NSNumber *DKProgressOffsetApplied(AWEDProgressCoreContainer *core) {
    AWEArchEventDataController *edc = [core respondsToSelector:@selector(edc)] ? [core edc] : nil;
    return edc ? objc_getAssociatedObject(edc, DKProgressOffsetAppliedKey) : nil;
}

static long long DKProgressOffsetState(AWEDProgressCoreContainer *core) {
    AWEDProgressStateChangeContainer *state = DKProgressOffsetStateOf(core);
    return [state respondsToSelector:@selector(currentState)] ? [state currentState] : 0;
}

// 进度条底边到交互层底边的原生距离。初始 frame 的底边与常态不同，只在常态 / 唤醒态取。
static BOOL DKProgressOffsetMeasureBar(UIView *container, CGFloat *out) {
    AWEFeedProgressSlider *slider = DKProgressOffsetSliderIn(container);
    AWEDProgressCoreContainer *core = DKProgressOffsetCore(slider);
    UIView *parent = container.superview;
    NSNumber *applied = DKProgressOffsetApplied(core);
    long long state = DKProgressOffsetState(core);
    if (!parent || !applied || (state != DKProgressStateStable && state != DKProgressStateWakeup)) return NO;
    CGFloat containerTop = container.center.y - CGRectGetHeight(container.bounds) / 2;
    *out = CGRectGetHeight(parent.bounds) - containerTop - CGRectGetMaxY(slider.frame) - applied.doubleValue;
    return YES;
}

void DKProgressOffsetLayoutContainer(UIView *container) {
    if (!DKProgressOffsetSliderIn(container)) return;
    if (!gDKProgressOffsetContainers) gDKProgressOffsetContainers = [NSHashTable weakObjectsHashTable];
    [gDKProgressOffsetContainers addObject:container];
    CGFloat base = 0;
    if (DKProgressOffsetMeasureBar(container, &base)) DKProgressOffsetStoreBase(DKKeyProgressBaseBottom, base);
}

static void DKProgressOffsetRefresh(void) {
    for (UIView *container in gDKProgressOffsetContainers.allObjects) {
        AWEDProgressStateChangeContainer *state =
            DKProgressOffsetStateOf(DKProgressOffsetCore(DKProgressOffsetSliderIn(container)));
        if ([state respondsToSelector:@selector(reapplyCurrentStateAppearance)]) [state reapplyCurrentStateAppearance];
    }
}

#pragma mark - 图片指示器

static UIView *DKStoryIndicatorBottomStack(UIView *parent) {
    Class stackClass = NSClassFromString(@"AWEElementStackView");
    for (UIView *sibling in parent.subviews) {
        if ([sibling isKindOfClass:stackClass] && [sibling.accessibilityLabel isEqualToString:@"bottom"]) return sibling;
    }
    return nil;
}

// 图片指示器线条底边到交互层底边的原生距离：取不含 transform 的位置，扣掉底部栈导流条的高度。
static BOOL DKStoryIndicatorMeasure(AWEStoryProgressContainerView *view, CGFloat *out) {
    UIView *parent = view.superview;
    if (!parent || view.hidden || view.alpha < 0.01
        || ![view respondsToSelector:@selector(currentProgressViewFrame)]) return NO;
    CGRect line = [view currentProgressViewFrame];
    if (CGRectIsEmpty(line)) return NO;
    CGFloat top = view.center.y - CGRectGetHeight(view.bounds) / 2;
    CGFloat rows = CGRectGetHeight(DKStoryIndicatorBottomStack(parent).bounds);
    *out = CGRectGetHeight(parent.bounds) - top - CGRectGetMaxY(line) - rows;
    return YES;
}

static void DKStoryIndicatorApply(UIView *view) {
    DKAdjustTransform(view, CGAffineTransformMakeTranslation(0, -DKAdjustValue(DKKeyStoryIndicatorOffset)));
}

void DKStoryIndicatorLayout(UIView *view) {
    if (!DKPlayInteractionControllerForView(view) || DKPlaybackOverlayIsPureControl(view)) return;
    if (!gDKStoryIndicators) gDKStoryIndicators = [NSHashTable weakObjectsHashTable];
    [gDKStoryIndicators addObject:view];
    DKStoryIndicatorApply(view);
    CGFloat base = 0;
    if (view.window && DKStoryIndicatorMeasure((AWEStoryProgressContainerView *)view, &base)) {
        DKProgressOffsetStoreBase(DKKeyStoryIndicatorBaseBottom, base);
    }
}

static void DKStoryIndicatorRefresh(void) {
    for (UIView *view in gDKStoryIndicators.allObjects) DKStoryIndicatorApply(view);
}

#pragma mark - 位置同图片指示器

// 按已见视图补测一次，再比较两者的最终底边：进度条上移取整后等于「指示器原生底边 + 指示器上移 − 进度条原生底边」即重合。
static NSString *DKProgressOffsetNote(NSInteger value) {
    CGFloat base = 0;
    for (UIView *container in gDKProgressOffsetContainers.allObjects) {
        if (DKProgressOffsetMeasureBar(container, &base)) DKProgressOffsetStoreBase(DKKeyProgressBaseBottom, base);
    }
    for (UIView *view in gDKStoryIndicators.allObjects) {
        if (DKStoryIndicatorMeasure((AWEStoryProgressContainerView *)view, &base)) {
            DKProgressOffsetStoreBase(DKKeyStoryIndicatorBaseBottom, base);
        }
    }
    CGFloat bar = 0, indicator = 0;
    if (!DKProgressOffsetStoredBase(DKKeyProgressBaseBottom, &bar)
        || !DKProgressOffsetStoredBase(DKKeyStoryIndicatorBaseBottom, &indicator)) return nil;
    NSInteger aligned = lround(indicator + DKAdjustValue(DKKeyStoryIndicatorOffset) - bar);
    return value == aligned ? @"位置同图片指示器" : nil;
}

#pragma mark - 诊断

static NSString *DKProgressOffsetBaseText(NSString *key) {
    CGFloat base = 0;
    return DKProgressOffsetStoredBase(key, &base) ? [NSString stringWithFormat:@"%.2fpt", base] : @"未测得";
}

NSString *DKProgressOffsetStatus(void) {
    NSMutableString *out = [NSMutableString string];
    NSInteger barOffset = DKAdjustValue(DKKeyProgressOffset), indicatorOffset = DKAdjustValue(DKKeyStoryIndicatorOffset);
    [out appendFormat:@"进度条上移=%ldpt 图片指示器上移=%ldpt\n", (long)barOffset, (long)indicatorOffset];
    CGFloat bar = 0, indicator = 0;
    BOOL measured = DKProgressOffsetStoredBase(DKKeyProgressBaseBottom, &bar)
        && DKProgressOffsetStoredBase(DKKeyStoryIndicatorBaseBottom, &indicator);
    [out appendFormat:@"本机实测（底边到交互层底，不含上移）：进度条=%@ 图片指示器=%@ 同位置时进度条上移=%@\n",
        DKProgressOffsetBaseText(DKKeyProgressBaseBottom), DKProgressOffsetBaseText(DKKeyStoryIndicatorBaseBottom),
        measured ? [NSString stringWithFormat:@"%ldpt", lround(indicator + indicatorOffset - bar)] : @"—"];
    [out appendFormat:@"已见进度条容器=%lu 已见图片指示器=%lu\n",
        (unsigned long)gDKProgressOffsetContainers.allObjects.count, (unsigned long)gDKStoryIndicators.allObjects.count];
    for (UIView *container in gDKProgressOffsetContainers.allObjects) {
        if (!container.window) continue;
        AWEFeedProgressSlider *slider = DKProgressOffsetSliderIn(container);
        AWEDProgressCoreContainer *core = DKProgressOffsetCore(slider);
        CGFloat base = 0;
        BOOL ok = DKProgressOffsetMeasureBar(container, &base);
        [out appendFormat:@"  进度条 窗口frame=%@ 状态=%lld 已加上移=%@ 原生底边=%@\n",
            NSStringFromCGRect([slider convertRect:slider.bounds toView:nil]), DKProgressOffsetState(core),
            DKProgressOffsetApplied(core) ?: @"—", ok ? [NSString stringWithFormat:@"%.2fpt", base] : @"—"];
    }
    for (UIView *view in gDKStoryIndicators.allObjects) {
        if (!view.window) continue;
        CGFloat base = 0;
        BOOL ok = DKStoryIndicatorMeasure((AWEStoryProgressContainerView *)view, &base);
        [out appendFormat:@"  图片指示器 窗口frame=%@ ty=%.1f 原生底边=%@\n",
            NSStringFromCGRect([view convertRect:view.bounds toView:nil]), view.transform.ty,
            ok ? [NSString stringWithFormat:@"%.2fpt", base] : @"—"];
    }
    return out;
}

#pragma mark - Hook

%group DKProgressOffsetFeedHooks
%hook AWEDProgressLayoutFeedStrategy

- (double)posAdjustY {
    CGFloat offset = DKAdjustValue(DKKeyProgressOffset);
    AWEArchEventDataController *edc = [self respondsToSelector:@selector(edc)] ? [self edc] : nil;
    if (edc) objc_setAssociatedObject(edc, DKProgressOffsetAppliedKey, @(offset), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return %orig + offset;
}

%end
%end

%ctor {
    if ([NSClassFromString(@"AWEDProgressLayoutFeedStrategy") instancesRespondToSelector:@selector(posAdjustY)]) {
        %init(DKProgressOffsetFeedHooks);
    }

    DKSettingsRegister(DKKeyProgressOffset, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeAdjustSliderWithNote(DKKeyProgressOffset, @"进度条上移",
            @"上移：0 pt 为抖音原位。", ^NSString *(NSInteger value) { return DKProgressOffsetNote(value); },
            ^(__unused NSInteger value) { DKProgressOffsetRefresh(); });
        return DKSettingsWithInfo(item,
            @"整体上移视频底部的进度条，拖动与暂停加粗随之移动；左下昵称文案与右侧互动区不跟随。");
    });

    DKSettingsRegister(DKKeyStoryIndicatorOffset, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeAdjustSlider(DKKeyStoryIndicatorOffset, @"图片指示器上移",
            @"上移：0 pt 为抖音原位。", ^(__unused NSInteger value) { DKStoryIndicatorRefresh(); });
        return DKSettingsWithInfo(item,
            @"整体上移图文作品底部的图片指示器，点按与拖动切换图片随之移动；左下昵称文案与右侧互动区不跟随。");
    });
}
