//
//  DKTopChannelCapsule.m
//  DYKiller
//
//  选中块的位置统一由「锚点」决定：频道内容坐标里的一个 x，选中块宽度按锚点两侧频道的宽度插值。
//  平时锚点取原生选中线的中心，按压时取被按频道的中心，拖选时取手指位置。
//

#import "DKTopChannelCapsule.h"

#import "DKGlassFlexView.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"
#import "DouyinHeaders.h"

#import <math.h>
#import <objc/runtime.h>

// 须短于原生长按的 0.4 s：拖选先开始，原生排序面板由 Hook 拦下。
static const NSTimeInterval kDKDragPressDuration = 0.3;
static const CGFloat kDKDragEdgeZone = 40.0;
static const CGFloat kDKPillMinVisibleWidth = 12.0;
// 选中块比胶囊暗：底栏透镜在玻璃上挖空、露出背后原始画面，这两档黑色染色在深色页与浅色页最接近其观感。
static const CGFloat kDKPillTintOnDark = 0.5;
static const CGFloat kDKPillTintOnLight = 0.1;
static const CGFloat kDKArrowIconSize = 13.0;
static const CGFloat kDKArrowIconInkWhite = 0.09;
static const NSTimeInterval kDKMaterialAnimation = 0.2;

typedef NS_ENUM(NSInteger, DKTopChannelTouchMode) {
    DKTopChannelTouchIdle = 0,
    DKTopChannelTouchPressing,
    DKTopChannelTouchDragging,
};

static BOOL gDKTopChannelDragging = NO;
static char kDKGlassMaterialKey;
static char kDKArrowCircleKey;

BOOL DKTopChannelArrowContainsPoint(UIView *arrow, CGPoint point, BOOL *handled) {
    UIView *circle = objc_getAssociatedObject(arrow, &kDKArrowCircleKey);
    *handled = circle != nil;
    return CGRectContainsPoint(circle.frame, point);
}

API_AVAILABLE(ios(26.0))
static UIGlassEffect *DKTopBarGlassMakeEffect(DKTopBarGlassMaterial material, UIColor *tint, BOOL interactive) {
    UIGlassEffect *effect = [UIGlassEffect effectWithStyle:
        material.clear ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular];
    effect.tintColor = tint;
    effect.interactive = interactive;
    return effect;
}

void DKTopBarGlassApplyMaterial(UIVisualEffectView *glass, DKTopBarGlassMaterial material, UIColor *tint,
                                BOOL interactive) {
    NSInteger signature = (material.clear ? 1 : 0) | (material.lightContent ? 2 : 0);
    NSNumber *installed = objc_getAssociatedObject(glass, &kDKGlassMaterialKey);
    if (installed && installed.integerValue == signature) return;
    objc_setAssociatedObject(glass, &kDKGlassMaterialKey, @(signature), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // Clear 对 overrideUserInterfaceStyle 不敏感，深色靠染色；Regular 靠外观。
    UIColor *resolved = tint ?: (material.clear && !material.lightContent
        ? DKGlassTintForStyle(UIUserInterfaceStyleDark) : nil);
    void (^changes)(void) = ^{
        glass.overrideUserInterfaceStyle = material.lightContent ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark;
        glass.effect = DKTopBarGlassMakeEffect(material, resolved, interactive);
    };
    if (installed) {
        [UIView animateWithDuration:kDKMaterialAnimation animations:changes];
    } else {
        changes();
    }
}

UIVisualEffectView *DKTopBarGlassMakeView(UIView *touchSource) {
    DKGlassFlexView *glass = [[DKGlassFlexView alloc] initWithEffect:nil];
    glass.flexSourceView = touchSource;
    glass.userInteractionEnabled = NO;
    glass.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];
    return glass;
}

@interface DKTopChannelCapsule () <UIGestureRecognizerDelegate>
@end

@implementation DKTopChannelCapsule {
    __weak AWEFeedMultiTabSegmentedControl *_control;
    UIVisualEffectView *_capsule;
    UIVisualEffectView *_pill;
    UIVisualEffectView *_arrowCircle;
    UIImageView *_arrowIcon;
    UILongPressGestureRecognizer *_pressGesture;
    UILongPressGestureRecognizer *_dragGesture;
    DKTopChannelTouchMode _mode;
    CGFloat _pillHeight;
    CGFloat _anchorX;
    NSInteger _hoverIndex;
    DKTopBarGlassMaterial _material;
}

+ (BOOL)dragging {
    return gDKTopChannelDragging;
}

- (instancetype)initWithControl:(AWEFeedMultiTabSegmentedControl *)control {
    if ((self = [super init])) {
        _control = control;
        _hoverIndex = NSNotFound;
        _capsule = DKTopBarGlassMakeView(nil);
        _pill = DKTopBarGlassMakeView(control.multiTabSegmentedControlScollWrapperView);
        [control insertSubview:_capsule atIndex:0];
        [control insertSubview:_pill atIndex:1];

        _pressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handlePress:)];
        _pressGesture.minimumPressDuration = 0.0;
        _pressGesture.cancelsTouchesInView = NO;
        _pressGesture.delegate = self;
        _dragGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleDrag:)];
        _dragGesture.minimumPressDuration = kDKDragPressDuration;
        _dragGesture.cancelsTouchesInView = NO;
        _dragGesture.delegate = self;
        UIScrollView *scrollView = control.multiTabSegmentedControlScollWrapperView;
        [scrollView addGestureRecognizer:_pressGesture];
        [scrollView addGestureRecognizer:_dragGesture];
    }
    return self;
}

- (UIView *)pillView {
    return _pill;
}

- (void)invalidate {
    AWEFeedMultiTabSegmentedControl *control = _control;
    [_pressGesture.view removeGestureRecognizer:_pressGesture];
    [_dragGesture.view removeGestureRecognizer:_dragGesture];
    [_capsule removeFromSuperview];
    [_pill removeFromSuperview];
    [_arrowCircle removeFromSuperview];
    [_arrowIcon removeFromSuperview];
    AWEMultiTabNavigationArrowView *arrow = control.rightNavigationArrowView;
    if (arrow) objc_setAssociatedObject(arrow, &kDKArrowCircleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKAdjustFade(arrow.arrowImageView, 1.0, CGSizeZero);
    if (_mode == DKTopChannelTouchDragging) {
        control.multiTabSegmentedControlScollWrapperView.panGestureRecognizer.enabled = YES;
        gDKTopChannelDragging = NO;
    }
    _mode = DKTopChannelTouchIdle;
    DKAdjustFade(control.selectedLineContainerView, 1.0, CGSizeZero);
}

#pragma mark - 布局

- (void)layoutCapsuleFrame:(CGRect)capsuleFrame pillHeight:(CGFloat)pillHeight {
    AWEFeedMultiTabSegmentedControl *control = _control;
    if (!CGRectEqualToRect(_capsule.frame, capsuleFrame)) _capsule.frame = capsuleFrame;
    _pillHeight = pillHeight;
    // 原生选中线（含活动样式图）由选中块取代，只取位置。
    UIView *line = control.selectedLineContainerView;
    DKAdjustFade(line, 0.0, line.bounds.size);
    if (_mode == DKTopChannelTouchIdle) [self updateAnchorFromLine];
    [self placePillAnimated:NO];
    [self layoutArrow];
}

// 「返回推荐」箭头：原生图换成与胶囊右端同心的玻璃圆钮，显隐与点击沿用原生。
- (void)layoutArrow {
    AWEFeedMultiTabSegmentedControl *control = _control;
    AWEMultiTabNavigationArrowView *arrow = control.rightNavigationArrowView;
    if (!arrow) return;
    if (!_arrowCircle) {
        _arrowCircle = DKTopBarGlassMakeView(arrow);
        [arrow insertSubview:_arrowCircle atIndex:0];
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:kDKArrowIconSize
                                                                                             weight:UIImageSymbolWeightSemibold];
        _arrowIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right" withConfiguration:config]];
        _arrowIcon.contentMode = UIViewContentModeCenter;
        [arrow addSubview:_arrowIcon];
        objc_setAssociatedObject(arrow, &kDKArrowCircleKey, _arrowCircle, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self applyArrowMaterial];
    }
    DKAdjustFade(arrow.arrowImageView, 0.0, arrow.arrowImageView.bounds.size);
    CGRect strip = [control.multiTabSegmentedControlScollWrapperView.superview
        convertRect:control.multiTabSegmentedControlScollWrapperView.frame toView:control];
    CGRect inControl = CGRectMake(CGRectGetMaxX(strip) - _pillHeight, CGRectGetMidY(strip) - _pillHeight / 2.0,
                                  _pillHeight, _pillHeight);
    CGRect frame = [control convertRect:inControl toView:arrow];
    if (!CGRectEqualToRect(_arrowCircle.frame, frame)) {
        _arrowCircle.frame = frame;
        _arrowIcon.frame = frame;
    }
}

- (void)applyArrowMaterial {
    if (!_arrowCircle) return;
    // 不加深色染色：圆钮比胶囊略亮，与选中块区分。
    DKTopBarGlassApplyMaterial(_arrowCircle, _material, UIColor.clearColor, YES);
    _arrowIcon.tintColor = _material.lightContent ? [UIColor colorWithWhite:kDKArrowIconInkWhite alpha:1.0] : UIColor.whiteColor;
}

- (void)applyMaterial:(DKTopBarGlassMaterial)material {
    UIColor *pillTint = [UIColor colorWithWhite:0.0 alpha:material.lightContent ? kDKPillTintOnLight : kDKPillTintOnDark];
    _material = material;
    DKTopBarGlassApplyMaterial(_capsule, material, nil, NO);
    DKTopBarGlassApplyMaterial(_pill, material, pillTint, YES);
    [self applyArrowMaterial];
}

#pragma mark - 选中块

- (NSArray<UIView *> *)items {
    return _control.itemViews;
}

- (void)updateAnchorFromLine {
    UIView *line = _control.selectedLineContainerView;
    // 分页滑动时原生只改约束，取值前先落实；没有待处理的布局时开销可忽略。
    [line.superview layoutIfNeeded];
    _anchorX = CGRectGetMidX(line.frame);
}

// 锚点两侧频道的宽度按距离插值，频道宽度不同（如城市名）时选中块平滑过渡。
- (CGFloat)pillWidthAtAnchor:(CGFloat)anchor {
    NSArray<UIView *> *items = [self items];
    UIView *previous = nil;
    for (UIView *item in items) {
        CGFloat center = CGRectGetMidX(item.frame);
        if (anchor <= center) {
            if (!previous) return CGRectGetWidth(item.frame);
            CGFloat from = CGRectGetMidX(previous.frame);
            CGFloat progress = center > from ? (anchor - from) / (center - from) : 1.0;
            return CGRectGetWidth(previous.frame)
                + (CGRectGetWidth(item.frame) - CGRectGetWidth(previous.frame)) * progress;
        }
        previous = item;
    }
    return previous ? CGRectGetWidth(previous.frame) : 0.0;
}

// 选中块不在滚动内容内（祖先的渐变 mask 会让玻璃失真），按频道条可见范围裁到胶囊内，滚出后隐藏。
- (void)placePillAnimated:(BOOL)animated {
    AWEFeedMultiTabSegmentedControl *control = _control;
    UIScrollView *scrollView = control.multiTabSegmentedControlScollWrapperView;
    UIView *content = [self items].firstObject.superview;
    if (!content) {
        _pill.hidden = YES;
        return;
    }
    CGFloat width = [self pillWidthAtAnchor:_anchorX];
    CGRect inContent = CGRectMake(_anchorX - width / 2.0, 0.0, width, CGRectGetHeight(content.bounds));
    CGRect rect = [content convertRect:inContent toView:control];
    CGRect visible = [scrollView.superview convertRect:scrollView.frame toView:control];
    CGFloat minX = fmax(CGRectGetMinX(rect), CGRectGetMinX(visible));
    CGFloat maxX = fmin(CGRectGetMaxX(rect), CGRectGetMaxX(visible));
    CGRect target = CGRectMake(minX, CGRectGetMidY(visible) - _pillHeight / 2.0, fmax(0.0, maxX - minX), _pillHeight);

    BOOL hidden = CGRectGetWidth(target) < kDKPillMinVisibleWidth;
    if (_pill.hidden != hidden) _pill.hidden = hidden;
    if (hidden || CGRectEqualToRect(_pill.frame, target)) return;
    if (animated && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:0.42
                              delay:0.0
             usingSpringWithDamping:0.78
              initialSpringVelocity:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState
                                  | UIViewAnimationOptionAllowUserInteraction
                         animations:^{ self->_pill.frame = target; }
                         completion:nil];
    } else {
        _pill.frame = target;
    }
}

- (void)selectionDidChange {
    if (_mode != DKTopChannelTouchIdle) return;
    [self updateAnchorFromLine];
    [self placePillAnimated:YES];
}

- (void)selectionLineDidMove {
    if (_mode != DKTopChannelTouchIdle) return;
    [self updateAnchorFromLine];
    [self placePillAnimated:NO];
}

- (void)channelsDidScroll {
    if (_mode == DKTopChannelTouchDragging) [self updateDragTarget];
    [self placePillAnimated:NO];
}

- (void)channelsWillBeginDragging {
    if (_mode != DKTopChannelTouchPressing) return;
    _mode = DKTopChannelTouchIdle;
    [self updateAnchorFromLine];
    [self placePillAnimated:YES];
}

#pragma mark - 手势

- (NSInteger)itemIndexAtContentX:(CGFloat)x {
    NSArray<UIView *> *items = [self items];
    NSInteger nearest = NSNotFound;
    CGFloat distance = CGFLOAT_MAX;
    for (NSInteger index = 0; index < (NSInteger)items.count; index++) {
        CGRect frame = items[index].frame;
        if (x >= CGRectGetMinX(frame) && x <= CGRectGetMaxX(frame)) return index;
        CGFloat current = fabs(x - CGRectGetMidX(frame));
        if (current < distance) {
            distance = current;
            nearest = index;
        }
    }
    return nearest;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

// 按住选中频道才进入拖选，按住其它频道仍走原生的频道排序面板。
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer != _dragGesture) return YES;
    AWEFeedMultiTabSegmentedControl *control = _control;
    UIView *content = [self items].firstObject.superview;
    if (!content || control.multiTabSegmentedControlScollWrapperView.isDragging) return NO;
    CGFloat x = [gestureRecognizer locationInView:content].x;
    return [self itemIndexAtContentX:x] == control.selectedIndex;
}

- (void)handlePress:(UILongPressGestureRecognizer *)gesture {
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            UIView *content = [self items].firstObject.superview;
            NSInteger index = content ? [self itemIndexAtContentX:[gesture locationInView:content].x] : NSNotFound;
            if (index == NSNotFound) return;
            _mode = DKTopChannelTouchPressing;
            _anchorX = CGRectGetMidX([self items][index].frame);
            [self placePillAnimated:YES];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            if (_mode != DKTopChannelTouchPressing) return;
            _mode = DKTopChannelTouchIdle;
            // 原生点按在同一轮手势更新里提交，下一轮再按实际选中频道归位。
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self->_mode != DKTopChannelTouchIdle) return;
                [self updateAnchorFromLine];
                [self placePillAnimated:YES];
            });
            break;
        }
        default:
            break;
    }
}

// 手指所指的频道；接近两端时把该频道滚进可见范围，滚动回调再次进入此处，持续按住即可一路滚到头。
- (void)updateDragTarget {
    AWEFeedMultiTabSegmentedControl *control = _control;
    NSArray<UIView *> *items = [self items];
    UIView *content = items.firstObject.superview;
    if (!content) return;
    CGFloat x = [_dragGesture locationInView:content].x;
    _anchorX = fmin(fmax(x, CGRectGetMidX(items.firstObject.frame)), CGRectGetMidX(items.lastObject.frame));

    NSInteger index = [self itemIndexAtContentX:_anchorX];
    if (index == NSNotFound || index == _hoverIndex) return;
    _hoverIndex = index;
    [[UISelectionFeedbackGenerator new] selectionChanged];

    UIScrollView *scrollView = control.multiTabSegmentedControlScollWrapperView;
    CGFloat inScroll = [_dragGesture locationInView:scrollView].x - scrollView.contentOffset.x;
    if (inScroll < kDKDragEdgeZone || inScroll > CGRectGetWidth(scrollView.bounds) - kDKDragEdgeZone) {
        [control scrollSegmentedControlItemViewToIndex:(unsigned long long)index animated:YES];
    }
}

- (void)handleDrag:(UILongPressGestureRecognizer *)gesture {
    AWEFeedMultiTabSegmentedControl *control = _control;
    UIScrollView *scrollView = control.multiTabSegmentedControlScollWrapperView;
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            _mode = DKTopChannelTouchDragging;
            gDKTopChannelDragging = YES;
            _hoverIndex = control.selectedIndex;
            scrollView.panGestureRecognizer.enabled = NO;
            // 手指还压在选中频道上，撤掉它的点按，避免松手触发原生的重复点击刷新。
            AWEHPTopTabItemView *selected = (AWEHPTopTabItemView *)[self items][control.selectedIndex];
            selected.singleTap.enabled = NO;
            selected.singleTap.enabled = YES;
            [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
            [self updateDragTarget];
            [self placePillAnimated:YES];
            break;
        }
        case UIGestureRecognizerStateChanged:
            [self updateDragTarget];
            [self placePillAnimated:NO];
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            if (_mode != DKTopChannelTouchDragging) return;
            _mode = DKTopChannelTouchIdle;
            scrollView.panGestureRecognizer.enabled = YES;
            NSInteger target = _hoverIndex;
            _hoverIndex = NSNotFound;
            if (gesture.state == UIGestureRecognizerStateEnded && target != NSNotFound && target != control.selectedIndex) {
                [control segmentedControlTapped:target];
            } else {
                [self updateAnchorFromLine];
                [self placePillAnimated:YES];
            }
            // 原生长按的结束回调可能晚于这里，下一轮再放开拦截。
            dispatch_async(dispatch_get_main_queue(), ^{ gDKTopChannelDragging = NO; });
            break;
        }
        default:
            break;
    }
}

@end
