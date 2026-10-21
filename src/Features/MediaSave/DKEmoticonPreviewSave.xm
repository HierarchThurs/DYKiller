// 表情面板长按预览：在底部操作按钮行与原生按钮等分并列「保存表情包」。
// 只改按钮行子视图的水平约束：停用可见原生按钮的水平约束并记录，换成等分链；开关关闭或按钮变化时还原。
#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import "DKMediaResolver.h"
#import "DKMediaSaveDiagnostics.h"
#import "DKMediaSaveRuntime.h"
#import "DKMediaSaveTask.h"
#import "DKMediaSelect.h"
#import <objc/runtime.h>

static char kDKPreviewStateKey;

@interface DKPreviewRowState : NSObject
@property (nonatomic, strong) UIButton *button;
@property (nonatomic, strong) NSMutableArray<NSLayoutConstraint *> *disabled;
@property (nonatomic, strong) NSMutableArray<NSLayoutConstraint *> *added;
@property (nonatomic, strong) NSMutableArray<UIView *> *separators;
@property (nonatomic, assign) BOOL separatorChanged;
@property (nonatomic, assign) BOOL separatorWasHidden;
@end

@implementation DKPreviewRowState
@end

@interface AWEIMEmoticonPreviewV2 (DKMediaSave)
- (void)dk_previewSave:(id)sender;
@end

static BOOL DKHorizontal(NSLayoutAttribute attribute) {
    switch (attribute) {
        case NSLayoutAttributeLeading: case NSLayoutAttributeTrailing: case NSLayoutAttributeLeft: case NSLayoutAttributeRight:
        case NSLayoutAttributeCenterX: case NSLayoutAttributeWidth: case NSLayoutAttributeLeadingMargin:
        case NSLayoutAttributeTrailingMargin: case NSLayoutAttributeLeftMargin: case NSLayoutAttributeRightMargin:
        case NSLayoutAttributeCenterXWithinMargins: return YES;
        default: return NO;
    }
}

static NSArray<UIButton *> *DKPreviewVisibleButtons(AWEIMEmoticonPreviewV2 *preview, UIButton *ours) {
    NSMutableArray<UIButton *> *out = [NSMutableArray array];
    for (NSString *key in @[@"checkSeriesButton", @"addToCustomButton", @"deleteFromCustomButton", @"deleteDoubleCheckButton", @"sendButton", @"gagasEditButton"]) {
        UIButton *button = DKMediaValue(preview, key);
        if ([button isKindOfClass:UIButton.class] && button != ours && !button.hidden && button.alpha > 0.01 && button.superview == preview.container) {
            [out addObject:button];
        }
    }
    return out;
}

static void DKPreviewRestore(AWEIMEmoticonPreviewV2 *preview) {
    DKPreviewRowState *state = objc_getAssociatedObject(preview, &kDKPreviewStateKey);
    if (!state) return;
    [NSLayoutConstraint deactivateConstraints:state.added];
    [state.added removeAllObjects];
    [NSLayoutConstraint activateConstraints:state.disabled];
    [state.disabled removeAllObjects];
    for (UIView *separator in state.separators) [separator removeFromSuperview];
    [state.separators removeAllObjects];
    if (state.separatorChanged) preview.verticalSeparateLineView.hidden = state.separatorWasHidden;
    state.separatorChanged = NO;
    [state.button removeFromSuperview];
}

static DKPreviewRowState *DKPreviewState(AWEIMEmoticonPreviewV2 *preview) {
    DKPreviewRowState *state = objc_getAssociatedObject(preview, &kDKPreviewStateKey);
    if (state) return state;
    state = [DKPreviewRowState new];
    state.disabled = [NSMutableArray array];
    state.added = [NSMutableArray array];
    state.separators = [NSMutableArray array];
    objc_setAssociatedObject(preview, &kDKPreviewStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return state;
}

static UIButton *DKPreviewButton(AWEIMEmoticonPreviewV2 *preview, DKPreviewRowState *state, UIButton *reference) {
    UIButton *button = state.button;
    if (!button) {
        button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.titleLabel.adjustsFontSizeToFitWidth = YES;
        button.titleLabel.minimumScaleFactor = 0.6;
        [button addTarget:preview action:@selector(dk_previewSave:) forControlEvents:UIControlEventTouchUpInside];
        state.button = button;
    }
    UIColor *color = [reference titleColorForState:UIControlStateNormal] ?: UIColor.labelColor;
    button.titleLabel.font = reference.titleLabel.font ?: [UIFont systemFontOfSize:14];
    [button setTitleColor:color forState:UIControlStateNormal];
    [button setTitleColor:[color colorWithAlphaComponent:0.5] forState:UIControlStateHighlighted];
    return button;
}

static void DKPreviewApply(AWEIMEmoticonPreviewV2 *preview) {
    DKPreviewRestore(preview);
    if (!DKPrefBool(DKKeyMediaSaveChatSticker)) return;
    if ([preview respondsToSelector:@selector(shouldShowOptionButtons)] && ![preview shouldShowOptionButtons]) return;
    if (!DKResolveStickerURLGroups(preview.model).count) return;
    UIView *container = preview.container;
    DKPreviewRowState *state = DKPreviewState(preview);
    NSArray<UIButton *> *natives = DKPreviewVisibleButtons(preview, state.button);
    if (!container || !natives.count || natives.count > 2) return;

    // 停用可见原生按钮的水平约束（内容尺寸约束除外）。
    for (UIButton *button in natives) {
        NSMutableArray<NSLayoutConstraint *> *candidates = [NSMutableArray arrayWithArray:container.constraints];
        [candidates addObjectsFromArray:button.constraints];
        for (NSLayoutConstraint *constraint in candidates) {
            if (!constraint.active || [NSStringFromClass(constraint.class) containsString:@"ContentSize"]) continue;
            BOOL first = constraint.firstItem == button && DKHorizontal(constraint.firstAttribute);
            BOOL second = constraint.secondItem == button && DKHorizontal(constraint.secondAttribute);
            if ((first || second) && ![state.disabled containsObject:constraint]) [state.disabled addObject:constraint];
        }
    }
    [NSLayoutConstraint deactivateConstraints:state.disabled];

    UIButton *anchor = natives.firstObject;
    UIButton *save = DKPreviewButton(preview, state, anchor);
    [save setTitle:natives.count == 1 ? @"保存表情包" : @"保存" forState:UIControlStateNormal];
    [container addSubview:save];
    NSArray<UIView *> *row = [natives arrayByAddingObject:save];
    NSMutableArray<NSLayoutConstraint *> *added = state.added;
    [added addObject:[row.firstObject.leadingAnchor constraintEqualToAnchor:container.leadingAnchor]];
    [added addObject:[row.lastObject.trailingAnchor constraintEqualToAnchor:container.trailingAnchor]];
    for (NSUInteger i = 1; i < row.count; i++) {
        [added addObject:[row[i].leadingAnchor constraintEqualToAnchor:row[i - 1].trailingAnchor]];
        [added addObject:[row[i].widthAnchor constraintEqualToAnchor:row.firstObject.widthAnchor]];
    }
    [added addObject:[save.topAnchor constraintEqualToAnchor:anchor.topAnchor]];
    [added addObject:[save.bottomAnchor constraintEqualToAnchor:anchor.bottomAnchor]];

    // 两项时复用原生竖分隔线（居中于预览内容）；三项时隐藏它，在每个分界处加同色分隔线。
    UIView *nativeSeparator = preview.verticalSeparateLineView;
    if (nativeSeparator) {
        state.separatorChanged = YES;
        state.separatorWasHidden = nativeSeparator.hidden;
        nativeSeparator.hidden = row.count != 2;
    }
    if (row.count > 2) {
        for (NSUInteger i = 1; i < row.count; i++) {
            UIView *separator = [UIView new];
            separator.translatesAutoresizingMaskIntoConstraints = NO;
            separator.backgroundColor = nativeSeparator.backgroundColor ?: UIColor.separatorColor;
            [container addSubview:separator];
            [state.separators addObject:separator];
            [added addObjectsFromArray:@[
                [separator.widthAnchor constraintEqualToConstant:0.5],
                [separator.heightAnchor constraintEqualToConstant:13],
                [separator.centerXAnchor constraintEqualToAnchor:row[i].leadingAnchor],
                [separator.centerYAnchor constraintEqualToAnchor:anchor.centerYAnchor],
            ]];
        }
    }
    [NSLayoutConstraint activateConstraints:added];
    DKMediaSaveHit(DKMediaSaveEntryPreview);
}

// 原生按钮配置前先还原，原生始终在自己的约束上重建；配置完再重新等分。
%group DKPreviewHooks
%hook AWEIMEmoticonPreviewV2
- (void)p_setupOptionButtonsIfNeededWithModel:(id)model {
    DKPreviewRestore(self);
    %orig;
    DKPreviewApply(self);
}

- (void)resetButtonsAndColor {
    DKPreviewRestore(self);
    %orig;
    DKPreviewApply(self);
}

- (void)didTapDeleteFromCustom:(id)sender {
    DKPreviewRestore(self);
    %orig;
    DKPreviewApply(self);
}

%new
- (void)dk_previewSave:(id)sender {
    DKMediaSaveItem *item = DKSelectStickerItem(DKResolveStickerURLGroups(self.model));
    UIWindowScene *scene = DKPromptSceneForResponder(self);
    if ([self respondsToSelector:@selector(p_hidePreview)]) [self p_hidePreview];
    DKMediaSaveRun(item ? @[item] : @[], @"表情预览", scene);
}
%end
%end

%ctor {
    Class cls = NSClassFromString(@"AWEIMEmoticonPreviewV2");
    BOOL ok = DKMediaMethod(cls, @selector(p_setupOptionButtonsIfNeededWithModel:), "v@")
        && DKMediaMethod(cls, @selector(resetButtonsAndColor), "v")
        && DKMediaMethod(cls, @selector(didTapDeleteFromCustom:), "v@")
        && DKMediaMethod(cls, @selector(container), "@") && DKMediaMethod(cls, @selector(model), "@");
    if (ok) %init(DKPreviewHooks);
    DKMediaSaveInstalled(DKMediaSaveEntryPreview, ok);
}
