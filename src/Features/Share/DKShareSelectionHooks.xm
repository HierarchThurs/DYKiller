// 分享评论选人后的状态同步与发送按钮布局入口。
#import "DKShareSelectionHooks.h"
#import "DKGlassGuard.h"
#import <objc/runtime.h>
#import <stdlib.h>
#import <string.h>

@interface DKShareCommentSelectionSection : NSObject
- (UIView *)createAdditionTextAndAppendToViewHierarchyWithShareContactList:(id)list;
- (void)shareContactList:(id)list stateDidChangeFromState:(NSUInteger)fromState
                toState:(NSUInteger)toState;
@end

@interface DKShareAdditionTextButton : UIButton
@end

static Class gSelectionSectionClass;
static Class gSendButtonClass;
static NSUInteger gSelectionCallbacks;
static NSUInteger gSendButtonLayouts;
static NSUInteger gSendButtonAttachments;

// 私有 Swift 类的哈希部分不参与匹配；只在输入覆盖层所在映像中查找语义类名。
static Class DKShareFindSendButtonClass(void) {
    Class overlay = NSClassFromString(@"AWEIMShareImpl.ShareAdditionTextView");
    const char *image = overlay ? class_getImageName(overlay) : NULL;
    if (!image) return Nil;
    unsigned int count = 0;
    const char **names = objc_copyClassNamesForImage(image, &count);
    Class found = Nil;
    for (unsigned int i = 0; i < count; i++) {
        if (!strstr(names[i], "AWEIMShareImpl")
            || !strstr(names[i], "ShareAdditionTextButton")) continue;
        Class candidate = objc_getClass(names[i]);
        for (Class parent = candidate; parent; parent = class_getSuperclass(parent)) {
            if (parent == UIButton.class) { found = candidate; break; }
        }
        if (found) break;
    }
    free(names);
    return found;
}

NSString *DKShareSelectionHooksStatus(void) {
    return [NSString stringWithFormat:
        @"选人回调 Hook=%@  发送布局 Hook=%@  选人回调=%lu  发送布局=%lu  首次挂载=%lu",
        gSelectionSectionClass ? @"已安装" : @"未找到类",
        gSendButtonClass ? @"已安装" : @"未找到类",
        (unsigned long)gSelectionCallbacks, (unsigned long)gSendButtonLayouts,
        (unsigned long)gSendButtonAttachments];
}

%group DKShareSelectionSectionHooks
%hook DKShareCommentSelectionSection

- (UIView *)createAdditionTextAndAppendToViewHierarchyWithShareContactList:(id)list {
    UIView *overlay = %orig;
    gSelectionCallbacks++;
    if (@available(iOS 26.0, *)) DKShareCommentSelectionChanged(self, overlay);
    return overlay;
}

- (void)shareContactList:(id)list stateDidChangeFromState:(NSUInteger)fromState
                toState:(NSUInteger)toState {
    %orig;
    gSelectionCallbacks++;
    if (@available(iOS 26.0, *)) DKShareCommentSelectionChanged(self, nil);
}

%end
%end

%group DKShareSendButtonLayoutHooks
%hook DKShareAdditionTextButton

- (void)layoutSubviews {
    %orig;
    gSendButtonLayouts++;
    if (@available(iOS 26.0, *)) {
        if (DKShareSendButtonDidLayout(self)) gSendButtonAttachments++;
    }
}

%end
%end

%ctor {
    if (!DKGlassOSAvailable()) return;
    gSelectionSectionClass = NSClassFromString(@"AWEIMShareImpl.ShareCommentHorizontalSectionController");
    if (gSelectionSectionClass
        && class_getInstanceMethod(gSelectionSectionClass,
            @selector(createAdditionTextAndAppendToViewHierarchyWithShareContactList:))
        && class_getInstanceMethod(gSelectionSectionClass,
            @selector(shareContactList:stateDidChangeFromState:toState:))) {
        %init(DKShareSelectionSectionHooks, DKShareCommentSelectionSection = gSelectionSectionClass);
    } else {
        gSelectionSectionClass = Nil;
    }
    gSendButtonClass = DKShareFindSendButtonClass();
    if (gSendButtonClass) {
        %init(DKShareSendButtonLayoutHooks, DKShareAdditionTextButton = gSendButtonClass);
    }
}
