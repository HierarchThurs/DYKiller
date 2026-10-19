//
//  DKSettingsColor.m
//  颜色设置项与网页入口。固定颜色的色板与十六进制入口读写同一个存值：保存后同页所有指向该存值的行一起换 detail。
//  onChange 在点开编辑页时从项上取出并持有，编辑期间页面重建也不会丢掉刷新。
//

#import "DKSettingsInternal.h"
#import "DKSettingsColorEditors.h"
#import "DKColorScheme.h"
#import <objc/runtime.h>

static char kDKColorKeyKey;   // 行读写的颜色存值键

@implementation DKColorSample
@end

static void DKColorRefreshDetails(NSString *colorKey, BOOL gradient) {
    NSString *detail = DKColorSchemeStoredColor(colorKey, gradient);
    DKSettingsEnumerateItems(DKSettingsCurrentPage(), ^(AWESettingItemModel *item) {
        if ([objc_getAssociatedObject(item, &kDKColorKeyKey) isEqual:colorKey]) item.detail = detail;
    });
}

static void DKColorCommit(NSString *colorKey, BOOL gradient, NSString *value, dispatch_block_t onChange) {
    DKSettingsValue *declaration = [DKSettingsValue colorWithKey:colorKey gradient:gradient];
    id canonical = [declaration normalize:value reason:NULL];
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

typedef UIViewController *(^DKColorEditorBuilder)(NSString *current, void (^commit)(NSString *value));

static AWESettingItemModel *DKColorItem(NSString *identifier, NSString *colorKey, NSString *title, BOOL gradient,
                                        DKColorEditorBuilder builder) {
    AWESettingItemModel *item = DKMakeAction(identifier, title, DKColorSchemeStoredColor(colorKey, gradient),
        ^(AWESettingItemModel *sender, UIViewController *presenter) {
            dispatch_block_t onChange = DKSettingsItemOnChange(sender);
            NSString *current = DKColorSchemeStoredColor(colorKey, gradient);
            DKColorPresent(presenter, builder(current, ^(NSString *value) {
                DKColorCommit(colorKey, gradient, value, onChange);
            }));
        });
    objc_setAssociatedObject(item, &kDKColorKeyKey, colorKey, OBJC_ASSOCIATION_COPY_NONATOMIC);
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
    AWESettingItemModel *item = DKColorItem(key, key, title, NO, ^UIViewController *(NSString *current, void (^commit)(NSString *)) {
        return [[DKColorPickerController alloc] initWithTitle:title color:current sample:sample completion:commit];
    });
    return DKColorDeclared(item, key, NO);
}

AWESettingItemModel *DKMakeColorHexInput(NSString *identifier, NSString *colorKey, NSString *title, DKColorSample *sample) {
    AWESettingItemModel *item = DKColorItem(identifier, colorKey, title, NO, ^UIViewController *(NSString *current, void (^commit)(NSString *)) {
        return [[DKColorTextController alloc] initWithTitle:title value:current gradient:NO sample:sample completion:commit];
    });
    return DKSettingsWithoutBackup(item);
}

AWESettingItemModel *DKMakeColorGradientInput(NSString *key, NSString *title, DKColorSample *sample) {
    AWESettingItemModel *item = DKColorItem(key, key, title, YES, ^UIViewController *(NSString *current, void (^commit)(NSString *)) {
        return [[DKColorTextController alloc] initWithTitle:title value:current gradient:YES sample:sample completion:commit];
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
