//
//  DKSettingsLock.m
//  建页收尾与两类锁：
//  - 玻璃锁：低于 iOS 26 时守卫表里的项灰显、加「 (iOS26+)」、按关显示（偏好已被守卫清掉），运行期不会解除。
//  - 联动锁：前置项未生效（「任一」前置项全部未生效）、或阻断条件成立时灰显，只改 isEnable、不动存值，条件解除后照原值显示。
//    带显示值的阻断项（总开关）成立时，子项另按该值显示。
//  - 设备锁：仅 iPad 生效的项在其他设备上灰显、加「 (iPad)」，只改 isEnable、不动存值。
//  灰显由抖音 cell 按 isEnable 完成（关开关交互、调暗 realContentView）；点击由页面 hook 拦截。
//

#import "DKSettingsInternal.h"
#import "DKSettingsLayout.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import <objc/runtime.h>

static char kDKBaseEnableKey;   // builder 给的可用态；有值即 DYKiller 自己的项

static NSString *const kDKGlassTitleSuffix = @" (iOS26+)";

// 前置链深度上限，防止布局表里误写出环。
static const NSUInteger kDKMaxRequireDepth = 8;

static NSString *const kDKPadTitleSuffix = @" (iPad)";

static BOOL DKKeyGlassLocked(NSString *key) {
    return !DKGlassOSAvailable() && DKGlassIsGatedKey(key);
}

static BOOL DKKeyPadLocked(NSString *key) {
    return UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad
        && [key isEqualToString:DKKeyGlassTabBarPadPosition];
}

static BOOL DKKeyLocked(NSString *key, NSUInteger depth);

static BOOL DKBlockerHolds(DKSettingsBlocker *blocker) {
    switch (blocker.match) {
        case DKSettingsBlockerWhenOn: return DKPrefBool(blocker.key);
        case DKSettingsBlockerWhenEqual: return DKPrefInteger(blocker.key) == blocker.value;
        case DKSettingsBlockerWhenNotEqual: return DKPrefInteger(blocker.key) != blocker.value;
    }
    return NO;
}

// 联动的有效值与总开关显示值一致；玻璃守卫优先于总开关。
static BOOL DKKeyActive(NSString *key, NSUInteger depth) {
    if (DKKeyGlassLocked(key) || DKKeyPadLocked(key)) return NO;
    for (DKSettingsBlocker *blocker in DKSettingsLayoutBlockers(key)) {
        if (blocker.shownValue && DKBlockerHolds(blocker)) return blocker.shownValue.integerValue != 0;
    }
    return !DKKeyLocked(key, depth) && DKPrefInteger(key) != 0;
}

static BOOL DKKeyBlocked(NSString *key) {
    for (DKSettingsBlocker *blocker in DKSettingsLayoutBlockers(key)) {
        if (DKBlockerHolds(blocker)) return YES;
    }
    return NO;
}

// 带显示值的阻断项（总开关的子项）：按「成立中的显示值，否则存值」刷新显示，返回显示是否有变化。
// 未配置显示值的项由各自工厂与玻璃锁维护显示。
static BOOL DKSyncShownValue(AWESettingItemModel *item) {
    BOOL governed = NO;
    NSNumber *shown = nil;
    for (DKSettingsBlocker *blocker in DKSettingsLayoutBlockers(item.identifier)) {
        if (!blocker.shownValue) continue;
        governed = YES;
        if (!shown && DKBlockerHolds(blocker)) shown = blocker.shownValue;
    }
    return governed && DKSettingsShowValue(item, shown);
}

static BOOL DKKeyLocked(NSString *key, NSUInteger depth) {
    if (DKKeyGlassLocked(key) || DKKeyPadLocked(key)) return YES;
    if (DKKeyBlocked(key)) return YES;
    if (depth >= kDKMaxRequireDepth) return NO;
    for (NSString *parent in DKSettingsLayoutRequires(key)) {
        if (!DKKeyActive(parent, depth + 1)) return YES;
    }
    NSArray<NSString *> *anyOf = DKSettingsLayoutRequiresAny(key);
    if (!anyOf.count) return NO;
    for (NSString *parent in anyOf) {
        if (DKKeyActive(parent, depth + 1)) return NO;
    }
    return YES;
}

// 低系统：标题加后缀、灰掉、掐掉点击。在 builder 返回之后调用，盖住功能自己包的回调。
static void DKGlassLockItemIfNeeded(AWESettingItemModel *item) {
    if (!DKKeyGlassLocked(item.identifier)) return;
    if (item.title.length && ![item.title hasSuffix:kDKGlassTitleSuffix]) {
        item.title = [item.title stringByAppendingString:kDKGlassTitleSuffix];
    }
    item.isEnable = NO;
    item.isSwitchOn = NO;
    __weak AWESettingItemModel *weakItem = item;
    item.switchChangedBlock = ^{
        weakItem.isSwitchOn = NO;
    };
    item.cellTappedBlock = nil;
}

void DKSettingsPrepareItem(AWESettingItemModel *item, NSString *icon) {
    if (!item) return;
    item.colorStyle = 2;                 // 卡片样式配色
    if (icon.length) item.svgIconImageName = icon;
    objc_setAssociatedObject(item, &kDKBaseEnableKey, @(item.isEnable), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKGlassLockItemIfNeeded(item);
    // 设备锁只加标题后缀；可用态由 DKSettingsApplyLocks 统一刷新。
    if (DKKeyPadLocked(item.identifier) && !DKKeyGlassLocked(item.identifier)
        && item.title.length && ![item.title hasSuffix:kDKPadTitleSuffix]) {
        item.title = [item.title stringByAppendingString:kDKPadTitleSuffix];
    }
}

void DKSettingsSetItemEnabled(AWESettingItemModel *item, BOOL enabled) {
    if (!item) return;
    objc_setAssociatedObject(item, &kDKBaseEnableKey, @(enabled), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BOOL enable = enabled && !DKKeyLocked(item.identifier, 0);
    BOOL shown = DKSyncShownValue(item);
    if (item.isEnable == enable && !shown) return;
    item.isEnable = enable;
    if ([item respondsToSelector:@selector(refreshCell)]) [item refreshCell];
}

BOOL DKSettingsIsOwnItem(AWESettingItemModel *item) {
    return item && objc_getAssociatedObject(item, &kDKBaseEnableKey) != nil;
}

NSArray<AWESettingItemModel *> *DKSettingsApplyLocks(NSArray *sections) {
    NSMutableArray<AWESettingItemModel *> *changed = [NSMutableArray array];
    for (AWESettingSectionModel *section in sections) {
        for (AWESettingItemModel *item in section.itemArray) {
            NSNumber *base = objc_getAssociatedObject(item, &kDKBaseEnableKey);
            if (!base) continue;
            BOOL enable = base.boolValue && !DKKeyLocked(item.identifier, 0);
            BOOL shown = DKSyncShownValue(item);
            if (item.isEnable == enable && !shown) continue;
            item.isEnable = enable;
            [changed addObject:item];
        }
    }
    return changed;
}

BOOL DKSettingsKeyIsLocked(NSString *key) { return DKKeyLocked(key, 0); }

NSString *DKSettingsKeyLockReason(NSString *key) {
    if (DKKeyGlassLocked(key)) return @"需要 iOS 26 或更高版本";
    if (DKKeyPadLocked(key)) return @"仅 iPad 可用";
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *parent in DKSettingsLayoutRequires(key)) {
        if (DKKeyActive(parent, 1)) continue;
        AWESettingItemModel *source = DKSettingsBuildItem(parent);
        NSString *format = DKSettingsItemIsChoice(source) ? @"需先设置「%@」" : @"需先开启「%@」";
        [parts addObject:[NSString stringWithFormat:format, source.title ?: parent]];
    }
    NSArray<NSString *> *anyOf = DKSettingsLayoutRequiresAny(key);
    BOOL anyActive = NO;
    NSMutableArray<NSString *> *anyTitles = [NSMutableArray array];
    for (NSString *parent in anyOf) {
        if (DKKeyActive(parent, 1)) { anyActive = YES; break; }
        [anyTitles addObject:[NSString stringWithFormat:@"「%@」", DKSettingsBuildItem(parent).title ?: parent]];
    }
    if (anyOf.count && !anyActive) {
        [parts addObject:[NSString stringWithFormat:@"需先开启%@", [anyTitles componentsJoinedByString:@"或"]]];
    }
    for (DKSettingsBlocker *blocker in DKSettingsLayoutBlockers(key)) {
        if (DKBlockerHolds(blocker)) [parts addObject:blocker.reason];
    }
    return parts.count ? [parts componentsJoinedByString:@"；"] : nil;
}

NSString *DKSettingsLockReason(AWESettingItemModel *item) {
    return DKSettingsIsOwnItem(item) ? DKSettingsKeyLockReason(item.identifier) : nil;
}
