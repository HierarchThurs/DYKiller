// 私有 getter 与 Hook 的 ABI 校验。
#import "DKContentFilter.h"
#import <objc/message.h>
#import <stdlib.h>
#import <string.h>

static const char *DKFilterUnqualified(const char *type) {
    while (*type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL DKFilterTypeMatches(const char *actual, const char *expected) {
    actual = DKFilterUnqualified(actual);
    // 对象可带类名或 block 编码；显式指针仍须匹配整个指针类型。
    return !strcmp(expected, "@") ? *actual == '@' : !strcmp(actual, expected);
}

BOOL DKFilterMethod(Class cls, SEL selector, const char *returnType, NSArray<NSString *> *arguments) {
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (signature.numberOfArguments != arguments.count + 2
        || !DKFilterTypeMatches(signature.methodReturnType, returnType)) return NO;
    for (NSUInteger i = 0; i < arguments.count; i++) {
        if (!DKFilterTypeMatches([signature getArgumentTypeAtIndex:i + 2], arguments[i].UTF8String)) return NO;
    }
    return YES;
}

BOOL DKFilterOwnMethod(Class cls, SEL selector) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == selector) { found = YES; break; }
    }
    free(methods);
    return found;
}

id DKFilterObject(id object, SEL selector) {
    if (!object || !DKFilterMethod(object_getClass(object), selector, "@", @[])) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(object, selector); }
    @catch (__unused NSException *exception) { return nil; }
}

BOOL DKFilterBool(id object, SEL selector) {
    Class cls = object ? object_getClass(object) : Nil;
    if (!DKFilterMethod(cls, selector, "B", @[]) && !DKFilterMethod(cls, selector, "c", @[])) return NO;
    @try { return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector); }
    @catch (__unused NSException *exception) { return NO; }
}

BOOL DKFilterIsClass(id object, NSString *className) {
    Class cls = NSClassFromString(className);
    return object && cls && [object isKindOfClass:cls];
}
