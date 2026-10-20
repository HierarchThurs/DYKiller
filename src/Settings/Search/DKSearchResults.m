// 搜索结果分组、行与分段标题。
#import "DKSearchViews.h"
#import "DKSearchIndex.h"
#import "DKSettingsInternal.h"
static const CGFloat kDKSearchHeaderHeight = 26.0;
static const CGFloat kDKSearchRowIconSide = 24.0;
static UIImage *DKSearchIconImage(NSString *name, CGFloat side) {
    if (!name.length) name = @"slider.horizontal.3";
    static NSMutableDictionary<NSString *, UIImage *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });
    NSString *key = [NSString stringWithFormat:@"%@@%.0f", name, side];
    UIImage *cached = cache[key];
    if (cached) return cached;
    UIImage *image = nil;
    if ([UIImage respondsToSelector:@selector(svg_userProfileImageWithName:size:color:)]) {
        image = [UIImage svg_userProfileImageWithName:name size:CGSizeMake(side, side) color:UIColor.blackColor];
    }
    if (!image) {
        UIImageSymbolConfiguration *config =
            [UIImageSymbolConfiguration configurationWithPointSize:side * 0.8 weight:UIImageSymbolWeightRegular];
        image = [UIImage systemImageNamed:@"slider.horizontal.3" withConfiguration:config];
    }
    if (!image) return nil;
    image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    cache[key] = image;
    return image;
}

#pragma mark - 结果行

@interface DKSearchResultCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIImageView *chevronView;
- (void)dkConfigureWithEntry:(DKSearchEntry *)entry;
@end

@implementation DKSearchResultCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _cardView = [[UIView alloc] init];
        _cardView.backgroundColor = UIColor.clearColor;
        _cardView.layer.cornerRadius = 10.0;
        _cardView.layer.cornerCurve = kCACornerCurveContinuous;
        _cardView.userInteractionEnabled = NO;
        [self.contentView addSubview:_cardView];

        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.tintColor = UIColor.labelColor;
        [self.contentView addSubview:_iconView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:17.0];
        _titleLabel.textColor = UIColor.labelColor;
        [self.contentView addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.font = [UIFont systemFontOfSize:12.0];
        _subtitleLabel.textColor = UIColor.secondaryLabelColor;
        _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_subtitleLabel];

        _chevronView = [[UIImageView alloc] init];
        _chevronView.contentMode = UIViewContentModeScaleAspectFit;
        _chevronView.tintColor = UIColor.tertiaryLabelColor;
        UIImageSymbolConfiguration *config =
            [UIImageSymbolConfiguration configurationWithPointSize:12.0 weight:UIImageSymbolWeightSemibold];
        _chevronView.image = [[UIImage systemImageNamed:@"chevron.right" withConfiguration:config]
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        [self.contentView addSubview:_chevronView];
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    UIColor *fill = [UIColor.labelColor colorWithAlphaComponent:0.10];
    [UIView animateWithDuration:highlighted ? 0.12 : 0.22 animations:^{
        self.cardView.backgroundColor = highlighted ? fill : UIColor.clearColor;
    }];
}

- (NSString *)dkSubtitleForEntry:(DKSearchEntry *)entry {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (entry.pageTitle.length) [parts addObject:entry.pageTitle];
    if (entry.sectionHeader.length && ![entry.sectionHeader isEqualToString:entry.pageTitle]) {
        [parts addObject:entry.sectionHeader];
    }
    NSString *base = [parts componentsJoinedByString:@" · "];
    if (entry.lockReason.length) {
        return base.length ? [NSString stringWithFormat:@"%@ · %@", base, entry.lockReason] : entry.lockReason;
    }
    return base;
}

- (void)dkConfigureWithEntry:(DKSearchEntry *)entry {
    self.titleLabel.text = entry.title;
    self.titleLabel.textColor = entry.lockReason.length ? UIColor.secondaryLabelColor : UIColor.labelColor;
    self.iconView.image = DKSearchIconImage(entry.icon, kDKSearchRowIconSide);
    self.iconView.tintColor = entry.lockReason.length ? UIColor.tertiaryLabelColor : UIColor.labelColor;
    self.subtitleLabel.text = [self dkSubtitleForEntry:entry];
    self.chevronView.hidden = !entry.isPageEntry;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.contentView.bounds;
    self.cardView.frame = CGRectInset(bounds, 4.0, 2.0);
    CGFloat leading = CGRectGetMinX(bounds) + 14.0;
    self.iconView.frame = CGRectMake(leading, round((CGRectGetHeight(bounds) - kDKSearchRowIconSide) / 2.0),
                                     kDKSearchRowIconSide, kDKSearchRowIconSide);
    CGFloat trailing = CGRectGetMaxX(bounds) - 14.0;
    self.chevronView.frame = CGRectMake(trailing - 6.0, round((CGRectGetHeight(bounds) - 14.0) / 2.0), 6.0, 14.0);
    if (!self.chevronView.isHidden) trailing = CGRectGetMinX(self.chevronView.frame) - 8.0;

    CGFloat textX = CGRectGetMaxX(self.iconView.frame) + 12.0;
    CGFloat textWidth = MAX(trailing - textX, 0.0);
    CGFloat titleHeight = ceil(self.titleLabel.font.lineHeight);
    CGFloat subtitleHeight = self.subtitleLabel.text.length ? ceil(self.subtitleLabel.font.lineHeight) : 0.0;
    CGFloat total = titleHeight + (subtitleHeight > 0.0 ? 2.0 + subtitleHeight : 0.0);
    CGFloat top = round((CGRectGetHeight(bounds) - total) / 2.0);
    self.titleLabel.frame = CGRectMake(textX, top, textWidth, titleHeight);
    self.subtitleLabel.frame = CGRectMake(textX, CGRectGetMaxY(self.titleLabel.frame) + 2.0, textWidth, subtitleHeight);
}

@end

#pragma mark - 分段标题

@interface DKSearchHeaderView : UITableViewHeaderFooterView
@property (nonatomic, strong) UILabel *titleLabel;
@end

@implementation DKSearchHeaderView

- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithReuseIdentifier:reuseIdentifier])) {
        self.contentView.backgroundColor = UIColor.clearColor;
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
        _titleLabel.textColor = UIColor.secondaryLabelColor;
        [self.contentView addSubview:_titleLabel];
    }
    return self;
}

// 新建时 contentView 还没有尺寸，标题按布局时的实际宽度排。
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.contentView.bounds;
    self.titleLabel.frame = CGRectMake(CGRectGetMinX(bounds) + 14.0, 0.0,
                                       MAX(CGRectGetWidth(bounds) - 28.0, 0.0), kDKSearchHeaderHeight);
}

@end

@implementation DKSearchResultsView {
    NSArray<NSArray<DKSearchEntry *> *> *_groups;
}
- (instancetype)initWithFrame:(CGRect)frame style:(UITableViewStyle)style {
    if ((self = [super initWithFrame:frame style:style])) {
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.backgroundColor = UIColor.clearColor;
        self.separatorStyle = UITableViewCellSeparatorStyleNone;
        self.dataSource = self;
        self.delegate = self;
        self.keyboardDismissMode = UIScrollViewKeyboardDismissModeNone;
        self.accessibilityLabel = @"搜索结果";
        self.rowHeight = 52.0;
        if (@available(iOS 15.0, *)) self.sectionHeaderTopPadding = 0.0;
        self.entries = @[];
    }
    return self;
}
- (void)setEntries:(NSArray<DKSearchEntry *> *)entries {
    _entries = [entries copy];
    NSMutableArray *current = [NSMutableArray array], *global = [NSMutableArray array];
    for (DKSearchEntry *entry in entries) [(entry.onCurrentPage ? current : global) addObject:entry];
    _groups = current.count ? @[ current, global ] : @[ global ];
    [self reloadData];
}
- (NSArray<DKSearchEntry *> *)dkEntriesInSection:(NSInteger)section {
    return section < (NSInteger)_groups.count ? _groups[section] : @[];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return _groups.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[self dkEntriesInSection:section].count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.rowHeight;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return [self numberOfSectionsInTableView:tableView] > 1 ? kDKSearchHeaderHeight : 0.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if ([self numberOfSectionsInTableView:tableView] <= 1) return nil;
    DKSearchHeaderView *header = [tableView dequeueReusableHeaderFooterViewWithIdentifier:@"DKSearchHeader"];
    if (!header) header = [[DKSearchHeaderView alloc] initWithReuseIdentifier:@"DKSearchHeader"];
    header.titleLabel.text = section == 0 ? @"本页" : @"全部设置";
    return header;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DKSearchResultCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DKSearchResultCell"];
    if (!cell) cell = [[DKSearchResultCell alloc] initWithStyle:UITableViewCellStyleDefault
                                               reuseIdentifier:@"DKSearchResultCell"];
    NSArray<DKSearchEntry *> *entries = [self dkEntriesInSection:indexPath.section];
    if (indexPath.row < (NSInteger)entries.count) [cell dkConfigureWithEntry:entries[indexPath.row]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    NSArray<DKSearchEntry *> *entries = [self dkEntriesInSection:indexPath.section];
    if (indexPath.row >= (NSInteger)entries.count) return;
    if (self.didChooseEntry) self.didChooseEntry(entries[indexPath.row]);
}

@end
