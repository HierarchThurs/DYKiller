//
//  DKNoteDetailGlass.xm
//  DYKiller
//
//  图文详情页 Compose 顶栏与底栏的液态玻璃。
//   - 两条栏是 Compose + DanceUI 渲染，元素是渲染视图的直接子视图，按类型与顺序识别。
//   - 玻璃垫在 Compose 视图下方，元素只用 transform 移位，栏底色清除后内容从栏下滚过。
//   - Compose 按原生布局坐标判定点击，整块玻璃的触摸在读坐标时换算到对应元素的中心。
//

#import "DKChatGlassStore.h"
#import "DKComposeTouchRemap.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKNoteDetailGlassShared.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"

#import <objc/runtime.h>
#include <vector>

@interface DKNoteBottomBar : UIView @end

static const CGFloat kDKNoteBottomHeight = 46.0;
static const CGFloat kDKNoteCapsuleEndPadding = 4.0;

static Class gDKNoteTopBarClass;
static Class gDKNoteBottomBarClass;
static Class gDKNoteInheritedClass;
static Class gDKNoteDrawingClass;
static Class gDKNoteShapeClass;
static Class gDKNoteGraphicsClass;
static Class gDKNoteInputClass;
static NSHashTable<UIView *> *gDKNoteRenderViews;

static UIView *DKNoteBarForRenderView(UIView *renderView) {
    for (UIView *node = renderView.superview; node; node = node.superview) {
        if ([node isKindOfClass:gDKNoteTopBarClass] || [node isKindOfClass:gDKNoteBottomBarClass]) return node;
    }
    return nil;
}

static CGPoint DKNoteCenter(CGRect rect) {
    return CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
}

API_AVAILABLE(ios(26.0))
static UIVisualEffectView *DKNotePlaceGlass(DKChatGlassStore *store, UIView *source, UIView *bar, CGRect rect, CGPoint origin) {
    return [store placeGlassFor:source in:bar frame:CGRectOffset(rect, origin.x, origin.y)
                          shape:DKChatGlassShapeRounded radius:CGRectGetHeight(rect) * 0.5 interactive:NO tint:nil];
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
    CGRect backFrame = DKAdjustLayoutFrame(back);
    CGFloat top = CGRectGetMidY(backFrame) - kDKNoteTopHeight * 0.5;
    NSMutableArray<DKComposeTouchRegion *> *hits = [NSMutableArray array];

    // 返回键的箭头在原生 24pt 框内偏左，框不移动时箭头正好落在玻璃中心。
    CGRect backGlass = CGRectMake(kDKNoteEdge, top, kDKNoteTopHeight, kDKNoteTopHeight);
    DKNotePlaceGlass(store, back, bar, backGlass, origin);
    [hits addObject:[DKComposeTouchRegion regionWithRect:backGlass target:DKNoteCenter(backFrame)
                                          sourceView:renderView touchView:touchView]];
    CGFloat cursor = CGRectGetMaxX(backGlass) + kDKNoteClusterGap;

    if (avatar) {
        CGRect frame = DKAdjustLayoutFrame(avatar);
        CGRect glass = CGRectMake(cursor, top, kDKNoteTopHeight, kDKNoteTopHeight);
        DKAdjustTransform(avatar, CGAffineTransformMakeTranslation(CGRectGetMidX(glass) - CGRectGetMidX(frame), 0.0));
        DKNotePlaceGlass(store, avatar, bar, glass, origin);
        [hits addObject:[DKComposeTouchRegion regionWithRect:glass target:DKNoteCenter(frame)
                                          sourceView:renderView touchView:touchView]];
        cursor = CGRectGetMaxX(glass) + kDKNoteClusterGap;
    }

    CGRect searchFrame = DKAdjustLayoutFrame(search);
    CGRect searchGlass = CGRectMake(width - kDKNoteEdge - kDKNoteTopHeight, top, kDKNoteTopHeight, kDKNoteTopHeight);
    DKAdjustTransform(search, CGAffineTransformMakeTranslation(CGRectGetMidX(searchGlass) - CGRectGetMidX(searchFrame), 0.0));
    DKNotePlaceGlass(store, search, bar, searchGlass, origin);
    [hits addObject:[DKComposeTouchRegion regionWithRect:searchGlass target:DKNoteCenter(searchFrame)
                                          sourceView:renderView touchView:touchView]];
    CGFloat limit = CGRectGetMinX(searchGlass) - kDKNoteEdge;

    if (followShape) {
        CGRect frame = DKAdjustLayoutFrame(followShape);
        DKAdjustFade(followShape, 0.0, CGSizeZero);
        CGRect glass = CGRectMake(CGRectGetMinX(frame), top, CGRectGetWidth(frame), kDKNoteTopHeight);
        DKNotePlaceGlass(store, followShape, bar, glass, origin);
        [hits addObject:[DKComposeTouchRegion regionWithRect:glass target:DKNoteCenter(frame)
                                          sourceView:renderView touchView:touchView]];
        limit = CGRectGetMinX(glass) - kDKNoteEdge;
    }

    if (name && CGRectGetWidth(name.bounds) > 0.0 && (!followShape || texts.count > 1)) {
        CGRect frame = DKAdjustLayoutFrame(name);
        CGFloat capsuleWidth = CGRectGetWidth(frame) + kDKNoteNamePadding * 2.0;
        CGRect glass = CGRectMake(cursor, top, MIN(capsuleWidth, limit - cursor), kDKNoteTopHeight);
        DKAdjustTransform(name, CGAffineTransformMakeTranslation(cursor + kDKNoteNamePadding - CGRectGetMinX(frame), 0.0));
        UIVisualEffectView *glassView = DKNotePlaceGlass(store, name, bar, glass, origin);
        // 长用户名超出胶囊的部分裁掉。
        if (capsuleWidth > limit - cursor) [store maskView:name toGlass:glassView];
        [hits addObject:[DKComposeTouchRegion regionWithRect:glass target:DKNoteCenter(frame)
                                          sourceView:renderView touchView:touchView]];
    }

    DKComposeSetTouchRegions(touchView, hits);
    DKNoteSetContentOverflow(bar, YES);
}

struct DKNoteBottomButton {
    CGPoint nativeCenter;
    CGRect contentFrame;
    CGFloat centerX;
};

static CGFloat DKNoteCapsuleEndInset(CGRect capsule, CGRect contentFrame) {
    CGFloat radius = CGRectGetHeight(capsule) * 0.5;
    CGFloat midY = CGRectGetMidY(capsule);
    CGFloat dy = MIN(radius, MAX(fabs(CGRectGetMinY(contentFrame) - midY),
                                 fabs(CGRectGetMaxY(contentFrame) - midY)));
    return radius - sqrt(radius * radius - dy * dy) + kDKNoteCapsuleEndPadding;
}

static void DKNoteSpaceBottomButtons(std::vector<DKNoteBottomButton> &buttons, CGRect capsule) {
    if (buttons.size() < 2) return;
    const auto &first = buttons.front();
    const auto &last = buttons.back();
    CGFloat start = CGRectGetMinX(capsule) + DKNoteCapsuleEndInset(capsule, first.contentFrame)
                    + (first.nativeCenter.x - CGRectGetMinX(first.contentFrame));
    CGFloat end = CGRectGetMaxX(capsule) - DKNoteCapsuleEndInset(capsule, last.contentFrame)
                  - (CGRectGetMaxX(last.contentFrame) - last.nativeCenter.x);
    CGFloat step = (end - start) / (buttons.size() - 1);

    // 相邻外接框重叠时沿用原生间距。
    for (NSUInteger index = 1; index < buttons.size(); index++) {
        const auto &left = buttons[index - 1];
        const auto &right = buttons[index];
        CGFloat occupied = (CGRectGetMaxX(left.contentFrame) - left.nativeCenter.x)
                           + (right.nativeCenter.x - CGRectGetMinX(right.contentFrame));
        if (step < occupied) return;
    }
    for (NSUInteger index = 0; index < buttons.size(); index++) {
        buttons[index].centerX = start + step * index;
    }
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
    DKNoteSetGlassHits(bar, nil);
    if (!inputHost || icons.count == 0) return;

    UIView *input = inputHost.subviews.firstObject;
    [store clearBackingOfView:input];

    CGPoint origin = [renderView convertPoint:CGPointZero toView:bar];
    CGFloat width = CGRectGetWidth(renderView.bounds);
    CGRect inputFrame = DKAdjustLayoutFrame(inputHost);
    CGFloat top = CGRectGetMidY(inputFrame) - kDKNoteBottomHeight * 0.5;

    CGRect inputGlass = CGRectMake(kDKNoteEdge, top, CGRectGetMaxX(inputFrame) - kDKNoteEdge, kDKNoteBottomHeight);
    UIVisualEffectView *inputGlassView = DKNotePlaceGlass(store, input, bar, inputGlass, origin);
    if (inputGlassView) DKNoteSetGlassHits(bar, @[[DKNoteGlassHit hitWithRect:inputGlassView.frame target:input]]);

    CGRect capsule = CGRectMake(CGRectGetMaxX(inputGlass) + kDKNoteEdge, top,
                                width - kDKNoteEdge - CGRectGetMaxX(inputGlass) - kDKNoteEdge, kDKNoteBottomHeight);
    CGRect firstIcon = DKAdjustLayoutFrame(icons.firstObject);
    CGRect lastIcon = DKAdjustLayoutFrame(icons.lastObject);
    CGFloat shift = CGRectGetMidX(capsule) - (CGRectGetMinX(firstIcon) + CGRectGetMaxX(lastIcon)) * 0.5;
    std::vector<DKNoteBottomButton> buttons;
    buttons.reserve(icons.count);
    for (UIView *icon in icons) {
        CGRect frame = DKAdjustLayoutFrame(icon);
        CGPoint center = DKNoteCenter(frame);
        buttons.push_back({center, frame, center.x + shift});
    }

    // 将数字归入水平中心最近的图标，合并两者的布局框。
    std::vector<NSUInteger> countOwners;
    countOwners.reserve(counts.count);
    for (UIView *count in counts) {
        CGRect frame = DKAdjustLayoutFrame(count);
        CGFloat centerX = CGRectGetMidX(frame);
        NSUInteger owner = 0;
        for (NSUInteger index = 1; index < buttons.size(); index++) {
            if (fabs(centerX - buttons[index].nativeCenter.x) < fabs(centerX - buttons[owner].nativeCenter.x)) {
                owner = index;
            }
        }
        buttons[owner].contentFrame = CGRectUnion(buttons[owner].contentFrame, frame);
        countOwners.push_back(owner);
    }
    DKNoteSpaceBottomButtons(buttons, capsule);
    for (NSUInteger index = 0; index < counts.count; index++) {
        const auto &button = buttons[countOwners[index]];
        DKAdjustTransform(counts[index], CGAffineTransformMakeTranslation(button.centerX - button.nativeCenter.x, 0.0));
    }
    DKNotePlaceGlass(store, icons.firstObject, bar, capsule, origin);

    // 按相邻新中心的中点划分胶囊，每段映射到图标的原生中心。
    NSMutableArray<DKComposeTouchRegion *> *hits = [NSMutableArray arrayWithCapacity:icons.count];
    CGFloat left = CGRectGetMinX(capsule);
    for (NSUInteger index = 0; index < icons.count; index++) {
        const auto &button = buttons[index];
        DKAdjustTransform(icons[index], CGAffineTransformMakeTranslation(button.centerX - button.nativeCenter.x, 0.0));
        CGFloat right = CGRectGetMaxX(capsule);
        if (index + 1 < icons.count) {
            right = (button.centerX + buttons[index + 1].centerX) * 0.5;
        }
        CGRect segment = CGRectMake(left, top, right - left, kDKNoteBottomHeight);
        [hits addObject:[DKComposeTouchRegion regionWithRect:segment target:button.nativeCenter
                                          sourceView:renderView touchView:touchView]];
        left = right;
    }
    DKComposeSetTouchRegions(touchView, hits);
}

API_AVAILABLE(ios(26.0))
static void DKNoteRestore(UIView *bar, UIView *renderView, UIView *touchView) {
    [DKChatGlassStore removeStoreForOwner:bar];
    for (UIView *child in renderView.subviews) {
        DKAdjustTransform(child, CGAffineTransformIdentity);
        DKAdjustFade(child, 1.0, CGSizeZero);
    }
    DKComposeSetTouchRegions(touchView, nil);
    DKNoteSetGlassHits(bar, nil);
    if ([bar isKindOfClass:gDKNoteTopBarClass]) DKNoteSetContentOverflow(bar, NO);
}

static void DKNoteSync(UIView *renderView) {
    if (!NSThread.isMainThread) return;
    if (@available(iOS 26.0, *)) {
        UIView *bar = DKNoteBarForRenderView(renderView);
        if (!bar) return;
        [gDKNoteRenderViews addObject:renderView];
        UIView *touchView = DKComposeTouchView(renderView);
        if (!touchView) return;

        if (!DKNoteGlassEnabled()) {
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
    DKNoteRefreshNativeTopBars();
}

%group DKNoteBottomBarHitHooks
%hook DKNoteBottomBar
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *result = %orig;
    return result && NSThread.isMainThread ? DKNoteGlassTargetAtPoint(self, point) ?: result : result;
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

    if (DKGlassOSAvailable() && (gDKNoteTopBarClass || gDKNoteBottomBarClass)) {
        DKComposeObserveRenderLayout(^(UIView *renderView) { DKNoteSync(renderView); });
        if (gDKNoteBottomBarClass) %init(DKNoteBottomBarHitHooks, DKNoteBottomBar=gDKNoteBottomBarClass);
    }
}
