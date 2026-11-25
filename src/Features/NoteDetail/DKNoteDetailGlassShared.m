#import "DKNoteDetailGlassShared.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKUtils.h"

#import <objc/runtime.h>

const CGFloat kDKNoteTopHeight = 40.0;
const CGFloat kDKNoteEdge = 8.0;
const CGFloat kDKNoteClusterGap = 4.0;
const CGFloat kDKNoteGlassMergeSpacing = 2.0;
const CGFloat kDKNoteNamePadding = 12.0;

static char kDKNoteGlassHitsKey;
static char kDKNoteScrollerClippingKey;

@interface DKNoteGlassHit ()
@property (nonatomic) CGRect rect;
@property (nonatomic, weak) UIView *target;
@end

@interface DKNoteScrollerClipping : NSObject
@property (nonatomic, weak) UIScrollView *scroller;
@property (nonatomic) BOOL clipsToBounds;
@end
@implementation DKNoteScrollerClipping
@end

@implementation DKNoteGlassHit
+ (instancetype)hitWithRect:(CGRect)rect target:(UIView *)target {
    DKNoteGlassHit *hit = [self new];
    hit.rect = rect;
    hit.target = target;
    return hit;
}
@end

BOOL DKNoteGlassEnabled(void) {
    return DKGlassOSAvailable() && DKPrefBool(DKKeyNoteDetailGlass);
}

void DKNoteSetGlassHits(UIView *bar, NSArray<DKNoteGlassHit *> *hits) {
    objc_setAssociatedObject(bar, &kDKNoteGlassHitsKey, hits, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

UIView *DKNoteGlassTargetAtPoint(UIView *bar, CGPoint point) {
    NSArray<DKNoteGlassHit *> *hits = objc_getAssociatedObject(bar, &kDKNoteGlassHitsKey);
    for (DKNoteGlassHit *hit in hits) {
        if (!CGRectContainsPoint(hit.rect, point)) continue;
        UIView *target = hit.target;
        for (UIView *view = target; view; view = view.superview) {
            if (view.hidden || view.alpha <= 0.01 || !view.userInteractionEnabled) break;
            if (view == bar) return target;
        }
    }
    return nil;
}

UIScrollView *DKNoteScrollerForBar(UIView *bar) {
    Class scrollerClass = objc_getClass("AWETabListContainerScrollView");
    for (UIView *sibling in bar.superview.subviews) {
        if (sibling == bar) continue;
        if ([sibling isKindOfClass:scrollerClass]) return (UIScrollView *)sibling;
        for (UIView *child in sibling.subviews) {
            if ([child isKindOfClass:scrollerClass]) return (UIScrollView *)child;
        }
    }
    return nil;
}

// 关闭外层滚动视图裁剪，让内容从顶栏下方滚过。
void DKNoteSetContentOverflow(UIView *bar, BOOL overflow) {
    UIScrollView *scroller = overflow ? DKNoteScrollerForBar(bar) : nil;
    DKNoteScrollerClipping *saved = objc_getAssociatedObject(bar, &kDKNoteScrollerClippingKey);
    if (saved && (!scroller || saved.scroller != scroller)) {
        saved.scroller.clipsToBounds = saved.clipsToBounds;
        objc_setAssociatedObject(bar, &kDKNoteScrollerClippingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        saved = nil;
    }
    if (!scroller) return;
    if (!saved) {
        saved = [DKNoteScrollerClipping new];
        saved.scroller = scroller;
        saved.clipsToBounds = scroller.clipsToBounds;
        objc_setAssociatedObject(bar, &kDKNoteScrollerClippingKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (scroller.clipsToBounds) scroller.clipsToBounds = NO;
}
