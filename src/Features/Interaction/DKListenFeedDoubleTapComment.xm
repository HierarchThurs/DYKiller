// 听抖音页双击使用播放控制栏的评论按钮操作，按本页当前作品校验并去重。
#import "DKDoubleTapComment.h"
#import "DouyinHeaders.h"
#import <objc/runtime.h>

static Class gDKListenControlClass;

static BOOL DKTapListenComment(AWEListenFeedOptimizedInteractionViewController *controller) {
    id model = DKDoubleTapCommentModel(controller);
    AWEListenFeedPlayControlView *control = DKDoubleTapCommentObject(controller, @selector(controlView));
    id receiver = DKDoubleTapCommentObject(control, @selector(delegate));
    if (!model || ![control isKindOfClass:gDKListenControlClass]
        || ![control isDescendantOfView:controller.viewIfLoaded]
        || !DKDoubleTapCommentMethod(object_getClass(receiver),
                                     @selector(playControlView:didClickCommentButton:), "v@@")) {
        DKDoubleTapCommentMissing();
        return NO;
    }
    // 原生评论面板读取接收方的 currentModel，三处作品一致才打开。
    if (!DKDoubleTapCommentModelsMatch(DKDoubleTapCommentModel(control), model)
        || !DKDoubleTapCommentModelsMatch(DKDoubleTapCommentObject(receiver, @selector(currentModel)), model)) {
        DKDoubleTapCommentStale();
        return YES;
    }
    if (DKDoubleTapCommentBool(receiver, @selector(pannelIsShowing))) {
        DKDoubleTapCommentDuplicate();
        return YES;
    }
    // 与原生评论项的点击回调一致，sender 为 nil。
    return DKDoubleTapCommentOpen(controller, model, ^{ [control commentButtonClicked:nil]; });
}

%group DKTapListenHooks
%hook AWEListenFeedOptimizedInteractionViewController
- (void)handleDoubleTap:(id)gesture {
    DKDoubleTapCommentDispatch(DKDoubleTapCommentListenFeed, self, ^{
        %orig;
    }, ^BOOL{
        return DKTapListenComment(self);
    });
}
%end
%end

%ctor {
    Class controller = NSClassFromString(@"AWEListenFeedOptimizedInteractionViewController");
    gDKListenControlClass = NSClassFromString(@"AWEListenFeedPlayControlView");
    if (![controller isSubclassOfClass:UIViewController.class]
        || ![gDKListenControlClass isSubclassOfClass:UIView.class]
        || !DKDoubleTapCommentMethod(controller, @selector(handleDoubleTap:), "v@")
        || !DKDoubleTapCommentMethod(controller, @selector(model), "@")
        || !DKDoubleTapCommentMethod(controller, @selector(controlView), "@")
        || !DKDoubleTapCommentMethod(gDKListenControlClass, @selector(delegate), "@")
        || !DKDoubleTapCommentMethod(gDKListenControlClass, @selector(commentButtonClicked:), "v@")) return;
    %init(DKTapListenHooks);
    DKDoubleTapCommentInstalled(DKDoubleTapCommentListenFeed);
}
