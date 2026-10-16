//
//  DKInteractionAppearance.xm
//  DYKiller
//
//  视频右侧互动按钮、头像和听音乐组件的外观定制。
//

#import "DKInteractionAppearance.h"
#import "DouyinHeaders.h"
#import "DKAdjustRange.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"

static const NSInteger kDKInteractionDisplayDefault = 0;
static const NSInteger kDKInteractionDisplayHiddenClickable = 1;
static const NSInteger kDKInteractionDisplayHiddenDisabled = 2;

static NSHashTable<AWEElementStackView *> *gDKInteractionStacks;

#pragma mark - 取值

static id DKInteractionValue(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSInteger DKInteractionStoredInteger(NSString *key, NSInteger defaultValue) {
    id raw = [NSUserDefaults.standardUserDefaults objectForKey:key];
    return raw ? [raw integerValue] : defaultValue;
}

static CGFloat DKInteractionAlpha(NSString *key) {
    return DKPrefFraction(key, 100);
}

static CGFloat DKInteractionScale(NSString *key) {
    return DKAdjustValue(key) / 100.0;
}

static NSInteger DKInteractionDisplay(NSString *key) {
    return MIN(kDKInteractionDisplayHiddenDisabled,
               MAX(kDKInteractionDisplayDefault, DKInteractionStoredInteger(key, 0)));
}

static CGFloat DKInteractionOffset(void) {
    return DKAdjustValue(DKKeyInteractionOffset);
}

// 缩放或位移生效时，右侧栈的几何偏离抖音原位。
static BOOL DKInteractionGeometryActive(void) {
    return DKInteractionOffset() != 0
        || DKInteractionScale(DKKeyInteractionScale) != 1.0
        || DKInteractionScale(DKKeyAvatarScale) != 1.0
        || DKInteractionScale(DKKeyMusicScale) != 1.0;
}

#pragma mark - 视图识别

static BOOL DKInteractionIsClass(UIView *view, NSString *className) {
    Class cls = NSClassFromString(className);
    return cls && [view isKindOfClass:cls];
}

static BOOL DKInteractionContainsClass(UIView *view, NSString *className) {
    if (!view) return NO;
    if (DKInteractionIsClass(view, className)) return YES;
    for (UIView *subview in view.subviews) {
        if (DKInteractionContainsClass(subview, className)) return YES;
    }
    return NO;
}

static NSUInteger DKInteractionCountClass(UIView *view, NSString *className) {
    if (!view) return 0;
    NSUInteger count = DKInteractionIsClass(view, className) ? 1 : 0;
    for (UIView *subview in view.subviews) count += DKInteractionCountClass(subview, className);
    return count;
}

static void DKInteractionCollectViews(UIView *root, NSString *className, NSMutableArray<UIView *> *result) {
    if (!root) return;
    if (DKInteractionIsClass(root, className)) [result addObject:root];
    for (UIView *subview in root.subviews) DKInteractionCollectViews(subview, className, result);
}

static BOOL DKInteractionIsRightStack(AWEElementStackView *stack) {
    if (!stack || !DKPlayInteractionControllerForView(stack)) return NO;
    if ([stack.accessibilityLabel isEqualToString:@"right"]) return YES;
    if (DKInteractionContainsClass(stack, @"AWEPlayInteractionUserProfileContainerView")) return YES;
    if (DKInteractionContainsClass(stack, @"AWEPlayInteractionListenFeedView")) return YES;

    NSUInteger buttons = DKInteractionCountClass(stack, @"AWEFeedVideoButton");
    BOOL hasLeftAnchor = DKInteractionContainsClass(stack, @"AWEFeedAnchorContainerView");
    return buttons >= 2 && !hasLeftAnchor;
}

// 听音乐组件：AWEMusicCoverButton 的父视图，覆盖听抖音、拍同款、音乐详情唱片、玩同款等样式。
static void DKInteractionCollectMusic(UIView *stack, NSMutableArray<UIView *> *result) {
    NSMutableArray<UIView *> *covers = [NSMutableArray array];
    DKInteractionCollectViews(stack, @"AWEMusicCoverButton", covers);
    for (UIView *cover in covers) {
        UIView *music = cover.superview;
        if (music && music != stack && ![result containsObject:music]) [result addObject:music];
    }
}

// 冷启动静音播放时，音乐组件位置显示「取消静音」按钮；它跟随听音乐的缩放与透明度，不受显示方式影响。
static void DKInteractionCollectMute(UIView *stack, NSMutableArray<UIView *> *result) {
    DKInteractionCollectViews(stack, @"AFDCancelMuteAwemeView", result);
}

// 显示方式为「隐藏不可点击」（disabled = YES）或其余两档（disabled = NO）的目标：
// 互动按钮、头像容器（头像本体与关注加号、私信小圆标）、音乐组件。
static void DKInteractionCollectTargets(UIView *stack, BOOL disabled, NSMutableArray<UIView *> *result) {
    if ((DKInteractionDisplay(DKKeyInteractionDisplay) == kDKInteractionDisplayHiddenDisabled) == disabled) {
        DKInteractionCollectViews(stack, @"AWEFeedVideoButton", result);
    }
    if ((DKInteractionDisplay(DKKeyAvatarDisplay) == kDKInteractionDisplayHiddenDisabled) == disabled) {
        DKInteractionCollectViews(stack, @"AWEPlayInteractionUserProfileContainerView", result);
    }
    if ((DKInteractionDisplay(DKKeyMusicDisplay) == kDKInteractionDisplayHiddenDisabled) == disabled) {
        DKInteractionCollectMusic(stack, result);
    }
}

static BOOL DKInteractionViewInTargets(UIView *view, NSArray<UIView *> *targets) {
    for (UIView *target in targets) {
        if ([view isDescendantOfView:target]) return YES;
    }
    return NO;
}

#pragma mark - 目标应用

static UIImageView *DKInteractionButtonImage(AWEFeedVideoButton *button) {
    id image = DKInteractionValue(button, @"buttonImageView");
    if ([image isKindOfClass:UIImageView.class]) return image;
    image = DKInteractionValue(button, @"aweImageView");
    if ([image isKindOfClass:UIImageView.class]) return image;
    NSMutableArray<UIView *> *images = [NSMutableArray array];
    DKInteractionCollectViews(button, @"UIImageView", images);
    return (UIImageView *)images.firstObject;
}

static UILabel *DKInteractionButtonLabel(AWEFeedVideoButton *button) {
    id label = DKInteractionValue(button, @"label");
    if ([label isKindOfClass:UILabel.class]) return label;
    label = DKInteractionValue(button, @"buttonLabel");
    if ([label isKindOfClass:UILabel.class]) return label;
    for (UIView *subview in button.subviews) {
        if ([subview isKindOfClass:UILabel.class] && !subview.hidden) return (UILabel *)subview;
    }
    return nil;
}

static void DKInteractionApplyButton(AWEFeedVideoButton *button) {
    if (!button) return;
    NSInteger display = DKInteractionDisplay(DKKeyInteractionDisplay);
    CGFloat visibleFactor = display == kDKInteractionDisplayDefault ? DKInteractionAlpha(DKKeyInteractionIconAlpha) : 0.0;
    CGFloat labelFactor = display == kDKInteractionDisplayDefault ? DKInteractionAlpha(DKKeyInteractionLabelAlpha) : 0.0;
    DKAdjustAlpha(DKInteractionButtonImage(button), visibleFactor);
    DKAdjustAlpha(DKInteractionButtonLabel(button), labelFactor);
}

static void DKInteractionApplyAvatar(AWEPlayInteractionUserProfileContainerView *avatar, CGSize outset) {
    if (!avatar) return;
    NSInteger display = DKInteractionDisplay(DKKeyAvatarDisplay);
    CGFloat factor = display == kDKInteractionDisplayDefault ? DKInteractionAlpha(DKKeyAvatarAlpha) : 0.0;
    DKAdjustFade(avatar, factor, outset);
}

static void DKInteractionApplyMusic(UIView *music, CGSize outset) {
    if (!music) return;
    NSInteger display = DKInteractionDisplay(DKKeyMusicDisplay);
    CGFloat factor = display == kDKInteractionDisplayDefault ? DKInteractionAlpha(DKKeyMusicAlpha) : 0.0;
    DKAdjustFade(music, factor, outset);
}

static void DKInteractionApplyMute(UIView *mute, CGSize outset) {
    DKAdjustFade(mute, DKInteractionAlpha(DKKeyMusicAlpha), outset);
}

static CGFloat DKInteractionRowScale(UIView *row) {
    if (DKInteractionContainsClass(row, @"AWEPlayInteractionUserProfileContainerView")) return DKInteractionScale(DKKeyAvatarScale);
    if (DKInteractionContainsClass(row, @"AWEMusicCoverButton")
        || DKInteractionContainsClass(row, @"AFDCancelMuteAwemeView")) return DKInteractionScale(DKKeyMusicScale);
    if (DKInteractionContainsClass(row, @"AWEFeedVideoButton")) return DKInteractionScale(DKKeyInteractionScale);
    return 1.0;
}

// 行内容底边（行坐标）：未隐藏的直接子视图底边最大值；没有可见子视图时取行底。
static CGFloat DKInteractionRowContentBottom(UIView *row) {
    CGFloat bottom = CGRectGetMinY(row.bounds);
    BOOL found = NO;
    for (UIView *subview in row.subviews) {
        if (subview.hidden || CGRectIsEmpty(subview.bounds)) continue;
        bottom = MAX(bottom, CGRectGetMaxY(subview.frame));
        found = YES;
    }
    return found ? MIN(bottom, CGRectGetMaxY(row.bounds)) : CGRectGetMaxY(row.bounds);
}

void DKInteractionAppearanceApplyStack(AWEElementStackView *stack) {
    if (!DKInteractionIsRightStack(stack)) return;
    if (!gDKInteractionStacks) gDKInteractionStacks = [NSHashTable weakObjectsHashTable];
    [gDKInteractionStacks addObject:stack];

    NSMutableArray<UIView *> *buttons = [NSMutableArray array];
    DKInteractionCollectViews(stack, @"AWEFeedVideoButton", buttons);
    for (UIView *button in buttons) DKInteractionApplyButton((AWEFeedVideoButton *)button);

    NSMutableArray<UIView *> *avatars = [NSMutableArray array];
    DKInteractionCollectViews(stack, @"AWEPlayInteractionUserProfileContainerView", avatars);
    for (UIView *avatar in avatars) {
        DKInteractionApplyAvatar((AWEPlayInteractionUserProfileContainerView *)avatar, stack.bounds.size);
    }

    NSMutableArray<UIView *> *music = [NSMutableArray array];
    DKInteractionCollectMusic(stack, music);
    for (UIView *view in music) DKInteractionApplyMusic(view, stack.bounds.size);

    NSMutableArray<UIView *> *mutes = [NSMutableArray array];
    DKInteractionCollectMute(stack, mutes);
    for (UIView *view in mutes) DKInteractionApplyMute(view, stack.bounds.size);

    // 每行按所含元素的比例贴右缘缩放，最底行以内容底边为锚，内容底边与进度条的间距保持 100% 时的值。
    DKAdjustStackRows(stack, DKStackEdgeRight,
                      ^CGFloat(UIView *row) { return DKInteractionRowScale(row); },
                      ^CGFloat(UIView *row) { return DKInteractionRowContentBottom(row); });
    // 上移整栈：栈的 bounds 随之上移，命中范围与显示一致；父视图不裁剪且高度覆盖上移范围。
    DKAdjustTransform(stack, CGAffineTransformMakeTranslation(0, -DKInteractionOffset()));
}

#pragma mark - 命中控制

// 「隐藏不可点击」的目标：命中落在目标子树内或点位落在目标范围内时整栈不接收。
static BOOL DKInteractionHitsDisabled(UIView *stack, UIView *hit, CGPoint point) {
    NSMutableArray<UIView *> *targets = [NSMutableArray array];
    DKInteractionCollectTargets(stack, YES, targets);
    if (hit && DKInteractionViewInTargets(hit, targets)) return YES;

    for (UIView *target in targets) {
        CGPoint local = [target convertPoint:point fromView:stack];
        if (CGRectContainsPoint(target.bounds, local)) return YES;
    }
    return NO;
}

// 进度条容器与右侧栈同属一个父视图且层级更高，其扩展触控区会盖住右侧栈底部。
// 缩放或上移生效时按 UIKit 的顺序问容器下方的兄弟：第一个接收该点的兄弟就是容器放手后的去处，
// 只有它是右侧栈、命中可点目标且点位在该目标自身范围内时容器才放手；目标 bounds 外的扩展触控区仍归进度条。
static BOOL DKInteractionStackClaimsPoint(UIView *container, CGPoint point, UIEvent *event) {
    if (!DKInteractionGeometryActive()) return NO;
    NSArray<UIView *> *siblings = container.superview.subviews;
    NSUInteger index = [siblings indexOfObjectIdenticalTo:container];
    if (!siblings || index == NSNotFound) return NO;

    Class stackClass = NSClassFromString(@"AWEElementStackView");
    while (index > 0) {
        UIView *sibling = siblings[--index];
        UIView *hit = [sibling hitTest:[sibling convertPoint:point fromView:container] withEvent:event];
        if (!hit) continue;
        if (![sibling isKindOfClass:stackClass] || !DKInteractionIsRightStack((AWEElementStackView *)sibling)) return NO;
        NSMutableArray<UIView *> *targets = [NSMutableArray array];
        DKInteractionCollectTargets(sibling, NO, targets);
        DKInteractionCollectMute(sibling, targets);
        for (UIView *target in targets) {
            if (![hit isDescendantOfView:target]) continue;
            return CGRectContainsPoint(target.bounds, [target convertPoint:point fromView:container]);
        }
        return NO;
    }
    return NO;
}

#pragma mark - 刷新与诊断

void DKInteractionAppearanceRefresh(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKInteractionAppearanceRefresh(); });
        return;
    }
    for (AWEElementStackView *stack in gDKInteractionStacks.allObjects) {
        [stack setNeedsLayout];
        [stack layoutIfNeeded];
    }
}

static NSString *DKInteractionDisplayText(NSInteger value) {
    switch (value) {
        case kDKInteractionDisplayHiddenClickable: return @"隐藏可点击";
        case kDKInteractionDisplayHiddenDisabled: return @"隐藏不可点击";
        default: return @"默认显示";
    }
}

NSString *DKInteractionAppearanceStatus(void) {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"互动按钮图标=%ld%% 数字=%ld%% 缩放=%ld%% 显示=%@\n",
        (long)DKInteractionStoredInteger(DKKeyInteractionIconAlpha, 100),
        (long)DKInteractionStoredInteger(DKKeyInteractionLabelAlpha, 100),
        (long)DKAdjustValue(DKKeyInteractionScale),
        DKInteractionDisplayText(DKInteractionDisplay(DKKeyInteractionDisplay))];
    [out appendFormat:@"头像透明度=%ld%% 缩放=%ld%% 显示=%@ · 听音乐透明度=%ld%% 缩放=%ld%% 显示=%@\n",
        (long)DKInteractionStoredInteger(DKKeyAvatarAlpha, 100),
        (long)DKAdjustValue(DKKeyAvatarScale),
        DKInteractionDisplayText(DKInteractionDisplay(DKKeyAvatarDisplay)),
        (long)DKInteractionStoredInteger(DKKeyMusicAlpha, 100),
        (long)DKAdjustValue(DKKeyMusicScale),
        DKInteractionDisplayText(DKInteractionDisplay(DKKeyMusicDisplay))];
    [out appendFormat:@"上移=%ldpt\n", (long)DKInteractionOffset()];
    [out appendFormat:@"可见交互栈=%lu\n", (unsigned long)gDKInteractionStacks.allObjects.count];
    for (AWEElementStackView *stack in gDKInteractionStacks.allObjects) {
        NSMutableArray<UIView *> *music = [NSMutableArray array];
        DKInteractionCollectMusic(stack, music);
        [out appendFormat:@"  %@ frame=%@ 按钮=%lu 头像=%@ 音乐=%@\n",
            NSStringFromClass(stack.class), NSStringFromCGRect(stack.frame),
            (unsigned long)DKInteractionCountClass(stack, @"AWEFeedVideoButton"),
            DKInteractionContainsClass(stack, @"AWEPlayInteractionUserProfileContainerView") ? @"有" : @"无",
            music.count ? NSStringFromClass(music.firstObject.class) : @"无"];
    }
    return out;
}

#pragma mark - Hook

%hook AWEElementStackView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = %orig(point, event);
    if (DKInteractionHitsDisabled(self, hit, point) && DKInteractionIsRightStack(self)) return nil;
    return hit;
}

%end

%hook AWEDPlayerProgressContainerView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = %orig(point, event);
    if (hit && DKInteractionStackClaimsPoint(self, point, event)) return nil;
    return hit;
}

%end

%ctor {
    %init;
}
