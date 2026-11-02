//
//  DKSettingsColor.m
//  颜色设置项与网页入口。固定颜色的色板与十六进制入口读写同一个存值：保存后同页所有指向该存值的行一起换 detail。
//  onChange 在点开编辑页时从项上取出并持有，编辑期间页面重建也不会丢掉刷新。
//

#import "DKSettingsInternal.h"
#import "DKSettingsColorEditors.h"
#import "DKColorScheme.h"
#import "DKColorHex.h"
#import <objc/runtime.h>

static char kDKColorKeyKey;       // 行读写的颜色存值键
static char kDKColorAlphaKey;      // 行是否允许颜色自身 alpha

@implementation DKColorSample
@end

static NSString *DKColorDisplayValue(NSString *colorKey, BOOL gradient, BOOL allowsAlpha) {
    NSString *value = DKColorSchemeStoredColor(colorKey, gradient);
    if (allowsAlpha) return value;
    return DKColorHexNormalizeScheme(value, gradient, NULL)
        ?: (gradient ? DKColorSchemeDefaultGradient : DKColorSchemeDefaultColor);
}

static void DKColorRefreshDetails(NSString *colorKey, BOOL gradient) {
    DKSettingsEnumerateItems(DKSettingsCurrentPage(), ^(AWESettingItemModel *item) {
        if (![objc_getAssociatedObject(item, &kDKColorKeyKey) isEqual:colorKey]) return;
        BOOL allowsAlpha = [objc_getAssociatedObject(item, &kDKColorAlphaKey) boolValue];
        item.detail = DKColorDisplayValue(colorKey, gradient, allowsAlpha);
    });
}

static void DKColorCommit(NSString *colorKey, BOOL gradient, BOOL allowsAlpha, NSString *value, dispatch_block_t onChange) {
    DKSettingsValue *declaration = [DKSettingsValue colorWithKey:colorKey gradient:gradient];
    NSString *normalized = allowsAlpha ? DKColorHexNormalizeSchemeAlpha(value, gradient, NULL)
                                        : DKColorHexNormalizeScheme(value, gradient, NULL);
    id canonical = [declaration normalize:normalized reason:NULL];
    if (![canonical isKindOfClass:NSString.class]) return;
    [declaration writeValue:canonical toStore:NSUserDefaults.standardUserDefaults];
    DKColorRefreshDetails(colorKey, gradient);
    DKSettingsReloadCurrentPage();
    if (onChange) onChange();
}

static void DKColorPresent(UIViewController *presenter, UIViewController *editor) {
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:editor];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    [presenter presentViewController:navigation animated:YES completion:nil];
}

static void DKPushGradient(UIViewController *presenter, DKGradientColorController *editor) {
    UINavigationController *navigation = presenter.navigationController;
    if (navigation && editor) [navigation pushViewController:editor animated:YES];
}

typedef void (^DKColorEditor)(UIViewController *presenter, NSString *current, void (^commit)(NSString *value));


static AWESettingItemModel *DKColorItem(NSString *identifier, NSString *colorKey, NSString *title, BOOL gradient,
                                        DKColorSample *sample, DKColorEditor editor) {
    BOOL allowsAlpha = sample.alphaEditable;
    AWESettingItemModel *item = DKMakeAction(identifier, title, DKColorDisplayValue(colorKey, gradient, allowsAlpha),
        ^(AWESettingItemModel *sender, UIViewController *presenter) {
            dispatch_block_t onChange = DKSettingsItemOnChange(sender);
            NSString *current = DKColorDisplayValue(colorKey, gradient, allowsAlpha);
            editor(presenter, current, ^(NSString *value) {
                DKColorCommit(colorKey, gradient, allowsAlpha, value, onChange);
            });
        });
    objc_setAssociatedObject(item, &kDKColorKeyKey, colorKey, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(item, &kDKColorAlphaKey, @(allowsAlpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return item;
}

static AWESettingItemModel *DKColorDeclared(AWESettingItemModel *item, NSString *colorKey, BOOL gradient) {
    NSString *fallback = gradient ? DKColorSchemeDefaultGradient : DKColorSchemeDefaultColor;
    return DKSettingsWithValues(item, @[ [DKSettingsValue colorWithKey:colorKey gradient:gradient] ],
        ^NSString *(NSArray *values, __unused BOOL brief) {
            return [values.firstObject isKindOfClass:NSString.class] ? values.firstObject : fallback;
        });
}

AWESettingItemModel *DKMakeColorPicker(NSString *key, NSString *title, DKColorSample *sample) {
    AWESettingItemModel *item = DKColorItem(key, key, title, NO, sample, ^(UIViewController *presenter, NSString *current,
                                                                   void (^commit)(NSString *)) {
        DKSettingsPresentSystemColorPicker(presenter, title, current, sample.alphaEditable, commit);
    });
    return DKColorDeclared(item, key, NO);
}

AWESettingItemModel *DKMakeColorHexInput(NSString *identifier, NSString *colorKey, NSString *title, DKColorSample *sample) {
    AWESettingItemModel *item = DKColorItem(identifier, colorKey, title, NO, sample, ^(UIViewController *presenter, NSString *current,
                                                                             void (^commit)(NSString *)) {
        DKColorPresent(presenter, [[DKColorTextController alloc] initWithTitle:title value:current sample:sample
                                                                    completion:commit]);
    });
    return DKSettingsWithoutBackup(item);
}

AWESettingItemModel *DKMakeColorGradientInput(NSString *key, NSString *title, DKColorSample *sample) {
    AWESettingItemModel *item = DKColorItem(key, key, title, YES, sample, ^(UIViewController *presenter, NSString *current,
                                                                   void (^commit)(NSString *)) {
        DKPushGradient(presenter, [[DKGradientColorController alloc] initWithTitle:title value:current sample:sample
                                                                        completion:commit]);
    });
    return DKColorDeclared(item, key, YES);
}

AWESettingItemModel *DKMakeWebLink(NSString *key, NSString *title, NSString *url) {
    NSURL *target = [NSURL URLWithString:url];
    AWESettingItemModel *item = DKMakeAction(key, title, @"", ^(__unused AWESettingItemModel *sender, __unused UIViewController *presenter) {
        if (target) [UIApplication.sharedApplication openURL:target options:@{} completionHandler:nil];
    });
    return DKSettingsWithoutBackup(item);
}
