//
//  DKListenGlassControl.xm
//  DYKiller
//
//  听抖音控制区的液态玻璃：互动按钮一个胶囊、倍速 / 顺序 / 定时各一个圆钮、播放控制一个胶囊、
//  进度条连同两侧时间排进一条单行胶囊、长按快进提示一个胶囊。
//   - 玻璃由约束贴在原生视图上，并挂在原生栈或控件里，原生隐藏、改尺寸时自动跟随。
//   - 进度条只改原生约束的常量：时间与滑条同一条中线，滑条让出两侧时间的宽度。
//

#import "DKListenGlass.h"
#import "DKListenHitLayer.h"
#import "DKViewAdjust.h"
#import "DouyinHeaders.h"

#import <objc/runtime.h>

static const CGFloat kDKListenTopRowHeight = 50.0;
static const CGFloat kDKListenBottomRowHeight = 56.0;
static const CGFloat kDKListenRowInset = 12.0;       // 胶囊相对屏幕两侧的边距，也是互动胶囊的内边距
static const CGFloat kDKListenPlaybackPadding = 32.0;  // 播放胶囊两端到前后按钮中心
static const CGFloat kDKListenProgressHeight = 32.0;
static const CGFloat kDKListenProgressGap = 10.0;    // 时间与滑条的间距

static char kDKListenNativeConstantKey;

static NSHashTable<AWEListenFeedPlayControlView *> *gDKListenControls;

// 写约束常量并记下原生值；target 为 nil 时写回原生值。
static void DKListenSetConstant(NSLayoutConstraint *constraint, NSNumber *target) {
    NSNumber *native = objc_getAssociatedObject(constraint, &kDKListenNativeConstantKey);
    if (!native) {
        if (!target) return;
        native = @(constraint.constant);
        objc_setAssociatedObject(constraint, &kDKListenNativeConstantKey, native, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat value = target ? target.doubleValue : native.doubleValue;
    if (constraint.constant != value) constraint.constant = value;
    if (!target) objc_setAssociatedObject(constraint, &kDKListenNativeConstantKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static CGFloat DKListenNativeConstant(NSLayoutConstraint *constraint) {
    NSNumber *native = objc_getAssociatedObject(constraint, &kDKListenNativeConstantKey);
    return native ? native.doubleValue : constraint.constant;
}

static BOOL DKListenIsLeftEdge(NSLayoutAttribute attribute) {
    return attribute == NSLayoutAttributeLeft || attribute == NSLayoutAttributeLeading;
}

static BOOL DKListenIsRightEdge(NSLayoutAttribute attribute) {
    return attribute == NSLayoutAttributeRight || attribute == NSLayoutAttributeTrailing;
}

// centerLine 是进度条中线相对进度视图顶部的目标位置；on 为 NO 时写回原生约束。
static void DKListenProgressLayout(AWEListenFeedSideLabelProgressViewV2 *progress, BOOL on, CGFloat centerLine) {
    // 滑条让出“时间到屏幕边的距离 + 时间宽度 + 间距”，两侧等宽，时长不变时滑条不随读数抖动。
    CGFloat leftEdge = 0.0, rightEdge = 0.0;
    for (NSLayoutConstraint *constraint in progress.constraints) {
        if (constraint.firstItem == progress.currentTime && DKListenIsLeftEdge(constraint.firstAttribute)) {
            leftEdge = DKListenNativeConstant(constraint);
        } else if (constraint.firstItem == progress.remainTime && DKListenIsRightEdge(constraint.firstAttribute)) {
            rightEdge = -DKListenNativeConstant(constraint);
        }
    }
    CGFloat timeSlot = progress.remainTime.intrinsicContentSize.width + kDKListenProgressGap;
    for (NSLayoutConstraint *constraint in progress.constraints) {
        id first = constraint.firstItem;
        NSLayoutAttribute attribute = constraint.firstAttribute;
        NSNumber *target = nil;
        if (first == progress.progressCenterYView && attribute == NSLayoutAttributeTop) {
            target = @(centerLine);
        } else if ((first == progress.currentTime || first == progress.remainTime) && attribute == NSLayoutAttributeTop) {
            target = @(-((UILabel *)first).intrinsicContentSize.height * 0.5);
        } else if (first == progress.progressSlider && DKListenIsLeftEdge(attribute)) {
            target = @(leftEdge + timeSlot);
        } else if (first == progress.progressSlider && DKListenIsRightEdge(attribute)) {
            target = @(-(rightEdge + timeSlot));
        } else {
            continue;
        }
        DKListenSetConstant(constraint, on ? target : nil);
    }
}

API_AVAILABLE(ios(26.0))
static UIView *DKListenPinRound(DKChatGlassStore *store, UIView *view, CGFloat diameter) {
    return [store pinGlassFor:view in:view shape:DKChatGlassShapeRounded radius:diameter * 0.5 interactive:YES
                  constraints:^NSArray<NSLayoutConstraint *> *(UIView *glass) {
        return @[
            [glass.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
            [glass.centerYAnchor constraintEqualToAnchor:view.centerYAnchor],
            [glass.widthAnchor constraintEqualToConstant:diameter],
            [glass.heightAnchor constraintEqualToConstant:diameter],
        ];
    }];
}

API_AVAILABLE(ios(26.0))
static void DKListenSyncRows(DKChatGlassStore *store, DKListenHitLayer *layer, AWEListenFeedPlayControlView *control) {
    UIStackView *top = control.topStackView;
    UIStackView *topRight = control.topRightStackView;
    UIStackView *bottom = control.bottomStackView;

    // 互动按钮：胶囊四周贴住栈，数字变长时一起变宽。
    UIView *actions = [store pinGlassFor:top in:top shape:DKChatGlassShapeRounded radius:kDKListenTopRowHeight * 0.5 interactive:YES
                             constraints:^NSArray<NSLayoutConstraint *> *(UIView *glass) {
        return @[
            [glass.leadingAnchor constraintEqualToAnchor:top.leadingAnchor constant:-kDKListenRowInset],
            [glass.trailingAnchor constraintEqualToAnchor:top.trailingAnchor constant:kDKListenRowInset],
            [glass.centerYAnchor constraintEqualToAnchor:top.centerYAnchor],
            [glass.heightAnchor constraintEqualToConstant:kDKListenTopRowHeight],
        ];
    }];
    [layer addRegionForGlass:actions targets:top.arrangedSubviews];

    // 倍速：玻璃挂在按钮里，原生隐藏按钮时跟着隐藏；右缘对齐屏幕边距。
    UIView *lastRight = topRight.arrangedSubviews.lastObject;
    for (UIView *button in topRight.arrangedSubviews) {
        [store clearBackingOfView:button];
        DKListenGlassSetUnclipped(button, YES);
        [layer addRegionForGlass:DKListenPinRound(store, button, kDKListenTopRowHeight) targets:@[ button ]];
    }
    if (lastRight) {
        [topRight layoutIfNeeded];
        CGFloat center = CGRectGetMinX(DKAdjustLayoutFrame(topRight)) + CGRectGetMidX(lastRight.frame);
        CGFloat target = CGRectGetWidth(control.bounds) - kDKListenRowInset - kDKListenTopRowHeight * 0.5;
        DKAdjustTransform(topRight, CGAffineTransformMakeTranslation(target - center, 0.0));
    }

    // 底排：后退、播放、前进合成胶囊，其余各一个圆钮。
    UIButton *rewind = control.rewindButton;
    UIButton *forward = control.forwardButton;
    for (UIView *item in bottom.arrangedSubviews) {
        if (item == rewind || item == forward || item == control.playButton) continue;
        [layer addRegionForGlass:DKListenPinRound(store, item, kDKListenBottomRowHeight) targets:@[ item ]];
    }
    if (rewind.superview == bottom && forward.superview == bottom && control.playButton.superview == bottom) {
        UIView *playback = [store pinGlassFor:control.playButton in:bottom shape:DKChatGlassShapeRounded
                                       radius:kDKListenBottomRowHeight * 0.5 interactive:YES
                                  constraints:^NSArray<NSLayoutConstraint *> *(UIView *glass) {
            return @[
                [glass.leadingAnchor constraintEqualToAnchor:rewind.centerXAnchor constant:-kDKListenPlaybackPadding],
                [glass.trailingAnchor constraintEqualToAnchor:forward.centerXAnchor constant:kDKListenPlaybackPadding],
                [glass.centerYAnchor constraintEqualToAnchor:bottom.centerYAnchor],
                [glass.heightAnchor constraintEqualToConstant:kDKListenBottomRowHeight],
            ];
        }];
        [layer addRegionForGlass:playback targets:@[ rewind, control.playButton, forward ]];
    }

    // 长按快进提示：原生圆角底板不在栈的排列里、盖在文字上方。玻璃挂到栈的最底层贴住底板，否则会折射自己上面的文字。
    UIStackView *fast = control.fastModeStackView;
    for (UIView *child in fast.subviews) {
        if ([fast.arrangedSubviews containsObject:child] || child.layer.cornerRadius <= 0.0) continue;
        [store clearBackingOfView:child];
        [store pinGlassFor:child in:fast shape:DKChatGlassShapeRounded radius:child.layer.cornerRadius interactive:NO
               constraints:^NSArray<NSLayoutConstraint *> *(UIView *glass) {
            return @[
                [glass.topAnchor constraintEqualToAnchor:child.topAnchor],
                [glass.leadingAnchor constraintEqualToAnchor:child.leadingAnchor],
                [glass.trailingAnchor constraintEqualToAnchor:child.trailingAnchor],
                [glass.bottomAnchor constraintEqualToAnchor:child.bottomAnchor],
            ];
        }];
    }
}

API_AVAILABLE(ios(26.0))
static void DKListenSyncProgress(DKChatGlassStore *store, AWEListenFeedPlayControlView *control) {
    Class progressClass = objc_getClass("AWEListenFeedSideLabelProgressViewV2");
    if (![control.progressView isKindOfClass:progressClass]) return;
    AWEListenFeedSideLabelProgressViewV2 *progress = (id)control.progressView;
    UIView *line = progress.progressCenterYView;
    if (line.superview != progress) return;

    // 单行胶囊放在互动行与底排之间的正中。
    CGFloat topEdge = CGRectGetMidY(DKAdjustLayoutFrame(control.topStackView)) + kDKListenTopRowHeight * 0.5;
    CGFloat bottomEdge = CGRectGetMidY(DKAdjustLayoutFrame(control.bottomStackView)) - kDKListenBottomRowHeight * 0.5;
    DKListenProgressLayout(progress, YES, (topEdge + bottomEdge) * 0.5 - CGRectGetMinY(DKAdjustLayoutFrame(progress)));

    [store pinGlassFor:progress.progressSlider in:progress shape:DKChatGlassShapeRounded
                radius:kDKListenProgressHeight * 0.5 interactive:NO
           constraints:^NSArray<NSLayoutConstraint *> *(UIView *glass) {
        return @[
            [glass.leadingAnchor constraintEqualToAnchor:progress.leadingAnchor constant:kDKListenRowInset],
            [glass.trailingAnchor constraintEqualToAnchor:progress.trailingAnchor constant:-kDKListenRowInset],
            [glass.centerYAnchor constraintEqualToAnchor:line.centerYAnchor],
            [glass.heightAnchor constraintEqualToConstant:kDKListenProgressHeight],
        ];
    }];
}

API_AVAILABLE(ios(26.0))
static void DKListenControlRestore(AWEListenFeedPlayControlView *control) {
    if (![DKChatGlassStore storeForOwner:control create:NO]) return;
    [DKChatGlassStore removeStoreForOwner:control];
    [DKListenHitLayer removeFromHost:control];
    DKAdjustTransform(control.topRightStackView, CGAffineTransformIdentity);
    for (UIView *button in control.topRightStackView.arrangedSubviews) DKListenGlassSetUnclipped(button, NO);
    if ([control.progressView isKindOfClass:objc_getClass("AWEListenFeedSideLabelProgressViewV2")]) {
        DKListenProgressLayout((id)control.progressView, NO, 0.0);
    }
}

static void DKListenControlSync(AWEListenFeedPlayControlView *control) {
    if (@available(iOS 26.0, *)) {
        if (!DKListenGlassOn()) {
            DKListenControlRestore(control);
            return;
        }
        DKChatGlassStore *store = [DKChatGlassStore storeForOwner:control create:YES];
        if (store.syncing) return;
        DKListenHitLayer *layer = [DKListenHitLayer layerInHost:control create:YES];
        // 透明层在最上方：胶囊内原生按钮之间的空隙也要分给最近的按钮。
        if (control.subviews.lastObject != layer) [control addSubview:layer];
        [layer removeAllRegions];
        DKListenGlassBegin(store);
        DKListenSyncRows(store, layer, control);
        DKListenSyncProgress(store, control);
        [store end];
    }
}

void DKListenControlGlassRefresh(void) {
    for (AWEListenFeedPlayControlView *control in gDKListenControls.allObjects) DKListenControlSync(control);
}

%group DKListenGlassControlHooks

%hook AWEListenFeedPlayControlView

- (void)layoutSubviews {
    %orig;
    [gDKListenControls addObject:self];
    DKListenControlSync(self);
}

// 原生换倍速文案时重写按钮底色，按钮宽度也会变。首次调用在 setupUI 内、底排组装之前，所以只标记重排。
- (void)updateTextSpeedButton:(id)button {
    %orig;
    if (DKListenGlassOn()) [self setNeedsLayout];
}

%end

// 时长变化后滑条要让出新的时间宽度。
%hook AWEListenFeedSideLabelProgressViewV2

- (void)updateCurrentTime:(double)current totalTime:(double)total {
    CGFloat before = self.remainTime.intrinsicContentSize.width;
    %orig;
    if (DKListenGlassOn() && self.remainTime.intrinsicContentSize.width != before) [self.superview setNeedsLayout];
}

%end

%end

%ctor {
    gDKListenControls = [NSHashTable weakObjectsHashTable];
    if (DKGlassOSAvailable()) %init(DKListenGlassControlHooks);
}
