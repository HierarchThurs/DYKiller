//
//  DKSearchReveal.m
//

#import "DKSearchReveal.h"
#import "DKSearchIndex.h"
#import "DKSettingsInternal.h"
#import "DKSettingsLayout.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

// 闪现时长与几何。
static const NSTimeInterval kDKSearchFlashIn = 0.12;
static const NSTimeInterval kDKSearchFlashHold = 0.90;
static const NSTimeInterval kDKSearchFlashOut = 0.50;
static const CGFloat kDKSearchFlashInsetSide = 4.0;
static const CGFloat kDKSearchFlashInsetVertical = 2.0;
static const CGFloat kDKSearchFlashRadius = 10.0;

static char kDKSearchPagePathKey;
static char kDKSearchPendingKey;
static char kDKSearchFlashKey;

#pragma mark - 页面路径

void DKSearchSetPagePath(UIViewController *page, NSArray<NSString *> *path) {
    if (!page) return;
    objc_setAssociatedObject(page, &kDKSearchPagePathKey, [path copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

NSArray<NSString *> *DKSearchPagePath(UIViewController *page) {
    if (!page) return nil;
    id path = objc_getAssociatedObject(page, &kDKSearchPagePathKey);
    return [path isKindOfClass:NSArray.class] ? path : nil;
}

#pragma mark - 定位与闪现

static NSIndexPath *DKSearchIndexPathForIdentifier(UIViewController *page, NSString *identifier) {
    if (!identifier.length) return nil;
    NSArray *sections = DKSettingsPageSections(page);
    for (NSUInteger section = 0; section < sections.count; section++) {
        NSArray *items = ((AWESettingSectionModel *)sections[section]).itemArray;
        for (NSUInteger row = 0; row < items.count; row++) {
            AWESettingItemModel *item = items[row];
            if ([item.identifier isEqualToString:identifier]) {
                return [NSIndexPath indexPathForRow:(NSInteger)row inSection:(NSInteger)section];
            }
        }
    }
    return nil;
}

// 定位提示：横向渐变的强调色薄层，淡入后停留片刻再淡出。
@interface DKSearchFlashView : UIView
@end

@implementation DKSearchFlashView
+ (Class)layerClass {
    return CAGradientLayer.class;
}
@end

static void DKSearchFlashCell(UITableViewCell *cell) {
    if (!cell) return;
    UIView *existing = objc_getAssociatedObject(cell, &kDKSearchFlashKey);
    [existing removeFromSuperview];
    objc_setAssociatedObject(cell, &kDKSearchFlashKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    CGRect frame = CGRectInset(cell.contentView.bounds, kDKSearchFlashInsetSide, kDKSearchFlashInsetVertical);
    DKSearchFlashView *flash = [[DKSearchFlashView alloc] initWithFrame:frame];
    flash.userInteractionEnabled = NO;
    flash.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    flash.layer.cornerRadius = kDKSearchFlashRadius;
    flash.layer.cornerCurve = kCACornerCurveContinuous;
    flash.clipsToBounds = YES;

    UIColor *accent = UIColor.systemBlueColor;
    CAGradientLayer *layer = (CAGradientLayer *)flash.layer;
    layer.colors = @[ (id)[accent colorWithAlphaComponent:0.26].CGColor,
                      (id)[accent colorWithAlphaComponent:0.10].CGColor,
                      (id)[accent colorWithAlphaComponent:0.00].CGColor ];
    layer.startPoint = CGPointMake(0.0, 0.5);
    layer.endPoint = CGPointMake(1.0, 0.5);

    flash.alpha = 0.0;
    [cell.contentView addSubview:flash];
    objc_setAssociatedObject(cell, &kDKSearchFlashKey, flash, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [UIView animateWithDuration:kDKSearchFlashIn animations:^{
        flash.alpha = 1.0;
    } completion:^(__unused BOOL finished) {
        [UIView animateWithDuration:kDKSearchFlashOut delay:kDKSearchFlashHold
                            options:UIViewAnimationOptionCurveEaseInOut animations:^{
            flash.alpha = 0.0;
        } completion:^(__unused BOOL done) {
            [flash removeFromSuperview];
            if (objc_getAssociatedObject(cell, &kDKSearchFlashKey) == flash) {
                objc_setAssociatedObject(cell, &kDKSearchFlashKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }];
    }];
}

static void DKSearchRevealIndexPath(UIViewController *page, NSIndexPath *indexPath) {
    UITableView *table = DKSettingsPageTableView(page);
    if (!table || !indexPath) return;
    __weak UITableView *weakTable = table;
    // 等这一帧的布局落定再滚：viewDidAppear 时行可能还没排好。
    dispatch_async(dispatch_get_main_queue(), ^{
        UITableView *strongTable = weakTable;
        if (!strongTable) return;
        if (indexPath.section >= (NSInteger)strongTable.numberOfSections) return;
        if (indexPath.row >= [strongTable numberOfRowsInSection:indexPath.section]) return;
        [strongTable scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
        __weak UITableView *weakScrolled = strongTable;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UITableView *scrolled = weakScrolled;
            if (!scrolled) return;
            UITableViewCell *cell = [scrolled cellForRowAtIndexPath:indexPath];
            if (!cell) {
                [scrolled layoutIfNeeded];
                cell = [scrolled cellForRowAtIndexPath:indexPath];
            }
            DKSearchFlashCell(cell);
        });
    });
}

#pragma mark - 待定位标记

void DKSearchMarkPendingReveal(UIViewController *page, NSString *identifier) {
    if (!page || !identifier.length) return;
    objc_setAssociatedObject(page, &kDKSearchPendingKey, [identifier copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void DKSearchConsumePendingReveal(UIViewController *page) {
    NSString *identifier = objc_getAssociatedObject(page, &kDKSearchPendingKey);
    if (!identifier.length) return;
    objc_setAssociatedObject(page, &kDKSearchPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSIndexPath *indexPath = DKSearchIndexPathForIdentifier(page, identifier);
    if (indexPath) DKSearchRevealIndexPath(page, indexPath);
}

#pragma mark - 跨页导航

static NSArray<NSString *> *DKSearchIdentifiersOfPath(NSArray<DKSettingsPage *> *path) {
    NSMutableArray<NSString *> *identifiers = [NSMutableArray arrayWithCapacity:path.count];
    for (DKSettingsPage *spec in path) {
        if (spec.identifier.length) [identifiers addObject:spec.identifier];
    }
    return identifiers;
}

void DKSearchRevealTarget(UIViewController *from, DKSearchEntry *entry) {
    if (!from || !entry) return;

    NSArray<DKSettingsPage *> *pagePath = entry.pagePath;
    NSString *identifier = entry.identifier;
    BOOL isPageEntry = entry.isPageEntry;
    // 目标路径被锁时定位到父页的灰显入口，沿用普通点击的可达边界。
    for (NSUInteger index = 0; index < pagePath.count; index++) {
        DKSettingsPage *spec = pagePath[index];
        if (!DKSettingsKeyIsLocked(spec.identifier)) continue;
        identifier = spec.identifier;
        pagePath = [pagePath subarrayWithRange:NSMakeRange(0, index)];
        isPageEntry = NO;
        break;
    }

    // 就在当前页：直接滚到该行。
    if (!isPageEntry) {
        NSIndexPath *inPlace = DKSearchIndexPathForIdentifier(from, identifier);
        if (inPlace) {
            DKSearchRevealIndexPath(from, inPlace);
            return;
        }
    }

    UINavigationController *nav = from.navigationController;
    if (!nav) return;
    NSArray<NSString *> *identifiers = DKSearchIdentifiersOfPath(pagePath);

    // 导航栈里最深的、路径为目标前缀的 DYKiller 页面，就是补齐路径的起点。
    UIViewController *anchor = nil;
    NSUInteger depth = 0;
    for (UIViewController *page in nav.viewControllers.reverseObjectEnumerator) {
        NSArray<NSString *> *path = DKSearchPagePath(page);
        if (!path || path.count > identifiers.count) continue;
        BOOL prefix = YES;
        for (NSUInteger index = 0; index < path.count; index++) {
            if (![path[index] isEqualToString:identifiers[index]]) { prefix = NO; break; }
        }
        if (!prefix) continue;
        anchor = page;
        depth = path.count;
        break;
    }
    if (!anchor) return;
    if (anchor != nav.topViewController) [nav popToViewController:anchor animated:NO];

    NSMutableArray<UIViewController *> *added = [NSMutableArray array];
    for (NSUInteger index = depth; index < pagePath.count; index++) {
        AWESettingBaseViewController *page = DKSettingsBuildPage(pagePath[index]);
        if (!page) break;
        NSUInteger length = MIN(index + 1, identifiers.count);
        DKSearchSetPagePath(page, [identifiers subarrayWithRange:NSMakeRange(0, length)]);
        [added addObject:page];
    }
    if (added.count) {
        UIViewController *target = added.lastObject;
        if (!isPageEntry) DKSearchMarkPendingReveal(target, identifier);
        NSMutableArray<UIViewController *> *stack = [nav.viewControllers mutableCopy];
        [stack addObjectsFromArray:added];
        [nav setViewControllers:stack animated:YES];
        return;
    }

    // 目标页已在栈里：挂上待定位标记，由它的 viewDidAppear 消费。
    if (isPageEntry) return;
    if (nav.topViewController == anchor) {
        NSIndexPath *indexPath = DKSearchIndexPathForIdentifier(anchor, identifier);
        if (indexPath) DKSearchRevealIndexPath(anchor, indexPath);
        return;
    }
    DKSearchMarkPendingReveal(anchor, identifier);
}
