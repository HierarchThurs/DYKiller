//
//  DKSettingsMenu.xm
//  在「抖音设置」主页插入 DYKiller 入口，并按 DKSettingsLayout 建出各级设置页。
//  页面统一走 DKMakeSettingsPage：卡片样式、viewModel 挂在关联对象上、出现时接管弹窗宿主并重算联动锁。
//

#import "DKSettingsInternal.h"
#import "DKSettingsLayout.h"
#import "DKKeys.h"
#import <objc/runtime.h>

static char kDKViewModelKey;   // 手动创建的设置页把 viewModel 挂在这，有值即 DYKiller 页面
static char kDKPageNoteKey;    // 页面顶部说明文字
static char kDKPageNoteViewKey; // 承载顶部说明的表头视图

// 顶部说明的排版：左右缩进与抖音分区页脚文字一致（卡片外边距 16 + 文字缩进 16）。
static const CGFloat kDKNoteInset = 32.0;
static const CGFloat kDKNoteTop = 12.0;
static const CGFloat kDKNoteBottom = 4.0;

static NSString *const kDKUnplacedHeader = @"未归类";
static NSString *const kDKEmptyPlaceholder = @"暂无设置项";

#pragma mark - 注册表

static NSMutableDictionary<NSString *, DKSettingItemBuilder> *DKBuilderRegistry(void) {
    static NSMutableDictionary *registry;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ registry = [NSMutableDictionary dictionary]; });
    return registry;
}

void DKSettingsRegister(NSString *key, DKSettingItemBuilder builder) {
    if (!key.length || !builder) return;
    NSMutableDictionary *registry = DKBuilderRegistry();
    if (registry[key]) {
        NSLog(@"[DYKiller] 设置键重复登记，保留首个：%@", key);
        return;
    }
    registry[key] = [builder copy];
}

AWESettingItemModel *DKSettingsBuildItem(NSString *key) {
    if (!key) return nil;
    DKSettingItemBuilder builder = DKBuilderRegistry()[key];
    return builder ? builder() : nil;
}

NSArray<NSString *> *DKSettingsRegisteredKeys(void) {
    NSDictionary *registry = DKBuilderRegistry();
    NSMutableArray<NSString *> *keys = [NSMutableArray arrayWithCapacity:registry.count];
    for (NSString *key in DKSettingsLayoutOrderedKeys()) {
        if (registry[key]) [keys addObject:key];
    }
    NSSet<NSString *> *placed = DKSettingsLayoutKeys();
    for (NSString *key in [registry.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if (![placed containsObject:key]) [keys addObject:key];
    }
    return keys;
}

#pragma mark - 当前页

// 当前显示的 DYKiller 设置页；子页出现时由 viewWillAppear 接管。
static __weak AWESettingBaseViewController *gSettingsPresenter = nil;

UIViewController *DKSettingsCurrentPage(void) {
    return gSettingsPresenter;
}

static AWESettingsViewModel *DKPageViewModel(UIViewController *page) {
    return page ? objc_getAssociatedObject(page, &kDKViewModelKey) : nil;
}

static UITableView *DKPageTableView(UIViewController *page) {
    if (![page respondsToSelector:@selector(tableView)]) return nil;
    UITableView *table = ((AWESettingBaseViewController *)page).tableView;
    return [table isKindOfClass:UITableView.class] ? table : nil;
}

AWESettingItemModel *DKSettingsFindItem(UIViewController *page, NSString *identifier) {
    for (AWESettingSectionModel *section in DKPageViewModel(page).sectionDataArray) {
        for (AWESettingItemModel *item in section.itemArray) {
            if ([item.identifier isEqualToString:identifier]) return item;
        }
    }
    return nil;
}

void DKSettingsEnumerateItems(UIViewController *page, void (^block)(AWESettingItemModel *item)) {
    if (!block) return;
    for (AWESettingSectionModel *section in DKPageViewModel(page).sectionDataArray) {
        for (AWESettingItemModel *item in section.itemArray) block(item);
    }
}

void DKSettingsReloadCurrentPage(void) {
    UIViewController *page = gSettingsPresenter;
    DKSettingsApplyLocks(DKPageViewModel(page).sectionDataArray);
    [DKPageTableView(page) reloadData];
}

void DKSettingsValuesChanged(void) {
    UIViewController *page = gSettingsPresenter;
    NSArray<AWESettingItemModel *> *changed = DKSettingsApplyLocks(DKPageViewModel(page).sectionDataArray);
    for (AWESettingItemModel *item in changed) {
        if ([item respondsToSelector:@selector(refreshCell)]) [item refreshCell];
        else { [DKPageTableView(page) reloadData]; break; }
    }
}

#pragma mark - 建页

AWESettingSectionModel *DKSettingsMakeSection(NSString *header, NSString *footer, NSArray<AWESettingItemModel *> *items) {
    AWESettingSectionModel *section = [[%c(AWESettingSectionModel) alloc] init];
    section.sectionHeaderTitle = header;
    section.sectionHeaderHeight = 40;
    section.type = 0;
    section.itemArray = items;
    if (footer.length && [section respondsToSelector:@selector(setSectionFooterTitle:)]) {
        section.sectionFooterTitle = footer;
        if ([section respondsToSelector:@selector(setUseNewFooterLayout:)]) section.useNewFooterLayout = YES;
    }
    return section;
}

static void DKSetNavigationTitle(UIViewController *page, NSString *title) {
    for (UIView *sub in page.view.subviews) {
        if (![sub isKindOfClass:%c(AWENavigationBar)]) continue;
        AWENavigationBar *bar = (AWENavigationBar *)sub;
        if ([bar respondsToSelector:@selector(titleLabel)]) bar.titleLabel.text = title;
        return;
    }
}

static void DKShowEmptyPlaceholder(UIViewController *page) {
    UITableView *table = DKPageTableView(page);
    if (!table) return;
    UILabel *label = [[UILabel alloc] init];
    label.text = kDKEmptyPlaceholder;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:13.0];
    label.textColor = UIColor.secondaryLabelColor;
    table.backgroundView = label;
}

// 手动建一个设置页：卡片样式要在 viewDidLoad 前设好（抖音在那里按 useCardUIStyle 配样式）。
static AWESettingBaseViewController *DKMakeSettingsPage(NSString *title, NSArray *sections) {
    AWESettingBaseViewController *page = [[%c(AWESettingBaseViewController) alloc] init];
    if ([page respondsToSelector:@selector(setUseCardUIStyle:)]) page.useCardUIStyle = YES;
    if ([page respondsToSelector:@selector(setColorStyle:)]) page.colorStyle = 2;

    AWESettingsViewModel *viewModel = [[%c(AWESettingsViewModel) alloc] init];
    if ([viewModel respondsToSelector:@selector(setColorStyle:)]) viewModel.colorStyle = 2;
    viewModel.sectionDataArray = sections;
    objc_setAssociatedObject(page, &kDKViewModelKey, viewModel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKSettingsApplyLocks(sections);

    BOOL empty = sections.count == 0;
    dispatch_async(dispatch_get_main_queue(), ^{
        DKSetNavigationTitle(page, title);
        if (empty) DKShowEmptyPlaceholder(page);
    });
    return page;
}

// 顶部说明文字：字体与颜色取抖音分区页脚的说明文字，取不到时用 13pt 次要文字色；行数不限。
static UILabel *DKMakeNoteLabel(NSString *note) {
    UILabel *label = [[UILabel alloc] init];
    label.numberOfLines = 0;
    label.font = [UIFont systemFontOfSize:13.0];
    label.textColor = UIColor.secondaryLabelColor;
    Class footerClass = NSClassFromString(@"AWESettingsTableSectionFooterView");
    if ([footerClass instancesRespondToSelector:@selector(footerNoticeLabel)]) {
        AWESettingsTableSectionFooterView *footer = [[footerClass alloc] initWithReuseIdentifier:nil];
        UILabel *sample = footer.footerNoticeLabel;
        if ([sample isKindOfClass:UILabel.class]) {
            if (sample.font) label.font = sample.font;
            if (sample.textColor) label.textColor = sample.textColor;
        }
    }
    label.text = note;
    return label;
}

// 顶部说明放在表头视图里，按表格宽度算出完整高度；宽度或高度变了才重设表头。
static void DKLayoutPageNote(UIViewController *page) {
    NSString *note = objc_getAssociatedObject(page, &kDKPageNoteKey);
    UITableView *table = note.length ? DKPageTableView(page) : nil;
    CGFloat width = CGRectGetWidth(table.bounds);
    if (!table || width <= kDKNoteInset * 2.0) return;
    UIView *header = objc_getAssociatedObject(page, &kDKPageNoteViewKey);
    if (!header) {
        header = [[UIView alloc] initWithFrame:CGRectZero];
        [header addSubview:DKMakeNoteLabel(note)];
        objc_setAssociatedObject(page, &kDKPageNoteViewKey, header, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UILabel *label = header.subviews.firstObject;
    CGFloat textWidth = width - kDKNoteInset * 2.0;
    CGFloat textHeight = ceil([label sizeThatFits:CGSizeMake(textWidth, CGFLOAT_MAX)].height);
    CGRect frame = CGRectMake(0.0, 0.0, width, kDKNoteTop + textHeight + kDKNoteBottom);
    if (table.tableHeaderView == header && CGRectEqualToRect(header.frame, frame)) return;
    label.frame = CGRectMake(kDKNoteInset, kDKNoteTop, textWidth, textHeight);
    header.frame = frame;
    table.tableHeaderView = header;
}

static void DKPushPage(UIViewController *presenter, AWESettingBaseViewController *page) {
    UINavigationController *nav = presenter.navigationController;
    if (nav && page) [nav pushViewController:page animated:YES];
}

static NSArray<AWESettingSectionModel *> *DKBuildSections(NSArray<DKSettingsSection *> *layout);

// 子页 / 动作入口；图标由 DKSettingsPrepareItem 统一挂上。
static AWESettingItemModel *DKMakeEntry(NSString *identifier, NSString *title) {
    AWESettingItemModel *item = [[%c(AWESettingItemModel) alloc] init];
    item.identifier = identifier;
    item.title = title;
    item.detail = @"";
    item.type = 0;
    item.cellType = 26;                // 可点击跳转型 cell
    item.isEnable = YES;
    return item;
}

static AWESettingItemModel *DKMakePageEntry(DKSettingsPage *spec) {
    AWESettingItemModel *item = DKMakeEntry(spec.identifier, spec.title);
    __weak AWESettingItemModel *weakItem = item;
    item.cellTappedBlock = ^{
        UIViewController *presenter = DKSettingsCurrentPage();
        if (!presenter || !weakItem.isEnable) return;
        AWESettingBaseViewController *page = DKMakeSettingsPage(spec.title, DKBuildSections(spec.sections));
        if (spec.note.length) objc_setAssociatedObject(page, &kDKPageNoteKey, spec.note, OBJC_ASSOCIATION_COPY_NONATOMIC);
        DKPushPage(presenter, page);
    };
    return item;
}

static AWESettingItemModel *DKMakeLinkEntry(DKSettingsLink *spec) {
    AWESettingItemModel *item = DKMakeEntry(spec.title, spec.title);
    item.cellTappedBlock = ^{
        UIViewController *presenter = DKSettingsCurrentPage();
        if (!presenter) return;
        switch (spec.action) {
            case DKSettingsLinkAuthor: DKSettingsShowAuthorCard(presenter.view); break;
        }
    };
    return item;
}

// 布局分区 → 抖音分区；未登记的键与空分区跳过。
static NSArray<AWESettingSectionModel *> *DKBuildSections(NSArray<DKSettingsSection *> *layout) {
    NSMutableArray<AWESettingSectionModel *> *sections = [NSMutableArray array];
    for (DKSettingsSection *spec in layout) {
        NSMutableArray<AWESettingItemModel *> *items = [NSMutableArray array];
        for (id row in spec.rows) {
            AWESettingItemModel *item = nil;
            NSString *icon = nil;
            if ([row isKindOfClass:DKSettingsRow.class]) {
                item = DKSettingsBuildItem(((DKSettingsRow *)row).key);
                icon = ((DKSettingsRow *)row).icon;
            } else if ([row isKindOfClass:DKSettingsPage.class]) {
                item = DKMakePageEntry(row);
                icon = ((DKSettingsPage *)row).icon;
            } else if ([row isKindOfClass:DKSettingsLink.class]) {
                item = DKMakeLinkEntry(row);
                icon = ((DKSettingsLink *)row).icon;
            }
            if (!item) continue;
            DKSettingsPrepareItem(item, icon);
            [items addObject:item];
        }
        if (items.count) [sections addObject:DKSettingsMakeSection(spec.header, spec.footer, items)];
    }
    return sections;
}

// 已登记却没写进布局表的键，放进一级页末尾，提醒补布局表。
static AWESettingSectionModel *DKBuildUnplacedSection(void) {
    NSSet<NSString *> *placed = DKSettingsLayoutKeys();
    NSArray<NSString *> *keys = [DKBuilderRegistry().allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<AWESettingItemModel *> *items = [NSMutableArray array];
    for (NSString *key in keys) {
        if ([placed containsObject:key]) continue;
        AWESettingItemModel *item = DKSettingsBuildItem(key);
        if (!item) continue;
        DKSettingsPrepareItem(item, nil);
        [items addObject:item];
    }
    return items.count ? DKSettingsMakeSection(kDKUnplacedHeader, nil, items) : nil;
}

static AWESettingBaseViewController *DKMakeMainPage(void) {
    NSMutableArray *sections = [DKBuildSections(DKSettingsLayoutMain()) mutableCopy];
    AWESettingSectionModel *unplaced = DKBuildUnplacedSection();
    if (unplaced) [sections addObject:unplaced];

    AWESettingBaseViewController *page = DKMakeSettingsPage(@"DYKiller", sections);
    gSettingsPresenter = page;
    return page;
}

static void DKShowSettings(UIViewController *rootVC) {
    if (!rootVC) return;
    DKPushPage(rootVC, DKMakeMainPage());
}

void DKSettingsOpenMain(UIViewController *presenter) {
    if (!presenter.navigationController) return;
    AWESettingBaseViewController *page = DKMakeMainPage();
    page.hidesBottomBarWhenPushed = YES;
    DKPushPage(presenter, page);
}

void DKSettingsPushSections(UIViewController *presenter, NSString *title, NSArray<AWESettingSectionModel *> *sections) {
    DKSettingsPushNotedSections(presenter, title, nil, sections);
}

void DKSettingsPushNotedSections(UIViewController *presenter, NSString *title, NSString *note,
                                 NSArray<AWESettingSectionModel *> *sections) {
    if (!presenter.navigationController || sections.count == 0) return;
    for (AWESettingSectionModel *section in sections) {
        for (AWESettingItemModel *item in section.itemArray) DKSettingsPrepareItem(item, nil);
    }
    AWESettingBaseViewController *page = DKMakeSettingsPage(title, sections);
    if (note.length) objc_setAssociatedObject(page, &kDKPageNoteKey, [note copy], OBJC_ASSOCIATION_COPY_NONATOMIC);
    DKPushPage(presenter, page);
}

void DKSettingsPushPage(UIViewController *presenter, NSString *title, NSString *sectionHeader,
                        NSArray<AWESettingItemModel *> *items) {
    if (items.count == 0) return;
    DKSettingsPushSections(presenter, title, @[ DKSettingsMakeSection(sectionHeader, nil, items) ]);
}

#pragma mark - 钩子

static AWESettingItemModel *DKOwnItemAtIndexPath(AWESettingBaseViewController *page, NSIndexPath *indexPath) {
    NSArray *sections = DKPageViewModel(page).sectionDataArray;
    if (indexPath.section >= (NSInteger)sections.count) return nil;
    NSArray *items = ((AWESettingSectionModel *)sections[indexPath.section]).itemArray;
    if (indexPath.row >= (NSInteger)items.count) return nil;
    AWESettingItemModel *item = items[indexPath.row];
    return DKSettingsIsOwnItem(item) ? item : nil;
}

%hook AWESettingBaseViewController

// 手动创建的设置页 viewModel 为 nil 时，回落到我们挂载的关联对象
- (AWESettingBaseViewModel *)viewModel {
    AWESettingBaseViewModel *orig = %orig;
    if (!orig) return objc_getAssociatedObject(self, &kDKViewModelKey);
    return orig;
}

// 本插件的页面重新出现时（含从子页面返回）接回弹窗宿主，重算联动锁并刷新各行。
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (!DKPageViewModel(self)) return;
    gSettingsPresenter = self;
    DKSettingsReloadCurrentPage();
}

- (void)viewDidLayoutSubviews {
    %orig;
    DKLayoutPageNote(self);
}

// 抖音点行时直接调 cellTappedBlock，不看 isEnable；灰显项在这里拦下。
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    AWESettingItemModel *item = DKPageViewModel(self) ? DKOwnItemAtIndexPath(self, indexPath) : nil;
    if (item && !item.isEnable) {
        [tableView deselectRowAtIndexPath:indexPath animated:NO];
        return;
    }
    %orig;
}

%new
- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    AWESettingItemModel *item = DKPageViewModel(self) ? DKOwnItemAtIndexPath(self, indexPath) : nil;
    return !(item && !item.isEnable);
}

%end

// 在抖音设置主页插入 DYKiller 分区
%hook AWESettingsViewModel

- (NSArray *)sectionDataArray {
    NSArray *sections = %orig;
    if (![sections isKindOfClass:[NSArray class]]) return sections;

    BOOL isMainPage = NO, exists = NO;
    for (AWESettingSectionModel *s in sections) {
        if (![s respondsToSelector:@selector(sectionHeaderTitle)]) continue;
        if ([s.sectionHeaderTitle isEqualToString:@"账号"])    isMainPage = YES;
        if ([s.sectionHeaderTitle isEqualToString:@"DYKiller"]) exists = YES;
    }
    if (!isMainPage || exists) return sections;

    AWESettingItemModel *entry = [[%c(AWESettingItemModel) alloc] init];
    entry.identifier = @"DYKiller";
    entry.title = @"DYKiller";
    entry.detail = DK_VERSION;
    entry.type = 0;
    entry.svgIconImageName = @"ic_gearsimplify_outlined_20";
    entry.cellType = 26;               // 可点击跳转型 cell
    entry.colorStyle = 0;
    entry.isEnable = YES;

    __weak AWESettingsViewModel *weakSelf = self;
    entry.cellTappedBlock = ^{
        __strong AWESettingsViewModel *s = weakSelf;
        DKShowSettings((UIViewController *)s.controllerDelegate);
    };

    AWESettingSectionModel *newSection = [[%c(AWESettingSectionModel) alloc] init];
    newSection.itemArray = @[ entry ];
    newSection.type = 0;
    newSection.sectionHeaderHeight = 40;
    newSection.sectionHeaderTitle = @"DYKiller";

    NSMutableArray *result = [NSMutableArray arrayWithArray:sections];
    [result insertObject:newSection atIndex:0];
    return result;
}

%end
