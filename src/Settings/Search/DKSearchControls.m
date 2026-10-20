// 搜索输入控件与玻璃材质，低系统使用系统模糊。
#import "DKSearchViews.h"
#import <QuartzCore/QuartzCore.h>
static const NSTimeInterval kDKSearchContentFade = 0.20;
static UIVisualEffect *DKSearchGlassEffect(void) {
    if (@available(iOS 26.0, *)) {
        UIGlassEffect *effect = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
        effect.interactive = YES;
        return effect;
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterial];
}

// 0 尺寸写入效果不会建材质层，之后只改 frame 补不回来。
static void DKSearchInstallMaterial(UIVisualEffectView *view) {
    if (!view || view.effect) return;
    if (CGRectGetWidth(view.bounds) < 8.0 || CGRectGetHeight(view.bounds) < 8.0) return;
    view.effect = DKSearchGlassEffect();
}

static void DKSearchApplyCapsule(UIVisualEffectView *view) {
    if (!view) return;
    if (@available(iOS 26.0, *)) {
        view.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];
    } else {
        view.layer.cornerRadius = CGRectGetHeight(view.bounds) / 2.0;
        view.layer.cornerCurve = kCACornerCurveContinuous;
        view.clipsToBounds = YES;
    }
}

static void DKSearchApplyRadius(UIVisualEffectView *view, CGFloat radius) {
    if (!view) return;
    if (@available(iOS 26.0, *)) {
        view.cornerConfiguration =
            [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius fixedRadius:radius]];
        // 玻璃圆角不裁剪 contentView；表格悬停标题下的滚动边缘效果按矩形绘制，需按同一圆角裁掉。
        view.contentView.layer.cornerRadius = radius;
        view.contentView.layer.cornerCurve = kCACornerCurveContinuous;
        view.contentView.clipsToBounds = YES;
    } else {
        view.layer.cornerRadius = radius;
        view.layer.cornerCurve = kCACornerCurveContinuous;
        view.clipsToBounds = YES;
    }
}

#pragma mark - 玻璃圆钮（搜索 / 关闭共用）


@implementation DKSearchGlassButton {
    CGFloat _appliedSide;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = YES;
        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.userInteractionEnabled = NO;
        [self.contentView addSubview:_iconView];
        _hitControl = [[UIControl alloc] init];
        _hitControl.isAccessibilityElement = YES;
        _hitControl.accessibilityTraits = UIAccessibilityTraitButton;
        _hitControl.accessibilityLabel = @"搜索设置";
        [self.contentView addSubview:_hitControl];
        self.flexSourceView = _hitControl;
        _symbolName = @"magnifyingglass";
    }
    return self;
}

- (void)dkSetSymbol:(NSString *)name animated:(BOOL)animated {
    if (name.length == 0 || [name isEqualToString:_symbolName]) return;
    _symbolName = [name copy];
    UIImage *image = animated ? [self dkSymbolImage] : nil;
    if (!image) {
        _appliedSide = 0.0;
        [self setNeedsLayout];
        return;
    }
    // 符号替换过渡：旧符号缩小退场后新符号放大进场，两个图标不会叠在一起。
    // 过渡类在 Symbols.framework（iOS 17+），按类名取用，不链接该框架。
    if (@available(iOS 17.0, *)) {
        NSSymbolContentTransition *transition =
            [NSClassFromString(@"NSSymbolReplaceContentTransition") replaceDownUpTransition];
        if (transition) {
            [UIView performWithoutAnimation:^{
                [self.iconView setSymbolImage:image withContentTransition:transition];
            }];
            return;
        }
    }
    [UIView transitionWithView:self.iconView duration:kDKSearchContentFade
                       options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        self.iconView.image = image;
    } completion:nil];
}

- (UIImage *)dkSymbolImage {
    CGFloat side = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds));
    if (side < 8.0) return nil;
    _appliedSide = side;
    CGFloat pointSize = MAX(round(side * 0.40), 16.0);
    UIImageSymbolConfiguration *config =
        [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightSemibold];
    UIImage *image = [UIImage systemImageNamed:self.symbolName ?: @"magnifyingglass" withConfiguration:config];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

- (void)dkUpdateSymbolImage {
    UIImage *image = [self dkSymbolImage];
    if (!image) return;
    self.iconView.image = image;
    self.iconView.tintColor = UIColor.labelColor;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    DKSearchInstallMaterial(self);
    CGFloat side = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds));
    if (fabs(side - _appliedSide) > 0.5) {
        DKSearchApplyCapsule(self);
        [self dkUpdateSymbolImage];
    }
    CGFloat glyph = round(side * 0.44);
    self.iconView.frame = CGRectMake(round((CGRectGetWidth(self.bounds) - glyph) / 2.0),
                                     round((CGRectGetHeight(self.bounds) - glyph) / 2.0), glyph, glyph);
    self.hitControl.frame = self.contentView.bounds;
}

@end

#pragma mark - 搜索胶囊


@implementation DKSearchCapsuleView {
    CGFloat _appliedHeight;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = YES;
        _glyphView = [[UIImageView alloc] init];
        _glyphView.contentMode = UIViewContentModeScaleAspectFit;
        _glyphView.tintColor = UIColor.secondaryLabelColor;
        _glyphView.userInteractionEnabled = NO;
        [self.contentView addSubview:_glyphView];

        _textField = [[UITextField alloc] init];
        _textField.font = [UIFont systemFontOfSize:17.0];
        _textField.textColor = UIColor.labelColor;
        _textField.tintColor = UIColor.labelColor;
        _textField.placeholder = @"搜索设置";
        _textField.returnKeyType = UIReturnKeySearch;
        _textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        _textField.autocorrectionType = UITextAutocorrectionTypeNo;
        _textField.spellCheckingType = UITextSpellCheckingTypeNo;
        _textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _textField.accessibilityLabel = @"搜索设置";
        [self.contentView addSubview:_textField];
    }
    return self;
}

- (void)dkSetContentAlpha:(CGFloat)alpha {
    self.glyphView.alpha = alpha;
    self.textField.alpha = alpha;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    DKSearchInstallMaterial(self);
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat width = CGRectGetWidth(self.bounds);
    if (fabs(height - _appliedHeight) > 0.5) {
        _appliedHeight = height;
        DKSearchApplyCapsule(self);
        CGFloat pointSize = MAX(round(height * 0.34), 12.0);
        UIImageSymbolConfiguration *config =
            [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightMedium];
        self.glyphView.image = [[UIImage systemImageNamed:@"magnifyingglass" withConfiguration:config]
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    CGFloat pad = round(height * 0.34);
    CGFloat glyph = round(height * 0.38);
    self.glyphView.frame = CGRectMake(pad, round((height - glyph) / 2.0), glyph, glyph);
    CGFloat textX = CGRectGetMaxX(self.glyphView.frame) + round(height * 0.18);
    self.textField.frame = CGRectMake(textX, 0.0, MAX(width - textX - pad, 0.0), height);
}

@end

#pragma mark - 结果面板


@implementation DKSearchPanelView {
    CGFloat _appliedRadius;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    DKSearchInstallMaterial(self);
    if (fabs(_appliedRadius - _radius) > 0.5) {
        _appliedRadius = _radius;
        DKSearchApplyRadius(self, _radius);
    }
}

@end

#pragma mark - 玻璃容器

@implementation DKSearchGlassGroupView {
    CGFloat _appliedSpacing;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self || hit == self.contentView) ? nil : hit;
}

- (void)setMergeSpacing:(CGFloat)mergeSpacing {
    if (fabs(mergeSpacing - _mergeSpacing) < 0.5) return;
    _mergeSpacing = mergeSpacing;
    [self setNeedsLayout];
}

// 与玻璃材质同口径：有尺寸后才写入容器效果。
- (void)layoutSubviews {
    [super layoutSubviews];
    if (@available(iOS 26.0, *)) {
        if (CGRectGetWidth(self.bounds) < 8.0 || CGRectGetHeight(self.bounds) < 8.0) return;
        if (self.effect && fabs(_appliedSpacing - _mergeSpacing) < 0.5) return;
        _appliedSpacing = _mergeSpacing;
        UIGlassContainerEffect *effect = [[UIGlassContainerEffect alloc] init];
        effect.spacing = _mergeSpacing;
        [UIView performWithoutAnimation:^{ self.effect = effect; }];
    }
}

@end

