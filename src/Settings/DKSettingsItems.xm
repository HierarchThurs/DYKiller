//
//  DKSettingsItems.xm
//  设置项工厂与项上的标记（ⓘ 说明、单选类型、值声明、值变化回调与备份标记）。
//  标准工厂建项时同时声明落盘值；写入后统一调项上的 onChange，恢复写入后也调同一个。
//  回调先看 isEnable：灰显项由页面 hook 拦住点击，这里再兜底，锁解除后无需重建回调。
//

#import "DKSettingsInternal.h"
#import "DKAdjustRange.h"
#import <math.h>
#import <objc/runtime.h>

static char kDKInfoKey;
static char kDKChoiceKey;
static char kDKSliderRelayKey;
static char kDKValuesKey;
static char kDKDescribeKey;
static char kDKOnChangeKey;
static char kDKNoBackupKey;
static char kDKRestartKey;
static char kDKDestructiveKey;

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

static BOOL DKItemFlag(AWESettingItemModel *item, const void *key) {
    return item && [objc_getAssociatedObject(item, key) boolValue];
}

static AWESettingItemModel *DKSetItemFlag(AWESettingItemModel *item, const void *key) {
    if (item) objc_setAssociatedObject(item, key, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return item;
}

AWESettingItemModel *DKSettingsWithValues(AWESettingItemModel *item, NSArray<DKSettingsValue *> *values,
                                          DKSettingsDescribe describe) {
    if (!item) return item;
    objc_setAssociatedObject(item, &kDKValuesKey, values, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(item, &kDKDescribeKey, describe, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return item;
}

AWESettingItemModel *DKSettingsOnChange(AWESettingItemModel *item, dispatch_block_t onChange) {
    if (item) objc_setAssociatedObject(item, &kDKOnChangeKey, onChange, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return item;
}

AWESettingItemModel *DKSettingsWithoutBackup(AWESettingItemModel *item) {
    return DKSetItemFlag(item, &kDKNoBackupKey);
}

AWESettingItemModel *DKSettingsNeedsRestart(AWESettingItemModel *item) {
    return DKSetItemFlag(item, &kDKRestartKey);
}

AWESettingItemModel *DKSettingsMarkDestructive(AWESettingItemModel *item) {
    if (item && [item respondsToSelector:@selector(setTitleColor:)]) item.titleColor = UIColor.systemRedColor;
    return DKSetItemFlag(item, &kDKDestructiveKey);
}

NSArray<DKSettingsValue *> *DKSettingsItemValues(AWESettingItemModel *item) {
    return item ? objc_getAssociatedObject(item, &kDKValuesKey) : nil;
}

DKSettingsDescribe DKSettingsItemDescribe(AWESettingItemModel *item) {
    return item ? objc_getAssociatedObject(item, &kDKDescribeKey) : nil;
}

dispatch_block_t DKSettingsItemOnChange(AWESettingItemModel *item) {
    return item ? objc_getAssociatedObject(item, &kDKOnChangeKey) : nil;
}

BOOL DKSettingsItemExcludedFromBackup(AWESettingItemModel *item) {
    return DKItemFlag(item, &kDKNoBackupKey);
}

BOOL DKSettingsItemNeedsRestart(AWESettingItemModel *item) {
    return DKItemFlag(item, &kDKRestartKey);
}

BOOL DKSettingsItemIsDestructive(AWESettingItemModel *item) {
    return DKItemFlag(item, &kDKDestructiveKey);
}

static void DKRunOnChange(AWESettingItemModel *item) {
    dispatch_block_t onChange = DKSettingsItemOnChange(item);
    if (onChange) onChange();
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

#pragma mark - 锁定显示

// 存值越界或未设置时按第 0 项显示，与 DKMakeChoiceItem 一致。
static NSString *DKOptionText(NSArray<NSString *> *options, NSInteger index) {
    return options[index >= 0 && index < (NSInteger)options.count ? index : 0];
}

BOOL DKSettingsShowValue(AWESettingItemModel *item, NSNumber *lockedValue) {
    NSArray<DKSettingsValue *> *values = DKSettingsItemValues(item);
    DKSettingsValue *spec = values.firstObject;
    if (values.count != 1 || !((spec.kind == DKSettingsValueKindBool && item.cellType == 6)
        || (spec.kind == DKSettingsValueKindInteger && DKSettingsItemIsChoice(item)))) return NO;
    id raw = lockedValue ?: [spec currentValueInStore:NSUserDefaults.standardUserDefaults];
    NSInteger value = raw == NSNull.null ? 0 : [raw integerValue];
    if (DKSettingsItemIsChoice(item)) {
        DKSettingsDescribe describe = DKSettingsItemDescribe(item);
        if (!describe) return NO;
        NSString *text = describe(@[ @(value) ], YES);
        if ([item.detail isEqualToString:text]) return NO;
        item.detail = text;
        return YES;
    }
    BOOL on = value != 0;
    if (item.isSwitchOn == on) return NO;
    item.isSwitchOn = on;
    return YES;
}

#pragma mark - 开关

AWESettingItemModel *DKMakeSwitch(NSString *key, NSString *title, NSString *detail) {
    // cellType 6：开关行。detail 不写进项里，卡片样式下它会显示成副标题。
    AWESettingItemModel *item = DKSettingsWithInfo(DKMakeItem(key, title, 6), detail);
    item.isSwitchOn = [NSUserDefaults.standardUserDefaults boolForKey:key];
    DKSettingsWithValues(item, @[ [DKSettingsValue boolWithKey:key] ], nil);

    __weak AWESettingItemModel *weakItem = item;
    item.switchChangedBlock = ^{
        __strong AWESettingItemModel *it = weakItem;
        if (!it.isEnable) return;
        BOOL value = !it.isSwitchOn;
        it.isSwitchOn = value;
        [NSUserDefaults.standardUserDefaults setBool:value forKey:it.identifier];
        DKSettingsValuesChanged();
        DKRunOnChange(it);
    };
    return item;
}

AWESettingItemModel *DKMakeSwitchConfirmingOn(NSString *key, NSString *title, NSString *detail,
                                              void (^confirm)(UIViewController *presenter, dispatch_block_t commit)) {
    AWESettingItemModel *item = DKMakeSwitch(key, title, detail);
    dispatch_block_t toggle = [item.switchChangedBlock copy];
    void (^confirmCopy)(UIViewController *, dispatch_block_t) = [confirm copy];
    __weak AWESettingItemModel *weakItem = item;
    item.switchChangedBlock = ^{
        __strong AWESettingItemModel *it = weakItem;
        if (!it.isEnable) return;
        if (it.isSwitchOn || !confirmCopy) {
            toggle();
            return;
        }
        // 打开要先确认：行上的开关先拨回关，确认后由 commit 打开；取不到宿主页就不打开。
        DKSettingsReloadCurrentPage();
        UIViewController *presenter = DKSettingsCurrentPage();
        if (!presenter) return;
        confirmCopy(presenter, ^{
            if (weakItem.isSwitchOn) return;
            toggle();
            DKSettingsReloadCurrentPage();
        });
    };
    return item;
}

#pragma mark - 单选

// 单选行：点击弹出框，选中后交给 apply 写入，再调项上的 onChange。current 越界时按第 0 项显示。
// confirm 非空时先交给它，它调 commit 才写入；commit 强持有 onChange，页面退出后仍能完成。
static AWESettingItemModel *DKMakeChoiceItem(NSString *key, NSString *title, NSArray<NSString *> *options,
                                             NSInteger current, void (^apply)(NSInteger index),
                                             void (^confirm)(NSInteger, UIViewController *, dispatch_block_t)) {
    if (current < 0 || current >= (NSInteger)options.count) current = 0;

    // cellType 26：可点击、右侧显示 detail 与箭头。
    AWESettingItemModel *item = DKMakeItem(key, title, 26);
    item.detail = options[current];
    objc_setAssociatedObject(item, &kDKChoiceKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    __weak AWESettingItemModel *weakItem = item;
    void (^applyCopy)(NSInteger) = [apply copy];
    void (^confirmCopy)(NSInteger, UIViewController *, dispatch_block_t) = [confirm copy];
    item.cellTappedBlock = ^{
        UIViewController *presenter = DKSettingsCurrentPage();
        if (!presenter || !weakItem.isEnable) return;
        UIAlertController *sheet =
            [UIAlertController alertControllerWithTitle:title message:nil
                                         preferredStyle:UIAlertControllerStyleActionSheet];
        [options enumerateObjectsUsingBlock:^(NSString *name, NSUInteger index, __unused BOOL *stop) {
            [sheet addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault
                                                   handler:^(__unused UIAlertAction *action) {
                dispatch_block_t onChange = DKSettingsItemOnChange(weakItem);
                dispatch_block_t commit = ^{
                    if (applyCopy) applyCopy((NSInteger)index);
                    weakItem.detail = name;
                    DKSettingsReloadCurrentPage();
                    if (onChange) onChange();
                };
                if (confirmCopy) confirmCopy((NSInteger)index, presenter, commit);
                else commit();
            }]];
        }];
        [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        DKPresentFromSettings(presenter, sheet, weakItem);
    };
    return item;
}

AWESettingItemModel *DKMakeChoiceConfirm(NSString *key, NSString *title, NSArray<NSString *> *options,
                                         void (^confirm)(NSInteger index, UIViewController *presenter, dispatch_block_t commit)) {
    NSInteger current = [NSUserDefaults.standardUserDefaults integerForKey:key];
    AWESettingItemModel *item = DKMakeChoiceItem(key, title, options, current, ^(NSInteger index) {
        [NSUserDefaults.standardUserDefaults setInteger:index forKey:key];
    }, confirm);
    NSArray<NSString *> *optionsCopy = [options copy];
    return DKSettingsWithValues(item,
        @[ [DKSettingsValue integerWithKey:key minimum:0 maximum:(long long)options.count - 1] ],
        ^NSString *(NSArray *values, __unused BOOL brief) {
            return DKOptionText(optionsCopy, values[0] == NSNull.null ? 0 : [values[0] integerValue]);
        });
}

AWESettingItemModel *DKMakeChoice(NSString *key, NSString *title, NSArray<NSString *> *options) {
    return DKMakeChoiceConfirm(key, title, options, nil);
}

#pragma mark - 文字输入

// 输入弹窗的文案：message 为空时按长度上限生成说明；留空时行右侧显示 emptyDetail，清空按钮标题为 resetTitle。
@interface _DKTextPrompt : NSObject
@property (nonatomic, copy) NSString *placeholder;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, copy) NSString *emptyDetail;
@property (nonatomic, copy) NSString *resetTitle;
@end

@implementation _DKTextPrompt
@end

static NSString *DKTextCurrent(DKSettingsValue *value) {
    id current = [value currentValueInStore:NSUserDefaults.standardUserDefaults];
    return [current isKindOfClass:NSString.class] ? current : nil;
}

static void DKTextCommit(AWESettingItemModel *item, DKSettingsValue *value, _DKTextPrompt *prompt, id normalized,
                         dispatch_block_t onChange) {
    [value writeValue:normalized toStore:NSUserDefaults.standardUserDefaults];
    item.detail = DKTextCurrent(value) ?: prompt.emptyDetail;
    DKSettingsReloadCurrentPage();
    if (onChange) onChange();
}

// 超宽或含换行时保留输入、换上原因重新弹出，不让用户的输入丢掉。
static void DKPresentTextInput(AWESettingItemModel *item, DKSettingsValue *value, NSString *title,
                               _DKTextPrompt *prompt, NSString *draft, NSString *problem) {
    UIViewController *presenter = DKSettingsCurrentPage();
    if (!presenter) return;
    NSUInteger maxWidth = value.maxWidth;
    NSString *hint = prompt.message ?: [NSString stringWithFormat:@"最多 %lu 个汉字或 %lu 个字母数字，留空为「%@」。",
                      (unsigned long)(maxWidth / 2), (unsigned long)maxWidth, prompt.placeholder];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:problem ? [NSString stringWithFormat:@"%@\n%@", problem, hint] : hint
                                                            preferredStyle:UIAlertControllerStyleAlert];
    NSString *current = DKTextCurrent(value);
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = draft ?: current;
        field.placeholder = prompt.placeholder;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.returnKeyType = UIReturnKeyDone;
    }];

    __weak AWESettingItemModel *weakItem = item;
    __weak UIAlertController *weakAlert = alert;
    dispatch_block_t onChange = DKSettingsItemOnChange(item);
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if (current) {
        [alert addAction:[UIAlertAction actionWithTitle:prompt.resetTitle style:UIAlertActionStyleDestructive
                                                handler:^(__unused UIAlertAction *action) {
            DKTextCommit(weakItem, value, prompt, NSNull.null, onChange);
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        NSString *text = weakAlert.textFields.firstObject.text ?: @"";
        NSString *reason = nil;
        id normalized = [value normalize:text reason:&reason];
        if (!normalized) {
            // 等这个弹窗收完再弹，present 不能压在 dismiss 动画上。
            dispatch_async(dispatch_get_main_queue(), ^{
                DKPresentTextInput(weakItem, value, title, prompt, text,
                                   [reason isEqualToString:@"文字过长"] ? @"文字超出长度。" : @"不能包含换行或控制字符。");
            });
            return;
        }
        DKTextCommit(weakItem, value, prompt, normalized, onChange);
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

static AWESettingItemModel *DKMakeTextInputItem(NSString *key, NSString *title, NSUInteger maxWidth, _DKTextPrompt *prompt) {
    DKSettingsValue *value = [DKSettingsValue stringWithKey:key maxWidth:maxWidth];
    // cellType 26：可点击、右侧显示 detail 与箭头。
    AWESettingItemModel *item = DKMakeItem(key, title, 26);
    item.detail = DKTextCurrent(value) ?: prompt.emptyDetail;

    __weak AWESettingItemModel *weakItem = item;
    item.cellTappedBlock = ^{
        if (!weakItem.isEnable) return;
        DKPresentTextInput(weakItem, value, title, prompt, nil, nil);
    };
    NSString *emptyDetail = prompt.emptyDetail;
    return DKSettingsWithValues(item, @[ value ], ^NSString *(NSArray *values, __unused BOOL brief) {
        return [values[0] isKindOfClass:NSString.class] ? values[0] : emptyDetail;
    });
}

AWESettingItemModel *DKMakeTextInput(NSString *key, NSString *title, NSString *placeholder, NSUInteger maxWidth) {
    _DKTextPrompt *prompt = [_DKTextPrompt new];
    prompt.placeholder = placeholder;
    prompt.emptyDetail = @"默认";
    prompt.resetTitle = @"恢复默认";
    return DKMakeTextInputItem(key, title, maxWidth, prompt);
}

AWESettingItemModel *DKMakeTextInputWithPrompt(NSString *key, NSString *title, NSString *placeholder, NSUInteger maxWidth,
                                               NSString *message, NSString *emptyDetail, NSString *resetTitle) {
    _DKTextPrompt *prompt = [_DKTextPrompt new];
    prompt.placeholder = placeholder;
    prompt.message = message;
    prompt.emptyDetail = emptyDetail ?: @"默认";
    prompt.resetTitle = resetTitle ?: @"恢复默认";
    return DKMakeTextInputItem(key, title, maxWidth, prompt);
}

AWESettingItemModel *DKMakeGlassChoice(NSString *key, NSString *clearKey, NSString *title, void (^onChange)(void)) {
    NSArray<NSString *> *options = @[ @"关闭", @"模糊玻璃", @"清透玻璃" ];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSInteger current = [defaults boolForKey:key] ? ([defaults boolForKey:clearKey] ? 2 : 1) : 0;
    AWESettingItemModel *item = DKMakeChoiceItem(key, title, options, current, ^(NSInteger index) {
        [NSUserDefaults.standardUserDefaults setBool:index > 0 forKey:key];
        [NSUserDefaults.standardUserDefaults setBool:index == 2 forKey:clearKey];
    }, nil);
    DKSettingsWithValues(item, @[ [DKSettingsValue boolWithKey:key], [DKSettingsValue boolWithKey:clearKey] ],
        ^NSString *(NSArray *values, __unused BOOL brief) {
            BOOL on = [values[0] isEqual:@YES], clear = [values[1] isEqual:@YES];
            return options[on ? (clear ? 2 : 1) : 0];
        });
    return DKSettingsOnChange(item, onChange);
}

#pragma mark - 有界滑条

typedef NSString * (^DKSliderDetailBlock)(NSInteger value);
typedef DKAdjustBounds (^DKSliderBoundsBlock)(void);
typedef NSString * (^DKSliderMessageBlock)(void);

static NSInteger DKClampSliderValue(NSInteger value, DKAdjustBounds bounds) {
    return MIN(bounds.maximum, MAX(bounds.minimum, value));
}

// 滑条范围与说明在显示、点开、onChange 时求值，可随「扩展所有缩放与位移」变化；
// 落盘值按 declared 声明，备份能容纳任一状态下写入的值。
static AWESettingItemModel *DKMakeBoundedSlider(NSString *key, NSString *title, DKSliderMessageBlock message,
                                                DKAdjustBounds declared, DKSliderBoundsBlock bounds,
                                                NSInteger defaultValue, DKSliderDetailBlock detailBlock,
                                                void (^onChange)(NSInteger value)) {
    defaultValue = DKClampSliderValue(defaultValue, declared);
    NSInteger (^currentValue)(void) = ^NSInteger {
        NSNumber *stored = [NSUserDefaults.standardUserDefaults objectForKey:key];
        return DKClampSliderValue(stored ? stored.integerValue : defaultValue, bounds());
    };

    AWESettingItemModel *item = DKMakeItem(key, title, 26);
    item.detail = detailBlock(currentValue());

    __weak AWESettingItemModel *weakItem = item;
    void (^onChangeCopy)(NSInteger) = [onChange copy];
    DKSettingsWithValues(item, @[ [DKSettingsValue integerWithKey:key minimum:declared.minimum maximum:declared.maximum] ],
        ^NSString *(NSArray *values, __unused BOOL brief) {
            NSInteger value = values[0] == NSNull.null ? defaultValue : [values[0] integerValue];
            return detailBlock(DKClampSliderValue(value, bounds()));
        });
    if (onChangeCopy) {
        DKSettingsOnChange(item, ^{ onChangeCopy(currentValue()); });
    }

    item.cellTappedBlock = ^{
        UIViewController *presenter = DKSettingsCurrentPage();
        if (!presenter || !weakItem.isEnable) return;

        DKAdjustBounds range = bounds();
        NSInteger value = currentValue();
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:title message:message()
                                         preferredStyle:UIAlertControllerStyleAlert];

        UIViewController *box = [[UIViewController alloc] init];
        box.preferredContentSize = CGSizeMake(250.0, 68.0);

        UILabel *readout = [[UILabel alloc] init];
        readout.text = detailBlock(value);
        readout.textAlignment = NSTextAlignmentCenter;
        readout.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
        readout.translatesAutoresizingMaskIntoConstraints = NO;
        [box.view addSubview:readout];

        UISlider *slider = [[UISlider alloc] init];
        slider.minimumValue = (float)range.minimum;
        slider.maximumValue = (float)range.maximum;
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
            NSInteger next = DKClampSliderValue((NSInteger)lroundf(raw), range);
            readout.text = detailBlock(next);
            [NSUserDefaults.standardUserDefaults setInteger:next forKey:key];
            if (onChangeCopy) onChangeCopy(next);
            if (!finish) return;
            weakItem.detail = detailBlock(next);
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
        DKPresentFromSettings(presenter, alert, weakItem);
    };
    return item;
}

// 范围固定的滑条。
static AWESettingItemModel *DKMakeFixedSlider(NSString *key, NSString *title, NSString *message,
                                              NSInteger minimum, NSInteger maximum, NSInteger defaultValue,
                                              DKSliderDetailBlock detailBlock, void (^onChange)(NSInteger value)) {
    DKAdjustBounds fixed = { minimum, MAX(minimum, maximum) };
    NSString *messageCopy = [message copy];
    return DKMakeBoundedSlider(key, title, ^NSString *{ return messageCopy; }, fixed,
                               ^DKAdjustBounds { return fixed; }, defaultValue, detailBlock, onChange);
}

static NSString *DKPercentSliderDetail(NSInteger percent) {
    if (percent <= 0) return @"抖音默认";
    if (percent >= 100) return @"胶囊";
    return [NSString stringWithFormat:@"%ld%%", (long)percent];
}

AWESettingItemModel *DKMakePercentSlider(NSString *key, NSString *title, NSString *message,
                                         NSInteger defaultPercent, void (^onChange)(NSInteger percent)) {
    return DKMakeFixedSlider(key, title, message, 0, 100, defaultPercent,
                             ^NSString *(NSInteger value) { return DKPercentSliderDetail(value); }, onChange);
}

AWESettingItemModel *DKMakeUnitSlider(NSString *key, NSString *title, NSString *message,
                                      NSInteger minimum, NSInteger maximum, NSInteger defaultValue,
                                      NSString *unit, void (^onChange)(NSInteger value)) {
    NSString *suffix = [unit copy] ?: @"";
    return DKMakeFixedSlider(key, title, message, minimum, maximum, defaultValue,
                             ^NSString *(NSInteger value) {
        return [NSString stringWithFormat:@"%ld%@", (long)value, suffix];
    }, onChange);
}

AWESettingItemModel *DKMakeRangeSlider(NSString *key, NSString *title, NSString *message,
                                       NSInteger minimum, NSInteger maximum, NSInteger defaultValue,
                                       void (^onChange)(NSInteger value)) {
    return DKMakeUnitSlider(key, title, message, minimum, maximum, defaultValue, @"%", onChange);
}

AWESettingItemModel *DKMakeAdjustSlider(NSString *key, NSString *title, NSString *message,
                                        void (^onChange)(NSInteger value)) {
    DKAdjustKind kind = DKAdjustKindForKey(key);
    NSString *messageCopy = [message copy];
    DKSliderMessageBlock fullMessage = ^NSString * {
        BOOL extended = DKAdjustRangeExtended();
        DKAdjustBounds range = DKAdjustEffectiveBounds(key);
        NSString *note = extended ? @"已扩展可调范围" : @"可调范围";
        NSString *below = extended && kind == DKAdjustKindOffset && range.minimum < 0 ? @"，负值为下移" : @"";
        return [NSString stringWithFormat:@"%@\n%@：%@%@。", messageCopy, note,
                DKAdjustBoundsText(kind, range), below];
    };
    return DKMakeBoundedSlider(key, title, fullMessage,
                               DKAdjustExtendedBounds(key), ^DKAdjustBounds { return DKAdjustEffectiveBounds(key); },
                               DKAdjustDefaultValue(key),
                               ^NSString *(NSInteger value) { return DKAdjustValueText(kind, value); }, onChange);
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
