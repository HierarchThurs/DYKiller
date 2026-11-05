//
//  DKNoteDetailGlass.xm
//  DYKiller
//
//  图文详情页（展开文案后进入）顶栏与底栏的液态玻璃。
//   - 两条栏是 Compose + DanceUI 渲染，元素是渲染视图的直接子视图，按类型与顺序识别。
//   - 玻璃垫在 Compose 视图下方，元素只用 transform 移位，栏底色清除后内容从栏下滚过。
//   - Compose 按原生布局坐标判定点击，整块玻璃的触摸在读坐标时换算到对应元素的中心。
//

#import "DKChatGlassStore.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"

#import <objc/runtime.h>

@interface DKNoteRenderView : UIView @end
@interface DKNoteBottomBar : UIView @end

static const CGFloat kDKNoteTopHeight = 40.0;
static const CGFloat kDKNoteBottomHeight = 46.0;
static const CGFloat kDKNoteEdge = 8.0;          // 屏幕边距、不同分组之间的间距
static const CGFloat kDKNoteClusterGap = 4.0;    // 返回、头像、用户名之间的间距
static const CGFloat kDKNoteNamePadding = 12.0;  // 用户名胶囊的左右内边距

static Class gDKNoteTopBarClass;
static Class gDKNoteBottomBarClass;
static Class gDKNoteInheritedClass;
static Class gDKNoteDrawingClass;
static Class gDKNoteShapeClass;
static Class gDKNoteGraphicsClass;
static Class gDKNoteInputClass;
static Class gDKNoteScrollerClass;
static NSHashTable<UIView *> *gDKNoteRenderViews;

static char kDKNoteHitsKey;
static char kDKNoteInputHitKey;
static char kDKNoteScrollerClipsKey;

// 一块玻璃的触摸区与原生元素中心，都是 Compose 触摸视图坐标。
@interface DKNoteHit : NSObject
@property (nonatomic) CGRect rect;
@property (nonatomic) CGPoint target;
@end
@implementation DKNoteHit
@end

// 输入框玻璃的命中区（栏坐标）：输入框是 UIKit 视图，由 hitTest 分发。
@interface DKNoteInputHit : NSObject
@property (nonatomic) CGRect rect;
@property (nonatomic, weak) UIView *input;
@end
@implementation DKNoteInputHit
@end

static UIView *DKNoteBarForRenderView(UIView *renderView) {
    for (UIView *node = renderView.superview; node; node = node.superview) {
        if ([node isKindOfClass:gDKNoteTopBarClass] || [node isKindOfClass:gDKNoteBottomBarClass]) return node;
    }
    return nil;
}

// 接收触摸的 Compose 视图：类名带版本后缀，按名称片段沿父链查找。
static UIView *DKNoteTouchViewForRenderView(UIView *renderView) {
    for (UIView *node = renderView.superview; node; node = node.superview) {
        if ([NSStringFromClass(node.class) containsString:@"UserInputView"]) return node;
    }
    return nil;
}

// 不含 transform 的原生 frame。
static CGRect DKNoteNativeFrame(UIView *view) {
    CALayer *layer = view.layer;
    CGSize size = layer.bounds.size;
    return CGRectMake(layer.position.x - layer.anchorPoint.x * size.width,
                      layer.position.y - layer.anchorPoint.y * size.height, size.width, size.height);
}

static CGPoint DKNoteCenter(CGRect rect) {
    return CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
}

static DKNoteHit *DKNoteMakeHit(CGRect rect, CGPoint target, UIView *renderView, UIView *touchView) {
    DKNoteHit *hit = [DKNoteHit new];
    hit.rect = [renderView convertRect:rect toView:touchView];
    hit.target = [renderView convertPoint:target toView:touchView];
    return hit;
}

API_AVAILABLE(ios(26.0))
static UIVisualEffectView *DKNotePlaceGlass(DKChatGlassStore *store, UIView *source, UIView *bar, CGRect rect, CGPoint origin) {
    return [store placeGlassFor:source in:bar frame:CGRectOffset(rect, origin.x, origin.y)
                          shape:DKChatGlassShapeRounded radius:CGRectGetHeight(rect) * 0.5 interactive:NO tint:nil];
}

static UIScrollView *DKNoteScrollerForBar(UIView *bar) {
    for (UIView *child in bar.superview.subviews) {
        for (UIView *inner in child.subviews) {
            if ([inner isKindOfClass:gDKNoteScrollerClass]) return (UIScrollView *)inner;
        }
    }
    return nil;
}

// 关掉外层滚动视图的裁剪，内容才能滚到顶栏下方；布局与 inset 保持原生。
static void DKNoteSetContentOverflow(UIView *bar, BOOL overflow) {
    UIScrollView *scroller = DKNoteScrollerForBar(bar);
    if (!scroller) return;
    NSNumber *saved = objc_getAssociatedObject(scroller, &kDKNoteScrollerClipsKey);
    if (overflow) {
        if (!saved) objc_setAssociatedObject(scroller, &kDKNoteScrollerClipsKey, @(scroller.clipsToBounds), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (scroller.clipsToBounds) scroller.clipsToBounds = NO;
    } else if (saved) {
        scroller.clipsToBounds = saved.boolValue;
        objc_setAssociatedObject(scroller, &kDKNoteScrollerClipsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

API_AVAILABLE(ios(26.0))
static void DKNoteSyncTopBar(DKChatGlassStore *store, UIView *bar, UIView *renderView, UIView *touchView) {
    NSMutableArray<UIView *> *controls = [NSMutableArray array];
    NSMutableArray<UIView *> *texts = [NSMutableArray array];
    UIView *followShape = nil;
    for (UIView *child in renderView.subviews) {
        if ([child isKindOfClass:gDKNoteInheritedClass]) {
            [controls addObject:child];
        } else if ([child isKindOfClass:gDKNoteDrawingClass]) {
            [texts addObject:child];
        } else if ([child isKindOfClass:gDKNoteShapeClass]) {
            followShape = child;
        } else if ([child isKindOfClass:gDKNoteGraphicsClass]) {
            DKAdjustFade(child, 0.0, CGSizeZero);  // 底部分隔线
        }
    }
    if (controls.count < 2) return;

    UIView *back = controls.firstObject;
    UIView *search = controls.lastObject;
    UIView *avatar = controls.count > 2 ? controls[1] : nil;
    UIView *name = texts.firstObject;
    CGPoint origin = [renderView convertPoint:CGPointZero toView:bar];
    CGFloat width = CGRectGetWidth(renderView.bounds);
    CGRect backFrame = DKNoteNativeFrame(back);
    CGFloat top = CGRectGetMidY(backFrame) - kDKNoteTopHeight * 0.5;
    NSMutableArray<DKNoteHit *> *hits = [NSMutableArray array];

    // 返回键的箭头在原生 24pt 框内偏左，框不移动时箭头正好落在玻璃中心。
    CGRect backGlass = CGRectMake(kDKNoteEdge, top, kDKNoteTopHeight, kDKNoteTopHeight);
    DKNotePlaceGlass(store, back, bar, backGlass, origin);
    [hits addObject:DKNoteMakeHit(backGlass, DKNoteCenter(backFrame), renderView, touchView)];
    CGFloat cursor = CGRectGetMaxX(backGlass) + kDKNoteClusterGap;

    if (avatar) {
        CGRect frame = DKNoteNativeFrame(avatar);
        CGRect glass = CGRectMake(cursor, top, kDKNoteTopHeight, kDKNoteTopHeight);
        DKAdjustTransform(avatar, CGAffineTransformMakeTranslation(CGRectGetMidX(glass) - CGRectGetMidX(frame), 0.0));
        DKNotePlaceGlass(store, avatar, bar, glass, origin);
        [hits addObject:DKNoteMakeHit(glass, DKNoteCenter(frame), renderView, touchView)];
        cursor = CGRectGetMaxX(glass) + kDKNoteClusterGap;
    }

    CGRect searchFrame = DKNoteNativeFrame(search);
    CGRect searchGlass = CGRectMake(width - kDKNoteEdge - kDKNoteTopHeight, top, kDKNoteTopHeight, kDKNoteTopHeight);
    DKAdjustTransform(search, CGAffineTransformMakeTranslation(CGRectGetMidX(searchGlass) - CGRectGetMidX(searchFrame), 0.0));
    DKNotePlaceGlass(store, search, bar, searchGlass, origin);
    [hits addObject:DKNoteMakeHit(searchGlass, DKNoteCenter(searchFrame), renderView, touchView)];
    CGFloat limit = CGRectGetMinX(searchGlass) - kDKNoteEdge;

    if (followShape) {
        CGRect frame = DKNoteNativeFrame(followShape);
        DKAdjustFade(followShape, 0.0, CGSizeZero);
        CGRect glass = CGRectMake(CGRectGetMinX(frame), top, CGRectGetWidth(frame), kDKNoteTopHeight);
        DKNotePlaceGlass(store, followShape, bar, glass, origin);
        [hits addObject:DKNoteMakeHit(glass, DKNoteCenter(frame), renderView, touchView)];
        limit = CGRectGetMinX(glass) - kDKNoteEdge;
    }

    if (name && CGRectGetWidth(name.bounds) > 0.0 && (!followShape || texts.count > 1)) {
        CGRect frame = DKNoteNativeFrame(name);
        CGFloat capsuleWidth = CGRectGetWidth(frame) + kDKNoteNamePadding * 2.0;
        CGRect glass = CGRectMake(cursor, top, MIN(capsuleWidth, limit - cursor), kDKNoteTopHeight);
        DKAdjustTransform(name, CGAffineTransformMakeTranslation(cursor + kDKNoteNamePadding - CGRectGetMinX(frame), 0.0));
        UIVisualEffectView *glassView = DKNotePlaceGlass(store, name, bar, glass, origin);
        // 长用户名超出胶囊的部分裁掉。
        if (capsuleWidth > limit - cursor) [store maskView:name toGlass:glassView];
        [hits addObject:DKNoteMakeHit(glass, DKNoteCenter(frame), renderView, touchView)];
    }

    objc_setAssociatedObject(touchView, &kDKNoteHitsKey, hits, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKNoteSetContentOverflow(bar, YES);
}

API_AVAILABLE(ios(26.0))
static void DKNoteSyncBottomBar(DKChatGlassStore *store, UIView *bar, UIView *renderView, UIView *touchView) {
    NSMutableArray<UIView *> *icons = [NSMutableArray array];
    NSMutableArray<UIView *> *counts = [NSMutableArray array];
    UIView *inputHost = nil;
    for (UIView *child in renderView.subviews) {
        if ([child isKindOfClass:gDKNoteInheritedClass]) {
            [icons addObject:child];
        } else if ([child isKindOfClass:gDKNoteDrawingClass]) {
            [counts addObject:child];
        } else if ([child isKindOfClass:gDKNoteGraphicsClass]) {
            DKAdjustFade(child, 0.0, CGSizeZero);  // 白色底板与顶部分隔线
        } else if (child.subviews.firstObject && [child.subviews.firstObject isKindOfClass:gDKNoteInputClass]) {
            inputHost = child;
        }
    }
    if (!inputHost || icons.count == 0) return;

    UIView *input = inputHost.subviews.firstObject;
    [store clearBackingOfView:input];

    CGPoint origin = [renderView convertPoint:CGPointZero toView:bar];
    CGFloat width = CGRectGetWidth(renderView.bounds);
    CGRect inputFrame = DKNoteNativeFrame(inputHost);
    CGFloat top = CGRectGetMidY(inputFrame) - kDKNoteBottomHeight * 0.5;

    CGRect inputGlass = CGRectMake(kDKNoteEdge, top, CGRectGetMaxX(inputFrame) - kDKNoteEdge, kDKNoteBottomHeight);
    DKNotePlaceGlass(store, input, bar, inputGlass, origin);
    DKNoteInputHit *inputHit = [DKNoteInputHit new];
    inputHit.input = input;
    inputHit.rect = CGRectOffset(inputGlass, origin.x, origin.y);
    objc_setAssociatedObject(bar, &kDKNoteInputHitKey, inputHit, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 四键在胶囊内整体居中，数字与图标同步移位。
    CGRect capsule = CGRectMake(CGRectGetMaxX(inputGlass) + kDKNoteEdge, top,
                                width - kDKNoteEdge - CGRectGetMaxX(inputGlass) - kDKNoteEdge, kDKNoteBottomHeight);
    CGRect firstIcon = DKNoteNativeFrame(icons.firstObject);
    CGRect lastIcon = DKNoteNativeFrame(icons.lastObject);
    CGFloat shift = CGRectGetMidX(capsule) - (CGRectGetMinX(firstIcon) + CGRectGetMaxX(lastIcon)) * 0.5;
    CGAffineTransform translation = CGAffineTransformMakeTranslation(shift, 0.0);
    for (UIView *icon in icons) DKAdjustTransform(icon, translation);
    for (UIView *count in counts) DKAdjustTransform(count, translation);
    DKNotePlaceGlass(store, icons.firstObject, bar, capsule, origin);

    // 胶囊按相邻图标的中点分成四段，每段换算到对应图标的中心。
    NSMutableArray<DKNoteHit *> *hits = [NSMutableArray arrayWithCapacity:icons.count];
    CGFloat left = CGRectGetMinX(capsule);
    for (NSUInteger index = 0; index < icons.count; index++) {
        CGRect frame = DKNoteNativeFrame(icons[index]);
        CGFloat right = CGRectGetMaxX(capsule);
        if (index + 1 < icons.count) {
            right = (CGRectGetMidX(frame) + CGRectGetMidX(DKNoteNativeFrame(icons[index + 1]))) * 0.5 + shift;
        }
        CGRect segment = CGRectMake(left, top, right - left, kDKNoteBottomHeight);
        [hits addObject:DKNoteMakeHit(segment, DKNoteCenter(frame), renderView, touchView)];
        left = right;
    }
    objc_setAssociatedObject(touchView, &kDKNoteHitsKey, hits, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

API_AVAILABLE(ios(26.0))
static void DKNoteRestore(UIView *bar, UIView *renderView, UIView *touchView) {
    [DKChatGlassStore removeStoreForOwner:bar];
    for (UIView *child in renderView.subviews) {
        DKAdjustTransform(child, CGAffineTransformIdentity);
        DKAdjustFade(child, 1.0, CGSizeZero);
    }
    objc_setAssociatedObject(touchView, &kDKNoteHitsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(bar, &kDKNoteInputHitKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if ([bar isKindOfClass:gDKNoteTopBarClass]) DKNoteSetContentOverflow(bar, NO);
}

static void DKNoteSync(UIView *renderView) {
    if (@available(iOS 26.0, *)) {
        UIView *bar = DKNoteBarForRenderView(renderView);
        if (!bar) return;
        [gDKNoteRenderViews addObject:renderView];
        UIView *touchView = DKNoteTouchViewForRenderView(renderView);
        if (!touchView) return;

        if (!DKPrefBool(DKKeyNoteDetailGlass) || !DKGlassOSAvailable()) {
            if ([DKChatGlassStore storeForOwner:bar create:NO]) DKNoteRestore(bar, renderView, touchView);
            return;
        }
        DKChatGlassStore *store = [DKChatGlassStore storeForOwner:bar create:YES];
        if (store.syncing) return;
        [store beginWithClear:DKPrefBool(DKKeyNoteDetailGlassClear) style:bar.traitCollection.userInterfaceStyle];
        [store clearBackingOfView:bar];
        if ([bar isKindOfClass:gDKNoteTopBarClass]) {
            DKNoteSyncTopBar(store, bar, renderView, touchView);
        } else {
            DKNoteSyncBottomBar(store, bar, renderView, touchView);
        }
        [store end];
    }
}

static void DKNoteRefresh(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKNoteRefresh(); });
        return;
    }
    for (UIView *renderView in gDKNoteRenderViews.allObjects) DKNoteSync(renderView);
}

%group DKNoteDetailGlassHooks
// 元素增减与尺寸变化都会让渲染视图重新布局，每轮按当前元素同步。
%hook DKNoteRenderView
- (void)layoutSubviews {
    %orig;
    DKNoteSync(self);
}
%end

%hook UITouch
- (CGPoint)locationInView:(UIView *)view {
    CGPoint location = %orig;
    NSArray<DKNoteHit *> *hits = view ? objc_getAssociatedObject(view, &kDKNoteHitsKey) : nil;
    for (DKNoteHit *hit in hits) {
        if (CGRectContainsPoint(hit.rect, location)) return hit.target;
    }
    return location;
}
%end

%hook DKNoteBottomBar
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *result = %orig;
    DKNoteInputHit *inputHit = objc_getAssociatedObject(self, &kDKNoteInputHitKey);
    if (result && inputHit.input && CGRectContainsPoint(inputHit.rect, point)) return inputHit.input;
    return result;
}
%end
%end

%ctor {
    gDKNoteRenderViews = [NSHashTable weakObjectsHashTable];
    DKSettingsRegister(DKKeyNoteDetailGlass, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeGlassChoice(DKKeyNoteDetailGlass, DKKeyNoteDetailGlassClear, @"图文详情页液态玻璃", ^{
            DKNoteRefresh();
        });
        return DKSettingsWithInfo(item,
            @"点开图文文案后的详情页：返回、头像、用户名、关注、搜索和底部输入框、互动按钮换成悬浮玻璃，顶栏和底栏透明，内容从栏下方滚过。关闭时保持抖音原生样式。");
    });

    gDKNoteTopBarClass = objc_getClass("AWEUGCKMPImpl.FullPageFeedKMPTopBarView");
    gDKNoteBottomBarClass = objc_getClass("AWEUGCKMPImpl.FullPageFeedKMPBottomBarView");
    gDKNoteInheritedClass = objc_getClass("DanceUI._InheritedView");
    gDKNoteDrawingClass = objc_getClass("DanceUI.CGDrawingView");
    gDKNoteShapeClass = objc_getClass("DanceUI._UIShapeHitTestingView");
    gDKNoteGraphicsClass = objc_getClass("DanceUI._UIGraphicsView");
    gDKNoteInputClass = objc_getClass("AWEKnowledgeRichContentImpl.FullPageFeedCommentInputView");
    gDKNoteScrollerClass = objc_getClass("AWETabListContainerScrollView");
    Class renderClass = objc_getClass("DanceUICompose.ComposeRenderingUIViewImpl");

    if (DKGlassOSAvailable() && renderClass && gDKNoteTopBarClass && gDKNoteBottomBarClass) {
        %init(DKNoteDetailGlassHooks, DKNoteRenderView=renderClass, DKNoteBottomBar=gDKNoteBottomBarClass);
    }
}
