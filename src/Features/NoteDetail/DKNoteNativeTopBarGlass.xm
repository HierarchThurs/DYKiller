#import "DKChatGlassStore.h"
#import "DKGlassGuard.h"
#import "DKImageOpaque.h"
#import "DKKeys.h"
#import "DKNoteDetailGlassShared.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"

#import <objc/runtime.h>

@interface DKNoteNativeTopBar : UIView @end

@interface DKNoteRelationButton : UIButton
@property (nonatomic, strong) id relationItem;
@end

static Class gDKNoteNativeTopBarClass;
static Class gDKNoteAuthorClass;
static Class gDKNoteRecommendClass;
static Class gDKNoteSegmentedClass;
static Class gDKNoteSegmentedCellClass;
static Class gDKNoteIndicatorClass;
static Class gDKNoteRelationClass;
static NSHashTable<UIView *> *gDKNoteNativeTopBars;
static char kDKNoteNativeGlassStateKey;

@interface DKNoteNativeParts : NSObject
@property (nonatomic, weak) UIImageView *back;
@property (nonatomic, weak) UIImageView *search;
@property (nonatomic, weak) UIView *author;
@property (nonatomic, weak) UIImageView *avatar;
@property (nonatomic, weak) UILabel *name;
@property (nonatomic, weak) DKNoteRelationButton *follow;
@property (nonatomic, weak) UIView *recommend;
@property (nonatomic, weak) UILabel *title;
@property (nonatomic, weak) UIView *segmented;
@property (nonatomic, weak) UIView *indicator;
@property (nonatomic, weak) UIView *separator;
- (UIView *)visibleMiddle;
@end

@implementation DKNoteNativeParts
- (UIView *)visibleMiddle {
    UIView *visible = nil;
    CGFloat alpha = 0.01;
    UIView *candidates[] = {self.author, self.recommend, self.segmented};
    for (UIView *candidate : candidates) {
        if (candidate.hidden || candidate.alpha <= alpha) continue;
        visible = candidate;
        alpha = candidate.alpha;
    }
    return visible;
}
@end

@interface DKNoteNativeGlassItem : NSObject
@property (nonatomic, weak) UIView *source;
@property (nonatomic) CGRect frame;
@end
@implementation DKNoteNativeGlassItem
@end

@interface DKNoteNativeGlassState : NSObject
@property (nonatomic, strong) DKNoteNativeParts *parts;
@property (nonatomic, weak) UIView *middle;
@property (nonatomic, weak) UIView *listHeader;
@property (nonatomic, strong) UIVisualEffectView *glassContainer;
@property (nonatomic, copy) NSArray<DKNoteNativeGlassItem *> *middleItems;
@property (nonatomic, strong) DKNoteNativeGlassItem *primaryItem;
@property (nonatomic) BOOL syncing;
@property (nonatomic) BOOL followBorderCleared;
@end
@implementation DKNoteNativeGlassState
- (void)dealloc {
    DKAdjustFade(_listHeader, 1.0, CGSizeZero);
}
@end

static DKNoteNativeGlassState *DKNoteNativeState(UIView *bar) {
    return bar ? objc_getAssociatedObject(bar, &kDKNoteNativeGlassStateKey) : nil;
}

static UIView *DKNoteNativeBarForView(UIView *view) {
    for (UIView *node = view.superview; node; node = node.superview) {
        if ([node isKindOfClass:gDKNoteNativeTopBarClass]) return node;
    }
    return nil;
}

static DKNoteNativeParts *DKNoteReadNativeParts(UIView *bar, UIView *glassContainer) {
    DKNoteNativeParts *parts = [DKNoteNativeParts new];
    UIView *content = nil;
    for (UIView *child in bar.subviews) {
        if (child == glassContainer) continue;
        UIImageView *left = nil;
        UIImageView *right = nil;
        for (UIView *item in child.subviews) {
            if (![item isKindOfClass:UIImageView.class]) continue;
            UIImageView *image = (UIImageView *)item;
            CGFloat x = CGRectGetMidX(DKAdjustLayoutFrame(image));
            if (!left || x < CGRectGetMidX(DKAdjustLayoutFrame(left))) left = image;
            if (!right || x > CGRectGetMidX(DKAdjustLayoutFrame(right))) right = image;
        }
        if (left && right && left != right) {
            content = child;
            parts.back = left;
            parts.search = right;
            break;
        }
    }
    if (!content) return nil;

    for (UIView *child in bar.subviews) {
        if (child == content || child.class != UIView.class) continue;
        CGRect frame = DKAdjustLayoutFrame(child);
        if (CGRectGetHeight(frame) > 0.0 && CGRectGetHeight(frame) <= 1.0
            && CGRectGetWidth(frame) >= CGRectGetWidth(bar.bounds)
            && CGRectGetMaxY(frame) >= CGRectGetMaxY(bar.bounds) - 1.0) {
            parts.separator = child;
            break;
        }
    }

    // 内容容器下的中部容器承载三个相互淡化的状态视图。
    for (UIView *container in content.subviews) {
        for (UIView *item in container.subviews) {
            if ([item isKindOfClass:gDKNoteAuthorClass]) parts.author = item;
            else if ([item isKindOfClass:gDKNoteRecommendClass]) parts.recommend = item;
            else if ([item isKindOfClass:gDKNoteSegmentedClass]) parts.segmented = item;
        }
    }
    for (UIView *item in parts.author.subviews) {
        if ([item isKindOfClass:UIImageView.class]) parts.avatar = (UIImageView *)item;
        else if ([item isKindOfClass:UILabel.class]) parts.name = (UILabel *)item;
        else if ([item isKindOfClass:gDKNoteRelationClass]) parts.follow = (DKNoteRelationButton *)item;
    }
    for (UIView *item in parts.recommend.subviews) {
        if ([item isKindOfClass:UILabel.class]) parts.title = (UILabel *)item;
    }
    for (UIView *container in parts.segmented.subviews) {
        if (![container isKindOfClass:UICollectionView.class]) continue;
        for (UIView *item in container.subviews) {
            if ([item isKindOfClass:gDKNoteIndicatorClass]) parts.indicator = item;
        }
    }
    return parts;
}

static void DKNoteClearFollowBorder(DKNoteNativeGlassState *state) {
    CALayer *layer = state.parts.follow.layer;
    if (layer.borderWidth == 0.0) return;
    layer.borderWidth = 0.0;
    state.followBorderCleared = YES;
}

static void DKNoteRestoreNativeParts(DKNoteNativeGlassState *state, DKNoteNativeParts *current) {
    DKNoteNativeParts *old = state.parts;
    if (old.back != current.back) DKAdjustTransform(old.back, CGAffineTransformIdentity);
    if (old.search != current.search) DKAdjustTransform(old.search, CGAffineTransformIdentity);
    if (old.avatar != current.avatar) DKAdjustTransform(old.avatar, CGAffineTransformIdentity);
    if (old.name != current.name) DKAdjustTransform(old.name, CGAffineTransformIdentity);
    if (old.title != current.title) DKAdjustTransform(old.title, CGAffineTransformIdentity);
    if (old.follow != current.follow) {
        DKNoteRelationButton *follow = old.follow;
        DKAdjustTransform(follow, CGAffineTransformIdentity);
        if (state.followBorderCleared) {
            state.followBorderCleared = NO;
            follow.relationItem = follow.relationItem;
        }
    }
    if (old.separator != current.separator) DKAdjustFade(old.separator, 1.0, CGSizeZero);
    if (old.indicator != current.indicator) DKAdjustFade(old.indicator, 1.0, CGSizeZero);
}

static CGRect DKNoteNativeFrame(UIView *view, UIView *bar) {
    return view ? [view.superview convertRect:DKAdjustLayoutFrame(view) toView:bar] : CGRectZero;
}

static void DKNoteCenterNativeElement(UIView *view, CGRect glass, UIView *bar) {
    CGPoint center = CGPointMake(CGRectGetMidX(glass), CGRectGetMidY(glass));
    center = [view.superview convertPoint:center fromView:bar];
    CGRect frame = DKAdjustLayoutFrame(view);
    DKAdjustTransform(view, CGAffineTransformMakeTranslation(center.x - CGRectGetMidX(frame), center.y - CGRectGetMidY(frame)));
}

// 图标按实际画出的像素居中：返回图片里的箭头不在 24pt 画布中间。没有位图时按图片框。
static void DKNoteCenterNativeIcon(UIImageView *icon, CGRect glass, UIView *bar) {
    if (!icon) return;
    CGRect visible = DKImageOpaqueVisibleRect(icon);
    if (CGRectIsNull(visible)) visible = icon.bounds;
    CGPoint center = [icon.superview convertPoint:CGPointMake(CGRectGetMidX(glass), CGRectGetMidY(glass)) fromView:bar];
    CGRect frame = DKAdjustLayoutFrame(icon);
    DKAdjustTransform(icon, CGAffineTransformMakeTranslation(center.x - CGRectGetMinX(frame) - CGRectGetMidX(visible),
                                                             center.y - CGRectGetMinY(frame) - CGRectGetMidY(visible)));
}

static CGRect DKNoteNativeCapsule(CGFloat x, CGFloat width, CGFloat centerY) {
    return CGRectMake(x, centerY - kDKNoteTopHeight * 0.5, width, kDKNoteTopHeight);
}

static CGFloat DKNoteTextWidth(UILabel *label) {
    if (!label) return 0.0;
    CGSize size = label.bounds.size;
    return MIN(size.width, [label sizeThatFits:CGSizeMake(CGFLOAT_MAX, size.height)].width);
}

static DKNoteNativeGlassItem *DKNoteNativeItem(UIView *source, CGRect frame) {
    DKNoteNativeGlassItem *item = [DKNoteNativeGlassItem new];
    item.source = source;
    item.frame = frame;
    return item;
}

static void DKNoteLayoutNativeAuthor(UIView *bar, DKNoteNativeParts *parts, CGFloat centerY,
                                     CGFloat cursor, CGFloat limit, NSMutableArray<DKNoteNativeGlassItem *> *items,
                                     BOOL *maskName) {
    UIImageView *avatar = parts.avatar;
    if (avatar && !avatar.hidden) {
        CGRect glass = DKNoteNativeCapsule(cursor, kDKNoteTopHeight, centerY);
        DKNoteCenterNativeElement(avatar, glass, bar);
        if (items) [items addObject:DKNoteNativeItem(avatar, glass)];
        cursor = CGRectGetMaxX(glass) + kDKNoteClusterGap;
    }

    DKNoteRelationButton *follow = parts.follow;
    CGRect followFrame = DKNoteNativeFrame(follow, bar);
    DKNoteNativeGlassItem *followItem = nil;
    if (follow && !follow.hidden && follow.alpha > 0.01 && !CGRectIsEmpty(followFrame)) {
        CGRect glass = DKNoteNativeCapsule(CGRectGetMinX(followFrame), CGRectGetWidth(followFrame), centerY);
        DKNoteCenterNativeElement(follow, glass, bar);
        if (items) followItem = DKNoteNativeItem(follow, glass);
        limit = MIN(limit, CGRectGetMinX(glass) - kDKNoteEdge);
    }

    UILabel *name = parts.name;
    CGFloat textWidth = DKNoteTextWidth(name);
    CGFloat wantedWidth = textWidth + 2.0 * kDKNoteNamePadding;
    CGFloat width = MIN(wantedWidth, limit - cursor);
    if (textWidth <= 0.0 || width <= 0.0 || name.hidden) {
        DKAdjustTransform(name, CGAffineTransformIdentity);
    } else {
        CGRect glass = DKNoteNativeCapsule(cursor, width, centerY);
        CGRect frame = DKNoteNativeFrame(name, bar);
        CGRect destination = CGRectMake(cursor + kDKNoteNamePadding, CGRectGetMinY(glass),
                                        CGRectGetWidth(frame), CGRectGetHeight(glass));
        DKNoteCenterNativeElement(name, destination, bar);
        if (items) [items addObject:DKNoteNativeItem(name, glass)];
        *maskName = width < wantedWidth;
    }
    if (followItem) [items addObject:followItem];
}

static UILabel *DKNoteFirstLabel(UIView *view) {
    for (UIView *child in view.subviews) {
        if (child.hidden) continue;
        if ([child isKindOfClass:UILabel.class]) return (UILabel *)child;
        UILabel *label = DKNoteFirstLabel(child);
        if (label) return label;
    }
    return nil;
}

static NSArray<DKNoteNativeGlassItem *> *DKNoteSegmentItems(UIView *bar, UIView *segmented, CGFloat centerY) {
    NSMutableArray<DKNoteNativeGlassItem *> *items = [NSMutableArray array];
    for (UIView *container in segmented.subviews) {
        if (![container isKindOfClass:UICollectionView.class]) continue;
        for (UIView *cell in container.subviews) {
            if (![cell isKindOfClass:gDKNoteSegmentedCellClass] || cell.hidden) continue;
            UILabel *label = DKNoteFirstLabel(cell);
            CGFloat textWidth = DKNoteTextWidth(label);
            if (textWidth <= 0.0) continue;
            CGRect cellFrame = DKNoteNativeFrame(cell, bar);
            CGRect text = [label textRectForBounds:label.bounds limitedToNumberOfLines:label.numberOfLines];
            CGFloat centerX = [label convertPoint:CGPointMake(CGRectGetMidX(text), CGRectGetMidY(text)) toView:bar].x;
            // 两侧以文字为中心收边，相邻胶囊至少留出一份簇间距。
            CGRect inset = CGRectInset(cellFrame, kDKNoteClusterGap * 0.5, 0.0);
            CGFloat limit = MIN(centerX - CGRectGetMinX(inset), CGRectGetMaxX(inset) - centerX);
            CGFloat halfWidth = MIN(textWidth * 0.5 + kDKNoteNamePadding, limit);
            if (halfWidth <= 0.0) continue;
            [items addObject:DKNoteNativeItem(cell, DKNoteNativeCapsule(centerX - halfWidth, 2.0 * halfWidth, centerY))];
        }
    }
    [items sortUsingComparator:^NSComparisonResult(DKNoteNativeGlassItem *lhs, DKNoteNativeGlassItem *rhs) {
        CGFloat a = CGRectGetMidX(lhs.frame), b = CGRectGetMidX(rhs.frame);
        return a < b ? NSOrderedAscending : a > b ? NSOrderedDescending : NSOrderedSame;
    }];
    return items;
}

static DKNoteNativeGlassItem *DKNoteNearestItem(DKNoteNativeGlassItem *item, NSArray<DKNoteNativeGlassItem *> *items) {
    DKNoteNativeGlassItem *nearest = nil;
    CGFloat best = CGFLOAT_MAX;
    for (DKNoteNativeGlassItem *candidate in items) {
        if (candidate == item) continue;
        CGFloat dx = CGRectGetMidX(candidate.frame) - CGRectGetMidX(item.frame);
        CGFloat dy = CGRectGetMidY(candidate.frame) - CGRectGetMidY(item.frame);
        CGFloat distance = dx * dx + dy * dy;
        if (distance >= best) continue;
        nearest = candidate;
        best = distance;
    }
    return nearest;
}

API_AVAILABLE(ios(26.0))
static void DKNotePairNativeGlass(DKChatGlassStore *store, UIView *carrier, DKNoteNativeGlassState *state,
                                  NSArray<DKNoteNativeGlassItem *> *middle, DKNoteNativeGlassItem *primary,
                                  NSArray<DKNoteNativeGlassItem *> *layout) {
    NSArray<DKNoteNativeGlassItem *> *old = state.middleItems;
    NSMutableArray<DKNoteNativeGlassItem *> *exits = [old mutableCopy];
    NSMutableArray<DKNoteNativeGlassItem *> *entries = [middle mutableCopy];
    if (state.primaryItem && primary) {
        NSInteger from = [old indexOfObjectIdenticalTo:state.primaryItem];
        NSInteger to = [middle indexOfObjectIdenticalTo:primary];
        NSInteger last = MIN((NSInteger)old.count - from, (NSInteger)middle.count - to);
        // 相同的相对下标表示主玻璃同侧、距主玻璃同序的槽位。
        for (NSInteger offset = -MIN(from, to); offset < last; offset++) {
            DKNoteNativeGlassItem *outgoing = old[from + offset];
            DKNoteNativeGlassItem *incoming = middle[to + offset];
            if ([store moveSlotFromSource:outgoing.source toSource:incoming.source]) {
                [exits removeObjectIdenticalTo:outgoing];
                [entries removeObjectIdenticalTo:incoming];
            }
        }
    }
    for (DKNoteNativeGlassItem *item in exits) {
        DKNoteNativeGlassItem *nearest = DKNoteNearestItem(item, layout);
        if (nearest) [store retireGlassFor:item.source toFrame:nearest.frame];
    }
    for (DKNoteNativeGlassItem *item in entries) {
        DKNoteNativeGlassItem *nearest = DKNoteNearestItem(item, layout);
        if (nearest) [store prepareGlassFor:item.source in:carrier fromFrame:nearest.frame];
    }
}

API_AVAILABLE(ios(26.0))
static UIView *DKNoteGlassCarrier(UIView *bar, DKNoteNativeGlassState *state) {
    UIVisualEffectView *container = state.glassContainer;
    if (!container) {
        [UIView performWithoutAnimation:^{
            UIVisualEffectView *view = [[UIVisualEffectView alloc] initWithFrame:bar.bounds];
            view.userInteractionEnabled = NO;
            [bar insertSubview:view atIndex:0];
            state.glassContainer = view;
        }];
        container = state.glassContainer;
    }
    container.frame = bar.bounds;
    if (!container.effect && !CGRectIsEmpty(container.bounds)) {
        UIGlassContainerEffect *effect = [UIGlassContainerEffect new];
        effect.spacing = kDKNoteGlassMergeSpacing;
        [UIView performWithoutAnimation:^{ container.effect = effect; }];
    }
    return container.contentView;
}

static void DKNoteSyncListHeader(UIView *bar, DKNoteNativeGlassState *state, BOOL segmented) {
    UIView *header = nil;
    if (segmented) {
        for (UIView *child in DKNoteScrollerForBar(bar).subviews) {
            if ([child isKindOfClass:gDKNoteSegmentedClass]) {
                header = child;
                break;
            }
        }
    }
    if (header != state.listHeader) {
        DKAdjustFade(state.listHeader, 1.0, CGSizeZero);
        state.listHeader = header;
    }
    DKAdjustFade(header, 0.0, CGSizeZero);
}

API_AVAILABLE(ios(26.0))
static void DKNoteApplyNativeGlass(UIView *bar, DKNoteNativeGlassState *state, DKNoteNativeParts *parts,
                                     UIView *middle, BOOL animate) {
    state.syncing = YES;
    DKNoteRestoreNativeParts(state, parts);
    state.parts = parts;
    state.middle = middle;

    DKChatGlassStore *store = [DKChatGlassStore storeForOwner:bar create:YES];
    [store beginWithClear:DKPrefBool(DKKeyNoteDetailGlassClear) style:bar.traitCollection.userInterfaceStyle
       animateSlotChanges:animate];
    [store clearBackingOfView:bar];
    DKAdjustFade(parts.separator, 0.0, CGSizeZero);
    DKAdjustFade(parts.indicator, 0.0, CGSizeZero);
    DKNoteClearFollowBorder(state);

    CGFloat centerY = CGRectGetMidY(DKNoteNativeFrame(parts.back, bar));
    CGRect back = DKNoteNativeCapsule(CGRectGetMinX(bar.bounds) + kDKNoteEdge, kDKNoteTopHeight, centerY);
    CGRect search = DKNoteNativeCapsule(CGRectGetMaxX(bar.bounds) - kDKNoteEdge - kDKNoteTopHeight, kDKNoteTopHeight, centerY);
    DKNoteCenterNativeIcon(parts.back, back, bar);
    DKNoteCenterNativeIcon(parts.search, search, bar);
    DKNoteNativeGlassItem *backItem = DKNoteNativeItem(parts.back, back);
    DKNoteNativeGlassItem *searchItem = !parts.search.hidden && parts.search.alpha > 0.01
        ? DKNoteNativeItem(parts.search, search) : nil;

    BOOL author = middle && middle == parts.author;
    BOOL segmented = middle && middle == parts.segmented;
    BOOL maskName = NO;
    NSMutableArray<DKNoteNativeGlassItem *> *authorItems = author ? [NSMutableArray arrayWithCapacity:3] : nil;
    DKNoteLayoutNativeAuthor(bar, parts, centerY, CGRectGetMaxX(back) + kDKNoteClusterGap,
                             CGRectGetMinX(search) - kDKNoteEdge, authorItems, &maskName);
    NSArray<DKNoteNativeGlassItem *> *middleItems = @[];
    DKNoteNativeGlassItem *primary = nil;

    if (author) {
        middleItems = authorItems;
        for (DKNoteNativeGlassItem *item in middleItems) if (item.source == parts.name) primary = item;
    } else if (middle && middle == parts.recommend) {
        CGRect frame = DKNoteNativeFrame(parts.title, bar);
        CGFloat textWidth = DKNoteTextWidth(parts.title);
        if (textWidth > 0.0) {
            CGFloat width = textWidth + 2.0 * kDKNoteNamePadding;
            CGRect glass = DKNoteNativeCapsule(CGRectGetMidX(frame) - width * 0.5, width, centerY);
            DKNoteCenterNativeElement(parts.title, glass, bar);
            primary = DKNoteNativeItem(parts.title, glass);
            middleItems = @[primary];
        }
    } else if (segmented) {
        middleItems = DKNoteSegmentItems(bar, parts.segmented, centerY);
        primary = middleItems.firstObject;
    }

    NSMutableArray<DKNoteNativeGlassItem *> *layout = [NSMutableArray arrayWithObject:backItem];
    [layout addObjectsFromArray:middleItems];
    if (searchItem) [layout addObject:searchItem];
    UIView *carrier = DKNoteGlassCarrier(bar, state);
    if (animate) DKNotePairNativeGlass(store, carrier, state, middleItems, primary, layout);
    NSMutableArray<DKNoteGlassHit *> *hits = [NSMutableArray arrayWithCapacity:layout.count];
    for (DKNoteNativeGlassItem *item in layout) {
        UIView *source = item.source;
        UIVisualEffectView *glass = [store placeGlassFor:source in:carrier frame:item.frame shape:DKChatGlassShapeRounded
                                                  radius:kDKNoteTopHeight * 0.5 interactive:NO tint:nil];
        if (!glass) continue;
        if (author || item == backItem || item == searchItem) {
            [hits addObject:[DKNoteGlassHit hitWithRect:item.frame target:source]];
        }
        if (author && maskName && item == primary) [store maskView:source toGlass:glass];
    }
    state.middleItems = middleItems;
    state.primaryItem = primary;
    DKNoteSetGlassHits(bar, hits);
    DKNoteSetContentOverflow(bar, YES);
    [store end];
    DKNoteSyncListHeader(bar, state, segmented);
    DKNoteSetSegmentedOverflow(bar, segmented);
    state.syncing = NO;
}

static CAPropertyAnimation *DKNoteOpacityAnimation(UIView *view) {
    for (NSString *key in view.layer.animationKeys) {
        CAAnimation *animation = [view.layer animationForKey:key];
        if ([animation isKindOfClass:CAPropertyAnimation.class]
            && [((CAPropertyAnimation *)animation).keyPath isEqualToString:@"opacity"]
            && animation.duration > 0.0) return (CAPropertyAnimation *)animation;
    }
    return nil;
}

API_AVAILABLE(ios(26.0))
static void DKNoteSyncNativeTopBar(UIView *bar) {
    DKNoteNativeGlassState *state = DKNoteNativeState(bar);
    if (state.syncing) return;
    DKNoteNativeParts *parts = DKNoteGlassEnabled() ? DKNoteReadNativeParts(bar, state.glassContainer) : nil;
    if (!parts) {
        if (!state) return;
        [UIView performWithoutAnimation:^{
            state.syncing = YES;
            [DKChatGlassStore removeStoreForOwner:bar];
            [state.glassContainer removeFromSuperview];
            DKNoteRestoreNativeParts(state, nil);
            DKNoteSyncListHeader(bar, state, NO);
            DKNoteSetSegmentedOverflow(bar, NO);
            DKNoteSetGlassHits(bar, nil);
            DKNoteSetContentOverflow(bar, NO);
            objc_setAssociatedObject(bar, &kDKNoteNativeGlassStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }];
        return;
    }
    if (!state) {
        state = [DKNoteNativeGlassState new];
        objc_setAssociatedObject(bar, &kDKNoteNativeGlassStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    UIView *middle = parts.visibleMiddle;
    BOOL changed = state.parts && middle != state.middle;
    BOOL inherited = UIView.inheritedAnimationDuration > 0.0;
    if (changed && !inherited) {
        CAPropertyAnimation *opacity = DKNoteOpacityAnimation(middle) ?: DKNoteOpacityAnimation(state.middle);
        if (opacity) {
            CAMediaTimingFunction *curve = opacity.timingFunction ?: [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionDefault];
            float first[2], second[2];
            [curve getControlPointAtIndex:1 values:first];
            [curve getControlPointAtIndex:2 values:second];
            UICubicTimingParameters *timing = [[UICubicTimingParameters alloc]
                initWithControlPoint1:CGPointMake(first[0], first[1]) controlPoint2:CGPointMake(second[0], second[1])];
            UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc] initWithDuration:opacity.duration timingParameters:timing];
            [animator addAnimations:^{ DKNoteApplyNativeGlass(bar, state, parts, middle, YES); }];
            [animator startAnimation];
            return;
        }
    }
    DKNoteApplyNativeGlass(bar, state, parts, middle, changed && inherited);
}

void DKNoteRefreshNativeTopBars(void) {
    if (@available(iOS 26.0, *)) {
        for (UIView *bar in gDKNoteNativeTopBars.allObjects) DKNoteSyncNativeTopBar(bar);
    }
}

%group DKNoteNativeTopBarHooks
%hook DKNoteNativeTopBar
- (void)layoutSubviews {
    %orig;
    if (!NSThread.isMainThread) return;
    if (@available(iOS 26.0, *)) {
        [gDKNoteNativeTopBars addObject:self];
        DKNoteSyncNativeTopBar(self);
    }
}

- (void)animatedChange:(NSInteger)type {
    %orig;
    if (!NSThread.isMainThread || !DKNoteGlassEnabled()) return;
    if (@available(iOS 26.0, *)) {
        DKNoteNativeGlassState *state = DKNoteNativeState(self);
        if (state.parts.visibleMiddle != state.middle) DKNoteSyncNativeTopBar(self);
    }
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *result = %orig;
    return result && NSThread.isMainThread ? DKNoteGlassTargetAtPoint(self, point) ?: result : result;
}
%end
%end

%group DKNoteRelationButtonHooks
%hook DKNoteRelationButton
- (void)setRelationItem:(id)item {
    %orig;
    if (!NSThread.isMainThread || !DKNoteGlassEnabled()) return;
    UIView *bar = DKNoteNativeBarForView(self);
    DKNoteNativeGlassState *state = DKNoteNativeState(bar);
    if (state.syncing) return;
    if (state.parts.follow == self) DKNoteClearFollowBorder(state);
    [bar setNeedsLayout];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (%orig) return YES;
    if (!NSThread.isMainThread) return NO;
    // UIButton 松手时再次判断是否在按钮内，沿用顶栏的玻璃命中范围。
    UIView *bar = DKNoteNativeBarForView(self);
    return bar && DKNoteGlassTargetAtPoint(bar, [self convertPoint:point toView:bar]) == self;
}
%end
%end

%ctor {
    if (!DKGlassOSAvailable()) return;
    gDKNoteNativeTopBarClass = objc_getClass("AWEKnowledgeRichContentImpl.FullPageFeedTopBarView");
    if (!gDKNoteNativeTopBarClass) return;
    gDKNoteAuthorClass = objc_getClass("_TtCC27AWEKnowledgeRichContentImpl22FullPageFeedTopBarView19AuthorContainerView");
    gDKNoteRecommendClass = objc_getClass("_TtCC27AWEKnowledgeRichContentImpl22FullPageFeedTopBarView22RecommendContainerView");
    gDKNoteSegmentedClass = objc_getClass("IESSegmentedControl");
    gDKNoteSegmentedCellClass = objc_getClass("IESSegmentedItemCell");
    gDKNoteIndicatorClass = objc_getClass("IESSegmentedIndicator");
    Class relationClass = objc_getClass("AWEKnowledgeRichContentImpl.FullPageFeedRelationButton");
    if (class_getInstanceMethod(relationClass, @selector(setRelationItem:))
        && class_getInstanceMethod(relationClass, @selector(relationItem))) gDKNoteRelationClass = relationClass;
    gDKNoteNativeTopBars = [NSHashTable weakObjectsHashTable];
    %init(DKNoteNativeTopBarHooks, DKNoteNativeTopBar=gDKNoteNativeTopBarClass);
    DKNoteInstallSegmentedOverflowHooks();
    if (gDKNoteRelationClass) %init(DKNoteRelationButtonHooks, DKNoteRelationButton=gDKNoteRelationClass);
}
