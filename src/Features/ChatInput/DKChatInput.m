//
//  DKChatInput.m
//  DYKiller
//
//  聊天输入区的基础设施：宿主判定、ivar 读取、组件查找、布局对象登记与刷新。
//

#import "DKChatInput.h"
#import "DKChatTopBar.h"
#import "DKChatEmojiTabGlass.h"
#import "DKChatFloatingGlass.h"
#import "DKChatInputList.h"
#import "DKChatInputPendant.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import "DouyinHeaders.h"
#import <objc/runtime.h>

static NSHashTable *gDKChatLayouts;
static char kDKChatLayoutKey;

// 输入控制器上挂布局对象的弱引用容器，避免控制器反向持有布局组件。
@interface DKChatLayoutReference : NSObject
@property (nonatomic, weak) id layout;
@end
@implementation DKChatLayoutReference
@end

BOOL DKChatInputIsKind(id object, NSString *className) {
    Class cls = NSClassFromString(className);
    return cls && [object isKindOfClass:cls];
}

id DKChatInputObjectIvar(id object, const char *name) {
    if (!object) return nil;
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    return type && type[0] == '@' ? object_getIvar(object, ivar) : nil;
}

// 聊天页下的普通聊天输入控制器；专用会话与详情页内的输入页不算。
static UIViewController *DKChatNormalInput(UIViewController *host) {
    if (!DKChatInputIsKind(host, @"AWEIMMessageBaseViewController")) return nil;
    for (UIViewController *child in host.childViewControllers) {
        if (!DKChatInputIsKind(child, @"IESIMInputViewController")) continue;
        IESIMInputViewController *input = (id)child;
        if (input.isCompanyChat || input.isShowingInPOIIMConversationViewController
            || input.isShowingInFeedDetailViewController || input.isShowingInImageVideoDisplayViewController) return nil;
        return input;
    }
    return nil;
}

UIViewController *DKChatInputController(id component) {
    return DKChatNormalInput(((AWEIMComponentBase *)component).context.hostViewController);
}

UIViewController *DKChatInputControllerForPageView(UIView *view) {
    for (UIResponder *node = view; node; node = node.nextResponder) {
        if (DKChatInputIsKind(node, @"AWEIMMessageBaseViewController")) return DKChatNormalInput((id)node);
    }
    return nil;
}

BOOL DKChatInputGlassWanted(UIViewController *input) {
    return input && DKGlassOSAvailable() && DKPrefBool(DKKeyChatInputGlass)
        && input.isViewLoaded;
}

id DKChatInputComponent(id component, NSString *className) {
    for (id sibling in ((AWEIMComponentBase *)component).belongingManager.components) {
        if (DKChatInputIsKind(sibling, className)) return sibling;
    }
    return nil;
}

void DKChatInputRegisterLayout(id layout) {
    UIViewController *input = DKChatInputController(layout);
    if (!input) return;
    if (!gDKChatLayouts) gDKChatLayouts = [NSHashTable weakObjectsHashTable];
    [gDKChatLayouts addObject:layout];
    DKChatLayoutReference *reference = objc_getAssociatedObject(input, &kDKChatLayoutKey);
    if (!reference) {
        reference = [DKChatLayoutReference new];
        objc_setAssociatedObject(input, &kDKChatLayoutKey, reference, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    reference.layout = layout;
}

id DKChatInputLayoutForController(UIViewController *input) {
    DKChatLayoutReference *reference = input ? objc_getAssociatedObject(input, &kDKChatLayoutKey) : nil;
    return reference.layout;
}

id DKChatInputLayoutForView(UIView *view) {
    for (UIResponder *node = view; node; node = node.nextResponder) {
        if (DKChatInputIsKind(node, @"IESIMInputViewController")) return DKChatInputLayoutForController((id)node);
    }
    return nil;
}

NSArray *DKChatInputLayouts(void) {
    return gDKChatLayouts.allObjects ?: @[];
}

void DKChatInputRefresh(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKChatInputRefresh(); });
        return;
    }
    for (id layout in DKChatInputLayouts()) [layout refreshLayout];
    DKChatInputListRefresh();
    DKChatFloatingGlassRefresh();
    DKChatEmojiTabGlassRefresh();
    DKChatInputPendantRefresh();
    DKChatTopBarRefresh();
}
