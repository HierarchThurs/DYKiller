// iPad 共用播放页的双击关闭动作，复用本页评论容器的原生退出流程。
#import "DKDoubleTapComment.h"
#import "DouyinHeaders.h"
#import <objc/message.h>
#import <objc/runtime.h>

dispatch_block_t DKDoubleTapCommentPadCloseAction(UIViewController *owner) {
    if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad
        || ![owner isKindOfClass:NSClassFromString(@"AWEPlayInteractionViewController")]) return nil;
    id comment = DKDoubleTapCommentObject(owner, @selector(commentVC));
    if (![comment isKindOfClass:NSClassFromString(@"AWECommentContainerViewController")]
        || !DKDoubleTapCommentMethod(object_getClass(comment), @selector(dismiss), "v")) return nil;
    UIView *view = ((UIViewController *)comment).viewIfLoaded;
    if (!view.window || view.hidden || view.alpha <= 0.01) return nil;
    return ^{ ((void (*)(id, SEL))objc_msgSend)(comment, @selector(dismiss)); };
}
