// 按原生底部容器归属覆盖全部底部相关栏目：清除行内承载内容的底色，文字、图标与分隔圆点保留。
#import "DKRelatedBarBackground.h"
#import "DKPlaybackCatalog.h"
#import "DKPlaybackCleanRules.h"
#import "DKPlaybackOverlay.h"
#import "DKViewAdjust.h"
#import "DKKeys.h"
#import "DKUtils.h"

static BOOL gDKRelatedBarBackgroundUsed;

static BOOL DKRelatedBarColorVisible(UIColor *color) {
    return color && CGColorGetAlpha(color.CGColor) > 0;
}

// 底色衬在其他内容下面才算背景：容器、带底色的文字（标签胶囊）、盖住同级内容的空白视图。
// 不遮挡内容的小色块（分隔圆点）本身就是内容。
static BOOL DKRelatedBarViewIsBackdrop(UIView *view) {
    if (!DKRelatedBarColorVisible(view.backgroundColor)) return NO;
    if (view.subviews.count || [view respondsToSelector:@selector(attributedText)]) return YES;
    for (UIView *sibling in view.superview.subviews) {
        if (sibling == view || sibling.hidden || CGRectIsEmpty(sibling.bounds)) continue;
        if (CGRectContainsPoint(view.frame, sibling.center)) return YES;
    }
    return NO;
}

static void DKRelatedBarSyncBackdrops(UIView *view, BOOL transparent) {
    for (UIView *subview in view.subviews) {
        if (!transparent || DKAdjustBackgroundCleared(subview) || DKRelatedBarViewIsBackdrop(subview)) {
            DKAdjustClearBackground(subview, transparent);
        }
        DKRelatedBarSyncBackdrops(subview, transparent);
    }
}

void DKRelatedBarBackgroundApplyStack(UIView *stack) {
    BOOL enabled = DKPrefBool(DKKeyPlaybackBottomBarTransparent);
    if (!enabled && !gDKRelatedBarBackgroundUsed) return;
    if (!DKPlaybackCatalogStackIsBottom(stack)) return;
    gDKRelatedBarBackgroundUsed = YES;
    // 清屏页的底部容器放的是倍速等控件，不是相关栏目。
    BOOL transparent = enabled && !DKPlaybackOverlayIsPureControl(stack);
    for (UIView *row in ((UIStackView *)stack).arrangedSubviews) {
        if (!DKCleanRowElement(row)) continue;
        DKRelatedBarSyncBackdrops(row, transparent);
    }
}

static void DKRelatedBarCollectColors(UIView *view, NSMutableArray<NSString *> *cleared, NSMutableArray<NSString *> *remaining) {
    for (UIView *subview in view.subviews) {
        NSString *name = [NSString stringWithFormat:@"%@(%.0fx%.0f)", NSStringFromClass(subview.class),
            CGRectGetWidth(subview.bounds), CGRectGetHeight(subview.bounds)];
        if (DKAdjustBackgroundCleared(subview)) [cleared addObject:name];
        else if (DKRelatedBarColorVisible(subview.backgroundColor)) [remaining addObject:name];
        DKRelatedBarCollectColors(subview, cleared, remaining);
    }
}

NSString *DKRelatedBarBackgroundRowStatus(UIView *row) {
    NSMutableArray<NSString *> *cleared = [NSMutableArray array];
    NSMutableArray<NSString *> *remaining = [NSMutableArray array];
    DKRelatedBarCollectColors(row, cleared, remaining);
    return [NSString stringWithFormat:@"      背景透明=%d 已清底色=[%@] 保留底色=[%@]\n",
        DKPrefBool(DKKeyPlaybackBottomBarTransparent),
        [cleared componentsJoinedByString:@" "], [remaining componentsJoinedByString:@" "]];
}
