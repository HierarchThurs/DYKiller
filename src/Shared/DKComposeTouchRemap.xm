#import "DKComposeTouchRemap.h"

#import <objc/runtime.h>

@interface DKComposeRenderView : UIView @end
@interface DKComposeRowView : UIView @end

@interface DKComposeTouchRegion ()
@property (nonatomic) CGRect rect;
@property (nonatomic) CGPoint target;
@end

@implementation DKComposeTouchRegion
+ (instancetype)regionWithRect:(CGRect)rect target:(CGPoint)target
                    sourceView:(UIView *)sourceView touchView:(UIView *)touchView {
    DKComposeTouchRegion *region = [self new];
    region.rect = [sourceView convertRect:rect toView:touchView];
    region.target = [sourceView convertPoint:target toView:touchView];
    return region;
}
@end

static char kDKComposeRegionsKey;
static char kDKComposeRowLayoutObserverKey;
static NSMutableArray<void (^)(UIView *)> *gDKComposeObservers;

void DKComposeObserveRenderLayout(void (^observer)(UIView *)) {
    if (!gDKComposeObservers) gDKComposeObservers = [NSMutableArray array];
    [gDKComposeObservers addObject:[observer copy]];
}

void DKComposeSetRowLayoutObserver(UIView *row, void (^observer)(UIView *)) {
    if (row) objc_setAssociatedObject(row, &kDKComposeRowLayoutObserverKey, observer, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

UIView *DKComposeTouchView(UIView *renderView) {
    for (UIView *view = renderView.superview; view; view = view.superview) {
        if ([NSStringFromClass(view.class) containsString:@"UserInputView"]) return view;
    }
    return nil;
}

void DKComposeSetTouchRegions(UIView *touchView, NSArray<DKComposeTouchRegion *> *regions) {
    if (touchView) objc_setAssociatedObject(touchView, &kDKComposeRegionsKey, regions, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

%group DKComposeHooks

%hook DKComposeRenderView
- (void)layoutSubviews {
    %orig;
    if (!NSThread.isMainThread) return;
    for (void (^observer)(UIView *) in gDKComposeObservers) observer(self);
}
%end

%hook UITouch
- (CGPoint)locationInView:(UIView *)view {
    CGPoint location = %orig;
    if (!view || !NSThread.isMainThread) return location;
    NSArray<DKComposeTouchRegion *> *regions = objc_getAssociatedObject(view, &kDKComposeRegionsKey);
    for (DKComposeTouchRegion *region in regions) {
        if (CGRectContainsPoint(region.rect, location)) return region.target;
    }
    return location;
}
%end

%end

%group DKComposeRowHooks
%hook DKComposeRowView
- (void)layoutSubviews {
    %orig;
    void (^observer)(UIView *) = objc_getAssociatedObject(self, &kDKComposeRowLayoutObserverKey);
    if (observer && NSThread.isMainThread) observer(self);
}
%end
%end

%ctor {
    Class renderClass = objc_getClass("DanceUICompose.ComposeRenderingUIViewImpl");
    if (renderClass) %init(DKComposeHooks, DKComposeRenderView=renderClass);
    Class rowClass = objc_getClass("DanceUI._RenderNodeLayerView");
    if (rowClass) %init(DKComposeRowHooks, DKComposeRowView=rowClass);
}
