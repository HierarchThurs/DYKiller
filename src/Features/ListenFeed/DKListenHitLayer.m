//
//  DKListenHitLayer.m
//  DYKiller
//

#import "DKListenHitLayer.h"
#import <math.h>
#import <objc/runtime.h>

static char kDKListenHitLayerKey;

@interface DKListenHitRegion : NSObject
@property (nonatomic, strong) UIView *glass;
@property (nonatomic, copy) NSArray<UIView *> *targets;
@end
@implementation DKListenHitRegion
@end

// 视图到 stop 之间的每一层都可见；needsInteraction 时还要求都能响应触摸。
static BOOL DKListenHitChainUsable(UIView *view, UIView *stop, BOOL needsInteraction) {
    for (UIView *node = view; node && node != stop; node = node.superview) {
        if (node.hidden || node.alpha < 0.01) return NO;
        if (needsInteraction && !node.userInteractionEnabled) return NO;
    }
    return YES;
}

@implementation DKListenHitLayer {
    NSMutableArray<DKListenHitRegion *> *_regions;
}

+ (instancetype)layerInHost:(UIView *)host create:(BOOL)create {
    if (!host) return nil;
    DKListenHitLayer *layer = objc_getAssociatedObject(host, &kDKListenHitLayerKey);
    if (!layer && create) {
        layer = [[DKListenHitLayer alloc] initWithFrame:host.bounds];
        layer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        objc_setAssociatedObject(host, &kDKListenHitLayerKey, layer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return layer;
}

+ (void)removeFromHost:(UIView *)host {
    [[self layerInHost:host create:NO] removeFromSuperview];
    objc_setAssociatedObject(host, &kDKListenHitLayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _regions = [NSMutableArray array];
        self.backgroundColor = UIColor.clearColor;
    }
    return self;
}

- (void)removeAllRegions {
    [_regions removeAllObjects];
}

- (void)addRegionForGlass:(UIView *)glass targets:(NSArray<UIView *> *)targets {
    if (!glass || targets.count == 0) return;
    DKListenHitRegion *region = [DKListenHitRegion new];
    region.glass = glass;
    region.targets = targets;
    [_regions addObject:region];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *host = self.superview;
    for (DKListenHitRegion *region in _regions) {
        if (!DKListenHitChainUsable(region.glass, host, NO)) continue;
        if (!CGRectContainsPoint([region.glass convertRect:region.glass.bounds toView:self], point)) continue;
        UIView *nearest = nil;
        CGFloat nearestDistance = CGFLOAT_MAX;
        for (UIView *target in region.targets) {
            if (!DKListenHitChainUsable(target, host, YES)) continue;
            CGRect rect = [target convertRect:target.bounds toView:self];
            CGFloat distance = fabs(CGRectGetMidX(rect) - point.x);
            if (distance < nearestDistance) {
                nearestDistance = distance;
                nearest = target;
            }
        }
        return nearest;
    }
    return nil;
}

@end
