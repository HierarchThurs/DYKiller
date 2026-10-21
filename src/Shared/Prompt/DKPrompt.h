// 通用提示内容与会话。业务提交展示快照；窗口场景内的显示、轮换和材质由组件统一管理。
#ifndef DKPrompt_h
#define DKPrompt_h

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DKPromptTone) {
    DKPromptToneProcessing,
    DKPromptToneInformation,
    DKPromptToneSuccess,
    DKPromptToneWarning,
    DKPromptToneFailure,
    DKPromptToneCancelled,
};

typedef NS_ENUM(NSInteger, DKPromptProgressMode) {
    DKPromptProgressNone,
    DKPromptProgressDeterminate,
    DKPromptProgressIndeterminate,
};

typedef NS_ENUM(NSInteger, DKPromptDismissReason) {
    DKPromptDismissExpired,
    DKPromptDismissUser,
    DKPromptDismissAction,
    DKPromptDismissWithdrawn,
    DKPromptDismissSceneDisconnected,
};

@interface DKPromptAction : NSObject <NSCopying>
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic) BOOL destructive;
@property (nonatomic) BOOL dismissOnInvoke; // 默认 YES；取消运行中业务时设为 NO，等待业务提交结果。
@property (nonatomic, copy, nullable) dispatch_block_t handler;
+ (instancetype)actionWithIdentifier:(NSString *)identifier title:(NSString *)title handler:(nullable dispatch_block_t)handler;
@end

@interface DKPromptContent : NSObject <NSCopying>
@property (nonatomic, strong, nullable) UIImage *icon;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *subtitle;
@property (nonatomic, copy, nullable) NSString *progressText;
@property (nonatomic) DKPromptTone tone;
@property (nonatomic) DKPromptProgressMode progressMode;
@property (nonatomic) double progress;
@property (nonatomic, copy) NSArray<DKPromptAction *> *actions; // 最多两个，标识在会话中稳定且互不重复。
@property (nonatomic, copy, nullable) dispatch_block_t cardAction;
@property (nonatomic) BOOL cardActionDismisses;
@end

@interface DKPromptSession : NSObject
@property (nonatomic, readonly, copy) NSString *identifier;
@property (nonatomic, readonly, copy) NSString *ownerIdentifier;
// 关闭回调在主线程至多执行一次；业务捕获自身时使用弱引用。
@property (atomic, copy, nullable) void (^onDismiss)(DKPromptDismissReason reason);
- (void)update:(DKPromptContent *)content;
- (void)finish:(DKPromptContent *)content;
- (void)dismiss;
- (void)nudge;
@end

#ifdef __cplusplus
extern "C" {
#endif

// 可从任意线程调用；内容在调用时复制，UI 与会话状态串行在主线程处理。
DKPromptSession *DKPromptSubmit(DKPromptContent *content, UIWindowScene * _Nullable scene, NSString * _Nullable ownerIdentifier);
DKPromptSession *DKPromptPostResult(DKPromptContent *content, UIWindowScene * _Nullable scene, NSString * _Nullable ownerIdentifier);
// 只撤回提示，不取消相应业务。scene 为空时匹配该业务在所有场景的提示。
void DKPromptDismissOwner(NSString *ownerIdentifier, UIWindowScene * _Nullable scene);
// UI 上下文工具，仅在主线程调用；优先取响应链所属场景，不创建宿主视图或新窗口。
UIWindowScene * _Nullable DKPromptSceneForResponder(UIResponder * _Nullable responder);
UIWindow * _Nullable DKPromptWindowForScene(UIWindowScene * _Nullable scene);
// 当前队列的只读统计，不包含业务文字或联系人等内容。
NSDictionary *DKPromptDiagnostics(void);

#ifdef __cplusplus
}
#endif
NS_ASSUME_NONNULL_END
#endif
