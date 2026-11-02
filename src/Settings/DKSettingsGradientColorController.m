//
//  DKSettingsGradientColorController.m
//  渐变颜色设置子页面：预览、逐色选色/十六进制、拖动排序、删除、添加与整条不透明度。
//  所有编辑即时提交，返回时不保留未落盘草稿。
//

#import "DKSettingsColorEditors.h"
#import "DKColorHex.h"
#import <math.h>

static NSString *DKRGBOnly(NSString *hex) {
    NSString *canonical = DKColorHexNormalizeAlpha(hex);
    return canonical ? [@"#" stringByAppendingString:[canonical substringFromIndex:3]] : @"#FFFFFF";
}

static CGFloat DKAlphaOf(NSString *hex) {
    NSString *canonical = DKColorHexNormalizeAlpha(hex);
    if (!canonical) return 1.0;
    unsigned int value = 0;
    [[NSScanner scannerWithString:[canonical substringWithRange:NSMakeRange(1, 2)]] scanHexInt:&value];
    return value / 255.0;
}

static UIColor *DKColorOf(NSString *hex, CGFloat alpha) {
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:[DKRGBOnly(hex) substringFromIndex:1]] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb >> 16) & 255) / 255.0
                            green:((rgb >> 8) & 255) / 255.0
                             blue:(rgb & 255) / 255.0
                            alpha:MIN(1.0, MAX(0.0, alpha))];
}

static NSString *DKGradientPickerValue(NSString *rgb) {
    NSString *canonical = DKRGBOnly(rgb);
    return [NSString stringWithFormat:@"#FF%@", [canonical substringFromIndex:1]];
}

static void DKGradientSetNavigationTitle(UIViewController *page, NSString *title) {
    page.title = title;
    for (UIView *subview in page.view.subviews) {
        if (![subview isKindOfClass:NSClassFromString(@"AWENavigationBar")]) continue;
        AWENavigationBar *bar = (AWENavigationBar *)subview;
        if ([bar respondsToSelector:@selector(titleLabel)]) bar.titleLabel.text = title;
        break;
    }
}

#pragma mark - 预览

@interface DKGradientPreviewCell : UITableViewCell
@property (nonatomic, strong) UIView *preview;
@property (nonatomic, strong) CAGradientLayer *gradientLayer;
@property (nonatomic, strong) UILabel *sampleLabel;
@end

@implementation DKGradientPreviewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;

        _preview = [[UIView alloc] init];
        _preview.layer.cornerRadius = 12.0;
        _preview.layer.masksToBounds = YES;
        _gradientLayer = [CAGradientLayer layer];
        _gradientLayer.startPoint = CGPointMake(0.0, 0.5);
        _gradientLayer.endPoint = CGPointMake(1.0, 0.5);
        [_preview.layer addSublayer:_gradientLayer];
        [self.contentView addSubview:_preview];

        _sampleLabel = [[UILabel alloc] init];
        _sampleLabel.textAlignment = NSTextAlignmentCenter;
        _sampleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        _sampleLabel.numberOfLines = 2;
        [_preview addSubview:_sampleLabel];

        _preview.translatesAutoresizingMaskIntoConstraints = NO;
        _sampleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [_preview.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12.0],
            [_preview.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [_preview.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [_preview.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12.0],
            [_preview.heightAnchor constraintEqualToConstant:56.0],
            [_sampleLabel.leadingAnchor constraintEqualToAnchor:_preview.leadingAnchor constant:12.0],
            [_sampleLabel.trailingAnchor constraintEqualToAnchor:_preview.trailingAnchor constant:-12.0],
            [_sampleLabel.centerYAnchor constraintEqualToAnchor:_preview.centerYAnchor],
        ]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.gradientLayer.frame = self.preview.bounds;
}

@end

#pragma mark - 整条不透明度

@interface DKGradientAlphaCell : UITableViewCell
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, copy) void (^valueChanged)(CGFloat value);
@end

@implementation DKGradientAlphaCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;

        UILabel *title = [[UILabel alloc] init];
        title.text = @"不透明度";
        title.font = [UIFont systemFontOfSize:15.0];
        title.textColor = UIColor.labelColor;
        title.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:title];

        _slider = [[UISlider alloc] init];
        _slider.minimumValue = 0.0;
        _slider.maximumValue = 1.0;
        [_slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        _slider.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_slider];

        _valueLabel = [[UILabel alloc] init];
        _valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightRegular];
        _valueLabel.textAlignment = NSTextAlignmentRight;
        _valueLabel.textColor = UIColor.secondaryLabelColor;
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_valueLabel];

        [NSLayoutConstraint activateConstraints:@[
            [title.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [title.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_valueLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [_valueLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_valueLabel.widthAnchor constraintEqualToConstant:52.0],
            [_slider.leadingAnchor constraintEqualToAnchor:title.trailingAnchor constant:16.0],
            [_slider.trailingAnchor constraintEqualToAnchor:_valueLabel.leadingAnchor constant:-12.0],
            [_slider.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:52.0],
        ]];
    }
    return self;
}

- (void)sliderChanged:(UISlider *)sender {
    if (self.valueChanged) self.valueChanged(sender.value);
}

@end

#pragma mark - 颜色行

@interface DKGradientColorCell : UITableViewCell <UITextFieldDelegate>
@property (nonatomic, strong) UIButton *chipButton;
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, copy) void (^pickColor)(void);
@property (nonatomic, copy) void (^deleteColor)(void);
@property (nonatomic, copy) void (^textChanged)(UITextField *field);
@property (nonatomic, copy) void (^editingEnded)(UITextField *field);
@end

@implementation DKGradientColorCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;

        _chipButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _chipButton.layer.cornerRadius = 8.0;
        _chipButton.layer.borderWidth = 1.0 / MAX(1.0, self.traitCollection.displayScale);
        _chipButton.layer.borderColor = UIColor.separatorColor.CGColor;
        _chipButton.layer.masksToBounds = YES;
        [_chipButton addTarget:self action:@selector(chipTapped) forControlEvents:UIControlEventTouchUpInside];

        _field = [[UITextField alloc] init];
        _field.borderStyle = UITextBorderStyleNone;
        _field.backgroundColor = UIColor.clearColor;
        _field.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
        _field.autocorrectionType = UITextAutocorrectionTypeNo;
        _field.font = [UIFont monospacedSystemFontOfSize:15.0 weight:UIFontWeightRegular];
        _field.returnKeyType = UIReturnKeyDone;
        _field.delegate = self;
        [_field addTarget:self action:@selector(fieldEdited:) forControlEvents:UIControlEventEditingChanged];

        _deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
        UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightRegular];
        [_deleteButton setImage:[UIImage systemImageNamed:@"trash" withConfiguration:configuration] forState:UIControlStateNormal];
        [_deleteButton setTitle:@"删除" forState:UIControlStateNormal];
        _deleteButton.tintColor = UIColor.systemRedColor;
        [_deleteButton addTarget:self action:@selector(deleteTapped) forControlEvents:UIControlEventTouchUpInside];

        for (UIView *view in @[ _chipButton, _field, _deleteButton ]) {
            view.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:view];
        }
        [NSLayoutConstraint activateConstraints:@[
            [_chipButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [_chipButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_chipButton.widthAnchor constraintEqualToConstant:30.0],
            [_chipButton.heightAnchor constraintEqualToConstant:30.0],
            [_field.leadingAnchor constraintEqualToAnchor:_chipButton.trailingAnchor constant:12.0],
            [_field.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_field.heightAnchor constraintEqualToConstant:36.0],
            [_deleteButton.leadingAnchor constraintEqualToAnchor:_field.trailingAnchor constant:8.0],
            [_deleteButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12.0],
            [_deleteButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_deleteButton.widthAnchor constraintEqualToConstant:28.0],
            [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:52.0],
        ]];
    }
    return self;
}

- (void)chipTapped {
    if (self.pickColor) self.pickColor();
}

- (void)deleteTapped {
    if (self.deleteColor) self.deleteColor();
}

- (void)fieldEdited:(UITextField *)field {
    if (self.textChanged) self.textChanged(field);
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField endEditing:YES];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    if (self.editingEnded) self.editingEnded(textField);
}

@end

#pragma mark - 页面

@interface DKGradientColorController () <UITableViewDataSource, UITableViewDelegate,
    UITableViewDragDelegate, UITableViewDropDelegate>
@property (nonatomic, copy) NSString *editorTitle;
@property (nonatomic, strong) DKColorSample *sample;
@property (nonatomic, copy) void (^completion)(NSString *value);
@property (nonatomic, strong) NSMutableArray<NSString *> *colors;
@property (nonatomic) CGFloat alpha;
@property (nonatomic) BOOL allowsAlpha;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, weak) DKGradientPreviewCell *previewCell;
@property (nonatomic, weak) DKGradientAlphaCell *alphaCell;
@end

@implementation DKGradientColorController

- (instancetype)initWithTitle:(NSString *)title value:(NSString *)gradient sample:(DKColorSample *)sample
                    completion:(void (^)(NSString *))completion {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _editorTitle = [title copy];
        _sample = sample;
        _allowsAlpha = sample.alphaEditable;
        _completion = [completion copy];
        _colors = [NSMutableArray array];
        NSArray<NSString *> *parts = [gradient ?: @"" componentsSeparatedByString:@","];
        for (NSString *part in parts) {
            if (DKColorHexNormalizeAlpha(part)) [_colors addObject:DKRGBOnly(part)];
        }
        if (_colors.count < 2) {
            _colors = [@[ @"#FF2C55", @"#25F4EE" ] mutableCopy];
            _alpha = 1.0;
        } else {
            _alpha = _allowsAlpha ? DKAlphaOf(parts.firstObject) : 1.0;
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    DKGradientSetNavigationTitle(self, self.editorTitle);
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorColor = UIColor.separatorColor;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.dragDelegate = self;
    self.tableView.dropDelegate = self;
    self.tableView.dragInteractionEnabled = YES;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 56.0;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tableView registerClass:DKGradientPreviewCell.class forCellReuseIdentifier:@"preview"];
    [self.tableView registerClass:DKGradientAlphaCell.class forCellReuseIdentifier:@"alpha"];
    [self.tableView registerClass:DKGradientColorCell.class forCellReuseIdentifier:@"color"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"add"];
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)viewWillDisappear:(BOOL)animated {
    [self.view endEditing:YES];
    [self commitValue];
    [super viewWillDisappear:animated];
}

- (NSString *)value {
    unsigned int alpha = (unsigned int)lround((self.allowsAlpha ? self.alpha : 1.0) * 255.0);
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:self.colors.count];
    for (NSString *color in self.colors) {
        [parts addObject:[NSString stringWithFormat:@"#%02X%@", alpha, [DKRGBOnly(color) substringFromIndex:1]]];
    }
    return [parts componentsJoinedByString:@","];
}

- (void)commitValue {
    if (self.completion && self.colors.count >= 2) self.completion(self.value);
}

- (CGFloat)previewAlpha {
    return self.allowsAlpha ? self.alpha : (self.sample.alpha ? self.sample.alpha() : 1.0);
}

- (void)syncPreview {
    NSMutableArray *gradientColors = [NSMutableArray arrayWithCapacity:self.colors.count];
    CGFloat alpha = [self previewAlpha];
    for (NSString *color in self.colors) [gradientColors addObject:(__bridge id)DKColorOf(color, alpha).CGColor];
    self.previewCell.gradientLayer.colors = gradientColors;
    self.previewCell.sampleLabel.text = self.sample.text ?: self.editorTitle;
    self.previewCell.sampleLabel.textColor = DKColorOf(self.colors.firstObject ?: @"#FFFFFF", alpha);
    if (self.allowsAlpha) {
        self.alphaCell.slider.value = self.alpha;
        self.alphaCell.valueLabel.text = [NSString stringWithFormat:@"%.0f%%", self.alpha * 100.0];
    }
}

- (void)alphaChanged:(CGFloat)value {
    self.alpha = MIN(1.0, MAX(0.0, value));
    [self syncPreview];
    [self commitValue];
}

- (void)pickColorAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.colors.count) return;
    __weak typeof(self) weakSelf = self;
    DKSettingsPresentSystemColorPicker(self, @"选择渐变颜色", DKGradientPickerValue(self.colors[row]), NO, ^(NSString *hex) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || row >= (NSInteger)self.colors.count) return;
        self.colors[row] = DKRGBOnly(hex);
        [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:1]]
                              withRowAnimation:UITableViewRowAnimationNone];
        [self syncPreview];
        [self commitValue];
    });
}

- (void)addColor {
    if (self.colors.count >= 8) return;
    __weak typeof(self) weakSelf = self;
    DKSettingsPresentSystemColorPicker(self, @"添加颜色", DKGradientPickerValue(self.colors.lastObject), NO, ^(NSString *hex) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.colors.count >= 8) return;
        [self.colors addObject:DKRGBOnly(hex)];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
        [self syncPreview];
        [self commitValue];
    });
}

- (void)deleteColorAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.colors.count || self.colors.count <= 2) return;
    [self.colors removeObjectAtIndex:row];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
    [self syncPreview];
    [self commitValue];
}

- (void)textChanged:(UITextField *)field row:(NSInteger)row commit:(BOOL)commit {
    if (row < 0 || row >= (NSInteger)self.colors.count) return;
    NSString *canonical = DKColorHexNormalizeAlpha(field.text);
    if (!canonical) {
        field.textColor = UIColor.systemRedColor;
        if (commit) {
            field.text = self.colors[row];
            field.textColor = UIColor.labelColor;
        }
        return;
    }
    field.textColor = UIColor.labelColor;
    self.colors[row] = DKRGBOnly(canonical);
    DKGradientColorCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:1]];
    cell.chipButton.backgroundColor = DKColorOf(self.colors[row], 1.0);
    [self syncPreview];
    if (commit) {
        field.text = self.colors[row];
        [self commitValue];
    }
}

#pragma mark - 表格

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return self.allowsAlpha ? 2 : 1;
    return self.colors.count + 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"预览" : @"渐变颜色";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0 && self.allowsAlpha) return @"整条渐变共用一个不透明度；拖动滑条后立即生效。";
    if (section == 1) return @"2–8 个颜色，顺序决定从左到右的渐变方向；点色块可选色，长按颜色行可拖动排序。";
    if (section == 0 && !self.allowsAlpha) {
        NSString *note = self.sample.alphaNote ? self.sample.alphaNote([self previewAlpha]) : nil;
        return note.length ? note : @"弹幕不透明度继承抖音原生设置。";
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 40.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return section == 0 && self.allowsAlpha ? 34.0 : (section == 1 ? 48.0 : 34.0);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && indexPath.row == 0) {
        DKGradientPreviewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"preview" forIndexPath:indexPath];
        self.previewCell = cell;
        [self syncPreview];
        return cell;
    }
    if (indexPath.section == 0) {
        DKGradientAlphaCell *cell = [tableView dequeueReusableCellWithIdentifier:@"alpha" forIndexPath:indexPath];
        self.alphaCell = cell;
        cell.slider.value = self.alpha;
        cell.valueLabel.text = [NSString stringWithFormat:@"%.0f%%", self.alpha * 100.0];
        __weak typeof(self) weakSelf = self;
        cell.valueChanged = ^(CGFloat value) {
            __strong typeof(weakSelf) self = weakSelf;
            if (self) [self alphaChanged:value];
        };
        return cell;
    }
    if (indexPath.row == (NSInteger)self.colors.count) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"add" forIndexPath:indexPath];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.textLabel.text = @"添加颜色";
        cell.textLabel.textColor = UIColor.systemBlueColor;
        cell.imageView.image = [UIImage systemImageNamed:@"plus"];
        cell.imageView.tintColor = UIColor.systemBlueColor;
        return cell;
    }

    NSInteger row = indexPath.row;
    DKGradientColorCell *cell = [tableView dequeueReusableCellWithIdentifier:@"color" forIndexPath:indexPath];
    NSString *color = self.colors[row];
    cell.chipButton.backgroundColor = DKColorOf(color, 1.0);
    cell.chipButton.accessibilityLabel = [NSString stringWithFormat:@"选择第%ld个颜色", (long)row + 1];
    cell.field.text = color;
    cell.field.textColor = UIColor.labelColor;
    cell.field.tag = row;
    cell.deleteButton.enabled = self.colors.count > 2;
    __weak typeof(self) weakSelf = self;
    cell.pickColor = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self) [self pickColorAtRow:row];
    };
    cell.deleteColor = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self) [self deleteColorAtRow:row];
    };
    cell.textChanged = ^(UITextField *field) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self) [self textChanged:field row:row commit:NO];
    };
    cell.editingEnded = ^(UITextField *field) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self) [self textChanged:field row:row commit:YES];
    };
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1) return;
    if (indexPath.row == (NSInteger)self.colors.count) [self addColor];
    else [self pickColorAtRow:indexPath.row];
}

#pragma mark - 拖动排序

- (NSArray<UIDragItem *> *)tableView:(UITableView *)tableView itemsForBeginningDragSession:(id<UIDragSession>)session
                         atIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 1 || indexPath.row >= (NSInteger)self.colors.count) return @[];
    NSItemProvider *provider = [[NSItemProvider alloc] initWithObject:self.colors[indexPath.row]];
    UIDragItem *item = [[UIDragItem alloc] initWithItemProvider:provider];
    item.localObject = indexPath;
    return @[ item ];
}

- (UITableViewDropProposal *)tableView:(UITableView *)tableView dropSessionDidUpdate:(id<UIDropSession>)session
                  withDestinationIndexPath:(NSIndexPath *)destinationIndexPath {
    if (session.localDragSession && destinationIndexPath.section == 1) {
        return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationMove
                                                                 intent:UITableViewDropIntentInsertAtDestinationIndexPath];
    }
    return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationCancel];
}

- (void)tableView:(UITableView *)tableView performDropWithCoordinator:(id<UITableViewDropCoordinator>)coordinator {
    NSIndexPath *destination = coordinator.destinationIndexPath;
    if (!destination || destination.section != 1) return;
    for (id<UITableViewDropItem> item in coordinator.items) {
        NSIndexPath *source = item.sourceIndexPath ?: item.dragItem.localObject;
        if (![source isKindOfClass:NSIndexPath.class] || source.section != 1
            || source.row >= (NSInteger)self.colors.count) continue;
        NSString *color = self.colors[source.row];
        [self.colors removeObjectAtIndex:source.row];
        NSInteger target = MIN(destination.row, (NSInteger)self.colors.count);
        if (source.row < target) target--;
        [self.colors insertObject:color atIndex:MAX(0, target)];
        [tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
        [self syncPreview];
        [self commitValue];
        break;
    }
}

@end
