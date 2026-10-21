#import "DKPromptView.h"
#import "DKGlassFlexView.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#import <math.h>

typedef NS_ENUM(NSInteger, DKPromptMaterial) {
    DKPromptMaterialBlur,
    DKPromptMaterialRegular,
    DKPromptMaterialClear,
};

static UIColor *DKPromptColor(uint32_t hex, CGFloat alpha) {
    return [UIColor colorWithRed:((hex >> 16) & 255) / 255.0 green:((hex >> 8) & 255) / 255.0
                            blue:(hex & 255) / 255.0 alpha:alpha];
}

static UILabel *DKPromptLabel(CGFloat size, UIFontWeight weight, NSInteger lines) {
    UILabel *label = [UILabel new];
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = lines;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

static void DKPromptSetText(UILabel *label, NSString *text, CGFloat lineHeight) {
    if (!text.length) {
        label.attributedText = nil;
        label.text = nil;
        return;
    }
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = NSTextAlignmentCenter;
    paragraph.minimumLineHeight = lineHeight;
    paragraph.maximumLineHeight = lineHeight;
    paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
    label.attributedText = [[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName:label.font, NSParagraphStyleAttributeName:paragraph
    }];
}

static CGFloat DKPromptTextWidth(NSString *text, UIFont *font) {
    return ceil([text sizeWithAttributes:@{NSFontAttributeName:font}].width);
}

static CGFloat DKPromptTextHeight(UILabel *label, CGFloat width, CGFloat lineHeight) {
    if (!label.text.length) return 0.0;
    CGSize size = [label.text boundingRectWithSize:CGSizeMake(MAX(1.0, width), CGFLOAT_MAX)
                                         options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                      attributes:@{NSFontAttributeName:label.font} context:nil].size;
    NSInteger lines = MAX(1, (NSInteger)ceil(size.height / label.font.lineHeight));
    return MIN(lines, label.numberOfLines) * lineHeight;
}

// 持续观察触摸，不取消按钮或整卡点按的事件。
@interface DKPromptTouchRecognizer : UIGestureRecognizer
@property (nonatomic, strong) NSMutableSet<UITouch *> *trackedTouches;
@end

@implementation DKPromptTouchRecognizer
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!self.trackedTouches) self.trackedTouches = [NSMutableSet set];
    [self.trackedTouches unionSet:touches];
    self.state = self.state == UIGestureRecognizerStatePossible ? UIGestureRecognizerStateBegan : UIGestureRecognizerStateChanged;
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    self.state = UIGestureRecognizerStateChanged;
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.trackedTouches minusSet:touches];
    self.state = self.trackedTouches.count ? UIGestureRecognizerStateChanged : UIGestureRecognizerStateEnded;
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.trackedTouches removeAllObjects];
    self.state = UIGestureRecognizerStateCancelled;
}
- (void)reset {
    [super reset];
    [self.trackedTouches removeAllObjects];
}
@end

@interface DKPromptView () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIView *shadowView;
@property (nonatomic, strong) DKGlassFlexView *material;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIView *iconWell;
@property (nonatomic, strong) UIImageView *glyph;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *progressLabel;
@property (nonatomic, strong) UIView *track;
@property (nonatomic, strong) UIView *fill;
@property (nonatomic, strong) NSArray<UIButton *> *buttons;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSArray<NSString *> *> *armedActions;
@property (nonatomic, strong) DKPromptContent *displayContent;
@property (nonatomic, strong) UITapGestureRecognizer *cardTap;
@property (nonatomic, strong) DKPromptTouchRecognizer *touchObserver;
@property (nonatomic, strong) UIView *transitionSnapshot;
@property (nonatomic) DKPromptMaterial materialKind;
@property (nonatomic) UIUserInterfaceStyle style;
@property (nonatomic) BOOL presented;
@property (nonatomic) BOOL hasCardAction;
@property (nonatomic) BOOL interacting;
@property (nonatomic) NSUInteger generation;
@property (nonatomic, copy) NSString *appliedIdentifier;
@property (nonatomic) CGFloat indeterminateTrackWidth;
@property (nonatomic) CGFloat indeterminateFillWidth;
@end

@implementation DKPromptView

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _disabledActions = [NSSet set];
    _armedActions = [NSMutableDictionary dictionary];
    _shadowView = [UIView new];
    _shadowView.userInteractionEnabled = NO;
    _shadowView.layer.shadowColor = UIColor.blackColor.CGColor;
    _shadowView.layer.shadowOffset = CGSizeMake(0.0, 12.0);
    _shadowView.layer.shadowRadius = 14.0;
    [self addSubview:_shadowView];

    _material = [[DKGlassFlexView alloc] initWithEffect:nil];
    _material.userInteractionEnabled = NO;
    _material.flexSourceView = self;
    [self addSubview:_material];
    _contentView = [UIView new];
    _contentView.layer.cornerRadius = 21.0;
    _contentView.clipsToBounds = YES;
    [self addSubview:_contentView];

    _iconWell = [UIView new];
    _iconWell.layer.cornerRadius = 13.5;
    _iconWell.userInteractionEnabled = NO;
    [_contentView addSubview:_iconWell];
    _glyph = [UIImageView new];
    [_iconWell addSubview:_glyph];
    _titleLabel = DKPromptLabel(13.0, UIFontWeightSemibold, 2);
    _subtitleLabel = DKPromptLabel(11.0, UIFontWeightRegular, 4);
    _progressLabel = DKPromptLabel(11.0, UIFontWeightRegular, 1);
    for (UILabel *label in @[_titleLabel, _subtitleLabel, _progressLabel]) [_contentView addSubview:label];
    _track = [UIView new];
    _track.layer.cornerRadius = 1.5;
    _track.clipsToBounds = YES;
    _track.userInteractionEnabled = NO;
    _fill = [UIView new];
    _fill.backgroundColor = DKPromptColor(0x0A84FF, 1.0);
    [_track addSubview:_fill];
    [_contentView addSubview:_track];

    NSMutableArray *buttons = [NSMutableArray array];
    for (NSUInteger index = 0; index < 2; index++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = index;
        button.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
        button.contentEdgeInsets = UIEdgeInsetsMake(6.0, 8.0, 6.0, 8.0);
        button.layer.cornerRadius = 12.0;
        button.clipsToBounds = YES;
        button.titleLabel.numberOfLines = 2;
        button.titleLabel.textAlignment = NSTextAlignmentCenter;
        button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [button addTarget:self action:@selector(dk_buttonPressed:) forControlEvents:UIControlEventTouchDown];
        [button addTarget:self action:@selector(dk_buttonCancelled:) forControlEvents:UIControlEventTouchCancel | UIControlEventTouchUpOutside];
        [button addTarget:self action:@selector(dk_buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_contentView addSubview:button];
        [buttons addObject:button];
    }
    _buttons = buttons;
    _cardTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dk_cardTapped:)];
    _cardTap.delegate = self;
    [_contentView addGestureRecognizer:_cardTap];
    _touchObserver = [[DKPromptTouchRecognizer alloc] initWithTarget:self action:@selector(dk_touchChanged:)];
    _touchObserver.delegate = self;
    _touchObserver.cancelsTouchesInView = NO;
    _touchObserver.delaysTouchesBegan = NO;
    _touchObserver.delaysTouchesEnded = NO;
    [self addGestureRecognizer:_touchObserver];
    return self;
}

- (void)setDisabledActions:(NSSet<NSString *> *)disabledActions {
    _disabledActions = [disabledActions copy] ?: [NSSet set];
    [self dk_updateActions];
}

- (void)setCardActionDisabled:(BOOL)cardActionDisabled {
    _cardActionDisabled = cardActionDisabled;
    [self dk_updateActions];
}

- (void)dk_updateActions {
    NSArray<DKPromptAction *> *actions = self.displayContent.actions;
    [self.buttons enumerateObjectsUsingBlock:^(UIButton *button, NSUInteger index, BOOL *stop) {
        DKPromptAction *action = index < actions.count ? actions[index] : nil;
        button.hidden = action == nil;
        button.enabled = action && ![self.disabledActions containsObject:action.identifier];
        [button setTitle:action.title forState:UIControlStateNormal];
        button.accessibilityIdentifier = action.identifier;
    }];
    self.cardTap.enabled = self.hasCardAction && !self.cardActionDisabled;
    self.isAccessibilityElement = actions.count == 0;
    self.accessibilityTraits = self.cardTap.enabled ? UIAccessibilityTraitButton : UIAccessibilityTraitStaticText;
    NSMutableArray<NSString *> *spoken = [NSMutableArray array];
    for (UILabel *label in @[self.titleLabel, self.subtitleLabel, self.progressLabel]) {
        if (label.text.length) [spoken addObject:label.text];
    }
    self.accessibilityLabel = [spoken componentsJoinedByString:@"，"];
}

- (void)dk_buttonPressed:(UIButton *)button {
    if ((NSUInteger)button.tag >= self.displayContent.actions.count) return;
    self.armedActions[@(button.tag)] = @[self.displayContent.actions[button.tag].identifier, self.sessionIdentifier ?: @""];
}

- (void)dk_buttonCancelled:(UIButton *)button {
    [self.armedActions removeObjectForKey:@(button.tag)];
}

- (void)dk_buttonTapped:(UIButton *)button {
    NSArray<NSString *> *armed = self.armedActions[@(button.tag)];
    [self.armedActions removeObjectForKey:@(button.tag)];
    if (!self.presented || !button.enabled || (NSUInteger)button.tag >= self.displayContent.actions.count) return;
    NSString *identifier = self.displayContent.actions[button.tag].identifier;
    // 业务在按下期间结束或更换按钮时，松开不能触发新状态的操作。
    if (armed && (![armed[0] isEqual:identifier] || ![armed[1] isEqual:(self.sessionIdentifier ?: @"")])) return;
    if ([self.disabledActions containsObject:identifier]) return;
    if (self.onAction) self.onAction(identifier);
}

- (void)dk_cardTapped:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateEnded && self.presented && self.cardTap.enabled && self.onAction) {
        self.onAction(nil);
    }
}

- (BOOL)accessibilityActivate {
    if (!self.presented || !self.cardTap.enabled || !self.onAction) return NO;
    self.onAction(nil);
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    if (recognizer != self.cardTap) return YES;
    for (UIView *view = touch.view; view && view != self; view = view.superview) {
        if ([view isKindOfClass:UIControl.class]) return NO;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)first shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)second {
    return first == self.touchObserver || second == self.touchObserver;
}

- (void)dk_setInteracting:(BOOL)active {
    if (self.interacting == active) return;
    self.interacting = active;
    if (self.onInteraction) self.onInteraction(active);
}

- (void)dk_touchChanged:(UIGestureRecognizer *)recognizer {
    BOOL active = recognizer.state == UIGestureRecognizerStateBegan || recognizer.state == UIGestureRecognizerStateChanged;
    [self dk_setInteracting:active && self.presented];
}

- (void)dk_endInteraction {
    [self.touchObserver.trackedTouches removeAllObjects];
    self.touchObserver.enabled = NO;
    self.touchObserver.enabled = YES;
    [self dk_setInteracting:NO];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) [self dk_endInteraction];
}

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    if (!self.superview) [self dk_endInteraction];
}

- (void)dk_configureMaterial {
    BOOL blur = self.materialKind == DKPromptMaterialBlur;
    self.material.overrideUserInterfaceStyle = self.materialKind == DKPromptMaterialClear ? UIUserInterfaceStyleUnspecified : self.style;
    self.material.layer.cornerRadius = blur ? 21.0 : 0.0;
    self.material.layer.cornerCurve = kCACornerCurveContinuous;
    self.material.clipsToBounds = blur;
    if (@available(iOS 26.0, *)) {
        self.material.cornerConfiguration =
            [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius fixedRadius:21.0]];
    }
}

- (UIVisualEffect *)dk_targetEffect {
    if (self.materialKind != DKPromptMaterialBlur && DKGlassOSAvailable()) {
        if (@available(iOS 26.0, *)) {
            BOOL clear = self.materialKind == DKPromptMaterialClear;
            UIGlassEffect *effect = [UIGlassEffect effectWithStyle:clear ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular];
            effect.tintColor = clear ? DKGlassTintForStyle(self.style) : nil;
            effect.interactive = YES;
            return effect;
        }
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterial];
}

- (void)dk_applyColors {
    BOOL lightInk = self.materialKind == DKPromptMaterialClear || self.style == UIUserInterfaceStyleDark;
    uint32_t well = 0x0A84FF, glyph = lightInk ? 0x62B5FF : 0x087BEA;
    CGFloat wellAlpha = lightInk ? 0.22 : 0.14;
    switch (self.displayContent.tone) {
        case DKPromptToneSuccess:
            well = 0x30D158; glyph = lightInk ? 0x63E58B : 0x1DAD4D; wellAlpha = lightInk ? 0.22 : 0.16; break;
        case DKPromptToneWarning:
            well = 0xFF9F0A; glyph = lightInk ? 0xFFD080 : 0xB86E00; break;
        case DKPromptToneFailure:
            well = 0xFF453A; glyph = lightInk ? 0xFF8A83 : 0xD92D25; break;
        case DKPromptToneCancelled:
            well = 0x787880; glyph = lightInk ? 0xB8B9C1 : 0x686A73; wellAlpha = lightInk ? 0.25 : 0.16; break;
        case DKPromptToneProcessing:
        case DKPromptToneInformation: break;
    }
    self.iconWell.backgroundColor = DKPromptColor(well, wellAlpha);
    self.glyph.tintColor = DKPromptColor(glyph, 1.0);
    self.titleLabel.textColor = lightInk ? [UIColor colorWithWhite:1.0 alpha:0.94] : DKPromptColor(0x17181D, 1.0);
    UIColor *secondary = lightInk ? [UIColor colorWithWhite:1.0 alpha:0.56] : DKPromptColor(0x161823, 0.58);
    self.subtitleLabel.textColor = secondary;
    self.progressLabel.textColor = secondary;
    self.track.backgroundColor = lightInk ? [UIColor colorWithWhite:1.0 alpha:0.16] : DKPromptColor(0x161823, 0.14);
    self.shadowView.hidden = self.materialKind != DKPromptMaterialBlur;
    self.shadowView.layer.shadowOpacity = self.style == UIUserInterfaceStyleDark ? 0.34 : 0.16;
    [self.buttons enumerateObjectsUsingBlock:^(UIButton *button, NSUInteger index, BOOL *stop) {
        if (index >= self.displayContent.actions.count) return;
        UIColor *color = self.displayContent.actions[index].destructive ? DKPromptColor(lightInk ? 0xFF8A83 : 0xD92D25, 1.0) : DKPromptColor(lightInk ? 0x62B5FF : 0x087BEA, 1.0);
        button.backgroundColor = [color colorWithAlphaComponent:lightInk ? 0.18 : 0.12];
        [button setTitleColor:color forState:UIControlStateNormal];
        [button setTitleColor:[color colorWithAlphaComponent:0.4] forState:UIControlStateDisabled];
    }];
}

- (CGFloat)dk_widthWithin:(CGFloat)maximum {
    CGFloat desired = 208.0;
    for (UILabel *label in @[self.titleLabel, self.subtitleLabel, self.progressLabel]) {
        desired = MAX(desired, DKPromptTextWidth(label.text, label.font) + 32.0);
    }
    for (UIButton *button in self.buttons) {
        if (!button.hidden) desired = MAX(desired, DKPromptTextWidth(button.currentTitle, button.titleLabel.font) + 56.0);
    }
    return MIN(maximum, MIN(288.0, desired));
}

// 内容按槽位布局；窄小窗口先压缩说明行数，必要时省略装饰槽位并保留按钮。
- (CGFloat)dk_layoutContentWithWidth:(CGFloat)width maximumHeight:(CGFloat)maximumHeight {
    CGFloat textWidth = MAX(1.0, width - 32.0);
    __block CGFloat titleHeight = DKPromptTextHeight(self.titleLabel, textWidth, 18.0);
    __block CGFloat subtitleHeight = DKPromptTextHeight(self.subtitleLabel, textWidth, 15.0);
    __block BOOL hasIcon = self.glyph.image != nil;
    __block BOOL hasNumber = self.progressLabel.text.length > 0;
    __block BOOL hasTrack = self.displayContent.progressMode != DKPromptProgressNone;
    NSUInteger count = MIN((NSUInteger)2, self.displayContent.actions.count);
    __block BOOL horizontal = count == 2;
    CGFloat half = MAX(1.0, (textWidth - 8.0) / 2.0);
    for (NSUInteger index = 0; index < count; index++) {
        UIButton *button = self.buttons[index];
        if (DKPromptTextWidth(button.currentTitle, button.titleLabel.font) > (half - 16.0) * 1.5) horizontal = NO;
    }
    __block CGFloat topPadding = 12.0, bottomPadding = 11.0;
    CGFloat (^measure)(void) = ^CGFloat {
        CGFloat y = topPadding;
        if (hasIcon) y += 27.0 + ((titleHeight + subtitleHeight) > 0 ? 5.0 : 0.0);
        y += titleHeight + subtitleHeight;
        if (hasNumber) y += (y > topPadding ? 5.0 : 0.0) + 15.0;
        if (hasTrack) y += (y > topPadding ? 5.0 : 0.0) + 3.0;
        if (count) y += (y > topPadding ? 5.0 : 0.0) + (horizontal ? 44.0 : count * 44.0);
        return y + bottomPadding;
    };
    while (measure() > maximumHeight && subtitleHeight > 15.0) subtitleHeight -= 15.0;
    while (measure() > maximumHeight && titleHeight > 18.0) titleHeight -= 18.0;
    if (measure() > maximumHeight) hasIcon = NO;
    if (measure() > maximumHeight) hasNumber = NO;
    if (measure() > maximumHeight) hasTrack = NO;
    if (measure() > maximumHeight) subtitleHeight = 0.0;
    if (measure() > maximumHeight && count == 2) horizontal = YES;
    if (measure() > maximumHeight) titleHeight = 0.0;
    if (measure() > maximumHeight) {
        CGFloat available = MAX(0.0, maximumHeight - (measure() - topPadding - bottomPadding));
        topPadding = floor(available / 2.0);
        bottomPadding = available - topPadding;
    }

    CGFloat y = topPadding;
    self.iconWell.hidden = !hasIcon;
    if (hasIcon) {
        self.iconWell.frame = CGRectMake(round((width - 27.0) / 2.0), y, 27.0, 27.0);
        BOOL symbol = self.glyph.image.isSymbolImage;
        self.glyph.contentMode = symbol ? UIViewContentModeCenter : UIViewContentModeScaleAspectFit;
        self.glyph.frame = symbol ? self.iconWell.bounds : CGRectInset(self.iconWell.bounds, 4.0, 4.0);
        y += 27.0 + ((titleHeight + subtitleHeight) > 0 ? 5.0 : 0.0);
    }
    self.titleLabel.hidden = titleHeight == 0.0;
    self.titleLabel.frame = CGRectMake(16.0, y, textWidth, titleHeight);
    y += titleHeight;
    self.subtitleLabel.hidden = subtitleHeight == 0.0;
    self.subtitleLabel.frame = CGRectMake(16.0, y, textWidth, subtitleHeight);
    y += subtitleHeight;
    self.progressLabel.hidden = !hasNumber;
    if (hasNumber) {
        if (y > topPadding) y += 5.0;
        self.progressLabel.frame = CGRectMake(16.0, y, textWidth, 15.0);
        y += 15.0;
    }
    self.track.hidden = !hasTrack;
    if (hasTrack) {
        if (y > topPadding) y += 5.0;
        CGFloat trackWidth = MIN(128.0, textWidth);
        self.track.frame = CGRectMake(round((width - trackWidth) / 2.0), y, trackWidth, 3.0);
        double fraction = isfinite(self.displayContent.progress) ? MIN(1.0, MAX(0.0, self.displayContent.progress)) : 0.0;
        CGFloat fillWidth = self.displayContent.progressMode == DKPromptProgressIndeterminate ? trackWidth * 0.32 : round(trackWidth * fraction);
        self.fill.frame = CGRectMake(0.0, 0.0, fillWidth, 3.0);
        y += 3.0;
    }
    if (count) {
        if (y > topPadding) y += 5.0;
        for (NSUInteger index = 0; index < count; index++) {
            CGFloat buttonWidth = horizontal ? half : textWidth;
            self.buttons[index].frame = CGRectMake(16.0 + (horizontal ? index * (half + 8.0) : 0.0),
                                                   y + (horizontal ? 0.0 : index * 44.0), buttonWidth, 44.0);
        }
        y += horizontal ? 44.0 : count * 44.0;
    }
    return MIN(y + bottomPadding, maximumHeight);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.shadowView.frame = self.bounds;
    self.shadowView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:21.0].CGPath;
    self.material.frame = self.bounds;
    self.contentView.frame = self.bounds;
    self.transitionSnapshot.frame = self.bounds;
}

- (CGAffineTransform)dk_hiddenTransform {
    return UIAccessibilityIsReduceMotionEnabled() ? CGAffineTransformIdentity :
        CGAffineTransformScale(CGAffineTransformMakeTranslation(0.0, -8.0), 0.96, 0.96);
}

- (void)setHidden:(BOOL)hidden {
    [super setHidden:hidden];
    if (hidden) [self dk_endInteraction];
    [self dk_updateIndeterminateAnimation];
}

- (void)dk_updateIndeterminateAnimation {
    NSString *key = @"DKPromptIndeterminate";
    if (!self.presented || self.hidden || self.track.hidden
        || self.displayContent.progressMode != DKPromptProgressIndeterminate || UIAccessibilityIsReduceMotionEnabled()) {
        [self.fill.layer removeAnimationForKey:key];
        return;
    }
    CGFloat trackWidth = CGRectGetWidth(self.track.bounds), fillWidth = CGRectGetWidth(self.fill.bounds);
    if ([self.fill.layer animationForKey:key] && self.indeterminateTrackWidth == trackWidth
        && self.indeterminateFillWidth == fillWidth) return;
    self.indeterminateTrackWidth = trackWidth;
    self.indeterminateFillWidth = fillWidth;
    [self.fill.layer removeAnimationForKey:key];
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"transform.translation.x"];
    animation.beginTime = [self.fill.layer convertTime:CACurrentMediaTime() fromLayer:nil];
    animation.fromValue = @(-CGRectGetWidth(self.fill.bounds));
    animation.toValue = @(CGRectGetWidth(self.track.bounds));
    animation.duration = 1.0;
    animation.repeatCount = HUGE_VALF;
    [self.fill.layer addAnimation:animation forKey:@"DKPromptIndeterminate"];
}

- (void)applyContent:(DKPromptContent *)content inWindow:(UIWindow *)window animated:(BOOL)animated {
    NSAssert(NSThread.isMainThread, @"Prompt UI requires the main thread");
    NSUInteger generation = ++self.generation;
    BOOL entering = self.superview != window || !self.presented;
    BOOL animate = animated && !UIAccessibilityIsReduceMotionEnabled();
    BOOL contentTransition = self.displayContent && self.sessionIdentifier
        && ![self.appliedIdentifier isEqual:self.sessionIdentifier];
    BOOL iconChanged = self.displayContent.icon != content.icon && ![self.displayContent.icon isEqual:content.icon];
    self.appliedIdentifier = self.sessionIdentifier;
    id previousShadow = (__bridge id)self.shadowView.layer.shadowPath;
    [self.transitionSnapshot removeFromSuperview];
    self.transitionSnapshot = nil;
    if (!entering && animate && contentTransition) {
        self.transitionSnapshot = [self.contentView snapshotViewAfterScreenUpdates:NO];
        self.transitionSnapshot.userInteractionEnabled = NO;
        if (self.transitionSnapshot) [self addSubview:self.transitionSnapshot];
    }
    // 视图只持有展示值；业务回调由 presenter 持有并分派。
    DKPromptContent *display = [DKPromptContent new];
    display.title = content.title;
    display.subtitle = content.subtitle;
    display.progressText = content.progressText;
    display.icon = content.icon;
    display.tone = content.tone;
    display.progressMode = content.progressMode;
    display.progress = content.progress;
    NSMutableArray<DKPromptAction *> *actions = [NSMutableArray array];
    for (DKPromptAction *source in content.actions) {
        if (actions.count == 2) break;
        DKPromptAction *action = [DKPromptAction new];
        action.identifier = source.identifier;
        action.title = source.title;
        action.destructive = source.destructive;
        [actions addObject:action];
    }
    display.actions = actions;
    self.displayContent = display;
    self.hasCardAction = content.cardAction != nil || content.cardActionDismisses;
    DKPromptSetText(self.titleLabel, content.title, 18.0);
    DKPromptSetText(self.subtitleLabel, content.subtitle, 15.0);
    DKPromptSetText(self.progressLabel, content.progressText, 15.0);
    if (!entering && animate && iconChanged && !contentTransition) {
        [UIView transitionWithView:self.glyph duration:0.2
                          options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                       animations:^{ self.glyph.image = content.icon; } completion:nil];
    } else self.glyph.image = content.icon;
    [self dk_updateActions];
    UIUserInterfaceStyle style = window.windowScene.traitCollection.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified) style = window.traitCollection.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified) style = UIUserInterfaceStyleLight;
    DKPromptMaterial kind = DKPromptMaterialBlur;
    if (DKGlassOSAvailable() && DKPrefBool(DKKeyMediaSaveGlass)) {
        kind = DKPrefBool(DKKeyMediaSaveGlassClear) ? DKPromptMaterialClear : DKPromptMaterialRegular;
    }
    BOOL materialChanged = kind != self.materialKind || style != self.style;
    self.materialKind = kind;
    self.style = style;
    [self dk_configureMaterial];
    if (self.superview != window) {
        [self removeFromSuperview];
        [window addSubview:self];
    }
    [window bringSubviewToFront:self];
    self.presented = YES;
    self.userInteractionEnabled = YES;
    CGRect safe = UIEdgeInsetsInsetRect(window.bounds, window.safeAreaInsets);
    CGFloat availableWidth = MAX(1.0, CGRectGetWidth(safe) - 56.0);
    CGFloat maximumHeight = MAX(1.0, CGRectGetHeight(safe));
    CGFloat width = [self dk_widthWithin:availableWidth];
    void (^geometry)(void) = ^{
        CGFloat height = [self dk_layoutContentWithWidth:width maximumHeight:maximumHeight];
        CGFloat top = CGRectGetMinY(window.bounds) + round(CGRectGetHeight(window.bounds) * 0.165);
        top = MAX(CGRectGetMinY(safe), MIN(top, CGRectGetMaxY(safe) - height));
        self.bounds = CGRectMake(0.0, 0.0, width, height);
        self.center = CGPointMake(round(CGRectGetMidX(safe)), top + height / 2.0);
        [self setNeedsLayout];
        [self layoutIfNeeded];
        [self dk_applyColors];
    };
    if (entering || !animate) [UIView performWithoutAnimation:geometry];
    if (entering) {
        [UIView performWithoutAnimation:^{
            self.material.effect = nil;
            self.contentView.alpha = 0.0;
            self.shadowView.alpha = 0.0;
            self.transform = [self dk_hiddenTransform];
        }];
    } else if (self.transitionSnapshot) {
        self.contentView.alpha = 0.0;
    }
    UIView *snapshot = self.transitionSnapshot;
    void (^changes)(void) = ^{
        if (!entering && animate) geometry();
        if (entering || materialChanged) self.material.effect = [self dk_targetEffect];
        self.contentView.alpha = 1.0;
        self.shadowView.alpha = 1.0;
        snapshot.alpha = 0.0;
        if (entering) self.transform = CGAffineTransformIdentity;
    };
    void (^completion)(BOOL) = ^(BOOL finished) {
        [snapshot removeFromSuperview];
        if (self.generation == generation) self.transitionSnapshot = nil;
    };
    if (!animate) {
        [UIView performWithoutAnimation:changes];
        completion(YES);
    } else if (entering) {
        [UIView animateWithDuration:0.28 delay:0.0 usingSpringWithDamping:0.86 initialSpringVelocity:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:changes completion:completion];
    } else {
        UIViewAnimationOptions curve = !contentTransition && content.tone == DKPromptToneProcessing
            ? UIViewAnimationOptionCurveLinear : UIViewAnimationOptionCurveEaseInOut;
        [UIView animateWithDuration:0.25 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState |
            UIViewAnimationOptionAllowUserInteraction | curve animations:changes completion:completion];
    }
    if (!entering && animate && previousShadow && !self.shadowView.hidden) {
        CABasicAnimation *shadow = [CABasicAnimation animationWithKeyPath:@"shadowPath"];
        shadow.fromValue = previousShadow;
        shadow.duration = 0.25;
        shadow.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.shadowView.layer addAnimation:shadow forKey:@"shadowPath"];
    }
    [self dk_updateIndeterminateAnimation];
}

- (void)dismissWithCompletion:(dispatch_block_t)completion {
    NSAssert(NSThread.isMainThread, @"Prompt UI requires the main thread");
    NSUInteger generation = ++self.generation;
    self.presented = NO;
    self.userInteractionEnabled = NO;
    [self dk_endInteraction];
    [self.fill.layer removeAnimationForKey:@"DKPromptIndeterminate"];
    [self.transitionSnapshot removeFromSuperview];
    self.transitionSnapshot = nil;
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0.0 : 0.22 delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self.material.effect = nil;
        self.contentView.alpha = 0.0;
        self.shadowView.alpha = 0.0;
        self.transform = [self dk_hiddenTransform];
    } completion:^(BOOL finished) {
        if (self.generation != generation) return;
        [self removeFromSuperview];
        if (completion) completion();
    }];
}

- (void)nudge {
    if (!self.presented || UIAccessibilityIsReduceMotionEnabled()) return;
    [UIView animateKeyframesWithDuration:0.3 delay:0.0
                                 options:UIViewKeyframeAnimationOptionBeginFromCurrentState | UIViewKeyframeAnimationOptionAllowUserInteraction
                              animations:^{
        [UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:0.4 animations:^{
            self.transform = CGAffineTransformMakeScale(1.04, 1.04);
        }];
        [UIView addKeyframeWithRelativeStartTime:0.4 relativeDuration:0.6 animations:^{
            self.transform = CGAffineTransformIdentity;
        }];
    } completion:nil];
}
@end
