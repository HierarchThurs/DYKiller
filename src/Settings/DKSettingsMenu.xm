//
//  DKSettingsMenu.xm
//  在「抖音设置」主页插入 DYKiller 入口，点击进入本插件设置页。
//  设置页内容由各功能模块通过 DKSettingsRegisterItem 注册，这里只负责收集与呈现。
//

#import "DouyinHeaders.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import <math.h>
#import <objc/runtime.h>

@interface _DKSliderRelay : NSObject
@property (nonatomic, copy) void (^block)(UISlider *slider);
- (void)changed:(UISlider *)sender;
@end

@implementation _DKSliderRelay
- (void)changed:(UISlider *)sender {
    if (self.block) self.block(sender);
}
@end

static char kDKSliderRelayKey;

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

#pragma mark - 液态玻璃设置项

static NSString *const kDKGlassOSTitleSuffix = @" (iOS26+)";

// 低系统：标题加后缀、灰掉、掐掉点击。在 builder 返回之后调用，盖住功能自己包的回调。
static void DKGlassLockItemIfNeeded(AWESettingItemModel *item) {
    if (!item || DKGlassOSAvailable() || !DKGlassIsGatedKey(item.identifier)) return;

    if (item.title.length && ![item.title hasSuffix:kDKGlassOSTitleSuffix]) {
        item.title = [item.title stringByAppendingString:kDKGlassOSTitleSuffix];
    }
    item.isEnable = NO;
    item.isSwitchOn = NO;
    __weak AWESettingItemModel *weakItem = item;
    item.switchChangedBlock = ^{
        weakItem.isSwitchOn = NO;
    };
    item.cellTappedBlock = nil;
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
    item.isSwitchOn = DKPrefBool(key);

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

#pragma mark - 滑条项工厂

static NSString *DKPercentSliderDetail(NSInteger percent) {
    if (percent <= 0) return @"抖音默认";
    if (percent >= 100) return @"胶囊";
    return [NSString stringWithFormat:@"%ld%%", (long)percent];
}

AWESettingItemModel *DKMakePercentSlider(NSString *key, NSString *title, NSString *message,
                                         NSInteger defaultPercent, void (^onChange)(NSInteger percent)) {
    AWESettingItemModel *item = [[%c(AWESettingItemModel) alloc] init];
    NSNumber *stored = [NSUserDefaults.standardUserDefaults objectForKey:key];
    NSInteger current = stored ? stored.integerValue : defaultPercent;
    if (current < 0) current = 0;
    if (current > 100) current = 100;

    item.identifier = key;
    item.title = title;
    item.detail = DKPercentSliderDetail(current);
    item.type = 0;
    item.cellType = 26;
    item.colorStyle = 0;
    item.isEnable = YES;

    __weak AWESettingItemModel *weakItem = item;
    void (^onChangeCopy)(NSInteger) = [onChange copy];
    item.cellTappedBlock = ^{
        UIViewController *presenter = gSettingsPresenter;
        if (!presenter) return;

        NSNumber *now = [NSUserDefaults.standardUserDefaults objectForKey:key];
        NSInteger value = now ? now.integerValue : defaultPercent;
        if (value < 0) value = 0;
        if (value > 100) value = 100;

        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:title
                                                message:message
                                         preferredStyle:UIAlertControllerStyleAlert];

        // 读数与滑块都用约束定位：box.view 建出来时是整屏宽，之后被 alert 压到自己的
        // 内容宽度，写死 frame 会在两侧留下不对称的空当。
        UIViewController *box = [[UIViewController alloc] init];
        box.preferredContentSize = CGSizeMake(250.0, 68.0);

        UILabel *readout = [[UILabel alloc] init];
        readout.text = DKPercentSliderDetail(value);
        readout.textAlignment = NSTextAlignmentCenter;
        readout.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
        readout.translatesAutoresizingMaskIntoConstraints = NO;
        [box.view addSubview:readout];

        UISlider *slider = [[UISlider alloc] init];
        slider.minimumValue = 0.0;
        slider.maximumValue = 100.0;
        slider.value = (float)value;
        slider.continuous = YES;
        slider.translatesAutoresizingMaskIntoConstraints = NO;
        [box.view addSubview:slider];

        [NSLayoutConstraint activateConstraints:@[
            [readout.topAnchor constraintEqualToAnchor:box.view.topAnchor constant:4.0],
            [readout.leadingAnchor constraintEqualToAnchor:box.view.leadingAnchor constant:16.0],
            [readout.trailingAnchor constraintEqualToAnchor:box.view.trailingAnchor constant:-16.0],
            [readout.heightAnchor constraintEqualToConstant:22.0],
            [slider.topAnchor constraintEqualToAnchor:readout.bottomAnchor constant:6.0],
            [slider.leadingAnchor constraintEqualToAnchor:box.view.leadingAnchor constant:16.0],
            [slider.trailingAnchor constraintEqualToAnchor:box.view.trailingAnchor constant:-16.0],
            [slider.heightAnchor constraintEqualToConstant:30.0]
        ]];
        [alert setValue:box forKey:@"contentViewController"];

        void (^applyValue)(float, BOOL) = ^(float raw, BOOL finish) {
            NSInteger percent = (NSInteger)lroundf(raw);
            if (percent < 0) percent = 0;
            if (percent > 100) percent = 100;
            // 拖动途中就把读数写上去，用的是和设置行同一套文案，两处不会出现两种说法。
            readout.text = DKPercentSliderDetail(percent);
            [NSUserDefaults.standardUserDefaults setInteger:percent forKey:key];
            if (onChangeCopy) onChangeCopy(percent);
            if (!finish) return;
            [NSUserDefaults.standardUserDefaults synchronize];
            weakItem.detail = DKPercentSliderDetail(percent);
            [DKFindTableView(presenter.view) reloadData];
        };

        _DKSliderRelay *relay = [[_DKSliderRelay alloc] init];
        relay.block = ^(UISlider *sender) { applyValue(sender.value, NO); };
        objc_setAssociatedObject(slider, &kDKSliderRelayKey, relay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [slider addTarget:relay action:@selector(changed:) forControlEvents:UIControlEventValueChanged];

        [alert addAction:[UIAlertAction actionWithTitle:@"完成"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            applyValue(slider.value, YES);
        }]];
        [presenter presentViewController:alert animated:YES completion:nil];
    };
    return item;
}

#pragma mark - 动作项工厂

AWESettingItemModel *DKMakeAction(NSString *key, NSString *title, NSString *detail,
                                  void (^onTap)(AWESettingItemModel *item, UIViewController *presenter)) {
    AWESettingItemModel *item = [[%c(AWESettingItemModel) alloc] init];
    item.identifier = key;
    item.title = title;
    item.detail = detail ?: @"";
    item.type = 0;
    item.cellType = 26;
    item.colorStyle = 0;
    item.isEnable = YES;

    __weak AWESettingItemModel *weakItem = item;
    void (^onTapCopy)(AWESettingItemModel *, UIViewController *) = [onTap copy];
    item.cellTappedBlock = ^{
        UIViewController *presenter = gSettingsPresenter;
        if (onTapCopy && presenter) onTapCopy(weakItem, presenter);
    };
    return item;
}

void DKSettingsReloadCurrentPage(void) {
    UIViewController *presenter = gSettingsPresenter;
    if (presenter) [DKFindTableView(presenter.view) reloadData];
}

#pragma mark - 设置页构建

static AWESettingSectionModel *DKMakeSection(NSString *header, NSArray *items) {
    AWESettingSectionModel *section = [[%c(AWESettingSectionModel) alloc] init];
    section.sectionHeaderTitle = header;
    section.sectionHeaderHeight = 40;
    section.type = 0;
    section.itemArray = items;
    return section;
}

// 手动建一个设置页：设导航标题，把 viewModel 挂在关联对象上供 viewModel getter 回落。
static AWESettingBaseViewController *DKMakeSettingsPage(NSString *title, NSArray *sections) {
    AWESettingBaseViewController *vc = [[%c(AWESettingBaseViewController) alloc] init];

    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIView *sub in vc.view.subviews) {
            if ([sub isKindOfClass:%c(AWENavigationBar)]) {
                AWENavigationBar *bar = (AWENavigationBar *)sub;
                if ([bar respondsToSelector:@selector(titleLabel)]) bar.titleLabel.text = title;
                break;
            }
        }
    });

    AWESettingsViewModel *viewModel = [[%c(AWESettingsViewModel) alloc] init];
    viewModel.colorStyle = 0;
    viewModel.sectionDataArray = sections;
    objc_setAssociatedObject(vc, &kViewModelKey, viewModel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return vc;
}

void DKSettingsPushPage(UIViewController *presenter, NSString *title, NSString *sectionHeader,
                        NSArray<AWESettingItemModel *> *items) {
    UINavigationController *nav = presenter.navigationController;
    if (!nav || items.count == 0) return;
    AWESettingBaseViewController *vc = DKMakeSettingsPage(title, @[ DKMakeSection(sectionHeader, items) ]);
    [nav pushViewController:vc animated:YES];
}

static void DKShowSettings(UIViewController *rootVC) {
    if (!rootVC) return;

    // 遍历注册表，按 header 分组（保持首次出现顺序），每项即时构建以反映当前开关状态
    NSMutableArray<NSString *> *headerOrder = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray *> *itemsByHeader = [NSMutableDictionary dictionary];
    for (NSDictionary *desc in DKSectionRegistry()) {
        NSString *header = desc[@"header"];
        DKSettingItemBuilder builder = desc[@"builder"];
        AWESettingItemModel *item = builder ? builder() : nil;
        if (!item) continue;
        DKGlassLockItemIfNeeded(item);
        NSMutableArray *arr = itemsByHeader[header];
        if (!arr) { arr = [NSMutableArray array]; itemsByHeader[header] = arr; [headerOrder addObject:header]; }
        [arr addObject:item];
    }

    NSMutableArray *sections = [NSMutableArray array];
    for (NSString *header in headerOrder) {
        [sections addObject:DKMakeSection(header, itemsByHeader[header])];
    }

    AWESettingBaseViewController *vc = DKMakeSettingsPage(@"DYKiller", sections);
    gSettingsPresenter = vc;
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

// 本插件的页面重新出现时（含从子页面返回）接回弹窗宿主，并刷新各行 detail。
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (!objc_getAssociatedObject(self, &kViewModelKey)) return;
    gSettingsPresenter = self;
    [DKFindTableView(self.view) reloadData];
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
