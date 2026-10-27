//
//  DKChatGlassStore.m
//  DYKiller
//

#import "DKChatGlassStore.h"
#import "DKGlassFlexView.h"
#import "DKUtils.h"
#import <math.h>
#import <objc/runtime.h>

static char kDKChatGlassStoreKey;

// 接管过的原生外观：底色、模糊材质与不透明标记。
@interface DKChatGlassBacking : NSObject
@property (nonatomic, weak) UIView *view;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, strong) UIVisualEffect *effect;
@property (nonatomic) BOOL opaque;
@end
@implementation DKChatGlassBacking
@end

@interface DKChatGlassLayerBacking : NSObject
@property (nonatomic, weak) CAShapeLayer *layer;
@property (nonatomic, strong) UIColor *color;
@end
@implementation DKChatGlassLayerBacking
@end

@interface DKChatGlassShadowBacking : NSObject
@property (nonatomic, weak) CALayer *layer;
@property (nonatomic) float opacity;
@end
@implementation DKChatGlassShadowBacking
@end

// 一块玻璃：业务视图、玻璃本体与当前的形状、材质，未变化时不重写。
@interface DKChatGlassSlot : NSObject
@property (nonatomic, weak) UIView *source;
@property (nonatomic, strong) DKGlassFlexView *glass;
@property (nonatomic) DKChatGlassShape shape;
@property (nonatomic) CGFloat radius;
@property (nonatomic) BOOL interactive;
@property (nonatomic, strong) UIColor *tint;
@property (nonatomic) BOOL clear;
@property (nonatomic) UIUserInterfaceStyle style;
@property (nonatomic) BOOL configured;
@end
@implementation DKChatGlassSlot
@end

// 本模块挂上的 mask。
@interface DKChatGlassMask : NSObject
@property (nonatomic, weak) UIView *view;
@property (nonatomic, strong) CAShapeLayer *layer;
@end
@implementation DKChatGlassMask
@end

// 四角各自半径的圆角矩形。
static UIBezierPath *DKChatRoundedPath(CGRect rect, CGFloat topLeft, CGFloat topRight,
                                       CGFloat bottomRight, CGFloat bottomLeft) {
    CGFloat limit = MIN(CGRectGetWidth(rect), CGRectGetHeight(rect)) * 0.5;
    topLeft = MIN(topLeft, limit);
    topRight = MIN(topRight, limit);
    bottomRight = MIN(bottomRight, limit);
    bottomLeft = MIN(bottomLeft, limit);
    CGFloat minX = CGRectGetMinX(rect), maxX = CGRectGetMaxX(rect);
    CGFloat minY = CGRectGetMinY(rect), maxY = CGRectGetMaxY(rect);
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(minX + topLeft, minY)];
    [path addArcWithCenter:CGPointMake(maxX - topRight, minY + topRight) radius:topRight
                startAngle:-M_PI_2 endAngle:0.0 clockwise:YES];
    [path addArcWithCenter:CGPointMake(maxX - bottomRight, maxY - bottomRight) radius:bottomRight
                startAngle:0.0 endAngle:M_PI_2 clockwise:YES];
    [path addArcWithCenter:CGPointMake(minX + bottomLeft, maxY - bottomLeft) radius:bottomLeft
                startAngle:M_PI_2 endAngle:M_PI clockwise:YES];
    [path addArcWithCenter:CGPointMake(minX + topLeft, minY + topLeft) radius:topLeft
                startAngle:M_PI endAngle:M_PI * 1.5 clockwise:YES];
    [path closePath];
    return path;
}

static BOOL DKChatRectIsFinite(CGRect rect) {
    return isfinite(rect.origin.x) && isfinite(rect.origin.y)
        && isfinite(rect.size.width) && isfinite(rect.size.height);
}

@implementation DKChatGlassStore {
    NSMutableArray<DKChatGlassBacking *> *_backings;
    NSMutableArray<DKChatGlassLayerBacking *> *_layerBackings;
    NSMutableArray<DKChatGlassShadowBacking *> *_shadowBackings;
    NSMutableArray<DKChatGlassSlot *> *_slots;
    NSMutableArray<DKChatGlassMask *> *_masks;
    NSMutableSet *_wanted;
    BOOL _clear;
    UIUserInterfaceStyle _style;
}

+ (instancetype)storeForOwner:(id)owner create:(BOOL)create {
    if (!owner) return nil;
    DKChatGlassStore *store = objc_getAssociatedObject(owner, &kDKChatGlassStoreKey);
    if (!store && create) {
        store = [DKChatGlassStore new];
        objc_setAssociatedObject(owner, &kDKChatGlassStoreKey, store, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return store;
}

+ (void)removeStoreForOwner:(id)owner {
    DKChatGlassStore *store = [self storeForOwner:owner create:NO];
    if (!store || store.syncing) return;
    [store beginWithClear:NO style:UIUserInterfaceStyleUnspecified];
    [store end];
    objc_setAssociatedObject(owner, &kDKChatGlassStoreKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (instancetype)init {
    if ((self = [super init])) {
        _backings = [NSMutableArray array];
        _layerBackings = [NSMutableArray array];
        _shadowBackings = [NSMutableArray array];
        _slots = [NSMutableArray array];
        _masks = [NSMutableArray array];
        _wanted = [NSMutableSet set];
    }
    return self;
}

- (void)beginWithClear:(BOOL)clear style:(UIUserInterfaceStyle)style {
    _syncing = YES;
    _clear = clear;
    _style = style;
    [_wanted removeAllObjects];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
}

- (void)end {
    for (DKChatGlassLayerBacking *backing in _layerBackings.copy) {
        if ([_wanted containsObject:backing]) continue;
        if (backing.layer && (!backing.layer.fillColor || CGColorGetAlpha(backing.layer.fillColor) == 0.0)) {
            backing.layer.fillColor = backing.color.CGColor;
        }
        [_layerBackings removeObject:backing];
    }
    for (DKChatGlassShadowBacking *backing in _shadowBackings.copy) {
        if ([_wanted containsObject:backing]) continue;
        if (backing.layer.shadowOpacity == 0.0f) backing.layer.shadowOpacity = backing.opacity;
        [_shadowBackings removeObject:backing];
    }
    for (DKChatGlassSlot *slot in _slots.copy) {
        if ([_wanted containsObject:slot]) continue;
        [slot.glass removeFromSuperview];
        [_slots removeObject:slot];
    }
    for (DKChatGlassMask *mask in _masks.copy) {
        if ([_wanted containsObject:mask]) continue;
        if (mask.view.layer.mask == mask.layer) mask.view.layer.mask = nil;
        [_masks removeObject:mask];
    }
    for (DKChatGlassBacking *backing in _backings.copy) {
        if ([_wanted containsObject:backing]) continue;
        [self restoreBacking:backing];
        [_backings removeObject:backing];
    }
    [_wanted removeAllObjects];
    [CATransaction commit];
    _syncing = NO;
}

#pragma mark 底色

- (void)clearFillOfShapeLayer:(CAShapeLayer *)layer {
    if (!layer) return;
    DKChatGlassLayerBacking *backing = nil;
    for (DKChatGlassLayerBacking *item in _layerBackings) if (item.layer == layer) { backing = item; break; }
    if (!backing) {
        backing = [DKChatGlassLayerBacking new];
        backing.layer = layer;
        backing.color = layer.fillColor ? [UIColor colorWithCGColor:layer.fillColor] : nil;
        [_layerBackings addObject:backing];
    }
    if (layer.fillColor && CGColorGetAlpha(layer.fillColor) > 0.0) {
        backing.color = [UIColor colorWithCGColor:layer.fillColor];
    }
    [_wanted addObject:backing];
    layer.fillColor = UIColor.clearColor.CGColor;
}

- (void)clearShadowOfView:(UIView *)view {
    CALayer *layer = view.layer;
    if (!layer) return;
    DKChatGlassShadowBacking *backing = nil;
    for (DKChatGlassShadowBacking *item in _shadowBackings) if (item.layer == layer) { backing = item; break; }
    if (!backing) {
        backing = [DKChatGlassShadowBacking new];
        backing.layer = layer;
        [_shadowBackings addObject:backing];
    }
    // 宿主重设的阴影成为关闭功能后的恢复值。
    if (layer.shadowOpacity > 0.0f) backing.opacity = layer.shadowOpacity;
    [_wanted addObject:backing];
    if (layer.shadowOpacity != 0.0f) layer.shadowOpacity = 0.0f;
}

- (DKChatGlassBacking *)backingOfView:(UIView *)view {
    for (DKChatGlassBacking *backing in _backings) if (backing.view == view) return backing;
    return nil;
}

- (BOOL)tracksBackingOfView:(UIView *)view {
    return view && [self backingOfView:view] != nil;
}

- (UIColor *)clearBackingOfView:(UIView *)view {
    if (!view) return nil;
    DKChatGlassBacking *backing = [self backingOfView:view];
    if (!backing) {
        backing = [DKChatGlassBacking new];
        backing.view = view;
        backing.color = view.backgroundColor;
        backing.opaque = view.opaque;
        [_backings addObject:backing];
    }
    [_wanted addObject:backing];
    // 宿主重写的底色与材质成为关闭功能后的恢复值。
    if (view.backgroundColor && ![view.backgroundColor isEqual:UIColor.clearColor]) backing.color = view.backgroundColor;
    if (view.opaque) backing.opaque = YES;
    if ([view isKindOfClass:UIVisualEffectView.class]) {
        UIVisualEffectView *blur = (id)view;
        if (blur.effect) {
            backing.effect = blur.effect;
            blur.effect = nil;
        }
    }
    if (![view.backgroundColor isEqual:UIColor.clearColor]) view.backgroundColor = UIColor.clearColor;
    if (view.opaque) view.opaque = NO;
    return backing.color;
}

- (void)restoreBacking:(DKChatGlassBacking *)backing {
    UIView *view = backing.view;
    if (!view) return;
    if ([view.backgroundColor isEqual:UIColor.clearColor]) view.backgroundColor = backing.color;
    if (backing.opaque && !view.opaque) view.opaque = YES;
    if ([view isKindOfClass:UIVisualEffectView.class] && !((UIVisualEffectView *)view).effect && backing.effect) {
        ((UIVisualEffectView *)view).effect = backing.effect;
    }
}

#pragma mark 玻璃

- (UIVisualEffectView *)placeGlassFor:(UIView *)source
                                   in:(UIView *)carrier
                                frame:(CGRect)frame
                                shape:(DKChatGlassShape)shape
                               radius:(CGFloat)radius
                          interactive:(BOOL)interactive
                                 tint:(UIColor *)tint {
    if (!source || !carrier || CGRectIsEmpty(frame) || !DKChatRectIsFinite(frame)) return nil;
    DKChatGlassSlot *slot = nil;
    for (DKChatGlassSlot *item in _slots) if (item.source == source) { slot = item; break; }
    if (!slot) {
        slot = [DKChatGlassSlot new];
        slot.source = source;
        slot.glass = [[DKGlassFlexView alloc] initWithFrame:frame];
        slot.glass.userInteractionEnabled = NO;
        slot.glass.flexSourceView = source;
        [_slots addObject:slot];
    }
    [_wanted addObject:slot];
    DKGlassFlexView *glass = slot.glass;
    if (glass.superview != carrier || carrier.subviews.firstObject != glass) [carrier insertSubview:glass atIndex:0];
    if (!CGRectEqualToRect(glass.frame, frame)) glass.frame = frame;
    if (!slot.configured || slot.shape != shape || slot.radius != radius) {
        slot.shape = shape;
        slot.radius = radius;
        UICornerRadius *fixed = [UICornerRadius fixedRadius:radius];
        glass.cornerConfiguration = shape == DKChatGlassShapeCard
            ? [UICornerConfiguration configurationWithUniformTopRadius:fixed
                                                   uniformBottomRadius:[UICornerRadius containerConcentricRadiusWithMinimum:radius]]
            : [UICornerConfiguration configurationWithUniformRadius:fixed];
    }
    BOOL tintChanged = slot.tint != tint && ![slot.tint isEqual:tint];
    if (!slot.configured || slot.clear != _clear || slot.style != _style || slot.interactive != interactive || tintChanged) {
        slot.clear = _clear;
        slot.style = _style;
        slot.interactive = interactive;
        slot.tint = tint;
        glass.overrideUserInterfaceStyle = _clear ? UIUserInterfaceStyleUnspecified : _style;
        UIGlassEffect *effect = [UIGlassEffect effectWithStyle:_clear ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular];
        effect.interactive = interactive;
        effect.tintColor = tint ?: (_clear ? DKGlassTintForStyle(_style) : nil);
        [UIView performWithoutAnimation:^{ glass.effect = effect; }];
    }
    slot.configured = YES;
    return glass;
}

#pragma mark mask

- (void)maskView:(UIView *)view toGlass:(UIVisualEffectView *)glass {
    if (!view || !glass.superview) return;
    DKChatGlassMask *mask = nil;
    for (DKChatGlassMask *item in _masks) if (item.view == view) { mask = item; break; }
    if (view.layer.mask && view.layer.mask != mask.layer) return;
    if (!mask) {
        mask = [DKChatGlassMask new];
        mask.view = view;
        mask.layer = [CAShapeLayer layer];
        [_masks addObject:mask];
    }
    [_wanted addObject:mask];
    // mask 的坐标系是 view 的可见区域（bounds），滚动视图的 bounds 原点随滚动变化，路径按它换算。
    CGRect rect = [glass.superview convertRect:glass.frame toView:view];
    rect.origin.x -= CGRectGetMinX(view.bounds);
    rect.origin.y -= CGRectGetMinY(view.bounds);
    UIBezierPath *path = DKChatRoundedPath(rect,
        [glass effectiveRadiusForCorner:UIRectCornerTopLeft], [glass effectiveRadiusForCorner:UIRectCornerTopRight],
        [glass effectiveRadiusForCorner:UIRectCornerBottomRight], [glass effectiveRadiusForCorner:UIRectCornerBottomLeft]);
    mask.layer.frame = view.bounds;
    mask.layer.path = path.CGPath;
    if (view.layer.mask != mask.layer) view.layer.mask = mask.layer;
}

- (void)followBoundsOfMaskedView:(UIView *)view {
    for (DKChatGlassMask *mask in _masks) {
        if (mask.view != view || view.layer.mask != mask.layer || CGRectEqualToRect(mask.layer.frame, view.bounds)) continue;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        mask.layer.frame = view.bounds;
        [CATransaction commit];
    }
}

@end
