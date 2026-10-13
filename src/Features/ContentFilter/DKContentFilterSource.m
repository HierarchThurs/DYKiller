// 来源绑定按数据控制器保存，弱引用页面，避免跨页面共享的全局当前来源。
#import "DKContentFilter.h"
#import <os/lock.h>

@interface DKFilterOwnerBinding : NSObject
@property (nonatomic, weak) id owner;
@property (nonatomic, weak) id controller;
@property (nonatomic, copy) NSString *source;
@end
@implementation DKFilterOwnerBinding
@end

static char kDKFilterBindingsKey, kDKFilterOwnerKey;
static os_unfair_lock gDKSourceLock = OS_UNFAIR_LOCK_INIT;

void DKFilterBindSource(id owner, id controller, NSString *source) {
    if (!owner) return;
    NSString *name = [source isKindOfClass:NSString.class] ? [source copy] : nil;
    os_unfair_lock_lock(&gDKSourceLock);
    DKFilterOwnerBinding *binding = objc_getAssociatedObject(owner, &kDKFilterOwnerKey);
    id previous = binding.controller;
    if (previous != controller && previous) {
        NSMutableArray *records = objc_getAssociatedObject(previous, &kDKFilterBindingsKey);
        [records removeObjectIdenticalTo:binding];
    }
    if (!binding) {
        binding = [DKFilterOwnerBinding new];
        binding.owner = owner;
        objc_setAssociatedObject(owner, &kDKFilterOwnerKey, binding, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    binding.controller = controller;
    binding.source = name;
    if (controller) {
        NSMutableArray *records = objc_getAssociatedObject(controller, &kDKFilterBindingsKey);
        if (!records) {
            records = [NSMutableArray array];
            objc_setAssociatedObject(controller, &kDKFilterBindingsKey, records, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        NSIndexSet *expired = [records indexesOfObjectsPassingTest:^BOOL(DKFilterOwnerBinding *record, NSUInteger index, BOOL *stop) {
            return !record.owner;
        }];
        [records removeObjectsAtIndexes:expired];
        if (![records containsObject:binding]) [records addObject:binding];
    }
    os_unfair_lock_unlock(&gDKSourceLock);
}

DKFilterSource DKFilterControllerSource(id controller) {
    os_unfair_lock_lock(&gDKSourceLock);
    NSArray<DKFilterOwnerBinding *> *records = objc_getAssociatedObject(controller, &kDKFilterBindingsKey);
    BOOL recommended = NO, other = NO, unknown = NO;
    for (DKFilterOwnerBinding *record in records) {
        if (!record.owner || record.controller != controller) continue;
        if (!record.source.length) unknown = YES;
        else if ([record.source isEqualToString:@"homepage_hot"]) recommended = YES;
        else other = YES;
    }
    os_unfair_lock_unlock(&gDKSourceLock);
    if ((recommended && other) || (unknown && (recommended || other))) return DKFilterSourceConflict;
    if (other) return DKFilterSourceOther;
    if (recommended) return DKFilterSourceRecommended;
    return DKFilterSourceUnknown;
}
