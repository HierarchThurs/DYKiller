#import "DKComposeTouchRemap.h"
#import "DKProfileSettingsEntry.h"
#import "DKViewAdjust.h"

#import <objc/runtime.h>

@interface AWEProfileHeaderProvidedServiceCollectionViewCell : UICollectionViewCell @end

@interface AWEProfileKMPContainer : NSObject
- (BOOL)canScrollForward;
- (BOOL)canScrollBackward;
@end

@interface DKProfileServiceCard : NSObject
@property (nonatomic, strong) UIView *icon;
@property (nonatomic, strong) UIView *shape;
@property (nonatomic, strong) UIView *text;
@end
@implementation DKProfileServiceCard
@end

@interface DKProfileServiceButton : UIButton
@property (nonatomic, strong) UIImageView *gear;
@property (nonatomic, strong) UILabel *caption;
@end

@implementation DKProfileServiceButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    UIColor *ink = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithWhite:1.0 alpha:0.9]
            : [UIColor colorWithRed:22.0/255.0 green:24.0/255.0 blue:35.0/255.0 alpha:1.0];
    }];
    _gear = [UIImageView new];
    _gear.contentMode = UIViewContentModeScaleAspectFit;
    _gear.tintColor = ink;
    [self addSubview:_gear];
    _caption = [UILabel new];
    _caption.font = [UIFont systemFontOfSize:13.0];
    _caption.textAlignment = NSTextAlignmentCenter;
    _caption.textColor = ink;
    [self addSubview:_caption];
    DKProfileEntryConfigureButton(self);
    return self;
}
@end

@interface DKProfileServiceEntryState : NSObject
@property (nonatomic, weak) UIView *render;
@property (nonatomic, weak) UIView *row;
@property (nonatomic, weak) UIView *touchView;
@property (nonatomic, copy) NSSet<UIView *> *shiftedViews;
@property (nonatomic, strong) DKProfileServiceButton *button;
@end
@implementation DKProfileServiceEntryState
@end

static char kDKProfileServiceEntryKey;
static NSHashTable<UICollectionViewCell *> *gDKProfileServiceCells;

// 抖音 41.2.0 功能行实测从 4 张起两端对齐，左对齐档的文字框间距为 24pt。
static const NSUInteger kDKProfileServiceSpreadCount = 4;
static const CGFloat kDKProfileServiceLeadingGap = 24.0;

static BOOL DKProfileServiceIsMine(UICollectionViewCell *cell) {
    Class headerClass = objc_getClass("AWEProfileHeaderMyProfileView");
    for (UIView *view = cell.superview; view; view = view.superview) {
        if ([view isKindOfClass:headerClass]) return YES;
    }
    return NO;
}

static BOOL DKProfileServiceIsFixed(UICollectionViewCell *cell) {
    Ivar ivar = class_getInstanceVariable(cell.class, "_container");
    AWEProfileKMPContainer *container = ivar ? object_getIvar(cell, ivar) : nil;
    return [container isKindOfClass:objc_getClass("AWEProfileKMPContainer")]
        && [container respondsToSelector:@selector(canScrollForward)] && [container respondsToSelector:@selector(canScrollBackward)]
        && !container.canScrollForward && !container.canScrollBackward;
}

static UIView *DKProfileServiceRow(UIView *render) {
    Class inheritedClass = objc_getClass("DanceUI._InheritedView");
    Class rowClass = objc_getClass("DanceUI._RenderNodeLayerView");
    for (UIView *wrapper in render.subviews) {
        if (![wrapper isKindOfClass:inheritedClass]) continue;
        for (UIView *view in wrapper.subviews) {
            if ([view isKindOfClass:rowClass]) return view;
        }
    }
    return nil;
}

static NSArray<DKProfileServiceCard *> *DKProfileServiceCards(UIView *row) {
    Class inheritedClass = objc_getClass("DanceUI._InheritedView");
    Class drawingClass = objc_getClass("DanceUI.CGDrawingView");
    Class shapeClass = objc_getClass("DanceUI._UIShapeHitTestingView");
    NSMutableArray<UIView *> *icons = [NSMutableArray array];
    NSMutableArray<UIView *> *texts = [NSMutableArray array];
    NSMutableArray<UIView *> *shapes = [NSMutableArray array];
    for (UIView *view in row.subviews) {
        if (view.hidden || CGRectIsEmpty(view.bounds)) continue;
        if ([view isKindOfClass:shapeClass]) [shapes addObject:view];
        else if ([view isKindOfClass:inheritedClass]) {
            if ([view.subviews.firstObject isKindOfClass:drawingClass]) [texts addObject:view];
            else [icons addObject:view];
        }
    }
    if (!texts.count || icons.count != texts.count || shapes.count != texts.count) return nil;

    NSComparator byCenter = ^NSComparisonResult(UIView *lhs, UIView *rhs) {
        CGFloat x = CGRectGetMidX(DKAdjustLayoutFrame(lhs));
        CGFloat otherX = CGRectGetMidX(DKAdjustLayoutFrame(rhs));
        return x < otherX ? NSOrderedAscending : x > otherX ? NSOrderedDescending : NSOrderedSame;
    };
    [icons sortUsingComparator:byCenter];
    [texts sortUsingComparator:byCenter];
    [shapes sortUsingComparator:byCenter];

    CGFloat pixel = 1.0 / MAX(1.0, row.traitCollection.displayScale);
    NSMutableArray<DKProfileServiceCard *> *cards = [NSMutableArray arrayWithCapacity:texts.count];
    for (NSUInteger i = 0; i < texts.count; i++) {
        CGRect icon = DKAdjustLayoutFrame(icons[i]);
        CGRect shape = DKAdjustLayoutFrame(shapes[i]);
        CGRect text = DKAdjustLayoutFrame(texts[i]);
        if (fabs(CGRectGetMidX(icon) - CGRectGetMidX(text)) > pixel || CGRectGetMinY(text) < CGRectGetMaxY(icon) - pixel
            || !CGRectContainsRect(CGRectInset(icon, -pixel, -pixel), shape)
            || !CGRectContainsRect(CGRectInset(shape, -pixel, -pixel), icon)) return nil;
        DKProfileServiceCard *card = [DKProfileServiceCard new];
        card.icon = icons[i];
        card.text = texts[i];
        card.shape = shapes[i];
        [cards addObject:card];
    }
    return cards;
}

static void DKProfileServiceClearRemap(DKProfileServiceEntryState *state) {
    for (UIView *view in state.shiftedViews) DKAdjustTransform(view, CGAffineTransformIdentity);
    DKComposeSetTouchRegions(state.touchView, nil);
    state.shiftedViews = nil;
    state.touchView = nil;
}

static void DKProfileServiceRestore(DKProfileServiceEntryState *state) {
    DKProfileServiceClearRemap(state);
    [state.button removeFromSuperview];
    state.button = nil;
}

static void DKProfileServiceDistribute(DKProfileServiceEntryState *state, UIView *row, UIView *touchView,
                                       NSArray<DKProfileServiceCard *> *cards, CGFloat start, CGFloat gap) {
    if (state.touchView != touchView) DKComposeSetTouchRegions(state.touchView, nil);
    state.touchView = touchView;
    CGRect rowBounds = row.bounds;
    CGFloat top = CGRectGetMinY(rowBounds);
    CGFloat height = CGRectGetHeight(rowBounds);
    NSMutableSet<UIView *> *shifted = [NSMutableSet set];
    NSMutableArray<DKComposeTouchRegion *> *regions = [NSMutableArray arrayWithCapacity:cards.count];
    CGFloat x = start;
    CGFloat left = start;
    for (DKProfileServiceCard *card in cards) {
        CGRect labelFrame = DKAdjustLayoutFrame(card.text);
        CGRect shapeFrame = DKAdjustLayoutFrame(card.shape);
        CGAffineTransform delta = CGAffineTransformMakeTranslation(x - CGRectGetMinX(labelFrame), 0.0);
        for (UIView *part in @[card.icon, card.shape, card.text]) {
            [shifted addObject:part];
            DKAdjustTransform(part, delta);
        }
        CGFloat right = x + CGRectGetWidth(labelFrame) + gap * 0.5;
        CGRect region = CGRectMake(left, top, right - left, height);
        CGPoint target = CGPointMake(CGRectGetMidX(shapeFrame), CGRectGetMidY(shapeFrame));
        [regions addObject:[DKComposeTouchRegion regionWithRect:region target:target sourceView:row touchView:touchView]];
        left = right;
        x += CGRectGetWidth(labelFrame) + gap;
    }
    for (UIView *view in state.shiftedViews) {
        if (![shifted containsObject:view]) DKAdjustTransform(view, CGAffineTransformIdentity);
    }
    state.shiftedViews = shifted;
    DKComposeSetTouchRegions(touchView, regions);
}

static void DKProfileServiceApply(DKProfileServiceEntryState *state, UIView *content, UIView *row, UIView *touchView,
                                  NSArray<DKProfileServiceCard *> *cards) {
    DKProfileServiceButton *button = state.button ?: [DKProfileServiceButton new];
    NSString *title = DKProfileEntryTitle();
    button.caption.text = title;
    button.accessibilityLabel = title;
    CGRect icon = DKAdjustLayoutFrame(cards.firstObject.icon);
    CGRect text = DKAdjustLayoutFrame(cards.firstObject.text);
    CGFloat buttonWidth = MAX(CGRectGetWidth(icon), ceil([button.caption sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGRectGetHeight(text))].width));
    CGRect enclosing = [row.superview convertRect:row.superview.bounds toView:row];
    CGFloat start = CGRectGetMinX(text);
    CGFloat end = CGRectGetMaxX(enclosing) - (start - CGRectGetMinX(enclosing));
    CGRect rowBounds = row.bounds;
    // 行铺满时沿用原生右缘，端点比较允许 Compose 像素取整。
    CGFloat scale = MAX(1.0, row.traitCollection.displayScale);
    if (fabs(round((CGRectGetWidth(rowBounds) - (end - start)) * scale)) <= 2.0) end = CGRectGetMaxX(rowBounds);

    CGFloat x, gap;
    if (cards.count + 1 < kDKProfileServiceSpreadCount) {
        gap = cards.count == 1 ? kDKProfileServiceLeadingGap
            : CGRectGetMinX(DKAdjustLayoutFrame(cards[1].text)) - CGRectGetMaxX(text);
        x = CGRectGetMaxX(DKAdjustLayoutFrame(cards.lastObject.text)) + gap;
        if (x + buttonWidth > end) {
            DKProfileServiceRestore(state);
            return;
        }
        DKProfileServiceClearRemap(state);
    } else {
        CGFloat widths = buttonWidth;
        for (DKProfileServiceCard *card in cards) widths += CGRectGetWidth(DKAdjustLayoutFrame(card.text));
        gap = (end - start - widths) / cards.count;
        if (gap < CGRectGetWidth(icon) * 0.5) {
            DKProfileServiceRestore(state);
            return;
        }
        x = end - buttonWidth;
        DKProfileServiceDistribute(state, row, touchView, cards, start, gap);
    }

    CGFloat left = x - gap * 0.5;
    CGFloat top = CGRectGetMinY(rowBounds);
    button.frame = [row convertRect:CGRectMake(left, top, x + buttonWidth - left, CGRectGetHeight(rowBounds)) toView:content];
    CGFloat center = x + buttonWidth * 0.5 - left;
    button.gear.image = DKProfileEntryGearImage(icon.size);
    button.gear.frame = CGRectMake(center - CGRectGetWidth(icon) * 0.5, CGRectGetMinY(icon) - top,
                                   CGRectGetWidth(icon), CGRectGetHeight(icon));
    button.caption.frame = CGRectMake(x - left, CGRectGetMinY(text) - top, buttonWidth, CGRectGetHeight(text));
    if (button.superview != content) [content addSubview:button];
    else if (content.subviews.lastObject != button) [content bringSubviewToFront:button];
    state.button = button;
}

static void DKProfileServiceDetach(DKProfileServiceEntryState *state) {
    DKComposeSetRowLayoutObserver(state.row, nil);
    state.row = nil;
    state.render = nil;
    DKProfileServiceRestore(state);
}

static void DKProfileServiceSync(UICollectionViewCell *cell, UIView *render) {
    DKProfileServiceEntryState *state = objc_getAssociatedObject(cell, &kDKProfileServiceEntryKey);
    if (!DKProfileServiceIsMine(cell) || ![render isDescendantOfView:cell]) {
        DKProfileServiceDetach(state);
        return;
    }
    if (!state) {
        state = [DKProfileServiceEntryState new];
        objc_setAssociatedObject(cell, &kDKProfileServiceEntryKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gDKProfileServiceCells addObject:cell];
    }
    state.render = render;
    UIView *touchView = DKProfileEntryInServiceArea() ? DKComposeTouchView(render) : nil;
    UIView *row = touchView ? DKProfileServiceRow(render) : nil;
    if (state.row != row) {
        DKComposeSetRowLayoutObserver(state.row, nil);
        state.row = row;
        if (row) {
            __weak UICollectionViewCell *weakCell = cell;
            __weak DKProfileServiceEntryState *weakState = state;
            DKComposeSetRowLayoutObserver(row, ^(UIView *laidOutRow) {
                UICollectionViewCell *owner = weakCell;
                if (owner) DKProfileServiceSync(owner, weakState.render);
            });
        }
    }
    NSArray<DKProfileServiceCard *> *cards = row && DKProfileServiceIsFixed(cell) ? DKProfileServiceCards(row) : nil;
    if (cards.count) DKProfileServiceApply(state, cell.contentView, row, touchView, cards);
    else DKProfileServiceRestore(state);
}

void DKProfileComposeEntryRefresh(void) {
    for (UICollectionViewCell *cell in gDKProfileServiceCells.allObjects) {
        DKProfileServiceEntryState *state = objc_getAssociatedObject(cell, &kDKProfileServiceEntryKey);
        DKProfileServiceSync(cell, state.render);
    }
}

%group DKProfileServiceEntryHooks
%hook AWEProfileHeaderProvidedServiceCollectionViewCell
- (void)prepareForReuse {
    DKProfileServiceEntryState *state = objc_getAssociatedObject(self, &kDKProfileServiceEntryKey);
    DKProfileServiceDetach(state);
    %orig;
}
%end
%end

%ctor {
    Class cellClass = %c(AWEProfileHeaderProvidedServiceCollectionViewCell);
    if (!cellClass) return;
    %init(DKProfileServiceEntryHooks);
    gDKProfileServiceCells = [NSHashTable weakObjectsHashTable];
    DKComposeObserveRenderLayout(^(UIView *render) {
        for (UIView *view = render.superview; view; view = view.superview) {
            if (![view isKindOfClass:cellClass]) continue;
            DKProfileServiceSync((UICollectionViewCell *)view, render);
            break;
        }
    });
}
