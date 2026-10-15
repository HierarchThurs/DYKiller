//
//  DKSettingsCell.xm
//  设置行的 ⓘ：带说明文案的 DYKiller 项在标题文字末尾挂一个按钮，点开说明气泡。
//  按钮挂在 contentView 上：卡片样式下标题在 containerView 里，灰显时抖音调暗的是那一层，
//  ⓘ 不随之变暗；行未被 disableCell，灰显时按钮仍可点。
//  破坏性项：标题由项上的 titleColor 着红色；图标在抖音配色之后换成红色版本。
//

#import "DKSettingsInternal.h"
#import <objc/runtime.h>

static char kDKInfoButtonKey;
static char kDKTintedIconKey;   // 已换成红色版本的图标，避免重复着色

static const CGFloat kDKInfoHitSide = 28.0;
// 热区比图标宽，左缘往回收，图标与标题文字间距约 4pt。
static const CGFloat kDKInfoLeading = -2.0;

@interface AWESettingsTableViewCell (DKInfo)
- (void)dk_infoTapped:(UIButton *)sender;
@end

static NSString *DKCellInfo(AWESettingsTableViewCell *cell) {
    AWESettingItemModel *item = [cell respondsToSelector:@selector(itemModel)] ? cell.itemModel : nil;
    return DKSettingsIsOwnItem(item) ? DKSettingsItemInfo(item) : nil;
}

// 只给有说明的行建按钮；复用到抖音自己的行时按钮留着但隐藏。
static UIButton *DKInfoButton(AWESettingsTableViewCell *cell, BOOL create) {
    UIButton *button = objc_getAssociatedObject(cell, &kDKInfoButtonKey);
    if (button || !create) return button;
    button = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImageSymbolConfiguration *config =
        [UIImageSymbolConfiguration configurationWithPointSize:14.0 weight:UIImageSymbolWeightRegular];
    [button setImage:[UIImage systemImageNamed:@"info.circle" withConfiguration:config]
            forState:UIControlStateNormal];
    button.accessibilityLabel = @"说明";
    [button addTarget:cell action:@selector(dk_infoTapped:) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(cell, &kDKInfoButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return button;
}

static void DKInfoButtonLayout(AWESettingsTableViewCell *cell) {
    NSString *info = DKCellInfo(cell);
    UILabel *title = [cell respondsToSelector:@selector(titleLabel)] ? cell.titleLabel : nil;
    UIButton *button = DKInfoButton(cell, info && title);
    if (!button) return;

    BOOL visible = info && title.superview && !title.hidden && title.text.length;
    button.hidden = !visible;
    if (!visible) return;

    UIView *host = cell.contentView;
    if (button.superview != host) [host addSubview:button];
    else if (host.subviews.lastObject != button) [host bringSubviewToFront:button];

    CGRect titleRect = [title convertRect:title.bounds toView:host];
    CGSize fit = [title sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGRectGetHeight(titleRect))];
    CGFloat textWidth = MIN(ceil(fit.width), CGRectGetWidth(titleRect));
    button.tintColor = [title.textColor colorWithAlphaComponent:0.45];
    button.frame = CGRectMake(CGRectGetMinX(titleRect) + textWidth + kDKInfoLeading,
                              CGRectGetMidY(titleRect) - kDKInfoHitSide / 2.0,
                              kDKInfoHitSide, kDKInfoHitSide);
}

// 用图标的 alpha 作蒙版填红色；抖音换了图标后按新图标重新着色。
static void DKDestructiveIconLayout(AWESettingsTableViewCell *cell) {
    AWESettingItemModel *item = [cell respondsToSelector:@selector(itemModel)] ? cell.itemModel : nil;
    if (!DKSettingsIsOwnItem(item) || !DKSettingsItemIsDestructive(item)) return;
    UIImageView *iconView = [cell respondsToSelector:@selector(iconImageView)] ? cell.iconImageView : nil;
    UIImage *icon = iconView.image;
    if (!icon || objc_getAssociatedObject(iconView, &kDKTintedIconKey) == icon) return;

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat formatForTraitCollection:icon.traitCollection];
    format.scale = icon.scale;
    format.opaque = NO;
    CGRect bounds = (CGRect){ CGPointZero, icon.size };
    UIImage *red = [[[UIGraphicsImageRenderer alloc] initWithSize:icon.size format:format]
        imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [icon drawInRect:bounds];
            [UIColor.systemRedColor setFill];
            UIRectFillUsingBlendMode(bounds, kCGBlendModeSourceIn);
        }];
    red = [red imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    iconView.image = red;
    objc_setAssociatedObject(iconView, &kDKTintedIconKey, red, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook AWESettingsTableViewCell

- (void)setItemModel:(id)model {
    %orig;
    DKInfoButtonLayout(self);
    DKDestructiveIconLayout(self);
}

// 抖音在这里按深浅色重配标题与图标颜色，红色图标要在它之后补上。
- (void)updateSubviewsColor {
    %orig;
    DKDestructiveIconLayout(self);
}

// 抖音在这里强制完成 containerView 布局，标题 frame 此时已是最终值。
- (void)updateSubviewsAfterLayout {
    %orig;
    DKInfoButtonLayout(self);
}

- (void)layoutSubviews {
    %orig;
    DKInfoButtonLayout(self);
}

%new
- (void)dk_infoTapped:(UIButton *)sender {
    NSString *info = DKCellInfo(self);
    if (!info) return;
    AWESettingItemModel *item = self.itemModel;
    NSString *reason = item.isEnable ? nil : DKSettingsLockReason(item);
    DKSettingsShowTip(sender, reason ? [NSString stringWithFormat:@"%@\n%@", info, reason] : info);
}

%end
