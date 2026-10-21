#import "DKMediaSaveRuntime.h"
#import "DKMediaLibrary.h"
#import "DKPrompt.h"
#import <objc/runtime.h>
#import <string.h>

static char DKTypeChar(const char *type) {
    while (*type && strchr("rnNoORV", *type)) type++;
    return *type;
}

BOOL DKMediaMethod(Class cls, SEL selector, const char *types) {
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method || !types || !*types) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (signature.numberOfArguments != strlen(types) + 1 || DKTypeChar(signature.methodReturnType) != types[0]) return NO;
    for (NSUInteger i = 1; types[i]; i++) {
        if (DKTypeChar([signature getArgumentTypeAtIndex:i + 1]) != types[i]) return NO;
    }
    return YES;
}

BOOL DKMediaClassHasPrefix(id object, NSString *prefix) {
    return object && prefix.length && [NSStringFromClass([object class]) hasPrefix:prefix];
}

UIViewController *DKMediaControllerForResponder(UIResponder *responder, NSString *prefix) {
    for (UIResponder *r = responder; r; r = r.nextResponder) {
        if ([r isKindOfClass:UIViewController.class] && DKMediaClassHasPrefix(r, prefix)) return (UIViewController *)r;
    }
    return nil;
}

static UIViewController *DKSearch(UIViewController *controller, NSString *prefix, NSHashTable *visited) {
    if (!controller || [visited containsObject:controller] || visited.count > 400) return nil;
    [visited addObject:controller];
    if (DKMediaClassHasPrefix(controller, prefix)) return controller;
    for (UIViewController *child in controller.childViewControllers) {
        UIViewController *found = DKSearch(child, prefix, visited);
        if (found) return found;
    }
    return DKSearch(controller.presentedViewController, prefix, visited);
}

UIViewController *DKMediaFindControllerInScene(NSString *prefix, UIWindowScene *scene) {
    if (!scene) return nil;
    return DKSearch(DKPromptWindowForScene(scene).rootViewController, prefix, [NSHashTable weakObjectsHashTable]);
}

UIViewController *DKMediaFindController(NSString *prefix) {
    return DKMediaFindControllerInScene(prefix, DKMediaForegroundWindow().windowScene);
}
