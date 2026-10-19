//
//  DKFriendCleanSendMessage.xm
//  DYKiller
//
//  朋友页精简 —— 作品右侧头像下方的「私信」图标，凡出现处都生效。
//
//  实现：
//   - 图标由 AWEPlayInteractionUserAvatarSendMsgController 管理：作品激活与关注状态变化都经显示闸门
//     shouldShowSendMessageView:，显示走 showSendMessageViewWithAnimation:，收起走 hideSendMessageView。
//   - 移除：闸门返回 NO，显示点也不再执行，图标按抖音原生方式不出现，头像不受影响。
//   - 隐藏：图标视图（阴影与图标都在其中）挂全透明 mask，点击照常打开私信。
//   - 设置改动：改成移除时对已见控制器 hideSendMessageView；改回时按闸门重新判定，应显示则 showSendMessageViewWithAnimation:NO。
//

#import "DouyinHeaders.h"
#import "DKFriendClean.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"

// 弱表（已见的控制器），只在主线程读写。
static NSHashTable *gDKSendMessageControllers;

static void DKSendMessageTrack(AWEPlayInteractionUserAvatarSendMsgController *controller) {
    if (!controller) return;
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKSendMessageTrack(controller); });
        return;
    }
    if (!gDKSendMessageControllers) gDKSendMessageControllers = [NSHashTable weakObjectsHashTable];
    [gDKSendMessageControllers addObject:controller];
}

static DKDisplayMode DKSendMessageMode(void) {
    return DKPrefDisplayMode(DKKeyFriendSendMessageMode);
}

static UIView *DKSendMessageView(AWEPlayInteractionUserAvatarSendMsgController *controller) {
    UIView *view = [controller respondsToSelector:@selector(sendMessageView)] ? controller.sendMessageView : nil;
    return [view isKindOfClass:UIView.class] ? view : nil;
}

static void DKSendMessageApply(AWEPlayInteractionUserAvatarSendMsgController *controller) {
    UIView *view = DKSendMessageView(controller);
    if (view) DKAdjustFade(view, DKSendMessageMode() == DKDisplayModeShow ? 1.0 : 0.0, view.bounds.size);
}

void DKFriendCleanSendMessageRefresh(void) {
    BOOL removed = DKSendMessageMode() == DKDisplayModeRemove;
    for (AWEPlayInteractionUserAvatarSendMsgController *controller in gDKSendMessageControllers.allObjects) {
        if (removed) {
            if ([controller respondsToSelector:@selector(hideSendMessageView)]) [controller hideSendMessageView];
            continue;
        }
        UIView *view = DKSendMessageView(controller);
        if (!view || view.isHidden || !view.superview) {
            id model = [controller respondsToSelector:@selector(userAvatarContext)] ? controller.userAvatarContext.model : nil;
            if (model && [controller respondsToSelector:@selector(shouldShowSendMessageView:)] &&
                [controller shouldShowSendMessageView:model]) {
                [controller showSendMessageViewWithAnimation:NO];
            }
        }
        DKSendMessageApply(controller);
    }
}

NSString *DKFriendCleanSendMessageStatus(void) {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"已见私信图标控制器=%lu\n", (unsigned long)gDKSendMessageControllers.allObjects.count];
    for (AWEPlayInteractionUserAvatarSendMsgController *controller in gDKSendMessageControllers.allObjects) {
        UIView *view = DKSendMessageView(controller);
        if (!view.window) continue;
        [out appendFormat:@"  私信图标 hidden=%d alpha=%.2f 淡出=%.2f frame=%@\n", view.isHidden, view.alpha,
            DKAdjustFadeFactor(view), NSStringFromCGRect([view convertRect:view.bounds toView:nil])];
    }
    return out;
}

%hook AWEPlayInteractionUserAvatarSendMsgController

- (BOOL)shouldShowSendMessageView:(id)model {
    BOOL show = %orig;
    DKSendMessageTrack(self);
    return show && DKSendMessageMode() != DKDisplayModeRemove;
}

- (void)showSendMessageViewWithAnimation:(BOOL)animated {
    if (DKSendMessageMode() == DKDisplayModeRemove) return;
    %orig;
    DKSendMessageTrack(self);
    DKSendMessageApply(self);
}

%end
