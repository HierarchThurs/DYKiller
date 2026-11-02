// 图文画面按外层 Cell 居中，保留原生横向布局；超长静态图完整显示。

#import "DKVideoFullscreen.h"
#import "DKUtils.h"
#import <objc/runtime.h>
#import <math.h>

@interface DKRichImageView : UIView @end
@interface DKRichLiveView : UIView @end
@interface DKRichVideoView : UIView @end

@interface DKRichCenterState : NSObject
@property (nonatomic) CGAffineTransform applied;
@property (nonatomic, weak) UIImageView *imageView;
@property (nonatomic) UIViewContentMode imageMode;
@end

@implementation DKRichCenterState
@end

static char kDKRichCenterStateKey;
static NSHashTable<UIView *> *gDKRichCenteredViews;
static NSUInteger gDKRichCenterRewrites;

static Class DKRichCollectionClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(@"AWEStoryContainerCollectionView"); });
    return cls;
}

static Class DKRichImageClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(@"BDMultiContentContainer.ImageContentView"); });
    return cls;
}

static NSArray<Class> *DKRichMediaClasses(void) {
    static NSArray<Class> *classes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray<Class> *found = [NSMutableArray array];
        for (NSString *name in @[@"BDMultiContentContainer.ImageContentView",
                                 @"BDMultiContentContainer.LivePhotoContentView",
                                 @"BDMultiContentContainer.VideoContentView"]) {
            Class cls = NSClassFromString(name);
            if (cls) [found addObject:cls];
        }
        classes = found.copy;
    });
    return classes;
}

static void DKRichRestoreImageMode(DKRichCenterState *state) {
    if (state.imageView.contentMode == UIViewContentModeScaleAspectFit) {
        state.imageView.contentMode = state.imageMode;
    }
    state.imageView = nil;
}

static void DKRichCenterRelease(UIView *view) {
    DKRichCenterState *state = objc_getAssociatedObject(view, &kDKRichCenterStateKey);
    if (!state) return;
    DKRichRestoreImageMode(state);
    objc_setAssociatedObject(view, &kDKRichCenterStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gDKRichCenteredViews removeObject:view];
}

static void DKRichCenterRestore(UIView *view) {
    DKRichCenterState *state = objc_getAssociatedObject(view, &kDKRichCenterStateKey);
    if (!state) return;
    BOOL owned = CGAffineTransformEqualToTransform(view.transform, state.applied);
    DKRichCenterRelease(view);
    if (owned) view.transform = CGAffineTransformIdentity;
}

// 仅查看已确认的内容子树，跳过占位图与隐藏副本。
static UIImageView *DKRichContentImage(UIView *view, NSUInteger depth) {
    if (view.hidden || depth > 4) return nil;
    if ([view isKindOfClass:UIImageView.class] && ((UIImageView *)view).image) {
        return (UIImageView *)view;
    }
    for (UIView *child in view.subviews) {
        UIImageView *image = DKRichContentImage(child, depth + 1);
        if (image) return image;
    }
    return nil;
}

// 原生归零写入统一转换为居中态；缩放交互的非单位矩阵保持原生值。
static CGAffineTransform DKRichCenterTarget(UIView *view, CGAffineTransform native) {
    if (!DKVideoFullscreenOn() || !CGAffineTransformIsIdentity(native)) {
        DKRichCenterRelease(view);
        return native;
    }
    UIView *canvas = DKCellContentView(view.superview);
    DKRichCenterState *state = objc_getAssociatedObject(view, &kDKRichCenterStateKey);
    if (![view.superview isKindOfClass:UICollectionViewCell.class]
        || ![view.superview.superview isKindOfClass:DKRichCollectionClass()]
        || !canvas || !view.window || view.window.windowLevel != UIWindowLevelNormal) {
        DKRichCenterRelease(view);
        return native;
    }

    CGFloat height = CGRectGetHeight(canvas.bounds);
    CGFloat width = CGRectGetWidth(view.bounds);
    if (height <= 0.0 || width <= 0.0 || CGRectGetHeight(view.bounds) <= 0.0) {
        DKRichCenterRelease(view);
        return native;
    }
    UIScrollView *scroll = nil;
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:UIScrollView.class]) { scroll = (UIScrollView *)child; break; }
    }
    if (!scroll || scroll.zooming || scroll.zoomBouncing || fabs(scroll.zoomScale - 1.0) > 1e-4) {
        DKRichCenterRelease(view);
        return native;
    }

    CGFloat scale = 1.0;
    CGFloat centerY = CGRectGetMidY(view.bounds);
    UIImageView *fitImage = nil;
    if ([view isKindOfClass:DKRichImageClass()]) {
        UIImageView *image = DKRichContentImage(scroll, 1);
        CGSize size = image.image.size;
        CGSize bounds = image.bounds.size;
        if (size.width > 0.0 && size.height > 0.0 && bounds.width > 0.0 && bounds.height > 0.0
            && width * size.height / size.width > height + 0.5) {
            CGFloat nativeFit = MIN(bounds.width / size.width, bounds.height / size.height);
            scale = MIN(width / size.width, height / size.height) / nativeFit;
            centerY = [image convertPoint:CGPointMake(CGRectGetMidX(image.bounds),
                                                     CGRectGetMidY(image.bounds)) toView:view].y;
            fitImage = image;
        }
    }
    CGPoint target = [canvas convertPoint:CGPointMake(CGRectGetMidX(canvas.bounds),
                                                     CGRectGetMidY(canvas.bounds)) toView:view.superview];
    CGFloat shift = target.y - view.center.y - (centerY - CGRectGetMidY(view.bounds)) * scale;
    if (!fitImage && fabs(shift) <= 0.5) {
        DKRichCenterRelease(view);
        return native;
    }
    if (!state) {
        state = [DKRichCenterState new];
        objc_setAssociatedObject(view, &kDKRichCenterStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gDKRichCenteredViews addObject:view];
    }
    if (state.imageView != fitImage) DKRichRestoreImageMode(state);
    if (fitImage) {
        if (state.imageView != fitImage || fitImage.contentMode != UIViewContentModeScaleAspectFit) {
            state.imageMode = fitImage.contentMode;
            state.imageView = fitImage;
        }
        if (fitImage.contentMode != UIViewContentModeScaleAspectFit) {
            fitImage.contentMode = UIViewContentModeScaleAspectFit;
        }
    }
    state.applied = CGAffineTransformMake(scale, 0.0, 0.0, scale, 0.0, shift);
    gDKRichCenterRewrites++;
    return state.applied;
}

static void DKRichCenterSync(UIView *view) {
    DKRichCenterState *state = objc_getAssociatedObject(view, &kDKRichCenterStateKey);
    CGAffineTransform current = view.transform;
    BOOL owned = state && CGAffineTransformEqualToTransform(current, state.applied);
    view.transform = owned ? CGAffineTransformIdentity : current;
}

NSArray<UIView *> *DKRichContentCenterCollection(UICollectionView *collection) {
    NSMutableArray<UIView *> *media = [NSMutableArray array];
    for (UICollectionViewCell *cell in collection.visibleCells) {
        for (UIView *child in cell.subviews) {
            for (Class cls in DKRichMediaClasses()) {
                if (![child isKindOfClass:cls]) continue;
                DKRichCenterSync(child);
                if (objc_getAssociatedObject(child, &kDKRichCenterStateKey)) [media addObject:child];
                break;
            }
        }
    }
    return media;
}

%group DKRichImageCenter
%hook DKRichImageView
- (void)setTransform:(CGAffineTransform)transform {
    CGAffineTransform target = DKRichCenterTarget(self, transform);
    if (!CGAffineTransformEqualToTransform(((UIView *)self).transform, target)) %orig(target);
}
%end
%end

%group DKRichLiveCenter
%hook DKRichLiveView
- (void)setTransform:(CGAffineTransform)transform {
    CGAffineTransform target = DKRichCenterTarget(self, transform);
    if (!CGAffineTransformEqualToTransform(((UIView *)self).transform, target)) %orig(target);
}
%end
%end

%group DKRichVideoCenter
%hook DKRichVideoView
- (void)setTransform:(CGAffineTransform)transform {
    CGAffineTransform target = DKRichCenterTarget(self, transform);
    if (!CGAffineTransformEqualToTransform(((UIView *)self).transform, target)) %orig(target);
}
%end
%end

static void DKRichCenterRestoreAll(void) {
    for (UIView *view in gDKRichCenteredViews.allObjects) DKRichCenterRestore(view);
}

NSString *DKRichContentCenterStats(void) {
    return [NSString stringWithFormat:@"图文居中 写入转换=%lu 接管中=%lu",
            (unsigned long)gDKRichCenterRewrites, (unsigned long)gDKRichCenteredViews.count];
}

%ctor {
    gDKRichCenteredViews = [NSHashTable weakObjectsHashTable];
    DKVideoFullscreenRegisterRestore(DKRichCenterRestoreAll);
    Class image = NSClassFromString(@"BDMultiContentContainer.ImageContentView");
    Class live = NSClassFromString(@"BDMultiContentContainer.LivePhotoContentView");
    Class video = NSClassFromString(@"BDMultiContentContainer.VideoContentView");
    if (image) { %init(DKRichImageCenter, DKRichImageView=image); }
    if (live) { %init(DKRichLiveCenter, DKRichLiveView=live); }
    if (video) { %init(DKRichVideoCenter, DKRichVideoView=video); }
}
