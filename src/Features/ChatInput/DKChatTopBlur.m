//
//  DKChatTopBlur.m
//  DYKiller
//

#import "DKChatTopBlur.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static char kDKChatTopBlurKey;

API_AVAILABLE(ios(26.0))
@interface DKChatTopBlur : NSObject
@property (nonatomic, strong) UIVisualEffectView *view;
@property (nonatomic, strong) UIView *mask;
@property (nonatomic, strong) CAGradientLayer *gradient;
@property (nonatomic, weak) UIScrollView *table;
@property (nonatomic) BOOL nativeHidden;
- (void)restore;
@end

@implementation DKChatTopBlur
- (instancetype)init {
    if ((self = [super init])) {
        _view = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular]];
        _view.userInteractionEnabled = NO;
        _mask = [UIView new];
        _gradient = [CAGradientLayer layer];
        _gradient.colors = @[ (id)UIColor.blackColor.CGColor, (id)UIColor.clearColor.CGColor ];
        _gradient.startPoint = CGPointMake(0.5, 0.0);
        _gradient.endPoint = CGPointMake(0.5, 1.0);
        [_mask.layer addSublayer:_gradient];
    }
    return self;
}
- (void)restore {
    if (self.table) self.table.topEdgeEffect.hidden = self.nativeHidden;
    self.table = nil;
    [self.view removeFromSuperview];
}
@end

void DKChatTopBlurSync(UIView *bar, UIScrollView *table, CGFloat bottom,
                       UIUserInterfaceStyle style, BOOL wanted) {
    if (!bar) return;
    DKChatTopBlur *blur = objc_getAssociatedObject(bar, &kDKChatTopBlurKey);
    UIView *parent = bar.superview;
    UIView *list = table;
    while (list.superview && list.superview != parent) list = list.superview;
    if (!wanted || !table || !parent || list.superview != parent || bottom <= 0.0) {
        [blur restore];
        objc_setAssociatedObject(bar, &kDKChatTopBlurKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (!blur) {
        blur = [DKChatTopBlur new];
        objc_setAssociatedObject(bar, &kDKChatTopBlurKey, blur, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (blur.table != table) {
        [blur restore];
        blur.table = table;
        blur.nativeHidden = table.topEdgeEffect.hidden;
    }
    [UIView performWithoutAnimation:^{
        table.topEdgeEffect.hidden = YES;
        blur.view.overrideUserInterfaceStyle = style;
        CGFloat y = CGRectGetMinY(parent.bounds);
        CGFloat end = [bar convertPoint:CGPointMake(0.0, bottom) toView:parent].y;
        blur.view.frame = CGRectMake(CGRectGetMinX(parent.bounds), y, CGRectGetWidth(parent.bounds), MAX(0.0, end - y));
        if (!CGRectEqualToRect(blur.mask.frame, blur.view.bounds) || !blur.view.maskView) {
            blur.mask.frame = blur.view.bounds;
            blur.gradient.frame = blur.mask.bounds;
            blur.view.maskView = blur.mask;
        }
        [parent insertSubview:blur.view aboveSubview:list];
    }];
}
