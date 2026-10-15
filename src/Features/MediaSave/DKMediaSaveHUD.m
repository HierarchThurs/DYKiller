#import "DKMediaSaveHUD.h"
#import "DKGlassFlexView.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKMediaLibrary.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import <QuartzCore/QuartzCore.h>

__attribute__((constructor)) static void DKMediaHUDRegisterSetting(void) {
    DKSettingsRegister(DKKeyMediaSaveGlass, ^AWESettingItemModel *{
        return DKSettingsWithInfo(
            DKMakeGlassChoice(DKKeyMediaSaveGlass, DKKeyMediaSaveGlassClear, @"媒体保存提示液态玻璃", nil),
            @"媒体保存提示的材质：关闭时使用普通系统模糊提示；模糊玻璃使用 iOS 26 Regular；清透玻璃显示更多背后画面细节。");
    });
}

// 几何取自 docs/settings-preview.html 的媒体保存提示。
static const CGFloat kDKHUDMaxWidth = 208.0;
static const CGFloat kDKHUDWindowMargin = 28.0;    // 窄屏时卡片距窗口左右边缘
static const CGFloat kDKHUDTopRatio = 0.165;       // 卡片顶边位于窗口高度的比例
static const CGFloat kDKHUDRadius = 21.0;
static const CGFloat kDKHUDPadTop = 12.0;
static const CGFloat kDKHUDPadBottom = 11.0;
static const CGFloat kDKHUDPadSide = 16.0;
static const CGFloat kDKHUDIconSide = 27.0;
static const CGFloat kDKHUDIconGap = 5.0;
static const CGFloat kDKHUDTitleHeight = 18.0;
static const CGFloat kDKHUDSubtitleHeight = 15.0;
static const CGFloat kDKHUDTrackGap = 5.0;
static const CGFloat kDKHUDTrackWidth = 128.0;
static const CGFloat kDKHUDTrackHeight = 3.0;
static const CGFloat kDKHUDHiddenOffset = -8.0;
static const CGFloat kDKHUDHiddenScale = 0.96;
static const NSTimeInterval kDKHUDShowDuration = 0.28;
static const NSTimeInterval kDKHUDHideDuration = 0.22;
static const NSTimeInterval kDKHUDChangeDuration = 0.25;
static const NSTimeInterval kDKHUDResultDuration = 1.8;
static NSString *const kDKHUDCancelHint = @"点击取消";

typedef NS_ENUM(NSInteger, DKMediaHUDMaterial) {
    DKMediaHUDMaterialBlur,
    DKMediaHUDMaterialRegular,
    DKMediaHUDMaterialClear,
};

#pragma mark - 材质与配色

static DKMediaHUDMaterial DKMediaHUDCurrentMaterial(void) {
    if (!DKGlassOSAvailable() || !DKPrefBool(DKKeyMediaSaveGlass)) return DKMediaHUDMaterialBlur;
    return DKPrefBool(DKKeyMediaSaveGlassClear) ? DKMediaHUDMaterialClear : DKMediaHUDMaterialRegular;
}

// 与其他玻璃功能同一口径：先取场景的深浅色，再取窗口的。
static UIUserInterfaceStyle DKMediaHUDStyle(UIWindow *window) {
    UIUserInterfaceStyle style = window.windowScene.traitCollection.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified) style = window.traitCollection.userInterfaceStyle;
    return style == UIUserInterfaceStyleUnspecified ? UIUserInterfaceStyleLight : style;
}

static UIColor *DKMediaHUDColor(uint32_t hex, CGFloat alpha) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0 green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0 alpha:alpha];
}

// 状态色：图标圆底的基色与透明度、图标色，各分「深色文字」「浅色文字」两档。
typedef struct {
    uint32_t well;
    CGFloat wellAlpha[2];
    uint32_t glyph[2];
} DKMediaHUDTone;

static DKMediaHUDTone DKMediaHUDToneForState(DKMediaHUDState state) {
    switch (state) {
        case DKMediaHUDStateSuccess:   return (DKMediaHUDTone){ 0x30D158, { 0.16, 0.22 }, { 0x1DAD4D, 0x63E58B } };
        case DKMediaHUDStateCancelled: return (DKMediaHUDTone){ 0x787880, { 0.16, 0.25 }, { 0x686A73, 0xB8B9C1 } };
        case DKMediaHUDStateFailure:   return (DKMediaHUDTone){ 0xFF453A, { 0.14, 0.22 }, { 0xD92D25, 0xFF8A83 } };
        case DKMediaHUDStateProgress:  break;
    }
    return (DKMediaHUDTone){ 0x0A84FF, { 0.14, 0.22 }, { 0x087BEA, 0x62B5FF } };
}

// 保存中按内容类型取图标，结果按状态取图标。
static UIImage *DKMediaHUDGlyph(DKMediaHUDState state, DKMediaHUDScene scene) {
    NSString *name = nil;
    switch (state) {
        case DKMediaHUDStateSuccess:   name = @"checkmark"; break;
        case DKMediaHUDStateCancelled: name = @"xmark"; break;
        case DKMediaHUDStateFailure:   name = @"exclamationmark"; break;
        case DKMediaHUDStateProgress:
            switch (scene) {
                case DKMediaHUDSceneVideo:   name = @"arrow.down.to.line"; break;
                case DKMediaHUDSceneImage:   name = @"photo"; break;
                case DKMediaHUDSceneLive:    name = @"livephoto"; break;
                case DKMediaHUDSceneAlbum:   name = @"photo.on.rectangle"; break;
                case DKMediaHUDSceneMixed:   name = @"square.stack"; break;
                case DKMediaHUDSceneSticker: name = @"face.smiling"; break;
                case DKMediaHUDSceneMusic:   name = @"music.note"; break;
            }
            break;
    }
    UIImageSymbolConfiguration *config =
        [UIImageSymbolConfiguration configurationWithPointSize:13.0 weight:UIImageSymbolWeightSemibold];
    return [UIImage systemImageNamed:name ?: @"arrow.down.to.line" withConfiguration:config];
}

static UILabel *DKMediaHUDLabel(UIFont *font) {
    UILabel *label = [UILabel new];
    label.font = font;
    label.textAlignment = NSTextAlignmentCenter;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

#pragma mark - 卡片

// 层级：投影（仅模糊材质）→ 材质 → 内容。材质与内容不接触摸，点按由卡片本身处理。
// 进出场只动材质的 effect、内容与投影的 alpha 和卡片的 transform，不对材质及其父视图做 alpha 动画。
@interface DKMediaHUDView : UIView
@property (nonatomic, strong) UIView *shadowView;
@property (nonatomic, strong) DKGlassFlexView *material;
@property (nonatomic, strong) UIView *content;
@property (nonatomic, strong) UIView *iconWell;
@property (nonatomic, strong) UIImageView *glyph;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIView *track;
@property (nonatomic, strong) UIView *fill;
@property (nonatomic, assign) DKMediaHUDState state;
@property (nonatomic, assign) DKMediaHUDScene scene;
@property (nonatomic, assign) double fraction;
@property (nonatomic, assign) DKMediaHUDMaterial materialKind;
@property (nonatomic, assign) UIUserInterfaceStyle style;
@property (nonatomic, assign) BOOL presented;          // 在屏且不在退场中
@property (nonatomic, assign) NSUInteger generation;   // 每次显示或收起递增，过期的延时收起据此作废
@property (nonatomic, copy) dispatch_block_t onCancel;
@end

@implementation DKMediaHUDView

- (instancetype)init {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    self.isAccessibilityElement = YES;

    _shadowView = [UIView new];
    _shadowView.userInteractionEnabled = NO;
    _shadowView.layer.shadowColor = UIColor.blackColor.CGColor;
    _shadowView.layer.shadowOffset = CGSizeMake(0.0, 12.0);
    _shadowView.layer.shadowRadius = 14.0;
    [self addSubview:_shadowView];

    _content = [UIView new];
    _content.userInteractionEnabled = NO;
    [self addSubview:_content];

    _iconWell = [UIView new];
    _iconWell.layer.cornerRadius = kDKHUDIconSide / 2.0;
    [_content addSubview:_iconWell];
    _glyph = [UIImageView new];
    _glyph.contentMode = UIViewContentModeCenter;
    [_iconWell addSubview:_glyph];

    _titleLabel = DKMediaHUDLabel([UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold]);
    _subtitleLabel = DKMediaHUDLabel([UIFont systemFontOfSize:11.0]);
    [_content addSubview:_titleLabel];
    [_content addSubview:_subtitleLabel];

    _track = [UIView new];
    _track.layer.cornerRadius = kDKHUDTrackHeight / 2.0;
    _track.clipsToBounds = YES;
    _fill = [UIView new];
    _fill.backgroundColor = DKMediaHUDColor(0x0A84FF, 1.0);
    [_track addSubview:_fill];
    [_content addSubview:_track];

    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dk_tapped)]];
    return self;
}

- (void)dk_tapped {
    if (self.state != DKMediaHUDStateProgress) {
        [self dk_dismiss];
        return;
    }
    dispatch_block_t cancel = self.onCancel;
    self.onCancel = nil;
    if (cancel) cancel();
}

// 每次进场换一块新材质：模糊与玻璃的圆角写法不同，不在同一个视图上来回切。
- (void)dk_installMaterial {
    [self.material removeFromSuperview];
    DKGlassFlexView *material = [[DKGlassFlexView alloc] initWithEffect:nil];
    material.userInteractionEnabled = NO;
    material.flexSourceView = self;
    material.overrideUserInterfaceStyle =
        self.materialKind == DKMediaHUDMaterialClear ? UIUserInterfaceStyleUnspecified : self.style;
    if (self.materialKind == DKMediaHUDMaterialBlur) {
        material.layer.cornerRadius = kDKHUDRadius;
        material.layer.cornerCurve = kCACornerCurveContinuous;
        material.clipsToBounds = YES;
    } else if (@available(iOS 26.0, *)) {
        material.cornerConfiguration =
            [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius fixedRadius:kDKHUDRadius]];
    }
    [self insertSubview:material aboveSubview:self.shadowView];
    self.material = material;
}

- (UIVisualEffect *)dk_targetEffect {
    if (self.materialKind != DKMediaHUDMaterialBlur) {
        if (@available(iOS 26.0, *)) {
            BOOL clear = self.materialKind == DKMediaHUDMaterialClear;
            UIGlassEffect *effect = [UIGlassEffect effectWithStyle:
                clear ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular];
            effect.tintColor = clear ? DKGlassTintForStyle(self.style) : nil;
            effect.interactive = YES;
            return effect;
        }
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterial];
}

// 清透玻璃与深色下用浅色文字，其余用深色文字。
- (void)dk_applyColors {
    BOOL lightInk = self.materialKind == DKMediaHUDMaterialClear || self.style == UIUserInterfaceStyleDark;
    NSUInteger tier = lightInk ? 1 : 0;
    DKMediaHUDTone tone = DKMediaHUDToneForState(self.state);
    self.iconWell.backgroundColor = DKMediaHUDColor(tone.well, tone.wellAlpha[tier]);
    self.glyph.tintColor = DKMediaHUDColor(tone.glyph[tier], 1.0);
    self.titleLabel.textColor = lightInk ? [UIColor colorWithWhite:1.0 alpha:0.94] : DKMediaHUDColor(0x17181D, 1.0);
    self.subtitleLabel.textColor = lightInk ? [UIColor colorWithWhite:1.0 alpha:0.56] : DKMediaHUDColor(0x161823, 0.58);
    self.track.backgroundColor = lightInk ? [UIColor colorWithWhite:1.0 alpha:0.16] : DKMediaHUDColor(0x161823, 0.14);
    self.shadowView.hidden = self.materialKind != DKMediaHUDMaterialBlur;
    self.shadowView.layer.shadowOpacity = self.style == UIUserInterfaceStyleDark ? 0.34 : 0.16;
}

- (CGAffineTransform)dk_hiddenTransform {
    if (UIAccessibilityIsReduceMotionEnabled()) return CGAffineTransformIdentity;
    return CGAffineTransformScale(CGAffineTransformMakeTranslation(0.0, kDKHUDHiddenOffset),
                                  kDKHUDHiddenScale, kDKHUDHiddenScale);
}

- (void)dk_layoutFill {
    self.fill.frame = CGRectMake(0.0, 0.0, round(kDKHUDTrackWidth * self.fraction), kDKHUDTrackHeight);
}

// 宽度固定，高度随副标题与进度条增减；卡片可能带着进出场 transform，故用 bounds + center 定位。
- (void)dk_layoutInWindow:(UIWindow *)window {
    CGSize area = window.bounds.size;
    CGFloat width = MIN(kDKHUDMaxWidth, area.width - kDKHUDWindowMargin * 2.0);
    BOOL hasSubtitle = self.subtitleLabel.text.length > 0;
    BOOL hasTrack = self.state == DKMediaHUDStateProgress;
    CGFloat titleY = kDKHUDPadTop + kDKHUDIconSide + kDKHUDIconGap;
    CGFloat subtitleY = titleY + kDKHUDTitleHeight;
    CGFloat trackY = subtitleY + (hasSubtitle ? kDKHUDSubtitleHeight : 0.0) + kDKHUDTrackGap;
    CGFloat height = (hasTrack ? trackY + kDKHUDTrackHeight : trackY - kDKHUDTrackGap) + kDKHUDPadBottom;

    self.bounds = CGRectMake(0.0, 0.0, width, height);
    self.center = CGPointMake(round(area.width / 2.0), round(area.height * kDKHUDTopRatio) + height / 2.0);
    CGRect bounds = self.bounds;
    self.shadowView.frame = bounds;
    self.shadowView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:kDKHUDRadius].CGPath;
    self.material.frame = bounds;
    self.content.frame = bounds;

    self.iconWell.frame = CGRectMake(round((width - kDKHUDIconSide) / 2.0), kDKHUDPadTop, kDKHUDIconSide, kDKHUDIconSide);
    self.glyph.frame = self.iconWell.bounds;
    CGFloat textWidth = width - kDKHUDPadSide * 2.0;
    self.titleLabel.frame = CGRectMake(kDKHUDPadSide, titleY, textWidth, kDKHUDTitleHeight);
    self.subtitleLabel.frame = CGRectMake(kDKHUDPadSide, subtitleY, textWidth, kDKHUDSubtitleHeight);
    self.subtitleLabel.alpha = hasSubtitle ? 1.0 : 0.0;
    self.track.frame = CGRectMake(round((width - kDKHUDTrackWidth) / 2.0), trackY, kDKHUDTrackWidth, kDKHUDTrackHeight);
    self.track.alpha = hasTrack ? 1.0 : 0.0;
    [self dk_layoutFill];
}

- (void)dk_setTitle:(NSString *)title subtitle:(NSString *)subtitle {
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
    self.accessibilityLabel = subtitle.length ? [NSString stringWithFormat:@"%@，%@", title, subtitle] : title;
}

- (void)dk_setState:(DKMediaHUDState)state scene:(DKMediaHUDScene)scene
              title:(NSString *)title subtitle:(NSString *)subtitle fraction:(double)fraction {
    UIImage *glyph = DKMediaHUDGlyph(state, scene);
    BOOL glyphChanged = state != self.state || scene != self.scene || !self.glyph.image;
    self.state = state;
    self.scene = scene;
    self.fraction = MIN(MAX(fraction, 0.0), 1.0);
    self.accessibilityTraits = state == DKMediaHUDStateProgress ? UIAccessibilityTraitButton : UIAccessibilityTraitStaticText;
    [self dk_setTitle:title subtitle:subtitle];
    if (!glyphChanged) return;
    if (!self.presented) {
        self.glyph.image = glyph;
        return;
    }
    [UIView transitionWithView:self.glyph duration:0.2 options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{ self.glyph.image = glyph; } completion:nil];
}

- (void)dk_presentInWindow:(UIWindow *)window {
    BOOL entering = self.superview != window;
    if (entering) {
        [self removeFromSuperview];
        self.materialKind = DKMediaHUDCurrentMaterial();
        self.style = DKMediaHUDStyle(window);
        [self dk_installMaterial];
        [window addSubview:self];
    }
    [window bringSubviewToFront:self];
    // 先定尺寸再上材质：0 尺寸写入 UIGlassEffect 不会建材质层。
    [UIView performWithoutAnimation:^{
        [self dk_applyColors];
        [self dk_layoutInWindow:window];
        if (!entering) return;
        self.content.alpha = 0.0;
        self.shadowView.alpha = 0.0;
        self.transform = [self dk_hiddenTransform];
    }];
    self.presented = YES;
    self.userInteractionEnabled = YES;
    [UIView animateWithDuration:kDKHUDShowDuration delay:0.0 usingSpringWithDamping:0.86 initialSpringVelocity:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.material.effect = [self dk_targetEffect];
        self.content.alpha = 1.0;
        self.shadowView.alpha = 1.0;
        self.transform = CGAffineTransformIdentity;
    } completion:nil];
}

// 在屏时换状态：高度与配色动画过渡，投影路径同步。
- (void)dk_relayoutAnimated {
    [self.superview bringSubviewToFront:self];
    id oldShadow = (__bridge id)self.shadowView.layer.shadowPath;
    [UIView animateWithDuration:kDKHUDChangeDuration delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                              | UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        [self dk_applyColors];
        [self dk_layoutInWindow:self.window];
    } completion:nil];
    if (!oldShadow || self.shadowView.hidden) return;
    CABasicAnimation *shadow = [CABasicAnimation animationWithKeyPath:@"shadowPath"];
    shadow.fromValue = oldShadow;
    shadow.duration = kDKHUDChangeDuration;
    shadow.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.shadowView.layer addAnimation:shadow forKey:@"shadowPath"];
}

- (void)dk_updateTitle:(NSString *)title fraction:(double)fraction {
    [self dk_setTitle:title subtitle:self.subtitleLabel.text];
    self.fraction = MIN(MAX(fraction, 0.0), 1.0);
    [UIView animateWithDuration:kDKHUDChangeDuration delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                              | UIViewAnimationOptionCurveLinear
                     animations:^{ [self dk_layoutFill]; } completion:nil];
}

- (void)dk_dismiss {
    if (!self.presented) return;
    self.presented = NO;
    self.userInteractionEnabled = NO;
    self.onCancel = nil;
    NSUInteger generation = ++self.generation;
    [UIView animateWithDuration:kDKHUDHideDuration delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self.material.effect = nil;
        self.content.alpha = 0.0;
        self.shadowView.alpha = 0.0;
        self.transform = [self dk_hiddenTransform];
    } completion:^(__unused BOOL finished) {
        if (self.generation == generation) [self removeFromSuperview];
    }];
}

- (void)dk_nudge {
    if (!self.presented || UIAccessibilityIsReduceMotionEnabled()) return;
    [UIView animateKeyframesWithDuration:0.3 delay:0.0
                                 options:UIViewKeyframeAnimationOptionBeginFromCurrentState
                                       | UIViewKeyframeAnimationOptionAllowUserInteraction
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

#pragma mark - 接口

static DKMediaHUDView *gDKHUD;

// 卡片已在当前窗口上就原地换内容，否则进场。返回 nil 表示没有可挂的窗口。
static DKMediaHUDView *DKMediaHUDShow(DKMediaHUDState state, DKMediaHUDScene scene, NSString *title,
                                      NSString *subtitle, double fraction) {
    UIWindow *window = DKMediaForegroundWindow();
    if (!window) return nil;
    if (!gDKHUD) gDKHUD = [DKMediaHUDView new];
    DKMediaHUDView *hud = gDKHUD;
    hud.generation++;
    BOOL visible = hud.presented && hud.superview == window;
    [hud dk_setState:state scene:scene title:title subtitle:subtitle fraction:fraction];
    if (visible) [hud dk_relayoutAnimated];
    else [hud dk_presentInWindow:window];
    return hud;
}

void DKMediaHUDShowProgress(DKMediaHUDScene scene, NSString *title, double fraction, dispatch_block_t onCancel) {
    DKMediaHUDShow(DKMediaHUDStateProgress, scene, title, kDKHUDCancelHint, fraction).onCancel = onCancel;
}

void DKMediaHUDUpdateProgress(NSString *title, double fraction) {
    DKMediaHUDView *hud = gDKHUD;
    if (!hud.presented || hud.state != DKMediaHUDStateProgress) return;
    [hud dk_updateTitle:title fraction:fraction];
}

void DKMediaHUDShowResult(DKMediaHUDState state, NSString *title, NSString *subtitle) {
    DKMediaHUDView *hud = DKMediaHUDShow(state, gDKHUD.scene, title, subtitle, 0.0);
    if (!hud) return;
    hud.onCancel = nil;
    NSUInteger generation = hud.generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDKHUDResultDuration * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (hud.generation == generation) [hud dk_dismiss];
    });
}

void DKMediaHUDNudge(void) {
    if (gDKHUD.state == DKMediaHUDStateProgress) [gDKHUD dk_nudge];
}
