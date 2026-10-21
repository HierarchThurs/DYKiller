#import "DKPrompt.h"

NS_ASSUME_NONNULL_BEGIN
// 场景 presenter 持有一张卡片；视图不管理业务会话、期限或队列。
@interface DKPromptView : UIView
@property (nonatomic, copy, nullable) void (^onAction)(NSString * _Nullable identifier); // nil 为整卡点击。
@property (nonatomic, copy, nullable) void (^onInteraction)(BOOL active);
@property (nonatomic, copy) NSSet<NSString *> *disabledActions;
@property (nonatomic) BOOL cardActionDisabled;
@property (nonatomic, copy) NSString *sessionIdentifier; // 切换业务时才对整块内容做过渡。
- (void)applyContent:(DKPromptContent *)content inWindow:(UIWindow *)window animated:(BOOL)animated;
- (void)dismissWithCompletion:(nullable dispatch_block_t)completion;
- (void)nudge;
@end
NS_ASSUME_NONNULL_END
