//
//  DKListenGlassNav.m
//  DYKiller
//
//  听抖音页与分类列表页共用的顶部：返回圆钮与标题胶囊。玻璃放在原生按钮下方的透明层里，整块玻璃都能点。
//

#import "DKImageOpaque.h"
#import "DKListenGlass.h"
#import "DKListenHitLayer.h"
#import "DKViewAdjust.h"

#import <objc/runtime.h>

static const CGFloat kDKListenNavHeight = 44.0;
static const CGFloat kDKListenNavEdge = 16.0;
static const CGFloat kDKListenTitlePadding = 16.0;

static char kDKListenClipsKey;

void DKListenGlassSetUnclipped(UIView *view, BOOL unclipped) {
    if (!view) return;
    NSNumber *native = objc_getAssociatedObject(view, &kDKListenClipsKey);
    if (unclipped) {
        if (!native) objc_setAssociatedObject(view, &kDKListenClipsKey, @(view.clipsToBounds), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (view.clipsToBounds) view.clipsToBounds = NO;
    } else if (native) {
        view.clipsToBounds = native.boolValue;
        objc_setAssociatedObject(view, &kDKListenClipsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// 返回键实际画出的箭头相对玻璃中心的偏移：箭头不在 24pt 画布正中。
static CGAffineTransform DKListenBackTransform(UIButton *back, CGPoint center) {
    UIImageView *icon = back.imageView.image ? back.imageView : nil;
    if (!icon) {
        for (UIView *child in back.subviews) {
            if ([child isKindOfClass:UIImageView.class] && ((UIImageView *)child).image) {
                icon = (UIImageView *)child;
                break;
            }
        }
    }
    CGRect visible = icon ? DKImageOpaqueVisibleRect(icon) : CGRectNull;
    CGRect drawn = CGRectIsNull(visible) ? back.bounds : [icon convertRect:visible toView:back];
    CGRect frame = DKAdjustLayoutFrame(back);
    return CGAffineTransformMakeTranslation(center.x - CGRectGetMinX(frame) - CGRectGetMidX(drawn),
                                            center.y - CGRectGetMinY(frame) - CGRectGetMidY(drawn));
}

API_AVAILABLE(ios(26.0))
static void DKListenNavRestore(UIView *host, UIButton *back, UIView *title) {
    if (![DKChatGlassStore storeForOwner:host create:NO]) return;
    [DKChatGlassStore removeStoreForOwner:host];
    [DKListenHitLayer removeFromHost:host];
    DKAdjustTransform(back, CGAffineTransformIdentity);
    DKAdjustTransform(title, CGAffineTransformIdentity);
}

void DKListenGlassSyncNav(UIView *host, UIButton *back, UIView *title, CGFloat titleExtra) {
    if (@available(iOS 26.0, *)) {
        if (!DKListenGlassOn()) {
            DKListenNavRestore(host, back, title);
            return;
        }
        if (!back || back.hidden || back.superview != host) return;
        DKChatGlassStore *store = [DKChatGlassStore storeForOwner:host create:YES];
        if (store.syncing) return;

        DKListenHitLayer *layer = [DKListenHitLayer layerInHost:host create:YES];
        UIView *lowest = back;
        if (title && [host.subviews indexOfObject:title] < [host.subviews indexOfObject:back]) lowest = title;
        if (layer.superview != host || [host.subviews indexOfObject:layer] > [host.subviews indexOfObject:lowest]) {
            [host insertSubview:layer belowSubview:lowest];
        }
        [layer removeAllRegions];
        DKListenGlassBegin(store);

        CGRect backFrame = DKAdjustLayoutFrame(back);
        CGRect backGlass = CGRectMake(kDKListenNavEdge, CGRectGetMidY(backFrame) - kDKListenNavHeight * 0.5,
                                      kDKListenNavHeight, kDKListenNavHeight);
        UIView *glass = [store placeGlassFor:back in:layer frame:backGlass shape:DKChatGlassShapeRounded
                                      radius:kDKListenNavHeight * 0.5 interactive:YES tint:nil];
        [layer addRegionForGlass:glass targets:@[ back ]];
        DKAdjustTransform(back, DKListenBackTransform(back, CGPointMake(CGRectGetMidX(backGlass), CGRectGetMidY(backGlass))));

        if (title && !title.hidden) {
            // 标题连同右侧箭头在胶囊内居中，胶囊在页面上居中。
            CGRect titleFrame = DKAdjustLayoutFrame(title);
            CGFloat contentWidth = CGRectGetWidth(titleFrame) + titleExtra;
            CGFloat width = contentWidth + kDKListenTitlePadding * 2.0;
            CGFloat midX = CGRectGetMidX(host.bounds);
            CGRect titleGlass = CGRectMake(midX - width * 0.5, CGRectGetMidY(titleFrame) - kDKListenNavHeight * 0.5,
                                           width, kDKListenNavHeight);
            UIView *capsule = [store placeGlassFor:title in:layer frame:titleGlass shape:DKChatGlassShapeRounded
                                            radius:kDKListenNavHeight * 0.5 interactive:[title isKindOfClass:UIControl.class] tint:nil];
            if ([title isKindOfClass:UIControl.class]) [layer addRegionForGlass:capsule targets:@[ title ]];
            DKAdjustTransform(title, CGAffineTransformMakeTranslation(midX - CGRectGetMinX(titleFrame) - contentWidth * 0.5, 0.0));
        }
        [store end];
    }
}
