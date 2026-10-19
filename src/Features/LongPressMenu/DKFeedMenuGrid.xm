//
//  DKFeedMenuGrid.xm
//  长按菜单：作品长按菜单的宫格排列 —— 按设置把单按钮排成每行 2–4 个，带控件的整行项集中放在最下方。
//
//  实现：
//   - 分区：每行 2–4 个时，普通分组（groupType 0）的菜单项按原顺序拆成两组：单按钮全部聚到第一个普通分组的位置
//     （宫格区），整行项合成一组放在最后（长按钮区）；其它类型的分组位置不变。分区在 dataArray 取值时做，
//     取值钩子等所有 %ctor 跑完再装，套在插件保存项的插入之外，保存项也进宫格区。
//   - 整行项：带整行控件（倍速分段）、右侧附件里有开关或按钮、或没有点击动作的项，用原生行显示。
//   - 宫格区只改表格呈现：行数、行高、cell、即将显示与点击都按格子行处理。
//     每行 2 个：两个原生行 cell 半宽并排（图标在左、文字在右），右侧附件不显示；
//     每行 3–4 个：抖音现代长按面板的格子 cell（图标在上、文字在下）。
//   - 格子点击走面板的 executeActionForViewModel:，与原生行点击同一入口；卡片底由面板按行位置画。
//   - 设置在下一次打开菜单时生效。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKLongPressMenu.h"
#import "DKUtils.h"
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const kDKFeedGridCellID = @"DKFeedMenuGridCell";
// 抖音现代面板横排格子行的行高（cellHeight 对 groupType 11 的取值）。
static const CGFloat kDKFeedTileHeight = 73.0;
static const CGFloat kDKFeedCardInset = 16.0;

static char kDKFeedNeedsRowKey;

#pragma mark - 菜单项分类

static BOOL DKFeedViewHasControl(UIView *view, NSUInteger depth) {
    if (!view || depth > 4) return NO;
    if ([view isKindOfClass:UIControl.class]) return YES;
    for (UIView *subview in view.subviews) {
        if (DKFeedViewHasControl(subview, depth + 1)) return YES;
    }
    return NO;
}

// 基类的 configVM 是断言，只给覆写了它的类补一次配置，保证右侧附件已建好再分类。
static void DKFeedConfigureIfNeeded(id item) {
    Class base = NSClassFromString(@"AWELongPressPanelBaseViewModel");
    if (!base || ![item respondsToSelector:@selector(configVMIfNeeded)]) return;
    IMP own = class_getMethodImplementation(object_getClass(item), @selector(configVM));
    if (own == class_getMethodImplementation(base, @selector(configVM))) return;
    ((void (*)(id, SEL))objc_msgSend)(item, @selector(configVMIfNeeded));
}

// 同一菜单项只判一次：面板显示期间行数不能变。
static BOOL DKFeedItemNeedsRow(id item) {
    NSNumber *cached = objc_getAssociatedObject(item, &kDKFeedNeedsRowKey);
    if (cached) return cached.boolValue;
    BOOL row = YES;
    Class base = NSClassFromString(@"AWELongPressPanelBaseViewModel");
    if (base && [item isKindOfClass:base]) {
        DKFeedConfigureIfNeeded(item);
        AWELongPressPanelBaseViewModel *model = item;
        row = model.totalView != nil || model.action == nil || DKFeedViewHasControl(model.subView, 0);
    }
    objc_setAssociatedObject(item, &kDKFeedNeedsRowKey, @(row), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return row;
}

#pragma mark - 分区

// 宫格排列开启时把普通分组拆成宫格区与长按钮区；不需要时原样返回。
static NSArray *DKFeedZoneGroups(NSArray *groups) {
    if (DKLongPressMenuColumns(DKLongPressMenuFeed) < 2 || ![groups isKindOfClass:NSArray.class]) return groups;
    Class groupClass = NSClassFromString(@"AWELongPressPanelViewGroupModel");
    if (!groupClass) return groups;

    NSMutableArray *result = [NSMutableArray arrayWithCapacity:groups.count + 1];
    NSMutableArray *tiles = [NSMutableArray array];
    NSMutableArray *rows = [NSMutableArray array];
    AWELongPressPanelViewGroupModel *first = nil;
    NSUInteger tilePosition = 0;
    for (AWELongPressPanelViewGroupModel *group in groups) {
        NSArray *items = [group isKindOfClass:groupClass] && group.groupType == 0 ? group.groupArr : nil;
        if (![items isKindOfClass:NSArray.class]) {
            [result addObject:group];
            continue;
        }
        if (!first) {
            first = group;
            tilePosition = result.count;
        }
        for (id item in items) [(DKFeedItemNeedsRow(item) ? rows : tiles) addObject:item];
    }
    if (!first) return groups;

    id tileGroup = tiles.count ? DKFeedMenuCopyGroup(first, tiles) : nil;
    id rowGroup = rows.count ? DKFeedMenuCopyGroup(first, rows) : nil;
    if (tiles.count && !tileGroup) return groups;
    if (rows.count && !rowGroup) return groups;
    if (tileGroup) [result insertObject:tileGroup atIndex:tilePosition];
    if (rowGroup) [result addObject:rowGroup];
    return result;
}

#pragma mark - 宫格区映射

@interface DKFeedGridSection : NSObject
@property (nonatomic, strong) AWELongPressPanelViewGroupModel *group;
@property (nonatomic, copy) NSArray *items;
@property (nonatomic, assign) NSInteger columns;
@end

@implementation DKFeedGridSection

- (NSInteger)rows {
    return ((NSInteger)self.items.count + self.columns - 1) / self.columns;
}

// 本行格子在 groupArr 里的位置。
- (NSRange)rangeForRow:(NSInteger)row {
    NSInteger start = row * self.columns;
    if (row < 0 || start >= (NSInteger)self.items.count) return NSMakeRange(0, 0);
    return NSMakeRange(start, MIN(self.columns, (NSInteger)self.items.count - start));
}

- (NSArray *)itemsForRow:(NSInteger)row {
    return [self.items subarrayWithRange:[self rangeForRow:row]];
}

// 本行第一个格子对应的原 indexPath。
- (NSIndexPath *)dataIndexPath:(NSIndexPath *)indexPath {
    return [NSIndexPath indexPathForRow:[self rangeForRow:indexPath.row].location inSection:indexPath.section];
}

@end

// 只接管全是单按钮的普通分组（即宫格区）；含整行项的分组走原生。
static DKFeedGridSection *DKFeedGridSectionFor(AWELongPressPanelTableViewController *controller, NSInteger section) {
    NSInteger columns = DKLongPressMenuColumns(DKLongPressMenuFeed);
    if (columns < 2 || ![controller respondsToSelector:@selector(dataArray)]) return nil;
    NSArray *groups = controller.dataArray;
    if (![groups isKindOfClass:NSArray.class] || section < 0 || section >= (NSInteger)groups.count) return nil;
    Class groupClass = NSClassFromString(@"AWELongPressPanelViewGroupModel");
    AWELongPressPanelViewGroupModel *group = groups[section];
    if (!groupClass || ![group isKindOfClass:groupClass] || group.groupType != 0) return nil;
    NSArray *items = group.groupArr;
    if (![items isKindOfClass:NSArray.class] || items.count == 0) return nil;
    for (id item in items) {
        if (DKFeedItemNeedsRow(item)) return nil;
    }

    DKFeedGridSection *grid = [DKFeedGridSection new];
    grid.group = group;
    grid.items = items;
    grid.columns = columns;
    return grid;
}

#pragma mark - 格子

static UIColor *DKFeedHighlightColor(void) {
    Class config = NSClassFromString(@"AWEModernLongPressPanelUIConfig");
    id color = [config respondsToSelector:@selector(cellHighlightedColor)]
        ? ((id (*)(id, SEL))objc_msgSend)(config, @selector(cellHighlightedColor)) : nil;
    return [color isKindOfClass:UIColor.class] ? color : [UIColor colorWithWhite:0.5 alpha:0.15];
}

@interface DKFeedGridTile : UIControl
@property (nonatomic, strong) UIView *content;
@property (nonatomic, strong) UIView *highlight;
@property (nonatomic, strong) id viewModel;
@property (nonatomic, assign) NSInteger columns;
@property (nonatomic, weak) AWELongPressPanelTableViewController *controller;
@end

@implementation DKFeedGridTile

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _highlight = [[UIView alloc] initWithFrame:CGRectZero];
        _highlight.userInteractionEnabled = NO;
        _highlight.layer.cornerRadius = 8.0;
        _highlight.hidden = YES;
        [self addSubview:_highlight];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        [self addTarget:self action:@selector(dk_tapped) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (UIView *)dk_makeContentForModel:(id)model columns:(NSInteger)columns {
    if (columns == 2) {
        Class cls = NSClassFromString(@"AWELongPressPanelSettingCell");
        if (!cls) return nil;
        AWELongPressPanelSettingCell *cell = [[cls alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.backgroundColor = UIColor.clearColor;
        cell.contentView.backgroundColor = UIColor.clearColor;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [cell setLongPressPanelVM:model];
        return cell;
    }
    Class cls = NSClassFromString(@"AWEModernLongPressHorizontalSettingItemCell");
    if (!cls) return nil;
    AWEModernLongPressHorizontalSettingItemCell *cell = [cls new];
    [cell updateUI:model];
    return cell;
}

// 半宽原生行：卡片底由外层画，自带的卡片底、分割线与右侧附件不显示。
// 现代格子：只有 iconImage 的项（推荐、不感兴趣等）补上图标，去掉格子间的竖分割线。
- (void)dk_adjustContent {
    UIView *content = self.content;
    if ([content isKindOfClass:UITableViewCell.class]) {
        AWELongPressPanelSettingCell *cell = (AWELongPressPanelSettingCell *)content;
        if ([cell respondsToSelector:@selector(sectionBackgroundView)]) cell.sectionBackgroundView.hidden = YES;
        if ([cell respondsToSelector:@selector(sectionSeparatorView)]) cell.sectionSeparatorView.hidden = YES;
        UIView *right = [cell respondsToSelector:@selector(rightSubView)] ? cell.rightSubView : nil;
        if ([right isKindOfClass:UIView.class]) right.hidden = YES;
        return;
    }
    AWEModernLongPressHorizontalSettingItemCell *cell = (AWEModernLongPressHorizontalSettingItemCell *)content;
    if ([cell respondsToSelector:@selector(setSeparatorHidden:)]) [cell setSeparatorHidden:YES];
    UIImageView *icon = [cell respondsToSelector:@selector(buttonIcon)] ? cell.buttonIcon : nil;
    UIImage *image = [self.viewModel respondsToSelector:@selector(iconImage)]
        ? ((AWELongPressPanelBaseViewModel *)self.viewModel).iconImage : nil;
    if ([icon isKindOfClass:UIImageView.class] && !icon.image && [image isKindOfClass:UIImage.class]) icon.image = image;
}

- (void)dk_setViewModel:(id)model columns:(NSInteger)columns {
    if (model == self.viewModel && columns == self.columns && self.content) return;
    [self.content removeFromSuperview];
    self.viewModel = model;
    self.columns = columns;
    self.content = model ? [self dk_makeContentForModel:model columns:columns] : nil;
    if (self.content) {
        self.content.userInteractionEnabled = NO;
        [self insertSubview:self.content aboveSubview:self.highlight];
        [self dk_adjustContent];
    }
    AWELongPressPanelBaseViewModel *item = model;
    self.accessibilityLabel = [item respondsToSelector:@selector(describeString)] ? item.describeString : nil;
    BOOL disabled = [item respondsToSelector:@selector(disableInteraction)] && item.disableInteraction;
    self.enabled = model && !disabled;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // 原生行的内容区在行内左右各缩 16pt，宿主行向外各扩 16pt，内容区正好落在格子上。
    self.content.frame = self.columns == 2 ? CGRectInset(self.bounds, -kDKFeedCardInset, 0.0) : self.bounds;
    self.highlight.frame = CGRectInset(self.bounds, 4.0, 4.0);
    [self dk_adjustContent];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    if (highlighted) self.highlight.backgroundColor = DKFeedHighlightColor();
    self.highlight.hidden = !highlighted;
}

- (void)dk_tapped {
    AWELongPressPanelTableViewController *controller = self.controller;
    id model = self.viewModel;
    if (!controller || !model || ![controller respondsToSelector:@selector(executeActionForViewModel:)]) return;
    [controller executeActionForViewModel:model];
}

@end

@interface DKFeedGridCell : UITableViewCell
@property (nonatomic, strong) NSMutableArray<DKFeedGridTile *> *tiles;
@property (nonatomic, assign) NSInteger columns;
@end

@implementation DKFeedGridCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        _tiles = [NSMutableArray array];
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}

- (void)dk_configureItems:(NSArray *)items columns:(NSInteger)columns
               controller:(AWELongPressPanelTableViewController *)controller {
    self.columns = columns;
    while ((NSInteger)self.tiles.count < columns) {
        DKFeedGridTile *tile = [[DKFeedGridTile alloc] initWithFrame:CGRectZero];
        [self.contentView addSubview:tile];
        [self.tiles addObject:tile];
    }
    for (NSUInteger i = 0; i < self.tiles.count; i++) {
        DKFeedGridTile *tile = self.tiles[i];
        id model = (NSInteger)i < columns && i < items.count ? items[i] : nil;
        tile.controller = controller;
        [tile dk_setViewModel:model columns:columns];
        tile.hidden = model == nil;
    }
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.contentView.bounds;
    NSInteger columns = MAX(1, self.columns);
    // 格子在卡片宽度内等分，卡片与原生行一样左右各缩 16pt。
    CGFloat width = (CGRectGetWidth(bounds) - kDKFeedCardInset * 2.0) / columns;
    for (NSUInteger i = 0; i < self.tiles.count; i++) {
        self.tiles[i].frame = CGRectMake(kDKFeedCardInset + width * i, 0.0, width, CGRectGetHeight(bounds));
    }
}

@end

static void DKFeedGridTilesWillAppear(AWELongPressPanelTableViewController *controller, UITableView *tableView,
                                      UITableViewCell *cell, DKFeedGridSection *grid, NSIndexPath *indexPath) {
    if ([controller respondsToSelector:@selector(updateFirstScreenVisibleStatusForVMAtIndexPath:groupModel:)]) {
        NSRange range = [grid rangeForRow:indexPath.row];
        for (NSUInteger index = range.location; index < NSMaxRange(range); index++) {
            NSIndexPath *dataPath = [NSIndexPath indexPathForRow:(NSInteger)index inSection:indexPath.section];
            [controller updateFirstScreenVisibleStatusForVMAtIndexPath:dataPath groupModel:grid.group];
        }
    }
    // 与原生行一致：下一轮仍可见时执行各项的出现回调与曝光埋点。
    NSArray *items = [grid itemsForRow:indexPath.row];
    __weak UITableView *weakTable = tableView;
    __weak UITableViewCell *weakCell = cell;
    dispatch_async(dispatch_get_main_queue(), ^{
        UITableViewCell *strongCell = weakCell;
        if (!strongCell || ![weakTable.visibleCells containsObject:strongCell]) return;
        for (AWELongPressPanelBaseViewModel *item in items) {
            void (^appear)(void) = [item respondsToSelector:@selector(willAppearBlock)] ? item.willAppearBlock : nil;
            if (appear) appear();
            if ([item respondsToSelector:@selector(trackCellShow)]) [item trackCellShow];
        }
    });
}

#pragma mark - 钩子

%hook AWELongPressPanelTableViewController

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    DKFeedGridSection *grid = DKFeedGridSectionFor(self, section);
    return grid ? [grid rows] : %orig;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    DKFeedGridSection *grid = DKFeedGridSectionFor(self, indexPath.section);
    if (!grid) return %orig;
    if (grid.columns > 2) return kDKFeedTileHeight;
    return %orig(tableView, [grid dataIndexPath:indexPath]);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DKFeedGridSection *grid = DKFeedGridSectionFor(self, indexPath.section);
    if (!grid) return %orig;
    DKFeedGridCell *cell = [tableView dequeueReusableCellWithIdentifier:kDKFeedGridCellID];
    if (![cell isKindOfClass:DKFeedGridCell.class]) {
        cell = [[DKFeedGridCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kDKFeedGridCellID];
    }
    [cell dk_configureItems:[grid itemsForRow:indexPath.row] columns:grid.columns controller:self];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    DKFeedGridSection *grid = DKFeedGridSectionFor(self, indexPath.section);
    if (!grid) {
        %orig;
        return;
    }
    // 卡片圆角与分割线按格子行的位置画。
    if ([self respondsToSelector:@selector(setSectionCornreRadiusAndLines:forRowAtIndexPath:)]) {
        [self setSectionCornreRadiusAndLines:cell forRowAtIndexPath:indexPath];
    }
    DKFeedGridTilesWillAppear(self, tableView, cell, grid, indexPath);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!DKFeedGridSectionFor(self, indexPath.section)) {
        %orig;
        return;
    }
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
}

// 格子行由各格子自己处理按下与点击，整行不高亮。
%new
- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    return DKFeedGridSectionFor(self, indexPath.section) == nil;
}

%end

%group DKFeedZoneHooks

%hook AWELongPressPanelTableViewController

- (NSArray *)dataArray {
    return DKFeedZoneGroups(%orig);
}

%end

%end

static void DKFeedInstallZoneHooks(void) {
    Class panel = NSClassFromString(@"AWELongPressPanelTableViewController");
    if (panel && [panel instancesRespondToSelector:@selector(dataArray)]) %init(DKFeedZoneHooks);
}

%ctor {
    %init;
    // 插件保存项在 dataArray 取值时插入（DKFeedLongPressSave.xm 的 %ctor 安装）；
    // 分区钩子等所有 %ctor 跑完再装，套在它外面，看到的是已插入保存项的数据。
    dispatch_async(dispatch_get_main_queue(), ^{ DKFeedInstallZoneHooks(); });
}
