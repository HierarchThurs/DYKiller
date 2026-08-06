//
//  DKSettingsMenu.xm
//  在「抖音设置」主页插入 DYKiller 入口，点击进入本插件设置页。
//  设置页内容由各功能模块通过 DKSettingsRegisterItem 注册，这里只负责收集与呈现。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import <objc/runtime.h>

static char kViewModelKey;   // 手动创建的设置页把 viewModel 挂在这

#pragma mark - 分区注册表

static NSMutableArray<NSDictionary *> *DKSectionRegistry(void) {
    static NSMutableArray *registry;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ registry = [NSMutableArray array]; });
    return registry;
}

void DKSettingsRegisterItem(NSString *sectionHeader, DKSettingItemBuilder builder) {
    if (!sectionHeader || !builder) return;
    [DKSectionRegistry() addObject:@{ @"header": sectionHeader, @"builder": [builder copy] }];
}

#pragma mark - 开关项工厂

AWESettingItemModel *DKMakeSwitch(NSString *key, NSString *title, NSString *detail) {
    AWESettingItemModel *item = [[%c(AWESettingItemModel) alloc] init];
    item.identifier = key;
    item.title = title;
    item.detail = detail ?: @"";
    item.type = 0;
    item.cellType = 6;                 // 开关型 cell
    item.colorStyle = 0;
    item.isEnable = YES;
    item.isSwitchOn = [[NSUserDefaults standardUserDefaults] boolForKey:key];

    __weak AWESettingItemModel *weakItem = item;
    item.switchChangedBlock = ^{
        __strong AWESettingItemModel *it = weakItem;
        if (!it) return;
        BOOL v = !it.isSwitchOn;
        it.isSwitchOn = v;
        [[NSUserDefaults standardUserDefaults] setBool:v forKey:it.identifier];
        [[NSUserDefaults standardUserDefaults] synchronize];
    };
    return item;
}

#pragma mark - 单选项工厂

// 当前正在显示的设置页，供单选项弹对话框与选完刷新那一行。
static __weak UIViewController *gSettingsPresenter = nil;

static UITableView *DKFindTableView(UIView *root) {
    if ([root isKindOfClass:UITableView.class]) return (UITableView *)root;
    for (UIView *sub in root.subviews) {
        UITableView *found = DKFindTableView(sub);
        if (found) return found;
    }
    return nil;
}

AWESettingItemModel *DKMakeChoice(NSString *key, NSString *title, NSArray<NSString *> *options) {
    AWESettingItemModel *item = [[%c(AWESettingItemModel) alloc] init];
    NSInteger current = [[NSUserDefaults standardUserDefaults] integerForKey:key];
    if (current < 0 || current >= (NSInteger)options.count) current = 0;

    item.identifier = key;
    item.title = title;
    item.detail = options[current];
    item.type = 0;
    item.cellType = 26;                // 与 DYKiller 入口同型：可点击、右侧显示 detail
    item.colorStyle = 0;
    item.isEnable = YES;

    __weak AWESettingItemModel *weakItem = item;
    item.cellTappedBlock = ^{
        UIViewController *presenter = gSettingsPresenter;
        if (!presenter) return;
        UIAlertController *sheet =
            [UIAlertController alertControllerWithTitle:title message:nil
                                         preferredStyle:UIAlertControllerStyleActionSheet];
        [options enumerateObjectsUsingBlock:^(NSString *name, NSUInteger index, __unused BOOL *stop) {
            [sheet addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault
                                                   handler:^(__unused UIAlertAction *action) {
                [NSUserDefaults.standardUserDefaults setInteger:(NSInteger)index forKey:key];
                [NSUserDefaults.standardUserDefaults synchronize];
                // 这一行显示的就是所选值，不跟着变等于界面在说谎。改完就地刷新一次；
                // 找不到表格也只是要重进页面才更新，写入本身已经生效。
                weakItem.detail = name;
                [DKFindTableView(presenter.view) reloadData];
            }]];
        }];
        [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        // iPad 上 actionSheet 必须给锚点，否则直接抛异常。
        sheet.popoverPresentationController.sourceView = presenter.view;
        sheet.popoverPresentationController.sourceRect =
            CGRectMake(CGRectGetMidX(presenter.view.bounds), CGRectGetMidY(presenter.view.bounds), 1, 1);
        [presenter presentViewController:sheet animated:YES completion:nil];
    };
    return item;
}

#pragma mark - 设置页构建

static void DKShowSettings(UIViewController *rootVC) {
    if (!rootVC) return;

    AWESettingBaseViewController *vc = [[%c(AWESettingBaseViewController) alloc] init];
    gSettingsPresenter = vc;

    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIView *sub in vc.view.subviews) {
            if ([sub isKindOfClass:%c(AWENavigationBar)]) {
                AWENavigationBar *bar = (AWENavigationBar *)sub;
                if ([bar respondsToSelector:@selector(titleLabel)]) bar.titleLabel.text = @"DYKiller";
                break;
            }
        }
    });

    AWESettingsViewModel *viewModel = [[%c(AWESettingsViewModel) alloc] init];
    viewModel.colorStyle = 0;

    // 遍历注册表，按 header 分组（保持首次出现顺序），每项即时构建以反映当前开关状态
    NSMutableArray<NSString *> *headerOrder = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray *> *itemsByHeader = [NSMutableDictionary dictionary];
    for (NSDictionary *desc in DKSectionRegistry()) {
        NSString *header = desc[@"header"];
        DKSettingItemBuilder builder = desc[@"builder"];
        AWESettingItemModel *item = builder ? builder() : nil;
        if (!item) continue;
        NSMutableArray *arr = itemsByHeader[header];
        if (!arr) { arr = [NSMutableArray array]; itemsByHeader[header] = arr; [headerOrder addObject:header]; }
        [arr addObject:item];
    }

    NSMutableArray *sections = [NSMutableArray array];
    for (NSString *header in headerOrder) {
        AWESettingSectionModel *section = [[%c(AWESettingSectionModel) alloc] init];
        section.sectionHeaderTitle = header;
        section.sectionHeaderHeight = 40;
        section.type = 0;
        section.itemArray = itemsByHeader[header];
        [sections addObject:section];
    }

    viewModel.sectionDataArray = sections;
    objc_setAssociatedObject(vc, &kViewModelKey, viewModel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [rootVC.navigationController pushViewController:vc animated:YES];
}

#pragma mark - 钩子

// 手动创建的设置页 viewModel 为 nil 时，回落到我们挂载的关联对象
%hook AWESettingBaseViewController

- (AWESettingBaseViewModel *)viewModel {
    AWESettingBaseViewModel *orig = %orig;
    if (!orig) return objc_getAssociatedObject(self, &kViewModelKey);
    return orig;
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
