//
//  DKProfileCleanNameArea.xm
//  DYKiller
//
//  个人主页精简 —— 头像右下角加号、昵称后的切换账号箭头、抖音号下方的胶囊行。
//
//  实现：
//   - 头像加号是头像扩展 avatar_story_publish（AWEProfileAvatarStoryPublishController）。点击由头像分区按位置分派给
//     可显示的扩展。移除：canShow 返回 NO，加号不显示、不参与点击分派，点该处等同点头像。
//     隐藏：加号按钮挂全透明 mask，点击照常；两档都让 p_shouldAddHollowMasks 返回 NO，头像上不留加号的镂空。
//   - 切换账号箭头连同两个多账号未读点：隐藏与移除都挂全透明 mask；移除时昵称行 hitTest 落在其上返回 nil。
//   - 胶囊行是昵称区组件树里的 AWEProfileHeaderGenericOperationComponent。移除：buildVirtualView: 返回 nil
//     （抖音无胶囊时也是这样返回），昵称区按原生排布收拢。隐藏：mount 之后给组件容器的 renderedView 挂全透明 mask。
//   - 设置改动：头像分区 reloadAvatarExtension，已见昵称行与胶囊重挂 mask，胶囊组件 setNeedsUpdate 重新构建。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKProfileClean.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"
#import <objc/runtime.h>

// 弱表（头像分区、加号扩展、昵称行、胶囊组件、已挂 mask 的胶囊视图），只在主线程读写。
static NSHashTable *gDKProfileAvatarSections;
static NSHashTable *gDKProfilePublishControllers;
static NSHashTable *gDKProfileNameContainers;
static NSHashTable *gDKProfileCapsuleComponents;
static NSHashTable<UIView *> *gDKProfileCapsuleFadedViews;

static void DKProfileNameTrack(NSHashTable * __strong *table, id object) {
    if (!object) return;
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKProfileNameTrack(table, object); });
        return;
    }
    if (!*table) *table = [NSHashTable weakObjectsHashTable];
    [*table addObject:object];
}

static BOOL DKProfileNameMine(id context) {
    return [context respondsToSelector:@selector(isCurrentUser)] && [context isCurrentUser];
}

#pragma mark - 头像加号

static BOOL DKProfilePlusMine(AWEProfileAvatarStoryPublishController *controller) {
    return [controller respondsToSelector:@selector(profileContext)] && DKProfileNameMine([controller profileContext]);
}

static UIView *DKProfilePlusButton(AWEProfileAvatarStoryPublishController *controller) {
    UIView *button = [controller respondsToSelector:@selector(story25PublishButton)] ? [controller story25PublishButton] : nil;
    return [button isKindOfClass:UIView.class] ? button : nil;
}

static void DKProfilePlusApply(AWEProfileAvatarStoryPublishController *controller) {
    UIView *button = DKProfilePlusButton(controller);
    if (!button) return;
    BOOL faded = DKPrefDisplayMode(DKKeyProfileAvatarPlusMode) != DKDisplayModeShow && DKProfilePlusMine(controller);
    DKAdjustFade(button, faded ? 0.0 : 1.0, button.bounds.size);
}

#pragma mark - 切换账号箭头

static BOOL DKProfileArrowMine(AWEProfileHeaderNameLabelContainerView *container) {
    return [container respondsToSelector:@selector(context)] && DKProfileNameMine([container context]);
}

static NSArray<UIView *> *DKProfileArrowViews(AWEProfileHeaderNameLabelContainerView *container) {
    NSMutableArray<UIView *> *views = [NSMutableArray arrayWithCapacity:3];
    for (NSString *name in @[ @"switchAccountButton", @"noticeUnreadDotView", @"multiAccountNoticeUnreadDotView" ]) {
        SEL getter = NSSelectorFromString(name);
        id view = [container respondsToSelector:getter] ? [container valueForKey:name] : nil;
        if ([view isKindOfClass:UIView.class]) [views addObject:view];
    }
    return views;
}

static void DKProfileArrowApply(AWEProfileHeaderNameLabelContainerView *container) {
    BOOL faded = DKPrefDisplayMode(DKKeyProfileSwitchAccountMode) != DKDisplayModeShow && DKProfileArrowMine(container);
    for (UIView *view in DKProfileArrowViews(container)) DKAdjustFade(view, faded ? 0.0 : 1.0, view.bounds.size);
}

static BOOL DKProfileArrowHitRemoved(AWEProfileHeaderNameLabelContainerView *container, UIView *hit) {
    if (DKPrefDisplayMode(DKKeyProfileSwitchAccountMode) != DKDisplayModeRemove || !DKProfileArrowMine(container)) return NO;
    for (UIView *view in DKProfileArrowViews(container)) {
        if ([hit isDescendantOfView:view]) return YES;
    }
    return NO;
}

#pragma mark - 胶囊行

static BOOL DKProfileCapsuleMine(AWEProfileHeaderGenericOperationComponent *component) {
    return [component respondsToSelector:@selector(context)] && DKProfileNameMine([component context]);
}

static UIView *DKProfileCapsuleView(AWEProfileHeaderGenericOperationComponent *component) {
    AWERLVirtualView *node = [component respondsToSelector:@selector(containerNode)] ? [component containerNode] : nil;
    UIView *view = [node respondsToSelector:@selector(renderedView)] ? [node renderedView] : nil;
    return [view isKindOfClass:UIView.class] ? view : nil;
}

// 只给当前挂载着的胶囊容器挂 mask；不再是挂载视图的（可能已被组件复用到别处）摘掉 mask。
static void DKProfileCapsuleApplyAll(void) {
    NSHashTable<UIView *> *targets = [NSHashTable weakObjectsHashTable];
    if (DKPrefDisplayMode(DKKeyProfileCapsuleMode) == DKDisplayModeHide) {
        for (AWEProfileHeaderGenericOperationComponent *component in gDKProfileCapsuleComponents.allObjects) {
            UIView *view = DKProfileCapsuleMine(component) ? DKProfileCapsuleView(component) : nil;
            if (view) [targets addObject:view];
        }
    }
    for (UIView *view in gDKProfileCapsuleFadedViews.allObjects) {
        if (![targets containsObject:view]) DKAdjustFade(view, 1.0, view.bounds.size);
    }
    for (UIView *view in targets.allObjects) DKAdjustFade(view, 0.0, view.bounds.size);
    gDKProfileCapsuleFadedViews = targets;
}

#pragma mark - 刷新与诊断

void DKProfileCleanNameAreaRefresh(void) {
    for (AWEProfileAvatarSectionControllerV2 *section in gDKProfileAvatarSections.allObjects) {
        if ([section respondsToSelector:@selector(reloadAvatarExtension)]) [section reloadAvatarExtension];
    }
    for (AWEProfileAvatarStoryPublishController *controller in gDKProfilePublishControllers.allObjects) {
        DKProfilePlusApply(controller);
    }
    for (AWEProfileHeaderNameLabelContainerView *container in gDKProfileNameContainers.allObjects) {
        DKProfileArrowApply(container);
    }
    for (AWEProfileHeaderGenericOperationComponent *component in gDKProfileCapsuleComponents.allObjects) {
        if ([component respondsToSelector:@selector(setNeedsUpdate)]) [component setNeedsUpdate];
    }
    DKProfileCapsuleApplyAll();
}

static NSString *DKProfileNameFrame(UIView *view) {
    return view ? NSStringFromCGRect([view convertRect:view.bounds toView:nil]) : @"-";
}

NSString *DKProfileCleanNameAreaStatus(void) {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"已见头像分区=%lu\n", (unsigned long)gDKProfileAvatarSections.allObjects.count];
    for (AWEProfileAvatarStoryPublishController *controller in gDKProfilePublishControllers.allObjects) {
        UIView *button = DKProfilePlusButton(controller);
        [out appendFormat:@"  头像加号 自己=%d canShow=%d 镂空=%d 按钮在窗口=%d frame=%@ 淡出=%.2f\n", DKProfilePlusMine(controller),
            [controller respondsToSelector:@selector(canShow)] && [controller canShow],
            [controller respondsToSelector:@selector(p_shouldAddHollowMasks)] && [controller p_shouldAddHollowMasks],
            button.window != nil, DKProfileNameFrame(button), DKAdjustFadeFactor(button)];
    }
    for (AWEProfileHeaderNameLabelContainerView *container in gDKProfileNameContainers.allObjects) {
        for (UIView *view in DKProfileArrowViews(container)) {
            [out appendFormat:@"  昵称行 自己=%d %@ hidden=%d 在窗口=%d frame=%@ 淡出=%.2f\n", DKProfileArrowMine(container),
                NSStringFromClass(view.class), view.isHidden, view.window != nil, DKProfileNameFrame(view), DKAdjustFadeFactor(view)];
        }
    }
    for (AWEProfileHeaderGenericOperationComponent *component in gDKProfileCapsuleComponents.allObjects) {
        UIView *view = DKProfileCapsuleView(component);
        [out appendFormat:@"  胶囊行 自己=%d 挂载视图=%@ 在窗口=%d frame=%@ 淡出=%.2f\n", DKProfileCapsuleMine(component),
            view ? NSStringFromClass(view.class) : @"无", view.window != nil, DKProfileNameFrame(view), DKAdjustFadeFactor(view)];
    }
    return out;
}

#pragma mark - Hook

%hook AWEProfileAvatarStoryPublishController

- (BOOL)canShow {
    BOOL canShow = %orig;
    if (!canShow || DKPrefDisplayMode(DKKeyProfileAvatarPlusMode) != DKDisplayModeRemove) return canShow;
    return !DKProfilePlusMine(self);
}

- (BOOL)p_shouldAddHollowMasks {
    BOOL should = %orig;
    if (!should || DKPrefDisplayMode(DKKeyProfileAvatarPlusMode) == DKDisplayModeShow) return should;
    return !DKProfilePlusMine(self);
}

- (void)updateUIWithContainerView:(UIView *)containerView anchorView:(UIView *)anchorView {
    %orig;
    DKProfileNameTrack(&gDKProfilePublishControllers, self);
    DKProfilePlusApply(self);
}

%end

%hook AWEProfileAvatarSectionControllerV2

- (void)configCell:(id)cell index:(NSInteger)index model:(id)model {
    %orig;
    if ([self respondsToSelector:@selector(profileContext)] && DKProfileNameMine([self profileContext])) {
        DKProfileNameTrack(&gDKProfileAvatarSections, self);
    }
}

%end

%hook AWEProfileHeaderNameLabelContainerView

- (void)layoutSubviews {
    %orig;
    DKProfileNameTrack(&gDKProfileNameContainers, self);
    DKProfileArrowApply(self);
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = %orig;
    return (hit && DKProfileArrowHitRemoved(self, hit)) ? nil : hit;
}

%end

%hook AWEProfileHeaderGenericOperationComponent

- (id)buildVirtualView:(id)data {
    BOOL mine = DKProfileCapsuleMine(self);
    if (mine) DKProfileNameTrack(&gDKProfileCapsuleComponents, self);
    DKDisplayMode mode = mine ? DKPrefDisplayMode(DKKeyProfileCapsuleMode) : DKDisplayModeShow;
    if (mode == DKDisplayModeRemove) return nil;
    id node = %orig;
    // 本次构建后紧接着 mount，下一轮主队列时 renderedView 已就位。
    if (mode == DKDisplayModeHide || gDKProfileCapsuleFadedViews.count) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKProfileCapsuleApplyAll(); });
    }
    return node;
}

%end

%hook AWEProfileHeaderNameAreaSectionCell_New

- (void)layoutSubviews {
    %orig;
    if (gDKProfileCapsuleComponents.count) DKProfileCapsuleApplyAll();
}

%end
