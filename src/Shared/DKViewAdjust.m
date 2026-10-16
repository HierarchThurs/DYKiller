//
//  DKViewAdjust.m
//  DYKiller
//
//  可复位的视图调整，供互动按钮、昵称文案、顶栏与底栏等外观功能共用。
//

#import "DKViewAdjust.h"

#import <math.h>
#import <objc/runtime.h>

static char kDKAdjustBaseAlphaKey;
static char kDKAdjustAppliedAlphaKey;
static char kDKAdjustBaseTransformKey;
static char kDKAdjustAppliedTransformKey;
static char kDKAdjustFadeMaskKey;

BOOL DKAdjustTransformEqual(CGAffineTransform lhs, CGAffineTransform rhs) {
    return fabs(lhs.a - rhs.a) < 0.0005 && fabs(lhs.b - rhs.b) < 0.0005
        && fabs(lhs.c - rhs.c) < 0.0005 && fabs(lhs.d - rhs.d) < 0.0005
        && fabs(lhs.tx - rhs.tx) < 0.05 && fabs(lhs.ty - rhs.ty) < 0.05;
}

void DKAdjustAlpha(UIView *view, CGFloat factor) {
    if (!view) return;
    factor = MIN(1.0, MAX(0.0, factor));

    NSNumber *applied = objc_getAssociatedObject(view, &kDKAdjustAppliedAlphaKey);
    NSNumber *base = objc_getAssociatedObject(view, &kDKAdjustBaseAlphaKey);
    CGFloat current = view.alpha;
    CGFloat original = current;
    if (applied && base && fabs(current - applied.doubleValue) < 0.005) {
        original = base.doubleValue;
    }

    if (factor >= 0.9999) {
        if (applied && base) view.alpha = original;
        objc_setAssociatedObject(view, &kDKAdjustBaseAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &kDKAdjustAppliedAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    CGFloat target = original * factor;
    if (fabs(current - target) >= 0.005) view.alpha = target;
    objc_setAssociatedObject(view, &kDKAdjustBaseAlphaKey, @(original), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kDKAdjustAppliedAlphaKey, @(target), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void DKAdjustTransform(UIView *view, CGAffineTransform delta) {
    if (!view) return;

    NSValue *appliedValue = objc_getAssociatedObject(view, &kDKAdjustAppliedTransformKey);
    NSValue *baseValue = objc_getAssociatedObject(view, &kDKAdjustBaseTransformKey);
    CGAffineTransform current = view.transform;
    CGAffineTransform original = current;
    if (appliedValue && baseValue && DKAdjustTransformEqual(current, appliedValue.CGAffineTransformValue)) {
        original = baseValue.CGAffineTransformValue;
    }

    if (DKAdjustTransformEqual(delta, CGAffineTransformIdentity)) {
        if (appliedValue && baseValue) view.transform = original;
        objc_setAssociatedObject(view, &kDKAdjustBaseTransformKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &kDKAdjustAppliedTransformKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    CGAffineTransform target = CGAffineTransformConcat(original, delta);
    if (!DKAdjustTransformEqual(current, target)) view.transform = target;
    objc_setAssociatedObject(view, &kDKAdjustBaseTransformKey,
                             [NSValue valueWithCGAffineTransform:original], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kDKAdjustAppliedTransformKey,
                             [NSValue valueWithCGAffineTransform:target], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void DKAdjustFade(UIView *view, CGFloat factor, CGSize outset) {
    if (!view) return;
    factor = MIN(1.0, MAX(0.0, factor));

    CALayer *mask = objc_getAssociatedObject(view, &kDKAdjustFadeMaskKey);
    BOOL owned = mask && view.layer.mask == mask;
    if (factor >= 0.9999) {
        if (owned) view.layer.mask = nil;
        objc_setAssociatedObject(view, &kDKAdjustFadeMaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (view.layer.mask && !owned) return;

    if (!mask) {
        mask = [CALayer layer];
        objc_setAssociatedObject(view, &kDKAdjustFadeMaskKey, mask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    mask.frame = CGRectInset(view.bounds, -outset.width, -outset.height);
    mask.backgroundColor = [UIColor colorWithWhite:1.0 alpha:factor].CGColor;
    if (!owned) view.layer.mask = mask;
    [CATransaction commit];
}

CGFloat DKAdjustFadeFactor(UIView *view) {
    CALayer *mask = objc_getAssociatedObject(view, &kDKAdjustFadeMaskKey);
    if (!mask || view.layer.mask != mask) return 1.0;
    return CGColorGetAlpha(mask.backgroundColor);
}

void DKAdjustStackRows(UIStackView *stack, DKStackEdge edge,
                       CGFloat (^scaleForRow)(UIView *row),
                       CGFloat (^contentBottomForRow)(UIView *row)) {
    NSArray<UIView *> *rows = stack.arrangedSubviews;
    CGFloat direction = edge == DKStackEdgeRight ? 1.0 : -1.0;

    // 最底可见行：它内容下方的留白缩掉多少，就整体上提多少，内容底边保持原位。
    CGFloat shift = 0;
    for (UIView *row in rows.reverseObjectEnumerator) {
        if (row.hidden) continue;
        CGFloat padding = CGRectGetMaxY(row.bounds) - contentBottomForRow(row);
        shift = -padding * (1.0 - scaleForRow(row));
        break;
    }

    for (UIView *row in rows.reverseObjectEnumerator) {
        if (row.hidden) {
            DKAdjustTransform(row, CGAffineTransformIdentity);
            continue;
        }
        CGFloat scale = scaleForRow(row);
        CGSize size = row.bounds.size;
        DKAdjustTransform(row, CGAffineTransformMake(scale, 0, 0, scale,
                                                     direction * size.width * (1.0 - scale) / 2.0,
                                                     shift + size.height * (1.0 - scale) / 2.0));
        shift += size.height * (1.0 - scale);
    }
}
