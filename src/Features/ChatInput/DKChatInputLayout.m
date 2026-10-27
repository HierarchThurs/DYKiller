//
//  DKChatInputLayout.m
//  DYKiller
//
//  聊天输入区的悬浮布局：行内几何、文字区 inset 的计算与回写、收起态下沉，以及「行几何 → 文字区 → 玻璃」的单一同步入口。
//

#import "DKChatInputLayout.h"
#import "DKChatInput.h"
#import "DKChatInputGlass.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import "DouyinHeaders.h"

const CGFloat kDKChatRowGap = 8.0;
const CGFloat kDKChatButtonDiameter = 44.0;
const CGFloat kDKChatCapsuleTextPadding = 12.0;
const CGFloat kDKChatPanelInset = 8.0;
const CGFloat kDKChatPanelRadius = 22.0;
const CGFloat kDKChatFoldedSink = 16.0;

static BOOL gDKChatSyncing;

#pragma mark - 几何

DKChatRowFrames DKChatRowFramesMake(CGRect band, NSUInteger leftCount, NSUInteger rightCount) {
    DKChatRowFrames frames = {0};
    if (CGRectIsEmpty(band) || leftCount > DKChatRowLeftLimit || rightCount > DKChatRowRightLimit) return frames;
    CGFloat diameter = MIN(CGRectGetHeight(band), kDKChatButtonDiameter);
    if (diameter <= 0.0) return frames;
    CGFloat top = CGRectGetMaxY(band) - diameter;
    for (NSUInteger index = 0; index < leftCount; index++) {
        frames.left[index] = CGRectMake(CGRectGetMinX(band) + index * (diameter + kDKChatRowGap), top, diameter, diameter);
    }
    for (NSUInteger index = 0; index < rightCount; index++) {
        CGFloat x = CGRectGetMaxX(band) - (rightCount - index) * diameter - (rightCount - 1 - index) * kDKChatRowGap;
        frames.right[index] = CGRectMake(x, top, diameter, diameter);
    }
    frames.leftCount = leftCount;
    frames.rightCount = rightCount;
    CGFloat capsuleX = leftCount > 0 ? CGRectGetMaxX(frames.left[leftCount - 1]) + kDKChatRowGap : CGRectGetMinX(band);
    CGFloat capsuleRight = rightCount > 0 ? CGRectGetMinX(frames.right[0]) - kDKChatRowGap : CGRectGetMaxX(band);
    frames.capsule = CGRectMake(capsuleX, CGRectGetMinY(band), MAX(0.0, capsuleRight - capsuleX), CGRectGetHeight(band));
    return frames;
}

static NSArray<UIView *> *DKChatShownButtons(id layout, const char *ivar, UIView *elements) {
    NSMutableArray<UIView *> *buttons = [NSMutableArray array];
    for (UIView *button in DKChatInputObjectIvar(layout, ivar)) {
        if (![button isKindOfClass:UIView.class] || button.hidden || button.alpha < 0.01
            || ![button isDescendantOfView:elements]) continue;
        [buttons addObject:button];
    }
    return buttons;
}

void DKChatInputRowButtons(id layout, NSArray<UIView *> **left, NSArray<UIView *> **right) {
    UIView *elements = DKChatInputObjectIvar(layout, "_inputBarElementContainer");
    if (left) *left = DKChatShownButtons(layout, "_leftButtons", elements);
    if (right) *right = DKChatShownButtons(layout, "_rightButtons", elements);
}

BOOL DKChatInputRowFrames(id layout, DKChatRowFrames *frames) {
    UIView *elements = DKChatInputObjectIvar(layout, "_inputBarElementContainer");
    UIView *plate = DKChatInputObjectIvar(layout, "_textViewBackgroundView");
    if (!elements || !plate || CGRectIsEmpty(plate.bounds)) return NO;
    NSArray<UIView *> *left, *right;
    DKChatInputRowButtons(layout, &left, &right);
    *frames = DKChatRowFramesMake([plate convertRect:plate.bounds toView:elements], left.count, right.count);
    return !CGRectIsEmpty(frames->capsule);
}

static UIView *DKChatGrowingTextView(id layout) {
    return DKChatInputObjectIvar(DKChatInputComponent(layout, @"IESIMInputTextComponent"), "_textView");
}

UIEdgeInsets DKChatInputTextInsets(id layout, UIView *growing, UIEdgeInsets native) {
    if (!layout || !growing || growing != DKChatGrowingTextView(layout)
        || !DKChatInputGlassWanted(DKChatInputController(layout))) return native;
    UIView *elements = DKChatInputObjectIvar(layout, "_inputBarElementContainer");
    UITextView *text = DKChatInputObjectIvar(growing, "internalTextView");
    DKChatRowFrames frames;
    if (!text || ![growing isDescendantOfView:elements] || !DKChatInputRowFrames(layout, &frames)) return native;
    // 文字首字的横向起点 = 内部文字视图 x + 行片段留白 + 容器左内边距，右侧对称。
    CGRect capsule = [elements convertRect:frames.capsule toView:growing];
    CGFloat padding = text.textContainer.lineFragmentPadding;
    UIEdgeInsets insets = native;
    insets.left = CGRectGetMinX(capsule) + kDKChatCapsuleTextPadding - padding - text.textContainerInset.left;
    insets.right = CGRectGetWidth(growing.bounds) - CGRectGetMaxX(capsule) + kDKChatCapsuleTextPadding
        - padding - text.textContainerInset.right;
    return insets;
}

CGRect DKChatInputFoldedFrame(id layout, CGRect native) {
    UIViewController *input = DKChatInputController(layout);
    if (!DKChatInputGlassWanted(input)) return native;
    // 原生 y = 父视图高 − 行高 − 底部让位，让位量由父视图高与 frame 底边反推；没有让位的机型不下沉。
    CGFloat bottomOffset = CGRectGetHeight(input.view.superview.bounds) - CGRectGetMaxY(native);
    native.origin.y += MIN(kDKChatFoldedSink, MAX(0.0, bottomOffset));
    return native;
}

UIWindowScene *DKChatInputScene(UIViewController *input) {
    for (UIViewController *node = input; node; node = node.parentViewController) {
        UIWindowScene *scene = node.viewIfLoaded.window.windowScene;
        if (scene) return scene;
    }
    return nil;
}

UIUserInterfaceStyle DKChatInputStyle(UIViewController *input) {
    UIUserInterfaceStyle style = DKChatInputScene(input).traitCollection.userInterfaceStyle;
    if (!style) style = input.view.traitCollection.userInterfaceStyle;
    return style ?: UIUserInterfaceStyleLight;
}

#pragma mark - 写回原生视图

static void DKChatSetFrame(UIView *view, CGRect frame) {
    if (!view || CGRectEqualToRect(view.frame, frame)) return;
    view.frame = frame;
}

// 圆钮按原生左右分组排到槽位；语音态的按住说话区跟胶囊同框，长按与取消逻辑保持原生。
static void DKChatApplyRow(id layout) {
    DKChatRowFrames frames;
    if (!DKChatInputRowFrames(layout, &frames)) return;
    NSArray<UIView *> *left, *right;
    DKChatInputRowButtons(layout, &left, &right);
    for (NSUInteger index = 0; index < frames.leftCount; index++) DKChatSetFrame(left[index], frames.left[index]);
    for (NSUInteger index = 0; index < frames.rightCount; index++) DKChatSetFrame(right[index], frames.right[index]);
    UIView *elements = DKChatInputObjectIvar(layout, "_inputBarElementContainer");
    UIView *audio = DKChatInputObjectIvar(DKChatInputComponent(layout, @"IESIMInputAudioComponent"), "_audioInputView");
    if (audio && !audio.hidden && [audio isDescendantOfView:elements]) DKChatSetFrame(audio, frames.capsule);
}

// 文字区只经原生 setter 写入：DKChatInputTextInsets 在 setter 的 Hook 里换算，这里只在值不一致时触发一次。
static void DKChatApplyTextInsets(id layout) {
    IESIMGrowingTextView *growing = (id)DKChatGrowingTextView(layout);
    if (![growing respondsToSelector:@selector(setContentInsetPurely:)]) return;
    UIEdgeInsets current = growing.contentInset;
    if (UIEdgeInsetsEqualToEdgeInsets(current, DKChatInputTextInsets(layout, growing, current))) return;
    [growing setContentInsetPurely:current];
    [growing setNeedsLayout];
}

#pragma mark - 入口

void DKChatInputSync(id layout) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKChatInputSync(layout); });
        return;
    }
    if (!layout || gDKChatSyncing) return;
    UIViewController *input = DKChatInputController(layout);
    if (!DKChatInputGlassWanted(input)) {
        DKChatInputRestore(layout);
        return;
    }
    gDKChatSyncing = YES;
    DKChatInputRegisterLayout(layout);
    DKChatApplyRow(layout);
    DKChatApplyTextInsets(layout);
    DKChatInputGlassApply(layout, DKPrefBool(DKKeyChatInputGlassClear), DKChatInputStyle(input));
    gDKChatSyncing = NO;
}

void DKChatInputRestore(id layout) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKChatInputRestore(layout); });
        return;
    }
    if (!layout || gDKChatSyncing) return;
    DKChatInputGlassRestore(layout);
}
