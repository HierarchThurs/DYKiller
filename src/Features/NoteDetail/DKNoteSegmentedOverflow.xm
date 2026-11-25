#import "DKNoteDetailGlassShared.h"
#import "DKViewAdjust.h"

#import <objc/runtime.h>

@interface DKNoteTabListHolder : NSObject <UIScrollViewDelegate>
@property (nonatomic, weak) UIScrollView *tabSelectedScrollView;
@property (nonatomic, strong) UIView *headerView;
@end

static __weak UICollectionView *gDKNoteOverflowList;
// 只作地址比对，未登记的列表在 _visibleBounds 里不读弱引用。
static const void *gDKNoteOverflowListAddress;
static __weak UIView *gDKNoteOverflowBar;
static Class gDKNotePagerClass;
static char kDKNoteSegmentedOverflowKey;

@interface DKNoteSegmentedOverflow : NSObject
@property (nonatomic, weak) DKNoteTabListHolder *holder;
@property (nonatomic, weak) UIScrollView *pager;
@property (nonatomic, weak) UIView *header;
@property (nonatomic) BOOL clipsToBounds;
@property (nonatomic) CGFloat originalZ;
@property (nonatomic) CGFloat appliedZ;
@property (nonatomic, weak) UICollectionView *list;
- (void)selectList:(UIScrollView *)view;
@end

@implementation DKNoteSegmentedOverflow

- (void)selectList:(UIScrollView *)view {
    UICollectionView *list = [view isKindOfClass:UICollectionView.class] ? (UICollectionView *)view : nil;
    if (list == self.list) return;
    UICollectionView *previous = self.list;
    self.list = list;
    gDKNoteOverflowList = list;
    gDKNoteOverflowListAddress = (__bridge const void *)list;
    [previous setNeedsLayout];
    [list setNeedsLayout];
}

- (void)dealloc {
    UICollectionView *list = _list;
    if (gDKNoteOverflowList == list) {
        gDKNoteOverflowList = nil;
        gDKNoteOverflowListAddress = NULL;
    }
    [list setNeedsLayout];
    UIScrollView *pager = _pager;
    if (!pager.clipsToBounds && _clipsToBounds) pager.clipsToBounds = YES;
    if (_appliedZ != _originalZ && pager.layer.zPosition == _appliedZ) pager.layer.zPosition = _originalZ;
    DKAdjustFade(_header, 1.0, CGSizeZero);
}

@end

void DKNoteSetSegmentedOverflow(UIView *bar, BOOL enabled) {
    UIScrollView *scroller = enabled ? DKNoteScrollerForBar(bar) : nil;
    DKNoteTabListHolder *holder = (DKNoteTabListHolder *)scroller.delegate;
    UIScrollView *pager = nil;
    if ([holder respondsToSelector:@selector(tabSelectedScrollView)]) {
        for (UIView *child in scroller.subviews) {
            if (![child isKindOfClass:gDKNotePagerClass]) continue;
            pager = (UIScrollView *)child;
            break;
        }
    }
    DKNoteSegmentedOverflow *state = objc_getAssociatedObject(bar, &kDKNoteSegmentedOverflowKey);
    if (state && (!pager || state.pager != pager || state.holder != holder)) {
        gDKNoteOverflowBar = nil;
        objc_setAssociatedObject(bar, &kDKNoteSegmentedOverflowKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        state = nil;
    }
    if (!pager) return;
    if (!state) {
        UIView *previousBar = gDKNoteOverflowBar;
        if (previousBar) DKNoteSetSegmentedOverflow(previousBar, NO);
        state = [DKNoteSegmentedOverflow new];
        state.holder = holder;
        state.pager = pager;
        state.clipsToBounds = pager.clipsToBounds;
        state.originalZ = pager.layer.zPosition;
        CGFloat siblingZ = 0.0;
        for (UIView *child in scroller.subviews) {
            if (child != pager) siblingZ = MAX(siblingZ, child.layer.zPosition);
        }
        state.appliedZ = MAX(state.originalZ, siblingZ + 1.0);
        pager.clipsToBounds = NO;
        pager.layer.zPosition = state.appliedZ;
        // 吸顶后正文整块位于顶栏下方，评论 cell 底色透明，淡出正文避免两层文字叠在玻璃下。
        if ([holder respondsToSelector:@selector(headerView)]) {
            state.header = holder.headerView;
            DKAdjustFade(state.header, 0.0, CGSizeZero);
        }
        objc_setAssociatedObject(bar, &kDKNoteSegmentedOverflowKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        gDKNoteOverflowBar = bar;
    }
    [state selectList:holder.tabSelectedScrollView];
}

%group DKNoteSegmentedOverflowHooks
%hook UICollectionView
- (CGRect)_visibleBounds {
    CGRect bounds = %orig;
    if ((__bridge const void *)self != gDKNoteOverflowListAddress || self != gDKNoteOverflowList) return bounds;
    UIView *bar = gDKNoteOverflowBar;
    if (!bar) return bounds;
    CGRect barInList = [self convertRect:bar.bounds fromView:bar];
    CGFloat extension = MAX(0.0, CGRectGetMinY(self.bounds) - CGRectGetMinY(barInList));
    bounds.origin.y -= extension;
    bounds.size.height += extension;
    return bounds;
}
%end

%hook DKNoteTabListHolder
- (void)setTabSelectedScrollView:(UIScrollView *)view {
    %orig;
    UIView *bar = gDKNoteOverflowBar;
    if (!bar) return;
    DKNoteSegmentedOverflow *state = objc_getAssociatedObject(bar, &kDKNoteSegmentedOverflowKey);
    if (state.holder == self) [state selectList:state.holder.tabSelectedScrollView];
}
%end
%end

void DKNoteInstallSegmentedOverflowHooks(void) {
    Class pager = objc_getClass("AWETabListTabContainerScrollView");
    Class holder = objc_getClass("AWETabListInnerViewHolder");
    if (pager && class_getInstanceMethod(UICollectionView.class, @selector(_visibleBounds))
        && class_getInstanceMethod(holder, @selector(setTabSelectedScrollView:))) {
        gDKNotePagerClass = pager;
        %init(DKNoteSegmentedOverflowHooks, DKNoteTabListHolder=holder);
    }
}
