//
//  DKInfoLongPressCopy.xm
//  DYKiller
//
//  播放页长按左下昵称复制「@昵称」，长按文案复制作品完整文案（含话题标签）。
//
//  实现：
//   - 元素实现作者协议的行是昵称行，实现文案协议的行是文案行；从元素栈的统一布局入口给这两种行各装一个长按手势，
//     行内可点的内容（昵称按钮、文案文字与展开箭头）都在手势范围内。
//   - 手势代理逐次触摸判定：开关关闭或取不到内容时不接收触摸，行为与原生一致；祖先视图上的长按手势
//     （长按面板、播放器长按、cell 长按）等本手势失败后才识别。识别后行内触摸被取消，昵称按钮与文案面板不触发。
//   - 触发时从该行元素当前的作品取值：作者昵称前加「@」；文案取 descriptionString（正文与话题标签，不受折叠影响）。
//     写入剪贴板后轻震，并用通用提示面板显示复制内容。
//

#import "DKInfoLongPressCopy.h"
#import "DouyinHeaders.h"
#import "DKInfoAppearance.h"
#import "DKKeys.h"
#import "DKPrompt.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import <objc/runtime.h>

typedef NS_ENUM(NSInteger, DKInfoCopyKind) {
    DKInfoCopyNone = 0,
    DKInfoCopyNickname = 1,
    DKInfoCopyDescription = 2,
};

// 与抖音在视频上长按呼出面板的时长一致。
static const NSTimeInterval kDKInfoCopyPressDuration = 0.4;
static NSString *const kDKInfoCopyPromptOwner = @"info_long_press_copy";
static const void *kDKInfoCopyGestureKey = &kDKInfoCopyGestureKey;

static DKInfoCopyKind DKInfoCopyKindOfRow(UIView *row) {
    static Protocol *authorProtocol;
    static Protocol *descriptionProtocol;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        authorProtocol = NSProtocolFromString(@"AWEPlayInteractionAuthorElementProtocol");
        descriptionProtocol = NSProtocolFromString(@"AWEPlayInteractionDescriptionElementProtocol");
    });
    id element = DKInfoRowElement(row);
    if (authorProtocol && [element conformsToProtocol:authorProtocol]) return DKInfoCopyNickname;
    if (descriptionProtocol && [element conformsToProtocol:descriptionProtocol]) return DKInfoCopyDescription;
    return DKInfoCopyNone;
}

// 该行对应开关开启时返回要复制的文字；开关关闭、不是昵称 / 文案行或作品无此内容时返回 nil。
static NSString *DKInfoCopyText(UIView *row, DKInfoCopyKind kind) {
    if (kind == DKInfoCopyNone) return nil;
    if (!DKPrefBool(kind == DKInfoCopyNickname ? DKKeyLongPressCopyNickname : DKKeyLongPressCopyDescription)) return nil;
    id element = DKInfoRowElement(row);
    AWEAwemeModel *model = [element respondsToSelector:@selector(model)] ? [(AWEPlayInteractionBaseElement *)element model] : nil;
    if (![model isKindOfClass:%c(AWEAwemeModel)]) return nil;
    if (kind == DKInfoCopyNickname) {
        NSString *name = model.author.nickname;
        return name.length ? [@"@" stringByAppendingString:name] : nil;
    }
    NSString *text = model.descriptionString;
    return text.length ? text : nil;
}

static void DKInfoCopyShowPrompt(UIView *row, DKInfoCopyKind kind, NSString *text) {
    DKPromptContent *content = [DKPromptContent new];
    content.icon = [UIImage systemImageNamed:@"doc.on.doc" withConfiguration:
        [UIImageSymbolConfiguration configurationWithPointSize:13.0 weight:UIImageSymbolWeightSemibold]];
    content.title = kind == DKInfoCopyNickname ? @"已复制用户名" : @"已复制文案";
    content.subtitle = text;
    content.tone = DKPromptToneSuccess;
    UIWindowScene *scene = DKPromptSceneForResponder(row);
    // 连续复制时只留最新一条。
    DKPromptDismissOwner(kDKInfoCopyPromptOwner, scene);
    DKPromptPostResult(content, scene, kDKInfoCopyPromptOwner);
}

@interface DKInfoCopyHandler : NSObject <UIGestureRecognizerDelegate>
@end

@implementation DKInfoCopyHandler

+ (instancetype)shared {
    static DKInfoCopyHandler *handler;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ handler = [DKInfoCopyHandler new]; });
    return handler;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    return DKInfoCopyText(gesture.view, DKInfoCopyKindOfRow(gesture.view)) != nil;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)other {
    return [other isKindOfClass:UILongPressGestureRecognizer.class] && other.view && other.view != gesture.view
        && [gesture.view isDescendantOfView:other.view];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    UIView *row = gesture.view;
    DKInfoCopyKind kind = DKInfoCopyKindOfRow(row);
    NSString *text = DKInfoCopyText(row, kind);
    if (!text) return;
    UIPasteboard.generalPasteboard.string = text;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    DKInfoCopyShowPrompt(row, kind, text);
}

@end

void DKInfoLongPressCopyApplyStack(AWEElementStackView *stack) {
    if (!DKPrefBool(DKKeyLongPressCopyNickname) && !DKPrefBool(DKKeyLongPressCopyDescription)) return;
    DKInfoCopyHandler *handler = [DKInfoCopyHandler shared];
    for (UIView *row in stack.arrangedSubviews) {
        if (objc_getAssociatedObject(row, kDKInfoCopyGestureKey) || DKInfoCopyKindOfRow(row) == DKInfoCopyNone) continue;
        UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc] initWithTarget:handler
                                                                                             action:@selector(handleLongPress:)];
        gesture.minimumPressDuration = kDKInfoCopyPressDuration;
        gesture.delegate = handler;
        [row addGestureRecognizer:gesture];
        objc_setAssociatedObject(row, kDKInfoCopyGestureKey, gesture, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%ctor {
    DKSettingsRegister(DKKeyLongPressCopyNickname, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyLongPressCopyNickname, @"长按复制用户名",
                            @"长按播放页左下角的昵称，复制「@昵称」并提示复制内容。长按昵称不再呼出长按面板。");
    });
    DKSettingsRegister(DKKeyLongPressCopyDescription, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyLongPressCopyDescription, @"长按复制文案",
                            @"长按播放页左下角的文案，复制作品完整文案（含话题标签，不受折叠影响）并提示复制内容。长按文案不再呼出长按面板。");
    });
}
