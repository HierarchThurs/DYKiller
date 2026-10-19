#import "DKSettingsColorEditors.h"
#import "DKColorHex.h"
#import "DKColorScheme.h"
#import <math.h>

static CGFloat DKSampleAlpha(DKColorSample *sample) {
    CGFloat alpha = sample.alpha ? sample.alpha() : 1;
    return isfinite(alpha) && alpha >= 0 && alpha <= 1 ? alpha : 1;
}

static NSString *DKSampleNote(DKColorSample *sample, CGFloat alpha) {
    return sample.alphaNote ? sample.alphaNote(alpha) : nil;
}

static UILabel *DKSampleLabel(NSString *text) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    label.textAlignment = NSTextAlignmentCenter;
    label.backgroundColor = [UIColor colorWithWhite:.15 alpha:1];
    label.clipsToBounds = YES;
    label.layer.cornerRadius = 14;
    return label;
}

static UILabel *DKHintLabel(NSString *text, CGFloat size) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont systemFontOfSize:size];
    label.textColor = UIColor.secondaryLabelColor;
    label.numberOfLines = 0;
    return label;
}

#pragma mark - 色谱

// 横向饱和度、纵向明度的色板；色相由外部滑条给。
@interface DKColorSpectrum : UIControl
@property (nonatomic) CGFloat hue;
@property (nonatomic) CGFloat saturation;
@property (nonatomic) CGFloat brightness;
@property (nonatomic, strong) UIView *cursor;
@end

@implementation DKColorSpectrum
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = 14;
        self.clipsToBounds = YES;
        self.accessibilityLabel = @"饱和度与明度色板";
        _cursor = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
        _cursor.layer.borderWidth = 2;
        _cursor.layer.borderColor = UIColor.whiteColor.CGColor;
        _cursor.layer.cornerRadius = 10;
        _cursor.userInteractionEnabled = NO;
        [self addSubview:_cursor];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.cursor.center = CGPointMake(self.saturation * self.bounds.size.width, (1 - self.brightness) * self.bounds.size.height);
}
- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    [[UIColor colorWithHue:self.hue saturation:1 brightness:1 alpha:1] setFill];
    CGContextFillRect(context, self.bounds);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSArray *horizontal = @[ (__bridge id)UIColor.whiteColor.CGColor, (__bridge id)[UIColor colorWithWhite:1 alpha:0].CGColor ];
    CGGradientRef white = CGGradientCreateWithColors(space, (__bridge CFArrayRef)horizontal, NULL);
    CGContextDrawLinearGradient(context, white, CGPointZero, CGPointMake(self.bounds.size.width, 0), 0);
    NSArray *vertical = @[ (__bridge id)[UIColor colorWithWhite:0 alpha:0].CGColor, (__bridge id)UIColor.blackColor.CGColor ];
    CGGradientRef black = CGGradientCreateWithColors(space, (__bridge CFArrayRef)vertical, NULL);
    CGContextDrawLinearGradient(context, black, CGPointZero, CGPointMake(0, self.bounds.size.height), 0);
    CGGradientRelease(white);
    CGGradientRelease(black);
    CGColorSpaceRelease(space);
}
- (void)updateTouch:(UITouch *)touch {
    if (self.bounds.size.width <= 0 || self.bounds.size.height <= 0) return;
    CGPoint p = [touch locationInView:self];
    self.saturation = MIN(1, MAX(0, p.x / self.bounds.size.width));
    self.brightness = 1 - MIN(1, MAX(0, p.y / self.bounds.size.height));
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (BOOL)beginTracking:(UITouch *)touch withEvent:(UIEvent *)event { [self updateTouch:touch]; return YES; }
- (BOOL)continueTracking:(UITouch *)touch withEvent:(UIEvent *)event { [self updateTouch:touch]; return YES; }
@end

#pragma mark - 选色页

@interface DKColorPickerController () <UITextFieldDelegate>
@property (nonatomic, strong) DKColorSample *colorSample;
@property (nonatomic, strong) DKColorSpectrum *spectrum;
@property (nonatomic, strong) UISlider *hueSlider;
@property (nonatomic, strong) UIStackView *spectrumPanel;
@property (nonatomic, strong) UIStackView *rgbPanel;
@property (nonatomic, strong) NSArray<UISlider *> *rgbSliders;
@property (nonatomic, strong) NSArray<UITextField *> *rgbFields;
@property (nonatomic, strong) UILabel *sample;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UILabel *alphaLabel;
@property (nonatomic, copy) void (^completion)(NSString *hex);
@property (nonatomic, copy) NSString *selectedHex;
@property (nonatomic) CGFloat sampleAlpha;
@end

@implementation DKColorPickerController
- (instancetype)initWithTitle:(NSString *)title color:(NSString *)hex sample:(DKColorSample *)sample
                   completion:(void (^)(NSString *))completion {
    if ((self = [super init])) {
        _selectedHex = DKColorHexNormalize(hex) ?: DKColorSchemeDefaultColor;
        _colorSample = sample;
        _completion = [completion copy];
        _sampleAlpha = 1;
        self.title = title;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:scroll];
    self.sample = DKSampleLabel(self.colorSample.text);
    self.valueLabel = DKHintLabel(self.selectedHex, 15);
    self.valueLabel.textAlignment = NSTextAlignmentCenter;
    self.alphaLabel = DKHintLabel(@"", 13);
    self.alphaLabel.textAlignment = NSTextAlignmentCenter;
    UISegmentedControl *tabs = [[UISegmentedControl alloc] initWithItems:@[ @"色谱", @"RGB 滑块" ]];
    tabs.selectedSegmentIndex = 0;
    [tabs addTarget:self action:@selector(selectPanel:) forControlEvents:UIControlEventValueChanged];
    self.spectrum = [DKColorSpectrum new];
    [self.spectrum addTarget:self action:@selector(spectrumChanged) forControlEvents:UIControlEventValueChanged];
    self.hueSlider = [UISlider new];
    self.hueSlider.maximumValue = 1;
    self.hueSlider.accessibilityLabel = @"色相";
    [self.hueSlider addTarget:self action:@selector(hueChanged) forControlEvents:UIControlEventValueChanged];
    self.spectrumPanel = [[UIStackView alloc] initWithArrangedSubviews:@[ self.spectrum, DKHintLabel(@"色相", 14), self.hueSlider ]];
    self.spectrumPanel.axis = UILayoutConstraintAxisVertical;
    self.spectrumPanel.spacing = 10;
    self.rgbPanel = [UIStackView new];
    self.rgbPanel.axis = UILayoutConstraintAxisVertical;
    self.rgbPanel.spacing = 14;
    self.rgbPanel.hidden = YES;
    NSMutableArray *sliders = [NSMutableArray array], *fields = [NSMutableArray array];
    for (NSString *name in @[ @"红", @"绿", @"蓝" ]) {
        UISlider *slider = [UISlider new];
        slider.maximumValue = 255;
        slider.accessibilityLabel = [name stringByAppendingString:@"色"];
        [slider addTarget:self action:@selector(rgbChanged:) forControlEvents:UIControlEventValueChanged];
        UITextField *field = [UITextField new];
        field.borderStyle = UITextBorderStyleRoundedRect;
        field.keyboardType = UIKeyboardTypeNumberPad;
        field.textAlignment = NSTextAlignmentCenter;
        field.accessibilityLabel = [name stringByAppendingString:@"色数值"];
        field.delegate = self;
        [field addTarget:self action:@selector(numberChanged:) forControlEvents:UIControlEventEditingChanged];
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ DKHintLabel(name, 14), slider, field ]];
        row.spacing = 12;
        row.alignment = UIStackViewAlignmentCenter;
        [field.widthAnchor constraintEqualToConstant:64].active = YES;
        [self.rgbPanel addArrangedSubview:row];
        [sliders addObject:slider];
        [fields addObject:field];
    }
    self.rgbSliders = sliders;
    self.rgbFields = fields;
    UILabel *hint = DKHintLabel(@"颜色保存为 RGB，不含不透明度。需要输入精确数值时，可使用设置页的十六进制入口。", 13);
    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[ self.sample, tabs, self.spectrumPanel, self.rgbPanel, self.valueLabel, self.alphaLabel, hint ]];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 18;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:content];
    NSLayoutYAxisAnchor *bottom = self.view.safeAreaLayoutGuide.bottomAnchor;
    if (@available(iOS 15.0, *)) bottom = self.view.keyboardLayoutGuide.topAnchor;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:bottom],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [content.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:20],
        [content.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20],
        [content.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20],
        [content.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20],
        [content.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40],
        [self.sample.heightAnchor constraintEqualToConstant:64],
        [self.spectrum.heightAnchor constraintEqualToConstant:190],
    ]];
    [self syncColor:DKColorSchemeRGB(self.selectedHex) updateHSV:YES];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.sampleAlpha = DKSampleAlpha(self.colorSample);
    NSString *note = DKSampleNote(self.colorSample, self.sampleAlpha);
    self.alphaLabel.text = note;
    self.alphaLabel.hidden = note.length == 0;
    [self syncColor:DKColorSchemeRGB(self.selectedHex) updateHSV:YES];
}

// 任一 RGB 数值框里是 0–255 以外的内容时不能保存。
- (BOOL)fieldsValid {
    for (UITextField *field in self.rgbFields) {
        NSString *value = field.text ?: @"";
        BOOL valid = value.length > 0 && value.length <= 3
            && [value rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound
            && value.integerValue <= 255;
        if (!valid) return NO;
    }
    return YES;
}

- (void)syncColor:(UIColor *)color updateHSV:(BOOL)updateHSV {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    [color getRed:&r green:&g blue:&b alpha:&a];
    NSArray<NSNumber *> *channels = @[ @(lround(r * 255)), @(lround(g * 255)), @(lround(b * 255)) ];
    for (NSUInteger i = 0; i < channels.count; i++) {
        self.rgbSliders[i].value = channels[i].floatValue;
        if (!self.rgbFields[i].isFirstResponder) self.rgbFields[i].text = channels[i].stringValue;
    }
    if (updateHSV) {
        CGFloat h = self.spectrum.hue, s = 0, v = 0;
        [color getHue:&h saturation:&s brightness:&v alpha:&a];
        if (s > 0) self.spectrum.hue = h;
        self.spectrum.saturation = s;
        self.spectrum.brightness = v;
        self.hueSlider.value = self.spectrum.hue;
    }
    self.selectedHex = [NSString stringWithFormat:@"#%02X%02X%02X", channels[0].unsignedIntValue,
                        channels[1].unsignedIntValue, channels[2].unsignedIntValue];
    self.valueLabel.text = self.selectedHex;
    self.sample.textColor = [color colorWithAlphaComponent:self.sampleAlpha];
    [self.spectrum setNeedsLayout];
    [self.spectrum setNeedsDisplay];
    self.navigationItem.rightBarButtonItem.enabled = [self fieldsValid];
}

- (void)spectrumChanged {
    UIColor *color = [UIColor colorWithHue:self.spectrum.hue saturation:self.spectrum.saturation brightness:self.spectrum.brightness alpha:1];
    [self syncColor:color updateHSV:NO];
}

- (void)hueChanged {
    self.spectrum.hue = self.hueSlider.value;
    [self spectrumChanged];
}

- (void)selectPanel:(UISegmentedControl *)tabs {
    [self.view endEditing:YES];
    self.spectrumPanel.hidden = tabs.selectedSegmentIndex != 0;
    self.rgbPanel.hidden = tabs.selectedSegmentIndex != 1;
}

- (void)rgbChanged:(UISlider *)slider {
    slider.value = round(slider.value);
    UIColor *color = [UIColor colorWithRed:self.rgbSliders[0].value / 255.0 green:self.rgbSliders[1].value / 255.0
                                      blue:self.rgbSliders[2].value / 255.0 alpha:1];
    [self syncColor:color updateHSV:YES];
}

- (void)numberChanged:(UITextField *)field {
    NSString *value = field.text ?: @"";
    BOOL valid = value.length > 0 && value.length <= 3
        && [value rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound
        && value.integerValue <= 255;
    field.textColor = valid ? UIColor.labelColor : UIColor.systemRedColor;
    if (!valid) {
        self.navigationItem.rightBarButtonItem.enabled = NO;
        return;
    }
    NSUInteger index = [self.rgbFields indexOfObject:field];
    self.rgbSliders[index].value = value.integerValue;
    [self rgbChanged:self.rgbSliders[index]];
}

- (void)textFieldDidEndEditing:(UITextField *)field {
    NSUInteger index = [self.rgbFields indexOfObject:field];
    field.text = [NSString stringWithFormat:@"%.0f", self.rgbSliders[index].value];
    field.textColor = UIColor.labelColor;
    self.navigationItem.rightBarButtonItem.enabled = [self fieldsValid];
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)save {
    [self.view endEditing:YES];
    if (![self fieldsValid]) return;
    if (self.completion) self.completion(self.selectedHex);
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end

#pragma mark - 文字输入页

@interface DKColorTextController () <UITextFieldDelegate>
@property (nonatomic, strong) DKColorSample *colorSample;
@property (nonatomic) BOOL gradient;
@property (nonatomic, copy) NSString *initialValue;
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UILabel *hint;
@property (nonatomic, strong) UILabel *sample;
@property (nonatomic, copy) NSString *canonical;
@property (nonatomic) CGFloat sampleAlpha;
@property (nonatomic, copy) void (^completion)(NSString *value);
@end

@implementation DKColorTextController
- (instancetype)initWithTitle:(NSString *)title value:(NSString *)value gradient:(BOOL)gradient
                       sample:(DKColorSample *)sample completion:(void (^)(NSString *))completion {
    if ((self = [super init])) {
        _initialValue = [value copy];
        _gradient = gradient;
        _colorSample = sample;
        _completion = [completion copy];
        _sampleAlpha = 1;
        self.title = title;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    self.field = [UITextField new];
    self.field.font = [UIFont monospacedSystemFontOfSize:16 weight:UIFontWeightRegular];
    self.field.text = self.initialValue;
    self.field.borderStyle = UITextBorderStyleRoundedRect;
    self.field.autocorrectionType = UITextAutocorrectionTypeNo;
    self.field.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.field.spellCheckingType = UITextSpellCheckingTypeNo;
    self.field.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.field.returnKeyType = UIReturnKeyDone;
    self.field.accessibilityLabel = self.title;
    self.field.delegate = self;
    [self.field addTarget:self action:@selector(textChanged) forControlEvents:UIControlEventEditingChanged];
    self.hint = DKHintLabel(@"", 14);
    self.sample = DKSampleLabel(self.colorSample.text);
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ self.field, self.hint, self.sample ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.field.heightAnchor constraintEqualToConstant:44],
        [self.sample.heightAnchor constraintEqualToConstant:64],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.sampleAlpha = DKSampleAlpha(self.colorSample);
    [self textChanged];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.field becomeFirstResponder];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateSample];
}

// 样例居中显示，渐变按文字实际所在的横向区间生成。
- (void)updateSample {
    if (!self.canonical.length || self.sample.bounds.size.width <= 0) return;
    NSMutableArray *colors = [NSMutableArray array];
    for (NSString *hex in [self.canonical componentsSeparatedByString:@","]) [colors addObject:DKColorSchemeRGB(hex)];
    NSString *text = self.colorSample.text ?: @"";
    CGFloat width = ceil([text sizeWithAttributes:@{ NSFontAttributeName: self.sample.font }].width);
    CGFloat start = MAX(0, (self.sample.bounds.size.width - width) / 2);
    UIColor *color = DKColorSchemeRender(colors, start, MAX(1, width), self.traitCollection.displayScale);
    self.sample.attributedText = [[NSAttributedString alloc] initWithString:text attributes:@{
        NSForegroundColorAttributeName: [color colorWithAlphaComponent:self.sampleAlpha],
        NSFontAttributeName: self.sample.font,
    }];
}

- (void)textChanged {
    NSString *reason = nil;
    self.canonical = DKColorHexNormalizeScheme(self.field.text ?: @"", self.gradient, &reason);
    self.navigationItem.rightBarButtonItem.enabled = self.canonical != nil;
    NSMutableString *hint = [NSMutableString string];
    if (reason) [hint appendString:reason];
    else {
        if (self.gradient) [hint appendString:@"输入 2–8 个颜色，用英文逗号分隔，顺序即从左至右的渐变顺序。"];
        [hint appendString:@"支持 RGB、RRGGBB、AARRGGBB，# 可省略；八位输入忽略前两位透明度。"];
        NSString *note = DKSampleNote(self.colorSample, self.sampleAlpha);
        if (note.length) [hint appendString:note];
    }
    self.hint.text = hint;
    self.sample.hidden = !self.canonical;
    [self updateSample];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (self.canonical) [self save];
    return NO;
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)save {
    if (!self.canonical) return;
    if (self.completion) self.completion(self.canonical);
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end
