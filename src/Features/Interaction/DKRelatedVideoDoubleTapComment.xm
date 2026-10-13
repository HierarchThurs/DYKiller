// 关联视频详情使用页面绑定的评论按钮操作，播放器与交互视图共用页面去重。
#import "DKDoubleTapComment.h"
#import "DouyinHeaders.h"
#import <objc/runtime.h>

static Class gDKRelatedPageClass;
static Class gDKRelatedInteractionClass;

static AWERelatedVideoDetailVideoViewController *DKTapRelatedPage(id source) {
    UIResponder *responder = [source isKindOfClass:UIResponder.class] ? source : nil;
    for (NSUInteger i = 0; responder && i < 32; i++, responder = responder.nextResponder) {
        if ([responder isKindOfClass:gDKRelatedPageClass]) return (id)responder;
        if (![responder isKindOfClass:UIViewController.class]) continue;
        for (UIViewController *node = (id)responder; node; node = node.parentViewController) {
            if ([node isKindOfClass:gDKRelatedPageClass]) return (id)node;
        }
    }
    // 播放器的原生 delegate 直接绑定详情页；仍需后续验证视图与模型归属。
    id delegate = DKDoubleTapCommentObject(source, @selector(delegate));
    return [delegate isKindOfClass:gDKRelatedPageClass] ? delegate : nil;
}

static BOOL DKTapRelatedTarget(UIView *view, AWERelatedVideoDetailVideoViewController *page, id model) {
    return [view isKindOfClass:gDKRelatedInteractionClass]
        && [view isDescendantOfView:page.viewIfLoaded]
        && DKTapRelatedPage(view) == page
        && DKDoubleTapCommentModelsMatch(DKDoubleTapCommentModel(view), model)
        && DKDoubleTapCommentObject(view, @selector(commentActionBlock));
}

static AWERelatedVideoDetailVideoInteractView *DKTapRelatedInteraction(
    AWERelatedVideoDetailVideoViewController *page, id model) {
    id slot = DKDoubleTapCommentObject(page, @selector(bottomInteractView));
    if (DKTapRelatedTarget(slot, page, model)) return slot;
    UIView *root = page.viewIfLoaded;
    if (!root) return nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    AWERelatedVideoDetailVideoInteractView *found = nil;
    // 仅扫描本页已加载的视图；多个同模型入口或超过预算时由原生双击继续处理。
    for (NSUInteger index = 0; index < queue.count && index < 512; index++) {
        UIView *view = queue[index];
        if (DKTapRelatedTarget(view, page, model)) {
            if (found && found != view) return nil;
            found = (id)view;
        }
        if (queue.count + view.subviews.count > 512) return nil;
        [queue addObjectsFromArray:view.subviews];
    }
    return found;
}

static BOOL DKTapRelatedComment(id source) {
    AWERelatedVideoDetailVideoViewController *page = DKTapRelatedPage(source);
    if (!page) { DKDoubleTapCommentMissing(); return NO; }
    id context = DKDoubleTapCommentObject(page, @selector(pageContext));
    if (DKDoubleTapCommentBool(source, @selector(disableDoubleTap))
        || DKDoubleTapCommentBool(context, @selector(isFailedMode))
        || DKDoubleTapCommentBool(context, @selector(isInLandscape))
        || DKDoubleTapCommentBool(context, @selector(isEnterPureModePage))) return NO;
    id model = DKDoubleTapCommentModel(page);
    if (!DKDoubleTapCommentModelsMatch(DKDoubleTapCommentModel(source), model)) {
        DKDoubleTapCommentStale();
        return YES;
    }
    if ([source isKindOfClass:UIViewController.class]) {
        id player = DKDoubleTapCommentObject(page, @selector(videoViewController));
        if (player != source || ![((UIViewController *)source).viewIfLoaded isDescendantOfView:page.viewIfLoaded]) {
            DKDoubleTapCommentStale();
            return YES;
        }
    }
    AWERelatedVideoDetailVideoInteractView *target = DKTapRelatedInteraction(page, model);
    if (!target) { DKDoubleTapCommentMissing(); return NO; }
    return DKDoubleTapCommentOpen(page, model, ^{ [target onCommentButtonClicked]; });
}

%group DKTapRelatedPlayerHooks
%hook AWERelatedVideoVideoPlayerViewController
- (void)handleDoubleTap:(id)gesture {
    DKDoubleTapCommentDispatch(DKDoubleTapCommentRelatedPlayer, self, ^{ %orig; }, ^BOOL{
        return DKTapRelatedComment(self);
    });
}
%end
%end

%group DKTapRelatedInteractionHooks
%hook AWERelatedVideoDetailVideoInteractView
- (void)handleVideoDoubleTapped {
    DKDoubleTapCommentDispatch(DKDoubleTapCommentRelatedInteraction, self, ^{ %orig; }, ^BOOL{
        return DKTapRelatedComment(self);
    });
}
%end
%end

%ctor {
    gDKRelatedPageClass = NSClassFromString(@"AWERelatedVideoDetailVideoViewController");
    gDKRelatedInteractionClass = NSClassFromString(@"AWERelatedVideoDetailVideoInteractView");
    if (![gDKRelatedPageClass isSubclassOfClass:UIViewController.class]
        || ![gDKRelatedInteractionClass isSubclassOfClass:UIView.class]
        || !DKDoubleTapCommentMethod(gDKRelatedPageClass, @selector(awemeModel), "@")
        || !DKDoubleTapCommentMethod(gDKRelatedInteractionClass, @selector(awemeModel), "@")
        || !DKDoubleTapCommentMethod(gDKRelatedInteractionClass, @selector(commentActionBlock), "@")
        || !DKDoubleTapCommentMethod(gDKRelatedInteractionClass, @selector(onCommentButtonClicked), "v")) return;
    Class player = NSClassFromString(@"AWERelatedVideoVideoPlayerViewController");
    if ([player isSubclassOfClass:UIViewController.class]
        && DKDoubleTapCommentMethod(player, @selector(handleDoubleTap:), "v@")) {
        %init(DKTapRelatedPlayerHooks);
        DKDoubleTapCommentInstalled(DKDoubleTapCommentRelatedPlayer);
    }
    if (DKDoubleTapCommentMethod(gDKRelatedInteractionClass, @selector(handleVideoDoubleTapped), "v")) {
        %init(DKTapRelatedInteractionHooks);
        DKDoubleTapCommentInstalled(DKDoubleTapCommentRelatedInteraction);
    }
}
