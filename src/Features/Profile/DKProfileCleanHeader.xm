//
//  DKProfileCleanHeader.xm
//  DYKiller
//
//  个人主页精简 —— 头部分区：获赞与关注数据、编辑主页、功能区（观看历史 … 全部功能）、发布引导横幅（「记录下幸福瞬间」等）。
//
//  实现：
//   - 头部是 AWEBaseList 列表，每项各占一个分区。reloadSections 与 updateSections: 都从
//     -[AWEProfileHeaderSectionProviderManager sectionViewModelArray] 取分区 VM；reloadSections 替换分区后
//     由抖音自己重算头部高度、刷新分页栏位置。
//   - 移除：在该数组里按分区 VM 类去掉对应分区，抖音按原生排布收拢。横幅按所在分区识别，不看文字；功能区只有移除开关。
//     数据与编辑主页共用一行：编辑主页移除时去掉它的分区；数据只在编辑主页也移除时去掉分区，
//     否则数据格不绘制、不响应点击，编辑主页留在原位。
//   - 隐藏：对应 cell 的 contentView 挂全透明 mask，命中不受影响；移除时 cell 的 hitTest 返回 nil。
//   - 设置改动：已见 cell 重挂 mask，已见头部 VM 执行 reloadSections。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKProfileClean.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"
#import <objc/runtime.h>

static char kDKProfileHeaderCellKey;
// 弱表（头部 VM、cell），只在主线程读写。
static NSHashTable *gDKProfileHeaderViewModels;
static NSHashTable<UICollectionViewCell *> *gDKProfileHeaderCells;
static NSString *gDKProfileHeaderLastFilter;

static BOOL DKProfileHeaderMine(id context) {
    return [context respondsToSelector:@selector(isCurrentUser)] && [context isCurrentUser];
}

static BOOL DKProfileHeaderRemoved(NSString *key) {
    return DKPrefDisplayMode(key) == DKDisplayModeRemove;
}

static NSArray *DKProfileHeaderFilterSections(NSArray *sections) {
    BOOL editRemoved = DKProfileHeaderRemoved(DKKeyProfileEditMode);
    BOOL statsRemoved = editRemoved && DKProfileHeaderRemoved(DKKeyProfileStatsMode);
    BOOL bannerRemoved = DKProfileHeaderRemoved(DKKeyProfileGuideBannerMode);
    BOOL serviceRemoved = DKPrefBool(DKKeyProfileRemoveServiceArea);
    if (!editRemoved && !bannerRemoved && !serviceRemoved) {
        if (NSThread.isMainThread) gDKProfileHeaderLastFilter = nil;
        return sections;
    }

    Class edit = %c(AWEProfileHeaderHomeShortcutSectionViewModel);
    Class stats = %c(AWEProfileHeaderSocialStatisticSectionViewModelV2);
    Class banner = %c(AWEUserProfileUGCHeaderContributionGuideBannerSectionViewModel);
    Class service = %c(AWEProfileHeaderProvidedServiceSectionViewModel);
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:sections.count];
    NSMutableArray<NSString *> *dropped = [NSMutableArray array];
    for (id section in sections) {
        BOOL drop = (editRemoved && edit && [section isKindOfClass:edit])
            || (statsRemoved && stats && [section isKindOfClass:stats])
            || (bannerRemoved && banner && [section isKindOfClass:banner])
            || (serviceRemoved && service && [section isKindOfClass:service]);
        if (drop) [dropped addObject:NSStringFromClass([section class])];
        else [kept addObject:section];
    }
    if (NSThread.isMainThread) {
        gDKProfileHeaderLastFilter = [NSString stringWithFormat:@"%lu 个分区，去掉 [%@]", (unsigned long)sections.count,
                                      [dropped componentsJoinedByString:@", "]];
    }
    return dropped.count ? kept : sections;
}

static void DKProfileHeaderApplyCell(UICollectionViewCell *cell) {
    NSString *key = objc_getAssociatedObject(cell, &kDKProfileHeaderCellKey);
    DKDisplayMode mode = key ? DKPrefDisplayMode(key) : DKDisplayModeShow;
    UIView *content = cell.contentView;
    DKAdjustFade(content, mode == DKDisplayModeShow ? 1.0 : 0.0, content.bounds.size);
}

// 只给自己主页上的 cell 记设置键；没有记号的一律按「显示」处理。
static void DKProfileHeaderTrackCell(UICollectionViewCell *cell, NSString *key, BOOL mine) {
    objc_setAssociatedObject(cell, &kDKProfileHeaderCellKey, mine ? key : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!gDKProfileHeaderCells) gDKProfileHeaderCells = [NSHashTable weakObjectsHashTable];
    [gDKProfileHeaderCells addObject:cell];
    DKProfileHeaderApplyCell(cell);
}

static BOOL DKProfileHeaderCellRemoved(UICollectionViewCell *cell) {
    NSString *key = objc_getAssociatedObject(cell, &kDKProfileHeaderCellKey);
    return key && DKProfileHeaderRemoved(key);
}

void DKProfileCleanHeaderRefresh(void) {
    for (UICollectionViewCell *cell in gDKProfileHeaderCells.allObjects) DKProfileHeaderApplyCell(cell);
    for (AWEProfileHeaderViewModel *viewModel in gDKProfileHeaderViewModels.allObjects) {
        if ([viewModel respondsToSelector:@selector(reloadSections)]) [viewModel reloadSections];
    }
}

NSString *DKProfileCleanHeaderStatus(void) {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"已见头部 VM=%lu 最近一次分区过滤：%@\n", (unsigned long)gDKProfileHeaderViewModels.allObjects.count,
        gDKProfileHeaderLastFilter ?: @"未过滤"];
    for (UICollectionViewCell *cell in gDKProfileHeaderCells.allObjects) {
        NSString *key = objc_getAssociatedObject(cell, &kDKProfileHeaderCellKey);
        if (!key) continue;
        [out appendFormat:@"  %@ 在窗口=%d frame=%@ 淡出=%.2f\n", NSStringFromClass(cell.class), cell.window != nil,
            NSStringFromCGRect([cell convertRect:cell.bounds toView:nil]), DKAdjustFadeFactor(cell.contentView)];
    }
    return out;
}

%hook AWEProfileHeaderSectionProviderManager

- (NSArray *)sectionViewModelArray {
    NSArray *sections = %orig;
    if (![sections isKindOfClass:NSArray.class] || ![self respondsToSelector:@selector(context)]) return sections;
    return DKProfileHeaderMine([self context]) ? DKProfileHeaderFilterSections(sections) : sections;
}

%end

%hook AWEProfileHeaderViewModel

- (void)reloadSections {
    %orig;
    if (!NSThread.isMainThread || ![self respondsToSelector:@selector(isCurrentUser)] || ![self isCurrentUser]) return;
    if (!gDKProfileHeaderViewModels) gDKProfileHeaderViewModels = [NSHashTable weakObjectsHashTable];
    [gDKProfileHeaderViewModels addObject:self];
}

%end

%hook AWEProfileHeaderSocialStatisticCollectionViewCellV2

- (void)layoutSubviews {
    %orig;
    DKProfileHeaderTrackCell(self, DKKeyProfileStatsMode,
                             [self respondsToSelector:@selector(isCurrentUser)] && [self isCurrentUser]);
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = %orig;
    return (hit && DKProfileHeaderCellRemoved(self)) ? nil : hit;
}

%end

%hook AWEProfileHeaderHomeShortcutCell

- (void)layoutSubviews {
    %orig;
    DKProfileHeaderTrackCell(self, DKKeyProfileEditMode,
                             [self respondsToSelector:@selector(profileContext)] && DKProfileHeaderMine([self profileContext]));
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = %orig;
    return (hit && DKProfileHeaderCellRemoved(self)) ? nil : hit;
}

%end

%hook AWEUserProfileUGCHeaderContributionGuideBannerSectionCell

- (void)layoutSubviews {
    %orig;
    DKProfileHeaderTrackCell(self, DKKeyProfileGuideBannerMode,
                             [self respondsToSelector:@selector(context)] && DKProfileHeaderMine([self context]));
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = %orig;
    return (hit && DKProfileHeaderCellRemoved(self)) ? nil : hit;
}

%end
