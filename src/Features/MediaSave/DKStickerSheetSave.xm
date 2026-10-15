// 相似表情页（单击评论表情或私信表情消息后出现）：在「分享表情 / 添加表情」按钮行并列「保存表情包」。
#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import "DKMediaResolver.h"
#import "DKMediaSaveDiagnostics.h"
#import "DKMediaSaveRuntime.h"
#import "DKMediaSaveTask.h"
#import "DKMediaSelect.h"
#import <objc/runtime.h>

static char kDKSheetButtonKey;
static char kDKSheetModelKey;

@interface AWEIMSimilarEmojiDisplayView (DKMediaSave)
- (void)dk_saveSticker:(id)sender;
@end

// 评论来源 scene 为 0 且没有私信消息；其余按私信开关处理。上下文取不到时任一开关开启即显示。
static BOOL DKSheetEnabled(UIView *view, id context) {
    BOOL comment = DKPrefBool(DKKeyMediaSaveCommentSticker), chat = DKPrefBool(DKKeyMediaSaveChatSticker);
    if (!comment && !chat) return NO;
    id config = context;
    if (!DKMediaValue(config, @"scene") && !DKMediaValue(config, @"message")) {
        config = DKMediaValue(DKMediaControllerForResponder(view, @"AWEIMSimilarEmojiDisplayViewController"), @"context");
    }
    if (!config) return comment || chat;
    BOOL fromChat = DKMediaValue(config, @"message") != nil || [DKMediaValue(config, @"scene") integerValue] != 0;
    return fromChat ? chat : comment;
}

static UIButton *DKSheetTemplate(UIStackView *stack, UIButton *ours) {
    for (UIView *view in stack.arrangedSubviews) {
        if ([view isKindOfClass:UIButton.class] && view != ours) return (UIButton *)view;
    }
    return nil;
}

static UIButton *DKSheetButton(AWEIMSimilarEmojiDisplayView *view) {
    UIButton *button = objc_getAssociatedObject(view, &kDKSheetButtonKey);
    if (button) return button;
    UIButton *reference = DKSheetTemplate(view.buttonStackView, nil);
    button = [UIButton buttonWithType:UIButtonTypeCustom];
    UIColor *color = [reference titleColorForState:UIControlStateNormal] ?: UIColor.labelColor;
    UIFont *font = reference.titleLabel.font ?: [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    button.backgroundColor = reference.backgroundColor ?: UIColor.secondarySystemFillColor;
    button.layer.cornerRadius = reference ? reference.layer.cornerRadius : 10;
    button.layer.cornerCurve = reference.layer.cornerCurve ?: kCACornerCurveContinuous;
    button.clipsToBounds = YES;
    button.titleLabel.font = font;
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 0.7;
    button.tintColor = color;
    [button setTitle:@"保存表情包" forState:UIControlStateNormal];
    [button setTitleColor:color forState:UIControlStateNormal];
    [button setTitleColor:[color colorWithAlphaComponent:0.5] forState:UIControlStateHighlighted];
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:font.pointSize weight:UIImageSymbolWeightMedium];
    [button setImage:[UIImage systemImageNamed:@"square.and.arrow.down" withConfiguration:config] forState:UIControlStateNormal];
    button.titleEdgeInsets = UIEdgeInsetsMake(0, 4, 0, -4);
    button.imageEdgeInsets = UIEdgeInsetsMake(-2, -4, 2, 4);
    [button addTarget:view action:@selector(dk_saveSticker:) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(view, &kDKSheetButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return button;
}

static void DKSheetRemoveButton(AWEIMSimilarEmojiDisplayView *view) {
    UIButton *button = objc_getAssociatedObject(view, &kDKSheetButtonKey);
    if ([button.superview isKindOfClass:UIStackView.class]) [(UIStackView *)button.superview removeArrangedSubview:button];
    [button removeFromSuperview];
}

static void DKSheetEnsure(AWEIMSimilarEmojiDisplayView *view, id model, id context) {
    if (model) objc_setAssociatedObject(view, &kDKSheetModelKey, model, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIStackView *stack = view.buttonStackView;
    if (![stack isKindOfClass:UIStackView.class]) return;
    UIButton *existing = objc_getAssociatedObject(view, &kDKSheetButtonKey);
    id current = objc_getAssociatedObject(view, &kDKSheetModelKey);
    BOOL show = DKSheetEnabled(view, context) && DKResolveStickerURLGroups(current).count > 0 && DKSheetTemplate(stack, existing);
    if (!show) {
        DKSheetRemoveButton(view);
        return;
    }
    UIButton *button = DKSheetButton(view);
    button.hidden = NO;
    if (button.superview != stack || stack.arrangedSubviews.lastObject != button) {
        DKSheetRemoveButton(view);
        [stack addArrangedSubview:button];
        DKMediaSaveHit(DKMediaSaveEntrySimilarSheet);
    }
}

%group DKStickerSheetHooks
%hook AWEIMSimilarEmojiDisplayView
- (void)renderWithDisplayModel:(id)model context:(id)context {
    %orig;
    DKSheetEnsure(self, model, context);
}

- (void)p_configButtonsWithButtonViewModels:(id)models {
    // 原生按模型数量隐藏多余按钮，配置期间只保留原生按钮。
    DKSheetRemoveButton(self);
    %orig;
    DKSheetEnsure(self, nil, nil);
}

%new
- (void)dk_saveSticker:(id)sender {
    id model = objc_getAssociatedObject(self, &kDKSheetModelKey);
    DKMediaSaveItem *item = DKSelectStickerItem(DKResolveStickerURLGroups(model));
    DKMediaSaveRun(item ? @[item] : @[], @"表情页");
}
%end
%end

%ctor {
    Class cls = NSClassFromString(@"AWEIMSimilarEmojiDisplayView");
    BOOL ok = DKMediaMethod(cls, @selector(renderWithDisplayModel:context:), "v@@")
        && DKMediaMethod(cls, @selector(p_configButtonsWithButtonViewModels:), "v@")
        && DKMediaMethod(cls, @selector(buttonStackView), "@");
    if (ok) %init(DKStickerSheetHooks);
    DKMediaSaveInstalled(DKMediaSaveEntrySimilarSheet, ok);
}
