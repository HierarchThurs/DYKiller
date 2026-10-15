//
//  DKTabBarAppearance.xm
//  功能：外观定制 —— 底栏文字、原生底栏的图标模式、原生拍摄按钮。
//
//  实现：
//   - 文字：在 AWENormalModeTabBarTextView 的 layoutSubviews 之前按 label 同步。每个文字视图记两份：
//     original（抖音给的原文）与 written（写进去的自定义文字）；label 不等于 written 即视为抖音给了新值，
//     记为原文后再写自定义文字，%orig 按新文字排版。原文对外仍可读（currentTitleText / accessibilityLabel），
//     其他按标题认人的逻辑不受影响。悬浮玻璃底栏读 label，自然跟随。
//   - 图标模式：按钮里插一层不接收触摸的覆盖层（图标，图标+文字时另加一行小字），位于文字视图之上、角标之下；
//     文字视图挂空 mask 隐藏，alpha / hidden 仍归抖音，抖音显示特殊内容（隐藏文字视图）时覆盖层随之让位。
//     着色取抖音为该按钮算好的文字色，选中（status == 2）用实心图。
//   - 拍摄按钮：抖音的图片视图挂空 mask，上面放照相机或自定义图片；颜色取选中 tab 的文字色。
//   - 悬浮玻璃底栏开启时抖音按钮整体透明，覆盖层不可见；关掉玻璃后原样露出，不需要额外切换。
//

#import "DKTabBarAppearance.h"
#import "DKTabBarIcons.h"
#import "DKTabBarRemoval.h"
#import "DKGlassTabBar.h"
#import "DKPlusIcon.h"
#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKUtils.h"

#import <objc/runtime.h>

// 原生按钮里的图标尺寸：单图标 28，图标+文字 24 + 10pt 文字。
static const CGFloat kDKIconOnlySide = 28.0;
static const CGFloat kDKIconTextSide = 24.0;
static const CGFloat kDKIconTextGap = 2.0;
static const CGFloat kDKIconTextFontSize = 10.0;
static const CGFloat kDKIconTextLineHeight = 12.0;
// 原生拍摄按钮：照相机 34pt，自定义圆形图 36pt。
static const CGFloat kDKPlusCameraSide = 34.0;
static const CGFloat kDKPlusCustomSide = 36.0;
// 抖音按钮的选中态。
static const long long kDKSelectedStatus = 2;

static char kDKTitleOriginalKey;
static char kDKTitleWrittenKey;
static char kDKOverlayKey;
static char kDKMaskKey;

static __weak AWENormalModeTabBar *gAppearanceBar = nil;

static id DKAppearanceValue(id object, NSString *key) {
    if (!object) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

#pragma mark - 取值

DKTabBarStyle DKTabBarCurrentStyle(void) {
    NSInteger value = DKPrefInteger(DKKeyTabBarStyle);
    return value >= DKTabBarStyleDefault && value <= DKTabBarStyleIconText ? (DKTabBarStyle)value : DKTabBarStyleDefault;
}

DKPlusStyle DKPlusCurrentStyle(void) {
    NSInteger value = DKPrefInteger(DKKeyPlusStyle);
    if (value < DKPlusStyleDefault || value > DKPlusStyleCustom) return DKPlusStyleDefault;
    if (value == DKPlusStyleCustom && !DKPlusIconCustom()) return DKPlusStyleDefault;
    return (DKPlusStyle)value;
}

NSString *DKTabBarCustomTitle(NSString *tabID) {
    if (tabID.length == 0) return nil;
    id value = [NSUserDefaults.standardUserDefaults objectForKey:[DKKeyTabTitlePrefix stringByAppendingString:tabID]];
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *text = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return text.length ? text : nil;
}

#pragma mark - 空 mask

// 挂上或摘掉自己的空 mask；摘时只摘自己挂的，已有的其他 mask 不覆盖。
static void DKAppearanceSetMasked(UIView *view, BOOL masked) {
    if (!view) return;
    CALayer *ours = objc_getAssociatedObject(view, &kDKMaskKey);
    if (!masked) {
        if (!ours) return;
        if (view.layer.mask == ours) view.layer.mask = nil;
        objc_setAssociatedObject(view, &kDKMaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (view.layer.mask && view.layer.mask != ours) return;
    if (!ours) {
        ours = [CALayer layer];
        objc_setAssociatedObject(view, &kDKMaskKey, ours, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (view.layer.mask != ours) view.layer.mask = ours;
}

#pragma mark - 文字

static UIView *DKOwningButton(UIView *view) {
    Class buttonClass = NSClassFromString(@"AWENormalModeTabBarButton");
    for (UIView *current = view.superview; current; current = current.superview) {
        if (buttonClass && [current isKindOfClass:buttonClass]) return current;
    }
    return nil;
}

static void DKApplyTitle(UIView *textView) {
    UILabel *label = DKAppearanceValue(textView, @"label");
    if (![label isKindOfClass:UILabel.class]) return;
    NSString *custom = DKTabBarCustomTitle(DKTabBarButtonTabID(DKOwningButton(textView)));
    NSString *written = objc_getAssociatedObject(textView, &kDKTitleWrittenKey);
    NSString *text = label.text;

    // label 不是我们写的值：抖音（或其他插件）给了新文字，记为原文。
    if (!written || ![text isEqualToString:written]) {
        if (written || custom) {
            objc_setAssociatedObject(textView, &kDKTitleOriginalKey, text, OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
        written = nil;
    }

    if (custom) {
        if (![text isEqualToString:custom]) label.text = custom;
        objc_setAssociatedObject(textView, &kDKTitleWrittenKey, custom, OBJC_ASSOCIATION_COPY_NONATOMIC);
        return;
    }
    NSString *original = objc_getAssociatedObject(textView, &kDKTitleOriginalKey);
    if (written && original && ![text isEqualToString:original]) label.text = original;
    objc_setAssociatedObject(textView, &kDKTitleWrittenKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(textView, &kDKTitleOriginalKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

static NSString *DKOriginalTitle(UIView *textView) {
    if (!objc_getAssociatedObject(textView, &kDKTitleWrittenKey)) return nil;
    return objc_getAssociatedObject(textView, &kDKTitleOriginalKey);
}

#pragma mark - 原生图标模式

@interface DKTabIconOverlay : UIView
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@end

@implementation DKTabIconOverlay
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_iconView];
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:kDKIconTextFontSize weight:UIFontWeightSemibold];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_titleLabel];
    }
    return self;
}
@end

static void DKRemoveOverlay(UIView *host, UIView *masked) {
    UIView *overlay = objc_getAssociatedObject(host, &kDKOverlayKey);
    [overlay removeFromSuperview];
    objc_setAssociatedObject(host, &kDKOverlayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKAppearanceSetMasked(masked, NO);
}

static void DKSetFrame(UIView *view, CGRect frame) {
    if (!CGRectEqualToRect(view.frame, frame)) view.frame = frame;
}

static void DKApplyIconOverlay(UIView *button) {
    UIView *inner = DKAppearanceValue(button, @"innerView");
    if (![inner isKindOfClass:UIView.class]) inner = nil;
    NSString *tabID = DKTabBarButtonTabID(button);
    DKTabBarStyle style = DKTabBarCurrentStyle();
    if (style == DKTabBarStyleDefault || !inner || !DKTabBarHasIcon(tabID)) {
        DKRemoveOverlay(button, inner);
        return;
    }

    DKTabIconOverlay *overlay = objc_getAssociatedObject(button, &kDKOverlayKey);
    if (!overlay) {
        overlay = [[DKTabIconOverlay alloc] initWithFrame:button.bounds];
        objc_setAssociatedObject(button, &kDKOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // 紧贴在文字视图之上：仍在角标容器之下。
    if (inner.superview == button) {
        NSUInteger innerIndex = [button.subviews indexOfObjectIdenticalTo:inner];
        if (overlay.superview != button || [button.subviews indexOfObjectIdenticalTo:overlay] != innerIndex + 1) {
            [button insertSubview:overlay aboveSubview:inner];
        }
    } else if (overlay.superview != button) {
        [button addSubview:overlay];
    }
    DKAppearanceSetMasked(inner, YES);

    // 抖音隐藏文字视图（显示运营图、刷新动画等）时让位。
    BOOL visible = !inner.isHidden && inner.alpha > 0.01;
    if (overlay.isHidden == visible) overlay.hidden = !visible;

    UILabel *source = DKAppearanceValue(inner, @"label");
    UIColor *color = [source isKindOfClass:UILabel.class] && source.textColor ? source.textColor : UIColor.whiteColor;
    BOOL selected = [DKAppearanceValue(button, @"status") longLongValue] == kDKSelectedStatus;
    BOOL withText = style == DKTabBarStyleIconText;

    CGRect bounds = button.bounds;
    DKSetFrame(overlay, bounds);
    CGFloat side = withText ? kDKIconTextSide : kDKIconOnlySide;
    CGFloat contentHeight = withText ? side + kDKIconTextGap + kDKIconTextLineHeight : side;
    CGFloat top = floor((CGRectGetHeight(bounds) - contentHeight) / 2.0);
    DKSetFrame(overlay.iconView, CGRectMake(floor((CGRectGetWidth(bounds) - side) / 2.0), top, side, side));

    UIImage *image = DKTabBarIconTemplate(tabID, selected, side);
    if (overlay.iconView.image != image) overlay.iconView.image = image;
    if (![overlay.iconView.tintColor isEqual:color]) overlay.iconView.tintColor = color;

    overlay.titleLabel.hidden = !withText;
    if (withText) {
        NSString *title = [source isKindOfClass:UILabel.class] ? source.text : nil;
        if (![overlay.titleLabel.text isEqualToString:title]) overlay.titleLabel.text = title;
        if (![overlay.titleLabel.textColor isEqual:color]) overlay.titleLabel.textColor = color;
        DKSetFrame(overlay.titleLabel, CGRectMake(0, top + side + kDKIconTextGap, CGRectGetWidth(bounds), kDKIconTextLineHeight));
    }
}

#pragma mark - 原生拍摄按钮

@interface DKPlusOverlay : UIView
@property (nonatomic, strong) UIImageView *accentView;
@property (nonatomic, strong) UIImageView *bodyView;
@end

@implementation DKPlusOverlay
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        _accentView = [[UIImageView alloc] init];
        _bodyView = [[UIImageView alloc] init];
        _accentView.contentMode = UIViewContentModeScaleAspectFit;
        _bodyView.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_accentView];
        [self addSubview:_bodyView];
    }
    return self;
}
@end

// 选中 tab 的文字色（alpha 拉满）：抖音按页面底色算好的前景色，拍摄图标与它同色。
static UIColor *DKSelectedTitleColor(AWENormalModeTabBar *bar) {
    for (id button in DKAppearanceValue(bar, @"tabBarButtons")) {
        if ([DKAppearanceValue(button, @"status") longLongValue] != kDKSelectedStatus) continue;
        UILabel *label = DKAppearanceValue(DKAppearanceValue(button, @"innerView"), @"label");
        if (![label isKindOfClass:UILabel.class] || !label.textColor) continue;
        return [label.textColor colorWithAlphaComponent:1.0];
    }
    return UIColor.whiteColor;
}

// 抖音的拍摄图标视图：按钮下第一个 UIImageView（覆盖层是普通 UIView，不会被认成它）。
static UIImageView *DKPlusSourceImageView(UIView *button) {
    for (UIView *subview in button.subviews) {
        if ([subview isKindOfClass:UIImageView.class]) return (UIImageView *)subview;
    }
    return nil;
}

static void DKApplyPlusOverlay(UIView *button, AWENormalModeTabBar *bar) {
    UIImageView *source = DKPlusSourceImageView(button);
    DKPlusStyle style = DKPlusCurrentStyle();
    if (style == DKPlusStyleDefault || !source) {
        DKRemoveOverlay(button, source);
        return;
    }

    DKPlusOverlay *overlay = objc_getAssociatedObject(button, &kDKOverlayKey);
    if (!overlay) {
        overlay = [[DKPlusOverlay alloc] initWithFrame:button.bounds];
        objc_setAssociatedObject(button, &kDKOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (overlay.superview != button) [button insertSubview:overlay aboveSubview:source];
    DKAppearanceSetMasked(source, YES);

    CGRect bounds = button.bounds;
    DKSetFrame(overlay, bounds);
    CGFloat side = style == DKPlusStyleCustom ? kDKPlusCustomSide : kDKPlusCameraSide;
    CGRect frame = CGRectMake(floor((CGRectGetWidth(bounds) - side) / 2.0), floor((CGRectGetHeight(bounds) - side) / 2.0), side, side);
    DKSetFrame(overlay.accentView, frame);
    DKSetFrame(overlay.bodyView, frame);

    UIImage *accent = style == DKPlusStyleBrand ? DKTabBarCameraAccent(side) : nil;
    if (overlay.accentView.image != accent) overlay.accentView.image = accent;
    UIImage *body = style == DKPlusStyleCustom ? DKPlusIconCustom() : DKTabBarCameraTemplate(side);
    if (overlay.bodyView.image != body) overlay.bodyView.image = body;
    if (style != DKPlusStyleCustom) {
        UIColor *ink = DKSelectedTitleColor(bar);
        if (![overlay.bodyView.tintColor isEqual:ink]) overlay.bodyView.tintColor = ink;
    }
}

#pragma mark - 应用

static BOOL DKIsPlusButton(id button) {
    Class plusClass = NSClassFromString(@"AWENormalModeTabBarGeneralPlusInnerButton");
    return (plusClass && [button isKindOfClass:plusClass]) ||
           [DKTabBarButtonTabID(button) isEqualToString:@"homepage_publish"];
}

static void DKApplyBar(AWENormalModeTabBar *bar) {
    if (!bar) return;
    for (id button in DKAppearanceValue(bar, @"tabBarButtons")) {
        if (![button isKindOfClass:UIView.class]) continue;
        if (DKIsPlusButton(button)) DKApplyPlusOverlay(button, bar);
        else DKApplyIconOverlay(button);
    }
}

void DKTabBarAppearanceRefresh(void) {
    AWENormalModeTabBar *bar = gAppearanceBar;
    if (!bar) return;
    for (id button in DKAppearanceValue(bar, @"tabBarButtons")) {
        UIView *inner = DKAppearanceValue(button, @"innerView");
        if ([inner isKindOfClass:UIView.class]) {
            DKApplyTitle(inner);
            [inner setNeedsLayout];
        }
        if ([button isKindOfClass:UIView.class]) [(UIView *)button setNeedsLayout];
    }
    DKApplyBar(bar);
    [bar setNeedsLayout];
    DKGlassTabBarRefresh();
}

NSString *DKTabBarAppearanceStatus(void) {
    static NSArray<NSString *> *styles, *plusStyles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        styles = @[ @"默认", @"单图标", @"图标+文字" ];
        plusStyles = @[ @"默认", @"新图标", @"新双色图标", @"自定义图片" ];
    });
    NSMutableString *out = [NSMutableString string];
    NSInteger plusSetting = DKPrefInteger(DKKeyPlusStyle);
    [out appendFormat:@"底栏样式 = %@ · 拍摄按钮 = %@（设置 %ld）\n", styles[DKTabBarCurrentStyle()],
     plusStyles[DKPlusCurrentStyle()], (long)plusSetting];
    AWENormalModeTabBar *bar = gAppearanceBar;
    for (id button in DKAppearanceValue(bar, @"tabBarButtons")) {
        UIView *inner = DKAppearanceValue(button, @"innerView");
        UILabel *label = DKAppearanceValue(inner, @"label");
        UIView *overlay = objc_getAssociatedObject(button, &kDKOverlayKey);
        NSString *tabID = DKTabBarButtonTabID(button);
        [out appendFormat:@"  %@ 文字=%@ 原文=%@ 自定义=%@ 覆盖层=%@ 蒙版=%@\n", tabID ?: @"(nil)",
         [label isKindOfClass:UILabel.class] ? label.text : @"-", DKOriginalTitle(inner) ?: @"-",
         DKTabBarCustomTitle(tabID) ?: @"-", overlay ? (overlay.isHidden ? @"隐藏" : @"显示") : @"无",
         objc_getAssociatedObject(inner, &kDKMaskKey) || objc_getAssociatedObject(DKPlusSourceImageView(button), &kDKMaskKey)
             ? @"有" : @"无"];
    }
    return out;
}

#pragma mark - Hook

%hook AWENormalModeTabBar

- (void)layoutSubviews {
    %orig;
    gAppearanceBar = self;
    DKApplyBar(self);
}

// 首页与其他页之间的明暗渐变逐帧改写文字色，图标跟着同步。
- (void)switchToLightModeWithProgress:(double)progress businessID:(id)businessID {
    %orig;
    DKApplyBar(self);
}

%end

%hook AWENormalModeTabBarGeneralButton

- (void)layoutSubviews {
    %orig;
    DKApplyIconOverlay((UIView *)self);
}

- (void)switchToLightModeWithProgress:(double)progress {
    %orig;
    DKApplyIconOverlay((UIView *)self);
}

%end

%hook AWENormalModeTabBarGeneralPlusInnerButton

- (void)layoutSubviews {
    %orig;
    DKApplyPlusOverlay((UIView *)self, gAppearanceBar);
}

- (void)setLightMode:(BOOL)lightMode {
    %orig;
    DKApplyPlusOverlay((UIView *)self, gAppearanceBar);
}

%end

%hook AWENormalModeTabBarTextView

// 写在 %orig 之前：抖音随后按新文字排版。
- (void)layoutSubviews {
    DKApplyTitle((UIView *)self);
    %orig;
}

- (void)textColorChangedWithSelectedStatus:(BOOL)selected {
    %orig;
    DKApplyBar(gAppearanceBar);
}

- (void)tabbarStatusDidChanged:(long long)status animated:(BOOL)animated {
    %orig;
    DKApplyBar(gAppearanceBar);
}

- (id)currentTitleText {
    return DKOriginalTitle((UIView *)self) ?: %orig;
}

- (id)accessibilityLabel {
    return DKOriginalTitle((UIView *)self) ?: %orig;
}

%end

%ctor {
    %init;
}
