// iPad 竖屏评论玻璃的背景遮罩管理，保留原生遮罩的透明度与触摸行为。
#import "DKCommentPadBackdrop.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"

#import <objc/runtime.h>
#import <string.h>

@interface UIViewController (DKPadCommentLayout)
- (BOOL)isLandscape;
- (BOOL)isEmbeddedLandscape;
- (BOOL)isEmbeddedVC;
@end

static char kDKPadCommentBackdropKey;
static NSHashTable<UIViewController *> *gPadCommentControllers;

// Swift 惰性字段没有 ObjC 对象编码。只比较已挂载子视图的指针，不解引用字段中的对象，
// 也不调用会创建遮罩的 getter；偏移由当前运行时解析。
static UIView *DKPadCommentCachedBackdrop(UIViewController *controller, UIView *root) {
    Class cls = object_getClass(controller);
    Ivar ivar = class_getInstanceVariable(cls, "$__lazy_storage_$_backgroundMaskView");
    if (!ivar) return nil;
    ptrdiff_t offset = ivar_getOffset(ivar);
    if (offset < 0 || (size_t)offset + sizeof(void *) > class_getInstanceSize(cls)) return nil;

    void *cached = NULL;
    memcpy(&cached, (const uint8_t *)(__bridge const void *)controller + offset, sizeof(cached));
    for (UIView *view in root.subviews) {
        if ((__bridge void *)view == cached) return view;
    }
    return nil;
}

void DKCommentPadBackdropSync(UIViewController *controller) {
    if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad || !controller) return;

    UIView *previous = objc_getAssociatedObject(controller, &kDKPadCommentBackdropKey);
    UIView *target = nil;
    if (DKGlassOSAvailable() && DKPrefBool(DKKeyCommentGlass)) {
        UIView *root = controller.viewIfLoaded;
        if (root.window && CGRectGetHeight(root.bounds) > CGRectGetWidth(root.bounds)
            && [controller respondsToSelector:@selector(isLandscape)] && !controller.isLandscape
            && [controller respondsToSelector:@selector(isEmbeddedLandscape)] && !controller.isEmbeddedLandscape
            && [controller respondsToSelector:@selector(isEmbeddedVC)] && !controller.isEmbeddedVC) {
            target = DKPadCommentCachedBackdrop(controller, root);
        }
    }

    if (previous && previous != target) DKAdjustFade(previous, 1.0, CGSizeZero);
    if (target) {
        // 独立透明 mask 持续屏蔽原生 alpha 动画；不修改 hidden / alpha 或手势。
        DKAdjustFade(target, 0.0, target.bounds.size);
        if (DKAdjustFadeFactor(target) != 0.0) {
            DKAdjustFade(target, 1.0, CGSizeZero);
            target = nil;
        }
    }
    objc_setAssociatedObject(controller, &kDKPadCommentBackdropKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (target) {
        if (!gPadCommentControllers) gPadCommentControllers = [NSHashTable weakObjectsHashTable];
        [gPadCommentControllers addObject:controller];
    } else {
        [gPadCommentControllers removeObject:controller];
    }
}

void DKCommentPadBackdropRefresh(void) {
    for (UIViewController *controller in gPadCommentControllers.allObjects) {
        DKCommentPadBackdropSync(controller);
    }
}
