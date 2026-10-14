// 原生双击入口接入评论操作，按当前页面去重并记录诊断。
#import "DKDoubleTapComment.h"
#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdlib.h>
#import <string.h>

static BOOL gDKTapInstalled[DKDoubleTapCommentEntryCount];
static NSUInteger gDKTapHits[DKDoubleTapCommentEntryCount];
static NSUInteger gDKTapCalls, gDKTapDuplicates, gDKTapInactive, gDKTapStale;
static NSUInteger gDKTapMissing, gDKTapExceptions;
static NSString *gDKTapLastClass;
static char kDKTapPendingKey;

#pragma mark - 运行时契约

static char DKTapType(const char *type) {
    while (*type && strchr("rnNoORV", *type)) type++;
    return *type;
}

BOOL DKDoubleTapCommentMethod(Class cls, SEL selector, const char *types) {
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method || !types || !*types) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (signature.numberOfArguments != strlen(types) + 1
        || DKTapType(signature.methodReturnType) != types[0]) return NO;
    for (NSUInteger i = 1; types[i]; i++) {
        if (DKTapType([signature getArgumentTypeAtIndex:i + 1]) != types[i]) return NO;
    }
    return YES;
}

BOOL DKDoubleTapCommentOwnMethod(Class cls, SEL selector) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == selector) { found = YES; break; }
    }
    free(methods);
    return found;
}

id DKDoubleTapCommentObject(id object, SEL selector) {
    if (!object || !DKDoubleTapCommentMethod(object_getClass(object), selector, "@")) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

BOOL DKDoubleTapCommentBool(id object, SEL selector) {
    Class cls = object ? object_getClass(object) : Nil;
    if (!DKDoubleTapCommentMethod(cls, selector, "B")
        && !DKDoubleTapCommentMethod(cls, selector, "c")) return NO;
    @try {
        return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

id DKDoubleTapCommentModel(id object) {
    Class cls = NSClassFromString(@"AWEAwemeModel");
    for (NSString *name in @[@"model", @"awemeModel", @"currentModel"]) {
        id model = DKDoubleTapCommentObject(object, NSSelectorFromString(name));
        if (cls && [model isKindOfClass:cls]) return model;
    }
    return nil;
}

static NSString *DKTapItemID(id model) {
    id value = DKDoubleTapCommentObject(model, @selector(itemID));
    return [value isKindOfClass:NSString.class] ? value : nil;
}

BOOL DKDoubleTapCommentModelsMatch(id first, id second) {
    if (!first || !second) return NO;
    if (first == second) return YES;
    NSString *itemID = DKTapItemID(first);
    return itemID.length && [itemID isEqualToString:DKTapItemID(second)];
}

void DKDoubleTapCommentInstalled(DKDoubleTapCommentEntry entry) {
    gDKTapInstalled[entry] = YES;
}

void DKDoubleTapCommentMissing(void) {
    gDKTapMissing++;
}

void DKDoubleTapCommentStale(void) {
    gDKTapStale++;
}

void DKDoubleTapCommentDuplicate(void) {
    gDKTapDuplicates++;
}

#pragma mark - 页面与评论状态

static BOOL DKTapPageVisible(UIViewController *owner) {
    UIView *view = owner.viewIfLoaded;
    UIWindow *window = view.window;
    if (!window || window.windowLevel != UIWindowLevelNormal) return NO;
    if (window.windowScene && window.windowScene.activationState != UISceneActivationStateForegroundActive) return NO;
    CGRect rect = [view convertRect:view.bounds toView:window];
    if (CGRectIsEmpty(CGRectIntersection(rect, window.bounds))) return NO;
    for (UIView *node = view; node; node = node.superview) {
        if (node.hidden || node.alpha <= 0.01) return NO;
    }
    for (UIViewController *node = owner; node; node = node.parentViewController) {
        if (node.isBeingDismissed || node.isMovingFromParentViewController) return NO;
        if (node.presentedViewController || node.transitionCoordinator) return NO;
        UIViewController *parent = node.parentViewController;
        if ([parent isKindOfClass:UINavigationController.class]
            && ((UINavigationController *)parent).visibleViewController != node) return NO;
        if ([parent isKindOfClass:UITabBarController.class]
            && ((UITabBarController *)parent).selectedViewController != node) return NO;
    }
    return YES;
}

static BOOL DKTapCommentActive(UIViewController *owner) {
    if (DKDoubleTapCommentBool(owner, @selector(isCommentVCShowing))
        || DKDoubleTapCommentBool(owner, @selector(isCommentListShowing))) return YES;
    id context = DKDoubleTapCommentObject(owner, @selector(pageContext));
    if (DKDoubleTapCommentBool(context, @selector(commentPanelIsShowing))
        || DKDoubleTapCommentBool(context, @selector(isClickingBottomComment))) return YES;
    id comment = DKDoubleTapCommentObject(owner, @selector(commentVC));
    if (![comment isKindOfClass:UIViewController.class]) return NO;
    UIView *view = ((UIViewController *)comment).viewIfLoaded;
    return view.window && !view.hidden && view.alpha > 0.01;
}

BOOL DKDoubleTapCommentOpen(UIViewController *owner, id model, dispatch_block_t action) {
    if (!NSThread.isMainThread || !DKPrefBool(DKKeyDoubleTapOpenComment)) return NO;
    if (!owner || !model || !action) { DKDoubleTapCommentMissing(); return NO; }
    if (DKTapCommentActive(owner) || objc_getAssociatedObject(owner, &kDKTapPendingKey)) {
        gDKTapDuplicates++;
        return YES;
    }
    if (!DKTapPageVisible(owner)) { gDKTapInactive++; return YES; }

    NSObject *token = [NSObject new];
    objc_setAssociatedObject(owner, &kDKTapPendingKey, token, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // 标记跨过当前主队列回合，覆盖两个原生入口对同一次手势的转发。
    __weak UIViewController *weakOwner = owner;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *current = weakOwner;
        if (current && objc_getAssociatedObject(current, &kDKTapPendingKey) == token) {
            objc_setAssociatedObject(current, &kDKTapPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    });
    @try {
        gDKTapCalls++;
        action();
    } @catch (__unused NSException *exception) {
        gDKTapExceptions++;
    }
    return YES;
}

void DKDoubleTapCommentDispatch(DKDoubleTapCommentEntry entry, id source,
                               dispatch_block_t original, BOOL (^handler)(void)) {
    if (!DKPrefBool(DKKeyDoubleTapOpenComment)) { original(); return; }
    if (!NSThread.isMainThread) {
        // 队列等待后复查模型对象与 itemID，丢弃复用的回调。
        id model = DKDoubleTapCommentModel(source);
        NSString *itemID = [DKTapItemID(model) copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!DKPrefBool(DKKeyDoubleTapOpenComment)) { original(); return; }
            id current = DKDoubleTapCommentModel(source);
            if (!DKDoubleTapCommentModelsMatch(model, current)
                || (itemID.length && ![itemID isEqualToString:DKTapItemID(current)])) {
                gDKTapStale++;
                return;
            }
            DKDoubleTapCommentDispatch(entry, source, original, handler);
        });
        return;
    }
    gDKTapHits[entry]++;
    gDKTapLastClass = NSStringFromClass([source class]);
    if (!handler()) original();
}

NSString *DKDoubleTapCommentDiagnostics(void) {
    if (!NSThread.isMainThread) return @"诊断需在主线程读取\n";
    NSArray *names = @[@"默认播放器双击", @"默认交互双击", @"Story 双击", @"关联播放器双击", @"关联交互双击", @"听抖音双击"];
    NSMutableString *out = [NSMutableString stringWithFormat:@"开关=%@\n", DKPrefBool(DKKeyDoubleTapOpenComment) ? @"开启" : @"关闭"];
    for (NSUInteger i = 0; i < DKDoubleTapCommentEntryCount; i++) {
        [out appendFormat:@"%@：Hook=%@ 命中=%lu\n", names[i],
         gDKTapInstalled[i] ? @"已安装" : @"类或签名不兼容", (unsigned long)gDKTapHits[i]];
    }
    [out appendFormat:@"原生评论调用=%lu 去重=%lu 离屏或转场=%lu 过期模型=%lu 入口缺失=%lu 原生异常=%lu\n最近入口类=%@\n",
     (unsigned long)gDKTapCalls, (unsigned long)gDKTapDuplicates, (unsigned long)gDKTapInactive,
     (unsigned long)gDKTapStale, (unsigned long)gDKTapMissing, (unsigned long)gDKTapExceptions,
     gDKTapLastClass ?: @"(无)"];
    return out;
}

#pragma mark - 默认交互层

static BOOL DKTapFeedComment(AWEPlayInteractionViewController *controller, id player) {
    id model = DKDoubleTapCommentModel(controller);
    id playerModel = DKDoubleTapCommentModel(player);
    if (playerModel && !DKDoubleTapCommentModelsMatch(model, playerModel)) {
        DKDoubleTapCommentStale();
        return YES;
    }
    id video = DKDoubleTapCommentObject(controller, @selector(videoDelegate));
    if (DKDoubleTapCommentBool(controller, @selector(pureMode))
        || DKDoubleTapCommentBool(player, @selector(hasInlandscape))
        || DKDoubleTapCommentBool(video, @selector(hasInlandscape))) return NO;
    id panel = DKDoubleTapCommentObject(controller, @selector(panelDelegate));
    if (!DKDoubleTapCommentMethod(object_getClass(panel), @selector(performCommentAction), "v")) {
        DKDoubleTapCommentMissing();
        return NO;
    }
    return DKDoubleTapCommentOpen(controller, model, ^{
        [controller performCommentAction];
    });
}

%group DKTapFeedPlayerHooks
%hook AWEPlayInteractionViewController
- (void)onPlayer:(id)player didDoubleClick:(id)event {
    DKDoubleTapCommentDispatch(DKDoubleTapCommentFeedPlayer, self, ^{ %orig; }, ^BOOL{
        return DKTapFeedComment(self, player);
    });
}
%end
%end

%group DKTapFeedInteractionHooks
%hook AWEPlayInteractionViewController
- (void)onVideoPlayerViewDoubleClicked:(id)event {
    DKDoubleTapCommentDispatch(DKDoubleTapCommentFeedInteraction, self, ^{ %orig; }, ^BOOL{
        return DKTapFeedComment(self, nil);
    });
}
%end
%end

%group DKTapStoryHooks
%hook AFDStoryPlayInteractionViewController
- (void)onPlayer:(id)player didDoubleClick:(id)event {
    DKDoubleTapCommentDispatch(DKDoubleTapCommentStory, self, ^{ %orig; }, ^BOOL{
        return DKTapFeedComment(self, player);
    });
}
%end
%end

%ctor {
    DKSettingsRegisterItem(@"播放体验", ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyDoubleTapOpenComment, @"双击打开评论区", @"双击作品打开评论区，替代原双击操作");
    });
    Class feed = NSClassFromString(@"AWEPlayInteractionViewController");
    if (![feed isSubclassOfClass:UIViewController.class]
        || !DKDoubleTapCommentMethod(feed, @selector(performCommentAction), "v")) return;
    if (DKDoubleTapCommentMethod(feed, @selector(onPlayer:didDoubleClick:), "v@@")) {
        %init(DKTapFeedPlayerHooks);
        DKDoubleTapCommentInstalled(DKDoubleTapCommentFeedPlayer);
    }
    if (DKDoubleTapCommentMethod(feed, @selector(onVideoPlayerViewDoubleClicked:), "v@")) {
        %init(DKTapFeedInteractionHooks);
        DKDoubleTapCommentInstalled(DKDoubleTapCommentFeedInteraction);
    }
    Class story = NSClassFromString(@"AFDStoryPlayInteractionViewController");
    if ([story isSubclassOfClass:feed]
        && DKDoubleTapCommentOwnMethod(story, @selector(onPlayer:didDoubleClick:))
        && DKDoubleTapCommentMethod(story, @selector(onPlayer:didDoubleClick:), "v@@")) {
        %init(DKTapStoryHooks);
        DKDoubleTapCommentInstalled(DKDoubleTapCommentStory);
    }
}
