// iPad 进度条按原生左右约束让位，记录自己施加的增量并在退出时复位。
#import "DKProgressPadTime.h"
#import "DouyinHeaders.h"
#import <objc/runtime.h>
#import <math.h>

@interface DKPadTimeInsets : NSObject
@property (nonatomic, weak) NSLayoutConstraint *left;
@property (nonatomic, weak) NSLayoutConstraint *right;
@property (nonatomic) CGFloat baseLeft;
@property (nonatomic) CGFloat baseRight;
@property (nonatomic) CGFloat lastLeft;
@property (nonatomic) CGFloat lastRight;
@property (nonatomic) CGFloat inset;
@end
@implementation DKPadTimeInsets
@end

static char kDKPadTimeInsetsKey;
static BOOL DKPadTimeEqual(CGFloat a, CGFloat b) { return fabs(a - b) < 0.001; }

static void DKPadTimeRestore(DKPadTimeInsets *state) {
    if (state.left && DKPadTimeEqual(state.left.constant, state.lastLeft)) state.left.constant = state.baseLeft;
    if (state.right && DKPadTimeEqual(state.right.constant, state.lastRight)) state.right.constant = state.baseRight;
}

BOOL DKProgressPadTimeSync(UIView *slider, CGFloat inset, BOOL wakeup) {
    if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad || !slider) return NO;
    DKPadTimeInsets *state = objc_getAssociatedObject(slider, &kDKPadTimeInsetsKey);
    NSLayoutConstraint *left = nil, *right = nil;
    UIView *parent = slider.superview;
    if (!slider.translatesAutoresizingMaskIntoConstraints) {
        for (NSLayoutConstraint *constraint in parent.constraints) {
            if (!constraint.active || constraint.firstItem != slider || constraint.secondItem != parent
                || constraint.relation != NSLayoutRelationEqual || constraint.multiplier != 1
                || constraint.firstAttribute != constraint.secondAttribute) continue;
            if (constraint.firstAttribute == NSLayoutAttributeLeft) left = constraint;
            if (constraint.firstAttribute == NSLayoutAttributeRight) right = constraint;
        }
    }
    if (state && (state.left != left || state.right != right || inset <= 0)) {
        DKPadTimeRestore(state);
        objc_setAssociatedObject(slider, &kDKPadTimeInsetsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        state = nil;
    }
    if (!left || !right) return NO;
    if (inset <= 0) return YES;
    // 拖动期间保持已有边距；新的样式或作品宽度在回到常态后生效。
    if (wakeup && (!state || !DKPadTimeEqual(state.inset, inset))) return YES;
    if (!state) {
        state = [DKPadTimeInsets new];
        state.left = left; state.right = right;
        state.baseLeft = state.lastLeft = left.constant;
        state.baseRight = state.lastRight = right.constant;
        objc_setAssociatedObject(slider, &kDKPadTimeInsetsKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // 宿主重写约束时，以新原值重新叠加，不累计上一轮增量。
    if (!DKPadTimeEqual(left.constant, state.lastLeft)) state.baseLeft = left.constant;
    if (!DKPadTimeEqual(right.constant, state.lastRight)) state.baseRight = right.constant;
    state.lastLeft = state.baseLeft + inset;
    state.lastRight = state.baseRight - inset;
    state.inset = inset;
    if (!DKPadTimeEqual(left.constant, state.lastLeft)) left.constant = state.lastLeft;
    if (!DKPadTimeEqual(right.constant, state.lastRight)) right.constant = state.lastRight;
    return YES;
}

static CGFloat DKProgressPadTimeWidth(UIView *slider) {
    DKPadTimeInsets *state = objc_getAssociatedObject(slider, &kDKPadTimeInsetsKey);
    if (!state.left.active || !state.right.active) return 0;
    return MAX(0, CGRectGetWidth(slider.superview.bounds) - state.left.constant + state.right.constant);
}

%group DKProgressPadTimeHooks
%hook AWEDProgressChapterContainer
- (double)progressWidth {
    CGFloat width = DKProgressPadTimeWidth([self progressSlider]);
    return width > 0 ? width : %orig;
}
%end
%end

%ctor {
    if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad) return;
    Class chapter = NSClassFromString(@"AWEDProgressChapterContainer");
    if (!class_getInstanceMethod(chapter, @selector(progressWidth))
        || !class_getInstanceMethod(chapter, @selector(progressSlider))) return;
    %init(DKProgressPadTimeHooks);
}
