//
//  DKSettingsItems.xm
//  设置项工厂与项上的标记（ⓘ 说明、单选类型）。
//  回调先看 isEnable：灰显项由页面 hook 拦住点击，这里再兜底，锁解除后无需重建回调。
//

#import "DKSettingsInternal.h"
#import <math.h>
#import <objc/runtime.h>

static char kDKInfoKey;
static char kDKChoiceKey;
static char kDKSliderRelayKey;

@interface _DKSliderRelay : NSObject
@property (nonatomic, copy) void (^block)(UISlider *slider);
- (void)changed:(UISlider *)sender;
@end

@implementation _DKSliderRelay
- (void)changed:(UISlider *)sender {
    if (self.block) self.block(sender);
}
@end

#pragma mark - 项标记

AWESettingItemModel *DKSettingsWithInfo(AWESettingItemModel *item, NSString *info) {
    if (item) objc_setAssociatedObject(item, &kDKInfoKey, info, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return item;
}

NSString *DKSettingsItemInfo(AWESettingItemModel *item) {
    NSString *info = item ? objc_getAssociatedObject(item, &kDKInfoKey) : nil;
    return info.length ? info : nil;
}

BOOL DKSettingsItemIsChoice(AWESettingItemModel *item) {
    return item && [objc_getAssociatedObject(item, &kDKChoiceKey) boolValue];
}

static AWESettingItemModel *DKMakeItem(NSString *key, NSString *title, NSInteger cellType) {
    AWESettingItemModel *item = [[%c(AWESettingItemModel) alloc] init];
    item.identifier = key;
    item.title = title;
    item.detail = @"";
    item.type = 0;
    item.cellType = cellType;
    item.isEnable = YES;
    return item;
}

// 当前页列表里显示该项的可见行。
static UITableViewCell *DKSettingsCellForItem(UIViewController *presenter, AWESettingItemModel *item) {
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:presenter.view];
    while (queue.count) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([view isKindOfClass:UITableView.class]) {
            for (UITableViewCell *cell in ((UITableView *)view).visibleCells) {
                if (![cell respondsToSelector:@selector(itemModel)]) continue;
                AWESettingItemModel *model = [(id)cell itemModel];
                if (model == item || [model.identifier isEqualToString:item.identifier]) return cell;
            }
            continue;
        }
        [queue addObjectsFromArray:view.subviews];
    }
    return nil;
}

// 弹出框锚在被点的行上：箭头指向行右侧的当前值，展开动画从这一行出来。
// iPad 上 actionSheet 必须给锚点，找不到行时退回页面中心。
static void DKPresentFromSettings(UIViewController *presenter, UIViewController *controller, AWESettingItemModel *item) {
    UIPopoverPresentationController *popover = controller.popoverPresentationController;
    UITableViewCell *cell = item ? DKSettingsCellForItem(presenter, item) : nil;
    if (cell) {
        CGRect bounds = cell.bounds;
        CGFloat width = MIN(160.0, CGRectGetWidth(bounds) / 2.0);
        popover.sourceView = cell;
        popover.sourceRect = CGRectMake(CGRectGetMaxX(bounds) - width - 16.0, CGRectGetMinY(bounds), width, CGRectGetHeight(bounds));
        popover.permittedArrowDirections = UIPopoverArrowDirectionUp | UIPopoverArrowDirectionDown;
    } else {
        popover.sourceView = presenter.view;
        popover.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds), CGRectGetMidY(presenter.view.bounds), 1, 1);
    }
    [presenter presentViewController:controller animated:YES completion:nil];
}

#pragma mark - 开关

AWESettingItemModel *DKMakeSwitch(NSString *key, NSString *title, NSString *detail) {
    // cellType 6：开关行。detail 不写进项里，卡片样式下它会显示成副标题。
    AWESettingItemModel *item = DKSettingsWithInfo(DKMakeItem(key, title, 6), detail);
    item.isSwitchOn = [NSUserDefaults.standardUserDefaults boolForKey:key];

    __weak AWESettingItemModel *weakItem = item;
    item.switchChangedBlock = ^{
        __strong AWESettingItemModel *it = weakItem;
        if (!it.isEnable) return;
        BOOL value = !it.isSwitchOn;
        it.isSwitchOn = value;
        [NSUserDefaults.standardUserDefaults setBool:value forKey:it.identifier];
        DKSettingsValuesChanged();
    };
    return item;
}

#pragma mark - 单选

// 单选行：点击弹出框，选中后交给 apply 写入。current 越界时按第 0 项显示。
static AWESettingItemModel *DKMakeChoiceItem(NSString *key, NSString *title, NSArray<NSString *> *options,
                                             NSInteger current, void (^apply)(NSInteger index)) {
    if (current < 0 || current >= (NSInteger)options.count) current = 0;

    // cellType 26：可点击、右侧显示 detail 与箭头。
    AWESettingItemModel *item = DKMakeItem(key, title, 26);
    item.detail = options[current];
    objc_setAssociatedObject(item, &kDKChoiceKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    __weak AWESettingItemModel *weakItem = item;
    void (^applyCopy)(NSInteger) = [apply copy];
    item.cellTappedBlock = ^{
        UIViewController *presenter = DKSettingsCurrentPage();
        if (!presenter || !weakItem.isEnable) return;
        UIAlertController *sheet =
            [UIAlertController alertControllerWithTitle:title message:nil
                                         preferredStyle:UIAlertControllerStyleActionSheet];
        [options enumerateObjectsUsingBlock:^(NSString *name, NSUInteger index, __unused BOOL *stop) {
            [sheet addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault
                                                   handler:^(__unused UIAlertAction *action) {
                if (applyCopy) applyCopy((NSInteger)index);
                weakItem.detail = name;
                DKSettingsReloadCurrentPage();
            }]];
        }];
        [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        DKPresentFromSettings(presenter, sheet, weakItem);
    };
    return item;
}

AWESettingItemModel *DKMakeChoice(NSString *key, NSString *title, NSArray<NSString *> *options) {
    NSInteger current = [NSUserDefaults.standardUserDefaults integerForKey:key];
    return DKMakeChoiceItem(key, title, options, current, ^(NSInteger index) {
        [NSUserDefaults.standardUserDefaults setInteger:index forKey:key];
    });
}

AWESettingItemModel *DKMakeGlassChoice(NSString *key, NSString *clearKey, NSString *title, void (^onChange)(void)) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSInteger current = [defaults boolForKey:key] ? ([defaults boolForKey:clearKey] ? 2 : 1) : 0;
    void (^onChangeCopy)(void) = [onChange copy];
    return DKMakeChoiceItem(key, title, @[ @"关闭", @"模糊玻璃", @"清透玻璃" ], current, ^(NSInteger index) {
        [NSUserDefaults.standardUserDefaults setBool:index > 0 forKey:key];
        [NSUserDefaults.standardUserDefaults setBool:index == 2 forKey:clearKey];
        if (onChangeCopy) onChangeCopy();
    });
}

#pragma mark - 百分比滑条

static NSString *DKPercentSliderDetail(NSInteger percent) {
    if (percent <= 0) return @"抖音默认";
    if (percent >= 100) return @"胶囊";
    return [NSString stringWithFormat:@"%ld%%", (long)percent];
}

static NSInteger DKClampPercent(NSInteger value) {
    return MIN(100, MAX(0, value));
}

AWESettingItemModel *DKMakePercentSlider(NSString *key, NSString *title, NSString *message,
                                         NSInteger defaultPercent, void (^onChange)(NSInteger percent)) {
    NSNumber *stored = [NSUserDefaults.standardUserDefaults objectForKey:key];
    AWESettingItemModel *item = DKMakeItem(key, title, 26);
    item.detail = DKPercentSliderDetail(DKClampPercent(stored ? stored.integerValue : defaultPercent));

    __weak AWESettingItemModel *weakItem = item;
    void (^onChangeCopy)(NSInteger) = [onChange copy];
    item.cellTappedBlock = ^{
        UIViewController *presenter = DKSettingsCurrentPage();
        if (!presenter || !weakItem.isEnable) return;

        NSNumber *now = [NSUserDefaults.standardUserDefaults objectForKey:key];
        NSInteger value = DKClampPercent(now ? now.integerValue : defaultPercent);

        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:title message:message
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

        // 拖动途中就写入并回调，读数与设置行用同一套文案；点「完成」才刷新设置页。
        void (^applyValue)(float, BOOL) = ^(float raw, BOOL finish) {
            NSInteger percent = DKClampPercent((NSInteger)lroundf(raw));
            readout.text = DKPercentSliderDetail(percent);
            [NSUserDefaults.standardUserDefaults setInteger:percent forKey:key];
            if (onChangeCopy) onChangeCopy(percent);
            if (!finish) return;
            weakItem.detail = DKPercentSliderDetail(percent);
            DKSettingsReloadCurrentPage();
        };

        _DKSliderRelay *relay = [[_DKSliderRelay alloc] init];
        relay.block = ^(UISlider *sender) { applyValue(sender.value, NO); };
        objc_setAssociatedObject(slider, &kDKSliderRelayKey, relay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [slider addTarget:relay action:@selector(changed:) forControlEvents:UIControlEventValueChanged];

        [alert addAction:[UIAlertAction actionWithTitle:@"完成" style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            applyValue(slider.value, YES);
        }]];
        [presenter presentViewController:alert animated:YES completion:nil];
    };
    return item;
}

#pragma mark - 动作

AWESettingItemModel *DKMakeAction(NSString *key, NSString *title, NSString *detail,
                                  void (^onTap)(AWESettingItemModel *item, UIViewController *presenter)) {
    AWESettingItemModel *item = DKMakeItem(key, title, 26);
    item.detail = detail ?: @"";

    __weak AWESettingItemModel *weakItem = item;
    void (^onTapCopy)(AWESettingItemModel *, UIViewController *) = [onTap copy];
    item.cellTappedBlock = ^{
        UIViewController *presenter = DKSettingsCurrentPage();
        if (onTapCopy && presenter && weakItem.isEnable) onTapCopy(weakItem, presenter);
    };
    return item;
}
