//
//  DKPlaybackClean.xm
//  DYKiller
//
//  播放页精简：显示 / 隐藏 / 移除。
//
//  实现：
//   - 隐藏：对目标挂透明 mask（DKAdjustFade 系数 0），不改 alpha / hidden，命中与位置不变。整行项淡出行的直接子视图，
//     与「昵称文案」挂在行上的透明度 mask 叠乘。
//   - 移除（整行）：行显隐交给 DKElementRowHiding，行隐藏后由抖音的 UIStackView 原生收拢。
//   - 移除（子视图）：标签元素的三个子视图在各自 -setHidden: 汇聚点写入「抖音请求值 || 移除」；昵称右侧标签在标签管理器
//     更新后写隐藏，横向标签栈原生收窄。标签行只剩被移除的内容时整行一并移除。
//   - 全屏观看：入口不在元素栈里。移除时让控制器不显示入口（不再为入口上移视频），并在入口 -setHidden: 处保持隐藏。
//

#import "DKPlaybackClean.h"
#import "DKPlaybackCleanRules.h"
#import "DKElementRowHiding.h"
#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"
#import <objc/runtime.h>

static char kDKCleanHostHiddenKey;      // 子视图 / 全屏入口：抖音最近一次请求的 hidden
static char kDKCleanRemovedKey;         // 子视图：当前由本模块保持隐藏
static char kDKCleanTagOriginalKey;     // 昵称右侧标签：移除前的 hidden
static char kDKCleanRowFadedKey;        // 行：直接子视图已挂淡出

static NSHashTable<AWEElementStackView *> *gDKCleanStacks;
static NSHashTable<UIView *> *gDKCleanEntries;

static CGFloat DKCleanFadeFactor(DKDisplayMode mode) {
    return mode == DKDisplayModeHide ? 0.0 : 1.0;
}

#pragma mark - 整行淡出

// key 为 nil 时行不归任何设置项管理（如锚点换成了其他类型），已挂的淡出一并摘掉。
static void DKCleanFadeRowContent(UIView *row, NSString *key) {
    DKDisplayMode mode = key ? DKPrefDisplayMode(key) : DKDisplayModeShow;
    BOOL hide = mode == DKDisplayModeHide;
    BOOL faded = objc_getAssociatedObject(row, &kDKCleanRowFadedKey) != nil;
    if (!hide && !faded) return;
    for (UIView *subview in row.subviews) DKAdjustFade(subview, DKCleanFadeFactor(mode), CGSizeZero);
    objc_setAssociatedObject(row, &kDKCleanRowFadedKey, hide ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - 标签元素子视图

static NSString *DKCleanKeyForTagsSubview(UIView *view) {
    id element = DKCleanRowElement(DKCleanRowForView(view));
    __block NSString *found = nil;
    DKCleanEnumerateTagsElementViews(element, ^(UIView *candidate, NSString *key) {
        if (candidate == view) found = key;
    });
    return found;
}

static BOOL DKCleanHostHidden(UIView *view) {
    NSNumber *host = objc_getAssociatedObject(view, &kDKCleanHostHiddenKey);
    return host ? host.boolValue : view.hidden;
}

// 子视图 -setHidden: 汇聚点：记下抖音请求值，返回实际应写入的值。
static BOOL DKCleanSubviewHidden(UIView *view, BOOL hostHidden) {
    NSString *key = DKCleanKeyForTagsSubview(view);
    BOOL remove = key && DKPrefDisplayMode(key) == DKDisplayModeRemove;
    objc_setAssociatedObject(view, &kDKCleanHostHiddenKey, @(hostHidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kDKCleanRemovedKey, remove ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return hostHidden || remove;
}

// key 为 nil 表示视图已不属于任何设置项，按显示还原。
static void DKCleanSyncSubview(UIView *view, NSString *key) {
    DKDisplayMode mode = key ? DKPrefDisplayMode(key) : DKDisplayModeShow;
    DKAdjustFade(view, DKCleanFadeFactor(mode), CGSizeZero);

    BOOL removed = objc_getAssociatedObject(view, &kDKCleanRemovedKey) != nil;
    BOOL remove = mode == DKDisplayModeRemove;
    BOOL hostHidden = DKCleanHostHidden(view);
    if (removed != remove || view.hidden != (hostHidden || remove)) view.hidden = hostHidden;
}

// 子视图显隐变化后，行可能只剩被移除的内容（或重新有了内容）。
static void DKCleanSyncRowOfSubview(UIView *view) {
    DKElementRowSync(DKCleanRowForView(view));
}

static BOOL DKCleanViewShowsContent(UIView *view, NSSet<UIView *> *excluded) {
    if (view.hidden || [excluded containsObject:view]) return NO;
    if (![view isKindOfClass:UIStackView.class]) return YES;
    for (UIView *arranged in ((UIStackView *)view).arrangedSubviews) {
        if (DKCleanViewShowsContent(arranged, excluded)) return YES;
    }
    return NO;
}

// 标签行：至少有一项被本模块移除，且除被移除项外没有可见内容。
static BOOL DKCleanTagsRowRemoved(UIView *row, id element) {
    NSMutableSet<UIView *> *removed = [NSMutableSet set];
    DKCleanEnumerateTagsElementViews(element, ^(UIView *view, NSString *key) {
        if (DKPrefDisplayMode(key) == DKDisplayModeRemove && !DKCleanHostHidden(view)) [removed addObject:view];
    });
    if (removed.count == 0) return NO;
    for (UIView *subview in row.subviews) {
        if (DKCleanViewShowsContent(subview, removed)) return NO;
    }
    return YES;
}

#pragma mark - 昵称右侧标签

static void DKCleanApplyAuthorTag(UIView *tagView, NSString *key) {
    DKDisplayMode mode = DKPrefDisplayMode(key);
    DKAdjustFade(tagView, DKCleanFadeFactor(mode), CGSizeZero);

    NSNumber *original = objc_getAssociatedObject(tagView, &kDKCleanTagOriginalKey);
    if (mode == DKDisplayModeRemove) {
        if (!original) {
            objc_setAssociatedObject(tagView, &kDKCleanTagOriginalKey, @(tagView.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (!tagView.hidden) tagView.hidden = YES;
    } else if (original) {
        tagView.hidden = original.boolValue;
        objc_setAssociatedObject(tagView, &kDKCleanTagOriginalKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

#pragma mark - 全屏观看

static void DKCleanApplyEntry(UIView *entry) {
    DKDisplayMode mode = DKPrefDisplayMode(DKKeyPlaybackFullscreenMode);
    DKAdjustFade(entry, DKCleanFadeFactor(mode), CGSizeZero);
    BOOL hostHidden = DKCleanHostHidden(entry);
    if (entry.hidden != (hostHidden || mode == DKDisplayModeRemove)) entry.hidden = hostHidden;
}

#pragma mark - 应用

BOOL DKPlaybackCleanRowRemoved(UIView *row) {
    id element = DKCleanRowElement(row);
    if (!element) return NO;
    NSString *key = DKCleanKeyForRow(row);
    if (key) return DKPrefDisplayMode(key) == DKDisplayModeRemove;
    return DKCleanIsTagsElement(element) && DKCleanTagsRowRemoved(row, element);
}

void DKPlaybackCleanApplyStack(AWEElementStackView *stack) {
    if (!stack || !DKPlayInteractionControllerForView(stack)) return;
    if (!gDKCleanStacks) gDKCleanStacks = [NSHashTable weakObjectsHashTable];
    [gDKCleanStacks addObject:stack];

    for (UIView *row in stack.arrangedSubviews) {
        id element = DKCleanRowElement(row);
        if (element) {
            DKCleanFadeRowContent(row, DKCleanKeyForRow(row));
            DKCleanEnumerateTagsElementViews(element, ^(UIView *view, NSString *key) { DKCleanSyncSubview(view, key); });
            DKCleanEnumerateAuthorTags(element, ^(UIView *tagView, NSString *key) { DKCleanApplyAuthorTag(tagView, key); });
        }
        DKElementRowSync(row);
    }
}

void DKPlaybackCleanRefresh(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKPlaybackCleanRefresh(); });
        return;
    }
    for (UIView *entry in gDKCleanEntries.allObjects) DKCleanApplyEntry(entry);
    for (AWEElementStackView *stack in gDKCleanStacks.allObjects) {
        [stack setNeedsLayout];
        [stack layoutIfNeeded];
    }
}

#pragma mark - 诊断

static NSString *const kDKCleanKeyPrefix = @"DYKillerPlayback";

// 诊断里用键的短名：去掉公共前缀与 Mode 后缀，如 DYKillerPlaybackDanmakuMode → Danmaku。
static NSString *DKCleanShortName(NSString *key) {
    NSString *name = [key hasPrefix:kDKCleanKeyPrefix] ? [key substringFromIndex:kDKCleanKeyPrefix.length] : key;
    return [name hasSuffix:@"Mode"] ? [name substringToIndex:name.length - 4] : name;
}

static NSString *DKCleanModeText(DKDisplayMode mode) {
    switch (mode) {
        case DKDisplayModeHide: return @"隐藏";
        case DKDisplayModeRemove: return @"移除";
        default: return @"显示";
    }
}

NSString *DKPlaybackCleanStatus(void) {
    NSMutableString *out = [NSMutableString string];
    NSMutableArray<NSString *> *changed = [NSMutableArray array];
    NSArray<NSString *> *keys = [NSUserDefaults.standardUserDefaults.dictionaryRepresentation.allKeys
        sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in keys) {
        if (![key hasPrefix:kDKCleanKeyPrefix]) continue;
        DKDisplayMode mode = DKPrefDisplayMode(key);
        if (mode != DKDisplayModeShow) [changed addObject:[NSString stringWithFormat:@"%@=%@", DKCleanShortName(key), DKCleanModeText(mode)]];
    }
    [out appendFormat:@"非默认：%@\n", changed.count ? [changed componentsJoinedByString:@" "] : @"无"];

    for (UIView *entry in gDKCleanEntries.allObjects) {
        [out appendFormat:@"全屏观看入口 frame=%@ hidden=%d 淡出=%.2f\n",
            NSStringFromCGRect(entry.frame), entry.isHidden, DKAdjustFadeFactor(entry)];
    }
    [out appendFormat:@"已见元素栈=%lu\n", (unsigned long)gDKCleanStacks.allObjects.count];
    for (AWEElementStackView *stack in gDKCleanStacks.allObjects) {
        if (!stack.window) continue;
        [out appendFormat:@"  栈 frame=%@ a11y=%@\n", NSStringFromCGRect(stack.frame), stack.accessibilityLabel ?: @""];
        for (UIView *row in stack.arrangedSubviews) {
            id element = DKCleanRowElement(row);
            NSString *key = DKCleanKeyForRow(row);
            [out appendFormat:@"    %@ → %@ hidden=%d 移除=%d 高=%.1f\n",
                element ? NSStringFromClass([element class]) : NSStringFromClass(row.class),
                key ? [NSString stringWithFormat:@"%@(%@)", DKCleanShortName(key), DKCleanModeText(DKPrefDisplayMode(key))] : @"-",
                row.isHidden, DKElementRowShouldRemove(row), CGRectGetHeight(row.bounds)];
            DKCleanEnumerateTagsElementViews(element, ^(UIView *view, NSString *subKey) {
                [out appendFormat:@"      子视图 %@ → %@(%@) hidden=%d 淡出=%.2f\n", NSStringFromClass(view.class),
                    DKCleanShortName(subKey), DKCleanModeText(DKPrefDisplayMode(subKey)), view.isHidden, DKAdjustFadeFactor(view)];
            });
            DKCleanEnumerateAuthorTags(element, ^(UIView *tagView, NSString *tagKey) {
                [out appendFormat:@"      标签 %@ → %@(%@) hidden=%d 淡出=%.2f\n", NSStringFromClass(tagView.class),
                    DKCleanShortName(tagKey), DKCleanModeText(DKPrefDisplayMode(tagKey)), tagView.isHidden, DKAdjustFadeFactor(tagView)];
            });
        }
    }
    return out;
}

#pragma mark - Hook

%hook AFDRecommendToFriendEntranceLabel

- (void)setHidden:(BOOL)hidden {
    %orig(DKCleanSubviewHidden(self, hidden));
    DKCleanSyncRowOfSubview(self);
}

%end

%hook AWEPlayInteractionGeneralTagView

- (void)setHidden:(BOOL)hidden {
    %orig(DKCleanSubviewHidden(self, hidden));
    DKCleanSyncRowOfSubview(self);
}

%end

// 关系标签换内容时只改子视图，自身 hidden 不一定重写；布局后按当前内容重判是否为好友推荐。
%hook AWEFeedRelationView

- (void)setHidden:(BOOL)hidden {
    %orig(DKCleanSubviewHidden(self, hidden));
    DKCleanSyncRowOfSubview(self);
}

- (void)layoutSubviews {
    %orig;
    NSString *key = DKCleanKeyForTagsSubview(self);
    BOOL managed = objc_getAssociatedObject(self, &kDKCleanRemovedKey) != nil || DKAdjustFadeFactor(self) < 1.0;
    if (!key && !managed) return;
    DKCleanSyncSubview(self, key);
    DKCleanSyncRowOfSubview(self);
}

%end

%hook AWEVideoTagsPriorityManager

- (void)updateWithData:(id)data context:(id)context {
    %orig;
    DKCleanEnumerateManagerTags(self, ^(UIView *tagView, NSString *key) { DKCleanApplyAuthorTag(tagView, key); });
}

%end

%hook AWELandscapeFeedEntryView

- (void)setHidden:(BOOL)hidden {
    objc_setAssociatedObject(self, &kDKCleanHostHiddenKey, @(hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(hidden || DKPrefDisplayMode(DKKeyPlaybackFullscreenMode) == DKDisplayModeRemove);
}

- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;
    if (!gDKCleanEntries) gDKCleanEntries = [NSHashTable weakObjectsHashTable];
    [gDKCleanEntries addObject:self];
    DKCleanApplyEntry(self);
}

%end

%hook AWEPlayInteractionLandscapeFeedController

- (BOOL)enableShowEntryView {
    if (DKPrefDisplayMode(DKKeyPlaybackFullscreenMode) == DKDisplayModeRemove) return NO;
    return %orig;
}

%end

%ctor {
    %init;
}
