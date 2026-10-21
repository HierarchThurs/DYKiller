#import "DKPrompt.h"
@class DKPromptScenePresenter;

@interface DKPromptSession ()
@property (nonatomic, readwrite, copy) NSString *identifier;
@property (nonatomic, readwrite, copy) NSString *ownerIdentifier;
@property (nonatomic, strong) DKPromptContent *content;
@property (nonatomic, weak) UIWindowScene *scene;
@property (nonatomic) BOOL sceneWasSpecified;
@property (nonatomic, weak) DKPromptScenePresenter *presenter;
@property (nonatomic) BOOL finished;
@property (atomic) BOOL closed;
@property (nonatomic) BOOL cardConsumed;
@property (nonatomic, strong) NSMutableSet<NSString *> *consumedActions;
@end

@interface DKPromptCoordinator : NSObject
+ (instancetype)shared;
- (void)submit:(DKPromptSession *)session;
- (void)update:(DKPromptSession *)session content:(DKPromptContent *)content finished:(BOOL)finished;
- (void)dismiss:(DKPromptSession *)session reason:(DKPromptDismissReason)reason;
- (void)nudge:(DKPromptSession *)session;
- (void)dismissOwner:(NSString *)owner scene:(UIWindowScene *)scene;
- (NSDictionary *)diagnostics;
- (void)refreshAppearance;
@end

// 业务接口统一串行进入主线程，快照复制在调用线程完成。
static inline void DKPromptPerform(dispatch_block_t block) {
    if (NSThread.isMainThread) block();
    else dispatch_async(dispatch_get_main_queue(), block);
}
