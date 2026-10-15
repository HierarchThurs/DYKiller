//
//  DKSettingsPopup.m
//  设置页弹层：说明气泡与作者信息卡片。两者共用一层铺满窗口的承载视图，
//  它接住弹层以外的触摸并收起弹层，这一下不再传给下面的控件；同一时刻只有一个弹层。
//

#import "DKSettingsInternal.h"

static NSString *const kDKAuthorName   = @"Hierarch";
static NSString *const kDKAuthorRole   = @"DYKiller 作者";
static NSString *const kDKAuthorHandle = @"@Hierarch";
static NSString *const kDKRepoTitle    = @"GitHub · DYKiller";
static NSString *const kDKRepoURL      = @"https://github.com/HierarchThurs/DYKiller";
static NSString *const kDKTelegramName  = @"Telegram";
static NSString *const kDKTelegramTitle = @"t.me/DYKiller";
static NSString *const kDKTelegramURL   = @"https://t.me/DYKiller";

static UIColor *DKDynamicColor(UIColor *light, UIColor *dark) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
        return trait.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
    }];
}

static UIColor *DKRGB(uint32_t hex, CGFloat alpha) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0 green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0 alpha:alpha];
}

#pragma mark - 承载层

@interface DKSettingsPopupHost : UIView
@property (nonatomic, strong) UIView *content;
- (void)dismiss;
@end

static __weak DKSettingsPopupHost *gPopup = nil;

@implementation DKSettingsPopupHost

- (instancetype)initWithWindow:(UIWindow *)window dimmed:(BOOL)dimmed {
    if ((self = [super initWithFrame:window.bounds])) {
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.backgroundColor = dimmed ? [UIColor colorWithWhite:0.0 alpha:0.35] : UIColor.clearColor;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(dismiss)
                                                   name:UIApplicationWillResignActiveNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

// 弹层自身的空白处也会把触摸转发到这里，按落点区分。
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint point = [touches.anyObject locationInView:self];
    if (self.content && CGRectContainsPoint(self.content.frame, point)) return;
    [self dismiss];
}

// 气泡从尖角处放大展开，卡片从略大缩回。
- (void)presentFromScale:(CGFloat)scale {
    self.alpha = 0.0;
    self.content.transform = CGAffineTransformMakeScale(scale, scale);
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.alpha = 1.0;
        self.content.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)dismiss {
    if (gPopup == self) gPopup = nil;
    self.userInteractionEnabled = NO;
    [UIView animateWithDuration:0.18 animations:^{
        self.alpha = 0.0;
    } completion:^(__unused BOOL finished) {
        [self removeFromSuperview];
    }];
}

@end

static DKSettingsPopupHost *DKMakeHost(UIView *anchor, BOOL dimmed) {
    UIWindow *window = anchor.window;
    if (!window) return nil;
    [gPopup dismiss];
    DKSettingsPopupHost *host = [[DKSettingsPopupHost alloc] initWithWindow:window dimmed:dimmed];
    [window addSubview:host];
    gPopup = host;
    return host;
}

#pragma mark - 说明气泡

static const CGFloat kDKTipMaxWidth = 264.0;
static const CGFloat kDKTipPadH = 12.0;
static const CGFloat kDKTipPadV = 10.0;
static const CGFloat kDKTipArrowW = 12.0;
static const CGFloat kDKTipArrowH = 6.0;
static const CGFloat kDKTipMargin = 12.0;
static const CGFloat kDKTipIconHalf = 10.0;   // 尖角离 ⓘ 图标中心的距离

// 圆角矩形 + 指向 ⓘ 的尖角，用 CAShapeLayer 画；尖角在上（气泡在下方）或在下。
@interface DKSettingsTipView : UIView
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, assign) CGFloat arrowX;
@property (nonatomic, assign) BOOL arrowUp;
@end

@implementation DKSettingsTipView

+ (Class)layerClass {
    return CAShapeLayer.class;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = CGRectGetWidth(self.bounds), h = CGRectGetHeight(self.bounds);
    CGRect body = self.arrowUp ? CGRectMake(0, kDKTipArrowH, w, h - kDKTipArrowH)
                               : CGRectMake(0, 0, w, h - kDKTipArrowH);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:body cornerRadius:12.0];
    CGFloat baseY = self.arrowUp ? kDKTipArrowH : h - kDKTipArrowH;
    CGFloat tipY = self.arrowUp ? 0 : h;
    UIBezierPath *arrow = [UIBezierPath bezierPath];
    [arrow moveToPoint:CGPointMake(self.arrowX - kDKTipArrowW / 2.0, baseY)];
    [arrow addLineToPoint:CGPointMake(self.arrowX, tipY)];
    [arrow addLineToPoint:CGPointMake(self.arrowX + kDKTipArrowW / 2.0, baseY)];
    [arrow closePath];
    [path appendPath:arrow];
    ((CAShapeLayer *)self.layer).path = path.CGPath;
    self.label.frame = CGRectInset(body, kDKTipPadH, kDKTipPadV);
}

@end

void DKSettingsShowTip(UIView *source, NSString *text) {
    if (!source || !text.length) return;
    DKSettingsPopupHost *host = DKMakeHost(source, NO);
    if (!host) return;

    BOOL dark = source.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    DKSettingsTipView *tip = [[DKSettingsTipView alloc] init];
    ((CAShapeLayer *)tip.layer).fillColor = (dark ? DKRGB(0x3A3B46, 1.0) : DKRGB(0x1C1D24, 0.94)).CGColor;
    tip.layer.shadowColor = UIColor.blackColor.CGColor;
    tip.layer.shadowOpacity = 0.18;
    tip.layer.shadowRadius = 12.0;
    tip.layer.shadowOffset = CGSizeMake(0, 6);

    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.numberOfLines = 0;
    label.font = [UIFont systemFontOfSize:13.0];
    label.textColor = UIColor.whiteColor;
    tip.label = label;
    [tip addSubview:label];

    CGSize textSize = [label sizeThatFits:CGSizeMake(kDKTipMaxWidth - kDKTipPadH * 2.0, CGFLOAT_MAX)];
    CGFloat width = ceil(textSize.width) + kDKTipPadH * 2.0;
    CGFloat height = ceil(textSize.height) + kDKTipPadV * 2.0 + kDKTipArrowH;

    // 默认放在 ⓘ 下方，下方放不下且上方放得下时翻到上方。
    CGRect anchor = [source convertRect:source.bounds toView:host];
    UIEdgeInsets safe = source.window.safeAreaInsets;   // 承载层刚插入、尚未布局，安全区取窗口的
    CGFloat belowY = CGRectGetMidY(anchor) + kDKTipIconHalf;
    CGFloat aboveY = CGRectGetMidY(anchor) - kDKTipIconHalf - height;
    BOOL below = belowY + height <= CGRectGetHeight(host.bounds) - safe.bottom - kDKTipMargin
              || aboveY < safe.top + kDKTipMargin;
    CGFloat x = MIN(MAX(CGRectGetMidX(anchor) - width / 2.0, kDKTipMargin),
                    CGRectGetWidth(host.bounds) - kDKTipMargin - width);
    tip.arrowUp = below;
    tip.arrowX = MIN(MAX(CGRectGetMidX(anchor) - x, 16.0), width - 16.0);

    // 缩放从尖角处展开。
    tip.layer.anchorPoint = CGPointMake(tip.arrowX / width, below ? 0.0 : 1.0);
    tip.frame = CGRectMake(x, below ? belowY : aboveY, width, height);
    host.content = tip;
    [host addSubview:tip];
    [host presentFromScale:0.9];
}

#pragma mark - 作者信息卡片

// 整行可点，按下时变淡；点击打开 url。
@interface DKSettingsPressRow : UIControl
@property (nonatomic, copy) NSString *url;
@end

@implementation DKSettingsPressRow
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.6 : 1.0;
}
@end

static UILabel *DKLabel(NSString *text, UIFont *font, UIColor *color) {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

static UIImageView *DKSymbol(NSString *name, NSString *fallback, CGFloat size, UIColor *color) {
    UIImageSymbolConfiguration *config =
        [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightMedium];
    UIImage *image = [UIImage systemImageNamed:name withConfiguration:config]
                  ?: [UIImage systemImageNamed:fallback withConfiguration:config];
    UIImageView *view = [[UIImageView alloc] initWithImage:image];
    view.tintColor = color;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    return view;
}

@interface DKSettingsAuthorCard : UIView
@property (nonatomic, strong) UIColor *textColor;
@property (nonatomic, strong) UIColor *subColor;
@property (nonatomic, strong) UIColor *wellColor;
@property (nonatomic, strong) UIColor *badgeColor;
@end

@implementation DKSettingsAuthorCard

// 链接行：图标徽章 + 标题 / 副标题 + 外链箭头。
- (DKSettingsPressRow *)dk_linkRowWithSymbol:(NSString *)symbol fallback:(NSString *)fallback
                                       title:(NSString *)title subtitle:(NSString *)subtitle url:(NSString *)url {
    DKSettingsPressRow *link = [[DKSettingsPressRow alloc] init];
    link.url = url;
    link.backgroundColor = self.wellColor;
    link.layer.cornerRadius = 12.0;
    link.translatesAutoresizingMaskIntoConstraints = NO;
    link.accessibilityLabel = [NSString stringWithFormat:@"%@，%@", title, subtitle];
    [link addTarget:self action:@selector(dk_openLink:) forControlEvents:UIControlEventTouchUpInside];

    UIView *badge = [[UIView alloc] init];
    badge.backgroundColor = self.badgeColor;
    badge.layer.cornerRadius = 10.0;
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageView *icon = DKSymbol(symbol, fallback, 13.0, self.textColor);
    [badge addSubview:icon];

    UILabel *name = DKLabel(title, [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold], self.textColor);
    UILabel *detail = DKLabel(subtitle, [UIFont systemFontOfSize:12.0], self.subColor);
    UIImageView *arrow = DKSymbol(@"arrow.up.right", @"arrow.up.right", 12.0, self.subColor);
    for (UIView *view in @[ badge, name, detail, arrow ]) {
        view.userInteractionEnabled = NO;
        [link addSubview:view];
    }

    [NSLayoutConstraint activateConstraints:@[
        [link.heightAnchor constraintEqualToConstant:60.0],
        [badge.leadingAnchor constraintEqualToAnchor:link.leadingAnchor constant:12.0],
        [badge.centerYAnchor constraintEqualToAnchor:link.centerYAnchor],
        [badge.widthAnchor constraintEqualToConstant:36.0],
        [badge.heightAnchor constraintEqualToConstant:36.0],
        [icon.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
        [name.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:12.0],
        [name.bottomAnchor constraintEqualToAnchor:link.centerYAnchor constant:1.0],
        [detail.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
        [detail.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:1.0],
        [detail.trailingAnchor constraintLessThanOrEqualToAnchor:arrow.leadingAnchor constant:-8.0],
        [arrow.trailingAnchor constraintEqualToAnchor:link.trailingAnchor constant:-14.0],
        [arrow.centerYAnchor constraintEqualToAnchor:link.centerYAnchor],
    ]];
    return link;
}

- (instancetype)init {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    UIColor *panel = DKDynamicColor(UIColor.whiteColor, DKRGB(0x232430, 1.0));
    UIColor *text = DKDynamicColor(DKRGB(0x161823, 1.0), [UIColor colorWithWhite:1.0 alpha:0.9]);
    UIColor *sub = DKDynamicColor(DKRGB(0x8A8B91, 1.0), [UIColor colorWithWhite:1.0 alpha:0.5]);
    UIColor *line = DKDynamicColor(DKRGB(0x161823, 0.06), [UIColor colorWithWhite:1.0 alpha:0.06]);
    self.textColor = text;
    self.subColor = sub;
    self.wellColor = DKDynamicColor(DKRGB(0xF4F5F7, 1.0), DKRGB(0x2D2E3B, 1.0));
    self.badgeColor = panel;

    self.backgroundColor = panel;
    self.layer.cornerRadius = 16.0;
    self.layer.masksToBounds = YES;
    self.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *name = DKLabel(kDKAuthorName, [UIFont systemFontOfSize:19.0 weight:UIFontWeightSemibold], text);
    UILabel *role = DKLabel(kDKAuthorRole, [UIFont systemFontOfSize:13.0], sub);

    // 仓库行与 Telegram 行。
    DKSettingsPressRow *repo = [self dk_linkRowWithSymbol:@"chevron.left.forwardslash.chevron.right" fallback:@"link"
                                                    title:kDKAuthorHandle subtitle:kDKRepoTitle url:kDKRepoURL];
    DKSettingsPressRow *telegram = [self dk_linkRowWithSymbol:@"paperplane" fallback:@"link"
                                                        title:kDKTelegramName subtitle:kDKTelegramTitle url:kDKTelegramURL];

    UIView *separator = [[UIView alloc] init];
    separator.backgroundColor = line;
    separator.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"关闭" forState:UIControlStateNormal];
    [close setTitleColor:text forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close addTarget:self action:@selector(dk_close) forControlEvents:UIControlEventTouchUpInside];

    for (UIView *view in @[ name, role, repo, telegram, separator, close ]) [self addSubview:view];

    [NSLayoutConstraint activateConstraints:@[
        [self.widthAnchor constraintEqualToConstant:300.0],
        [name.topAnchor constraintEqualToAnchor:self.topAnchor constant:26.0],
        [name.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [role.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:2.0],
        [role.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],

        [repo.topAnchor constraintEqualToAnchor:role.bottomAnchor constant:20.0],
        [repo.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16.0],
        [repo.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16.0],
        [telegram.topAnchor constraintEqualToAnchor:repo.bottomAnchor constant:20.0],
        [telegram.leadingAnchor constraintEqualToAnchor:repo.leadingAnchor],
        [telegram.trailingAnchor constraintEqualToAnchor:repo.trailingAnchor],

        [separator.topAnchor constraintEqualToAnchor:telegram.bottomAnchor constant:20.0],
        [separator.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [separator.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
        [close.topAnchor constraintEqualToAnchor:separator.bottomAnchor],
        [close.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [close.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [close.heightAnchor constraintEqualToConstant:50.0],
        [close.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
    return self;
}

- (void)dk_openLink:(DKSettingsPressRow *)sender {
    NSURL *url = sender.url.length ? [NSURL URLWithString:sender.url] : nil;
    if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
    [self dk_close];
}

- (void)dk_close {
    [gPopup dismiss];
}

@end

void DKSettingsShowAuthorCard(UIView *host) {
    DKSettingsPopupHost *popup = DKMakeHost(host, YES);
    if (!popup) return;
    DKSettingsAuthorCard *card = [[DKSettingsAuthorCard alloc] init];
    [popup addSubview:card];
    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:popup.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:popup.centerYAnchor],
    ]];
    [popup layoutIfNeeded];
    popup.content = card;
    [popup presentFromScale:1.06];
}
