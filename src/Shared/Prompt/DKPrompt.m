#import "DKPromptInternal.h"
#import <math.h>

@implementation DKPromptAction
- (instancetype)init {
    if ((self = [super init])) { _identifier = @""; _title = @""; _dismissOnInvoke = YES; }
    return self;
}
+ (instancetype)actionWithIdentifier:(NSString *)identifier title:(NSString *)title handler:(dispatch_block_t)handler {
    DKPromptAction *action = [self new];
    action.identifier = identifier;
    action.title = title;
    action.handler = handler;
    return action;
}
- (id)copyWithZone:(NSZone *)zone {
    DKPromptAction *action = [[[self class] allocWithZone:zone] init];
    action.identifier = self.identifier;
    action.title = self.title;
    action.destructive = self.destructive;
    action.dismissOnInvoke = self.dismissOnInvoke;
    action.handler = self.handler;
    return action;
}
@end

@implementation DKPromptContent
- (instancetype)init {
    if ((self = [super init])) { _title = @""; _actions = @[]; }
    return self;
}
- (id)copyWithZone:(NSZone *)zone {
    DKPromptContent *content = [[[self class] allocWithZone:zone] init];
    content.icon = self.icon;
    content.title = self.title ?: @"";
    content.subtitle = self.subtitle;
    content.progressText = self.progressText;
    content.tone = self.tone;
    content.progressMode = self.progressMode;
    content.progress = isfinite(self.progress) ? MIN(1.0, MAX(0.0, self.progress)) : 0.0;
    NSMutableArray *actions = [NSMutableArray array];
    NSMutableSet *identifiers = [NSMutableSet set];
    for (DKPromptAction *action in self.actions) {
        if (!action.identifier.length || [identifiers containsObject:action.identifier]) continue;
        [actions addObject:[action copy]];
        [identifiers addObject:action.identifier];
        if (actions.count == 2) break;
    }
    content.actions = actions;
    content.cardAction = self.cardAction;
    content.cardActionDismisses = self.cardActionDismisses;
    return content;
}
@end

@implementation DKPromptSession {
    void (^_onDismiss)(DKPromptDismissReason);
}
- (void)setOnDismiss:(void (^)(DKPromptDismissReason))callback {
    @synchronized (self) { if (!self.closed || !callback) _onDismiss = [callback copy]; }
}
- (void (^)(DKPromptDismissReason))onDismiss {
    @synchronized (self) { return _onDismiss; }
}
- (instancetype)init {
    if ((self = [super init])) {
        _identifier = NSUUID.UUID.UUIDString;
        _ownerIdentifier = @"";
        _consumedActions = [NSMutableSet set];
    }
    return self;
}
- (void)update:(DKPromptContent *)content {
    DKPromptContent *snapshot = [content copy];
    DKPromptPerform(^{ [[DKPromptCoordinator shared] update:self content:snapshot finished:NO]; });
}
- (void)finish:(DKPromptContent *)content {
    DKPromptContent *snapshot = [content copy];
    DKPromptPerform(^{ [[DKPromptCoordinator shared] update:self content:snapshot finished:YES]; });
}
- (void)dismiss {
    DKPromptPerform(^{ [[DKPromptCoordinator shared] dismiss:self reason:DKPromptDismissWithdrawn]; });
}
- (void)nudge {
    DKPromptPerform(^{ [[DKPromptCoordinator shared] nudge:self]; });
}
@end

static DKPromptSession *DKPromptCreate(DKPromptContent *content, UIWindowScene *scene, NSString *owner, BOOL finished) {
    DKPromptSession *session = [DKPromptSession new];
    session.ownerIdentifier = owner ?: @"";
    session.content = [content copy];
    if (finished && !session.content.cardAction) session.content.cardActionDismisses = YES;
    session.scene = scene;
    session.sceneWasSpecified = scene != nil;
    session.finished = finished;
    DKPromptPerform(^{ [[DKPromptCoordinator shared] submit:session]; });
    return session;
}
DKPromptSession *DKPromptSubmit(DKPromptContent *content, UIWindowScene *scene, NSString *ownerIdentifier) {
    return DKPromptCreate(content, scene, ownerIdentifier, NO);
}
DKPromptSession *DKPromptPostResult(DKPromptContent *content, UIWindowScene *scene, NSString *ownerIdentifier) {
    return DKPromptCreate(content, scene, ownerIdentifier, YES);
}
void DKPromptDismissOwner(NSString *ownerIdentifier, UIWindowScene *scene) {
    NSString *owner = [ownerIdentifier copy];
    DKPromptPerform(^{ [[DKPromptCoordinator shared] dismissOwner:owner scene:scene]; });
}
NSDictionary *DKPromptDiagnostics(void) {
    if (!NSThread.isMainThread) return @{ @"state": @"main_thread_required" };
    return [[DKPromptCoordinator shared] diagnostics];
}
