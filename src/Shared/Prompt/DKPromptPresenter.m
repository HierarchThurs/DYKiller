#import "DKPromptInternal.h"
#import "DKPromptQueue.h"
#import "DKPromptView.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

UIWindow *DKPromptWindowForScene(UIWindowScene *scene) {
    if (!scene) {
        for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
            if (![candidate isKindOfClass:UIWindowScene.class]
                || candidate.activationState != UISceneActivationStateForegroundActive) continue;
            UIWindow *window = DKPromptWindowForScene((UIWindowScene *)candidate);
            if (window) return window;
        }
        return nil;
    }
    UIWindow *fallback = nil;
    for (UIWindow *window in scene.windows) {
        if (window.hidden || window.alpha <= 0.0 || window.windowLevel != UIWindowLevelNormal
            || CGRectIsEmpty(window.bounds)) continue;
        if (window.isKeyWindow) return window;
        if (!fallback) fallback = window;
    }
    return fallback;
}

UIWindowScene *DKPromptSceneForResponder(UIResponder *responder) {
    for (UIResponder *node = responder; node; node = node.nextResponder) {
        if ([node isKindOfClass:UIView.class] && ((UIView *)node).window.windowScene) {
            return ((UIView *)node).window.windowScene;
        }
        if ([node isKindOfClass:UIViewController.class] && ((UIViewController *)node).viewIfLoaded.window.windowScene) {
            return ((UIViewController *)node).viewIfLoaded.window.windowScene;
        }
    }
    return DKPromptWindowForScene(nil).windowScene;
}

static NSTimeInterval DKPromptResultDuration(DKPromptContent *content) {
    return content.actions.count ? 5.0 : 1.8;
}

static void DKPromptClose(DKPromptSession *session, DKPromptDismissReason reason) {
    if (session.closed) return;
    session.closed = YES;
    session.presenter = nil;
    session.content = nil;
    [session.consumedActions removeAllObjects];
    void (^callback)(DKPromptDismissReason) = session.onDismiss;
    session.onDismiss = nil;
    if (callback) callback(reason);
}

// 窗口中的透明尺寸观察视图；卡片独立挂在窗口上，保持既有玻璃层级。
@interface DKPromptWindowObserver : UIView
@property (nonatomic, copy) dispatch_block_t onLayout;
@end
@implementation DKPromptWindowObserver
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        if (@available(iOS 17.0, *)) {
            [self registerForTraitChanges:@[ UITraitUserInterfaceStyle.class ]
                              withHandler:^(DKPromptWindowObserver *view, __unused UITraitCollection *previous) {
                if (view.onLayout) view.onLayout();
            }];
        }
    }
    return self;
}
- (void)layoutSubviews { [super layoutSubviews]; if (self.onLayout) self.onLayout(); }
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (@available(iOS 17.0, *)) return;
    if (self.onLayout) self.onLayout();
}
@end

@interface DKPromptScenePresenter : NSObject
@property (nonatomic, weak) UIWindowScene *scene;
@property (nonatomic, strong) DKPromptQueue *queue;
@property (nonatomic, strong) NSMutableDictionary<NSString *, DKPromptSession *> *sessions;
@property (nonatomic, strong) DKPromptView *view;
@property (nonatomic, strong) DKPromptWindowObserver *observer;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) DKPromptContent *displayedContent;
@property (nonatomic, copy) NSString *displayedIdentifier;
@property (nonatomic) CGRect observedBounds;
@property (nonatomic) UIEdgeInsets observedInsets;
@property (nonatomic) UIUserInterfaceStyle observedStyle;
@property (nonatomic) BOOL pumping;
- (void)pump;
- (void)refreshGeometry;
- (void)disconnect;
@end

@implementation DKPromptScenePresenter
- (instancetype)init {
    if ((self = [super init])) {
        _queue = [DKPromptQueue new];
        _sessions = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)invoke:(NSString *)identifier {
    DKPromptSession *session = self.sessions[self.displayedIdentifier];
    if (!session || session.closed || ![self.queue.currentIdentifier isEqual:session.identifier]) return;
    if (!identifier) {
        if (session.cardConsumed) return;
        dispatch_block_t action = session.content.cardAction;
        BOOL dismiss = session.content.cardActionDismisses || (!action && session.finished);
        if (!action && !dismiss) return;
        session.cardConsumed = YES;
        self.view.cardActionDisabled = YES;
        if (dismiss) [[DKPromptCoordinator shared] dismiss:session reason:action ? DKPromptDismissAction : DKPromptDismissUser];
        if (action) action();
        return;
    }
    if ([session.consumedActions containsObject:identifier]) return;
    for (DKPromptAction *action in session.content.actions) {
        if (![action.identifier isEqual:identifier]) continue;
        [session.consumedActions addObject:identifier];
        self.view.disabledActions = [session.consumedActions copy];
        dispatch_block_t handler = action.handler;
        if (action.dismissOnInvoke) [[DKPromptCoordinator shared] dismiss:session reason:DKPromptDismissAction];
        if (handler) handler();
        break;
    }
}

- (void)installInWindow:(UIWindow *)window {
    __weak typeof(self) weakSelf = self;
    if (!self.observer) {
        self.observer = [[DKPromptWindowObserver alloc] initWithFrame:window.bounds];
        self.observer.onLayout = ^{ [weakSelf refreshGeometry]; };
    }
    if (self.observer.superview != window) {
        [self.observer removeFromSuperview];
        self.observer.frame = window.bounds;
        [window addSubview:self.observer];
    }
    if (!self.view) {
        self.view = [DKPromptView new];
        self.view.onAction = ^(NSString *identifier) { [weakSelf invoke:identifier]; };
        self.view.onInteraction = ^(BOOL active) {
            // 放开按钮后留到当前 UI 事件处理完成再恢复调度，避免先换卡片再分发点击。
            if (active) {
                [weakSelf.queue setInteracting:YES atTime:CACurrentMediaTime()];
                [weakSelf.timer invalidate];
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf.queue setInteracting:NO atTime:CACurrentMediaTime()];
                    [weakSelf pump];
                });
            }
        };
    }
}

- (void)refreshGeometry {
    if (self.pumping || !self.view.superview || self.view.hidden) return;
    UIWindow *window = self.view.window;
    UIUserInterfaceStyle style = window.windowScene.traitCollection.userInterfaceStyle;
    if (CGRectEqualToRect(self.observedBounds, window.bounds)
        && UIEdgeInsetsEqualToEdgeInsets(self.observedInsets, window.safeAreaInsets)
        && self.observedStyle == style) return;
    self.observedBounds = window.bounds;
    self.observedInsets = window.safeAreaInsets;
    self.observedStyle = style;
    DKPromptSession *session = self.sessions[self.displayedIdentifier];
    if (session) [self.view applyContent:session.content inWindow:window animated:NO];
}

- (void)pump {
    if (self.pumping) return;
    self.pumping = YES;
    [self.timer invalidate];
    self.timer = nil;
    UIWindow *window = DKPromptWindowForScene(self.scene);
    BOOL active = self.scene.activationState == UISceneActivationStateForegroundActive
        && UIApplication.sharedApplication.applicationState == UIApplicationStateActive && window;
    [self.queue setActive:active atTime:CACurrentMediaTime()];
    [self.queue advanceTo:CACurrentMediaTime()];
    for (NSString *identifier in [self.queue takeExpiredIdentifiers]) {
        DKPromptSession *expired = self.sessions[identifier];
        [self.sessions removeObjectForKey:identifier];
        if (expired) DKPromptClose(expired, DKPromptDismissExpired);
    }
    NSString *currentIdentifier = self.queue.currentIdentifier;
    DKPromptSession *session = currentIdentifier ? self.sessions[currentIdentifier] : nil;
    if (!active && self.queue.identifiers.count == 0) {
        [self.queue setInteracting:NO atTime:CACurrentMediaTime()];
        self.view.onInteraction = nil;
        self.view.onAction = nil;
        [self.view removeFromSuperview];
        [self.observer removeFromSuperview];
        self.view = nil;
        self.observer = nil;
        self.displayedIdentifier = nil;
        self.displayedContent = nil;
    } else if (!active) {
        self.view.hidden = YES;
    } else if (session) {
        [self installInWindow:window];
        self.view.hidden = NO;
        self.view.disabledActions = [session.consumedActions copy];
        self.view.cardActionDisabled = session.cardConsumed;
        self.view.sessionIdentifier = session.identifier;
        BOOL changed = ![self.displayedIdentifier isEqual:session.identifier] || self.displayedContent != session.content
            || !CGRectEqualToRect(self.observedBounds, window.bounds)
            || !UIEdgeInsetsEqualToEdgeInsets(self.observedInsets, window.safeAreaInsets)
            || self.observedStyle != window.windowScene.traitCollection.userInterfaceStyle;
        self.displayedIdentifier = session.identifier;
        self.displayedContent = session.content;
        if (changed || self.view.superview != window) {
            [self.view applyContent:session.content inWindow:window animated:YES];
        }
        [window bringSubviewToFront:self.view];
        [self refreshGeometryAfterPump:window];
    } else if (self.queue.identifiers.count == 0 && self.view) {
        DKPromptView *view = self.view;
        self.displayedIdentifier = nil;
        self.displayedContent = nil;
        __weak typeof(self) weakSelf = self;
        [view dismissWithCompletion:^{
            if (weakSelf.queue.identifiers.count || weakSelf.view != view) return;
            weakSelf.view = nil;
            [weakSelf.observer removeFromSuperview];
            weakSelf.observer = nil;
        }];
    }
    NSTimeInterval delay = self.queue.nextDelay;
    if (isfinite(delay)) {
        __weak typeof(self) weakSelf = self;
        self.timer = [NSTimer timerWithTimeInterval:MAX(0.001, delay) repeats:NO block:^(__unused NSTimer *timer) {
            [weakSelf pump];
        }];
        [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    }
    self.pumping = NO;
}

- (void)refreshGeometryAfterPump:(UIWindow *)window {
    self.observedBounds = window.bounds;
    self.observedInsets = window.safeAreaInsets;
    self.observedStyle = window.windowScene.traitCollection.userInterfaceStyle;
}

- (void)disconnect {
    [self.timer invalidate];
    self.timer = nil;
    self.view.onInteraction = nil;
    self.view.onAction = nil;
    [self.view removeFromSuperview];
    [self.observer removeFromSuperview];
    NSArray *sessions = self.sessions.allValues;
    [self.sessions removeAllObjects];
    self.queue = [DKPromptQueue new];
    for (DKPromptSession *session in sessions) DKPromptClose(session, DKPromptDismissSceneDisconnected);
    self.view = nil;
    self.observer = nil;
}
- (void)dealloc { [_timer invalidate]; }
@end

@implementation DKPromptCoordinator {
    NSMapTable<UIWindowScene *, DKPromptScenePresenter *> *_presenters;
    NSMutableArray<DKPromptSession *> *_unbound;
    __weak UIWindowScene *_lastScene;
    NSMutableArray<id> *_observers;
}
+ (instancetype)shared {
    static DKPromptCoordinator *coordinator;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ coordinator = [self new]; });
    return coordinator;
}
- (instancetype)init {
    if ((self = [super init])) {
        _presenters = [NSMapTable weakToStrongObjectsMapTable];
        _unbound = [NSMutableArray array];
        _observers = [NSMutableArray array];
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        __weak typeof(self) weakSelf = self;
        NSArray *names = @[ UISceneDidActivateNotification, UISceneWillDeactivateNotification,
            UISceneDidDisconnectNotification, UIApplicationDidBecomeActiveNotification,
            UIApplicationWillResignActiveNotification, UIWindowDidBecomeKeyNotification, UIWindowDidBecomeVisibleNotification ];
        for (NSString *name in names) {
            id token = [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                [weakSelf lifecycle:note];
            }];
            [_observers addObject:token];
        }
    }
    return self;
}

- (DKPromptScenePresenter *)presenterForScene:(UIWindowScene *)scene {
    DKPromptScenePresenter *presenter = [_presenters objectForKey:scene];
    if (!presenter) {
        presenter = [DKPromptScenePresenter new];
        presenter.scene = scene;
        [_presenters setObject:presenter forKey:scene];
    }
    return presenter;
}

- (void)submit:(DKPromptSession *)session {
    if (session.closed) return;
    if (session.sceneWasSpecified && !session.scene) {
        DKPromptClose(session, DKPromptDismissSceneDisconnected);
        return;
    }
    UIWindowScene *scene = session.scene ?: DKPromptWindowForScene(nil).windowScene ?: _lastScene;
    if (!scene) { [_unbound addObject:session]; return; }
    if (![UIApplication.sharedApplication.connectedScenes containsObject:scene]) {
        DKPromptClose(session, DKPromptDismissSceneDisconnected);
        return;
    }
    // 更早提交的无场景会话先绑定，保持首次接收顺序。
    if (_unbound.count) {
        NSArray *pending = [_unbound copy];
        [_unbound removeAllObjects];
        for (DKPromptSession *waiting in pending) { waiting.scene = scene; [self submit:waiting]; }
    }
    session.scene = scene;
    if (scene.activationState == UISceneActivationStateForegroundActive) _lastScene = scene;
    DKPromptScenePresenter *presenter = [self presenterForScene:scene];
    session.presenter = presenter;
    presenter.sessions[session.identifier] = session;
    BOOL active = scene.activationState == UISceneActivationStateForegroundActive
        && UIApplication.sharedApplication.applicationState == UIApplicationStateActive && DKPromptWindowForScene(scene);
    [presenter.queue setActive:active atTime:CACurrentMediaTime()];
    [presenter.queue enqueueIdentifier:session.identifier
                       resultDuration:session.finished ? DKPromptResultDuration(session.content) : 0.0
                               atTime:CACurrentMediaTime()];
    [presenter pump];
}

- (void)update:(DKPromptSession *)session content:(DKPromptContent *)content finished:(BOOL)finished {
    if (session.closed || session.finished) return;
    session.content = content;
    session.finished = finished;
    if (finished) {
        if (!content.cardAction) content.cardActionDismisses = YES;
        session.cardConsumed = NO;
        [session.consumedActions removeAllObjects];
        [session.presenter.queue finishIdentifier:session.identifier duration:DKPromptResultDuration(content) atTime:CACurrentMediaTime()];
    }
    [session.presenter pump];
}

- (void)dismiss:(DKPromptSession *)session reason:(DKPromptDismissReason)reason {
    if (session.closed) return;
    DKPromptScenePresenter *presenter = session.presenter;
    [presenter.sessions removeObjectForKey:session.identifier];
    [presenter.queue withdrawIdentifier:session.identifier atTime:CACurrentMediaTime()];
    [_unbound removeObjectIdenticalTo:session];
    DKPromptClose(session, reason);
    [presenter pump];
}
- (void)nudge:(DKPromptSession *)session {
    DKPromptScenePresenter *presenter = session.presenter;
    if (!session.closed && !presenter.view.hidden && [presenter.displayedIdentifier isEqual:session.identifier]) {
        [presenter.view nudge];
    }
}
- (void)dismissOwner:(NSString *)owner scene:(UIWindowScene *)scene {
    if (!owner.length) return;
    NSMutableArray *sessions = [_unbound mutableCopy];
    for (DKPromptScenePresenter *presenter in _presenters.objectEnumerator.allObjects) {
        [sessions addObjectsFromArray:presenter.sessions.allValues];
    }
    for (DKPromptSession *session in sessions) {
        if ([session.ownerIdentifier isEqual:owner] && (!scene || session.scene == scene)) {
            [self dismiss:session reason:DKPromptDismissWithdrawn];
        }
    }
}

- (void)lifecycle:(NSNotification *)note {
    UIWindowScene *scene = [note.object isKindOfClass:UIWindowScene.class] ? note.object : nil;
    if ([note.name isEqual:UISceneDidDisconnectNotification] && scene) {
        DKPromptScenePresenter *presenter = [_presenters objectForKey:scene];
        [_presenters removeObjectForKey:scene];
        [presenter disconnect];
        if (_lastScene == scene) _lastScene = nil;
        return;
    }
    if ([note.name isEqual:UISceneWillDeactivateNotification] && scene) {
        DKPromptScenePresenter *presenter = [_presenters objectForKey:scene];
        [presenter.queue setActive:NO atTime:CACurrentMediaTime()];
        [presenter.timer invalidate];
        presenter.view.hidden = YES;
        return;
    }
    if ([note.name isEqual:UIApplicationWillResignActiveNotification]) {
        for (DKPromptScenePresenter *presenter in _presenters.objectEnumerator.allObjects) {
            [presenter.queue setActive:NO atTime:CACurrentMediaTime()];
            [presenter.timer invalidate];
            presenter.view.hidden = YES;
        }
        return;
    }
    UIWindowScene *active = scene.activationState == UISceneActivationStateForegroundActive ? scene : DKPromptWindowForScene(nil).windowScene;
    if (active) _lastScene = active;
    if (active && _unbound.count) {
        NSArray *sessions = [_unbound copy];
        [_unbound removeAllObjects];
        for (DKPromptSession *session in sessions) { session.scene = active; [self submit:session]; }
    }
    for (DKPromptScenePresenter *presenter in _presenters.objectEnumerator.allObjects) [presenter pump];
}

- (void)refreshAppearance {
    for (DKPromptScenePresenter *presenter in _presenters.objectEnumerator.allObjects) {
        presenter.displayedContent = nil;
        [presenter pump];
    }
}

- (NSDictionary *)diagnostics {
    NSMutableArray *scenes = [NSMutableArray array];
    for (DKPromptScenePresenter *presenter in _presenters.objectEnumerator.allObjects) {
        [scenes addObject:@{ @"scene": presenter.scene.session.persistentIdentifier ?: @"",
            @"queued": @(presenter.queue.identifiers.count), @"visible": presenter.displayedIdentifier ?: @"",
            @"active": @(presenter.scene.activationState == UISceneActivationStateForegroundActive) }];
    }
    return @{ @"scenes": scenes, @"unbound": @(_unbound.count) };
}
@end
