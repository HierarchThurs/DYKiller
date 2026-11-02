//
//  DKSettingsColorEditors.m
//  系统颜色选择器与单行十六进制输入页。
//  系统选色关闭时提交 #AARRGGBB；十六进制页保存时按样例的 alphaEditable 保留或移除 AA。
//

#import "DKSettingsColorEditors.h"
#import "DKColorHex.h"
#import <math.h>
#import <objc/runtime.h>

static UIColor *DKColorFromHex(NSString *hex) {
    NSString *canonical = DKColorHexNormalizeAlpha(hex);
    if (!canonical) return UIColor.whiteColor;
    unsigned int value = 0;
    [[NSScanner scannerWithString:[canonical substringFromIndex:1]] scanHexInt:&value];
    return [UIColor colorWithRed:((value >> 16) & 255) / 255.0
                            green:((value >> 8) & 255) / 255.0
                             blue:(value & 255) / 255.0
                            alpha:((value >> 24) & 255) / 255.0];
}

static NSString *DKHexFromColor(UIColor *color, BOOL includeAlpha) {
    if (!color) color = UIColor.whiteColor;
    CGFloat red = 0, green = 0, blue = 0, alpha = 1;
    if (![color getRed:&red green:&green blue:&blue alpha:&alpha]) {
        const CGFloat *components = CGColorGetComponents(color.CGColor);
        size_t count = CGColorGetNumberOfComponents(color.CGColor);
        if (count == 2) {
            red = green = blue = components[0];
            alpha = components[1];
        } else if (count >= 4) {
            red = components[0];
            green = components[1];
            blue = components[2];
            alpha = components[3];
        }
    }
    red = MIN(1, MAX(0, red));
    green = MIN(1, MAX(0, green));
    blue = MIN(1, MAX(0, blue));
    alpha = MIN(1, MAX(0, alpha));
    unsigned int r = (unsigned int)lround(red * 255.0);
    unsigned int g = (unsigned int)lround(green * 255.0);
    unsigned int b = (unsigned int)lround(blue * 255.0);
    if (!includeAlpha) return [NSString stringWithFormat:@"#%02X%02X%02X", r, g, b];
    unsigned int a = (unsigned int)lround(alpha * 255.0);
    return [NSString stringWithFormat:@"#%02X%02X%02X%02X", a, r, g, b];
}

static CGFloat DKColorAlpha(NSString *hex) {
    NSString *canonical = DKColorHexNormalizeAlpha(hex);
    if (!canonical) return 1.0;
    unsigned int value = 0;
    [[NSScanner scannerWithString:[canonical substringWithRange:NSMakeRange(1, 2)]] scanHexInt:&value];
    return value / 255.0;
}

static CGFloat DKSampleAlpha(DKColorSample *sample) {
    CGFloat alpha = sample.alpha ? sample.alpha() : 1.0;
    return isfinite(alpha) ? MIN(1.0, MAX(0.0, alpha)) : 1.0;
}

static UIUserInterfaceStyle DKSettingsAppearanceStyle(UIViewController *presenter) {
    UIWindow *window = presenter.viewIfLoaded.window ?: presenter.navigationController.viewIfLoaded.window;
    UIWindowScene *scene = window.windowScene;
    UIUserInterfaceStyle style = scene.traitCollection.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified) style = window.traitCollection.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified) style = presenter.traitCollection.userInterfaceStyle;
    return style;
}

#pragma mark - 系统颜色选择器

@interface DKSystemColorPickerProxy : NSObject <UIColorPickerViewControllerDelegate, UIAdaptivePresentationControllerDelegate>
@property (nonatomic, weak) UIColorPickerViewController *picker;
@property (nonatomic, weak) UIWindowScene *scene;
@property (nonatomic, strong) id traitRegistration;
@property (nonatomic, copy) void (^completion)(NSString *hex);
@property (nonatomic, weak) UIViewController *presenter;
@property (nonatomic) BOOL allowsAlpha;
@end

@implementation DKSystemColorPickerProxy

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    [self commit:viewController];
}

- (void)colorPickerViewController:(UIColorPickerViewController *)__unused viewController
                   didSelectColor:(UIColor *)__unused color
                      continuously:(BOOL)__unused isContinuous {
    // 选择过程只更新 picker 自身；最终值统一由关闭回调提交。
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    UIColorPickerViewController *picker = (UIColorPickerViewController *)presentationController.presentedViewController;
    [self commit:picker ?: self.picker];
}

- (void)commit:(UIColorPickerViewController *)viewController {
    void (^completion)(NSString *) = self.completion;
    self.completion = nil;
    if (completion && viewController) completion(DKHexFromColor(viewController.selectedColor, self.allowsAlpha));
}

- (void)updateAppearance {
    UIColorPickerViewController *picker = self.picker;
    if (!picker) return;
    UIUserInterfaceStyle style = DKSettingsAppearanceStyle(self.presenter);
    if (style != UIUserInterfaceStyleUnspecified) picker.overrideUserInterfaceStyle = style;
}

- (void)observeScene:(UIWindowScene *)scene {
    self.scene = scene;
    if (!scene) return;
    if (@available(iOS 17.0, *)) {
        __weak typeof(self) weakSelf = self;
        self.traitRegistration = [scene registerForTraitChanges:@[ UITraitUserInterfaceStyle.class ]
                                                     withHandler:^(__unused UIWindowScene *changedScene,
                                                                   __unused UITraitCollection *previousCollection) {
            [weakSelf updateAppearance];
        }];
    }
}

- (void)dealloc {
    if (@available(iOS 17.0, *)) {
        if (self.traitRegistration && self.scene) [self.scene unregisterForTraitChanges:self.traitRegistration];
    }
}

@end

static char kDKSystemColorPickerProxyKey;

void DKSettingsPresentSystemColorPicker(UIViewController *presenter, NSString *title, NSString *storedHex,
                                        BOOL allowsAlpha, void (^completion)(NSString *hex)) {
    if (!presenter || !completion) return;
    UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
    picker.title = title;
    picker.selectedColor = DKColorFromHex(storedHex);
    picker.supportsAlpha = allowsAlpha;
    DKSystemColorPickerProxy *proxy = [DKSystemColorPickerProxy new];
    proxy.picker = picker;
    proxy.presenter = presenter;
    proxy.completion = completion;
    proxy.allowsAlpha = allowsAlpha;
    picker.delegate = proxy;
    objc_setAssociatedObject(picker, &kDKSystemColorPickerProxyKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (@available(iOS 17.0, *)) {
        [proxy updateAppearance];
        [proxy observeScene:presenter.viewIfLoaded.window.windowScene ?: presenter.navigationController.viewIfLoaded.window.windowScene];
    }
    [presenter presentViewController:picker animated:YES completion:^{
        picker.presentationController.delegate = proxy;
        [proxy updateAppearance];
    }];
}

#pragma mark - 十六进制输入页

@interface DKColorTextController () <UITextFieldDelegate>
@property (nonatomic, copy) NSString *editorTitle;
@property (nonatomic, copy) NSString *initialValue;
@property (nonatomic, strong) DKColorSample *sample;
@property (nonatomic, copy) void (^completion)(NSString *value);
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UILabel *sampleLabel;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) UIBarButtonItem *saveItem;
@end

@implementation DKColorTextController

- (instancetype)initWithTitle:(NSString *)title value:(NSString *)value sample:(DKColorSample *)sample
                   completion:(void (^)(NSString *))completion {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _editorTitle = [title copy];
        _sample = sample;
        _initialValue = (sample.alphaEditable ? DKColorHexNormalizeAlpha(value) : DKColorHexNormalize(value)) ?: @"#FFFFFF";
        _completion = [completion copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.editorTitle;
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                           target:self action:@selector(cancel)];
    self.saveItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                                   target:self action:@selector(save)];
    self.navigationItem.rightBarButtonItem = self.saveItem;

    self.field = [[UITextField alloc] init];
    self.field.borderStyle = UITextBorderStyleRoundedRect;
    self.field.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.field.autocorrectionType = UITextAutocorrectionTypeNo;
    self.field.font = [UIFont monospacedSystemFontOfSize:17 weight:UIFontWeightRegular];
    self.field.delegate = self;
    [self.field addTarget:self action:@selector(textChanged) forControlEvents:UIControlEventEditingChanged];

    self.sampleLabel = [[UILabel alloc] init];
    self.sampleLabel.text = self.sample.text ?: self.editorTitle;
    self.sampleLabel.textAlignment = NSTextAlignmentCenter;
    self.sampleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.sampleLabel.numberOfLines = 0;

    self.hintLabel = [[UILabel alloc] init];
    self.hintLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.hintLabel.textColor = UIColor.secondaryLabelColor;
    self.hintLabel.numberOfLines = 0;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ self.field, self.sampleLabel, self.hintLabel ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.field.text.length) self.field.text = self.initialValue;
    [self textChanged];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (self.saveItem.enabled) [self save];
    return YES;
}

- (void)textChanged {
    NSString *canonical = self.sample.alphaEditable ? DKColorHexNormalizeAlpha(self.field.text) : DKColorHexNormalize(self.field.text);
    self.saveItem.enabled = canonical != nil;
    self.sampleLabel.hidden = canonical == nil;
    NSString *hint = self.sample.alphaEditable
        ? @"支持 3、6、8 位十六进制；八位的前两位就是不透明度。保存后统一写入 #AARRGGBB。"
        : @"支持 3、6、8 位十六进制；八位的前两位透明度会忽略，弹幕不透明度继承抖音原生设置。";
    CGFloat alpha = self.sample.alphaEditable ? DKColorAlpha(canonical) : DKSampleAlpha(self.sample);
    if (canonical && self.sample.alphaNote) {
        NSString *note = self.sample.alphaNote(alpha);
        if (note.length) hint = [hint stringByAppendingFormat:@"\n%@", note];
    }
    self.hintLabel.text = hint;
    if (!canonical) return;
    UIColor *color = DKColorFromHex(canonical);
    self.sampleLabel.textColor = self.sample.alphaEditable ? color : [color colorWithAlphaComponent:alpha];
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)save {
    NSString *value = self.sample.alphaEditable ? DKColorHexNormalizeAlpha(self.field.text) : DKColorHexNormalize(self.field.text);
    if (!value) return;
    void (^completion)(NSString *) = self.completion;
    self.completion = nil;
    [self dismissViewControllerAnimated:YES completion:^{ if (completion) completion(value); }];
}

@end
