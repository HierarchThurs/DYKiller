// 三个独立开关与精确整数阈值输入。
#import "DKContentFilter.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import <objc/runtime.h>

@interface DKFilterNumberInput : NSObject
@property (nonatomic, weak) UIAlertController *alert;
@property (nonatomic, weak) UIAlertAction *confirm;
- (void)changed:(UITextField *)field;
@end
@implementation DKFilterNumberInput
- (void)changed:(UITextField *)field {
    BOOL valid = DKFilterParseInteger(field.text, NULL);
    self.confirm.enabled = valid;
    self.alert.message = valid ? @"0 不筛选；设置从后续批次生效。"
        : @"请输入 0 至 9223372036854775807 的整数。";
}
@end
static char kDKFilterNumberInputKey;

static AWESettingItemModel *DKFilterSwitch(NSString *key, NSString *title, NSString *detail) {
    AWESettingItemModel *item = DKMakeSwitch(key, title, detail);
    void (^original)(void) = item.switchChangedBlock;
    item.switchChangedBlock = ^{ original(); DKFilterPreferencesChanged(); };
    return item;
}

static NSString *DKFilterThresholdDetail(long long value) {
    return value ? [NSString stringWithFormat:@"%lld", value] : @"0（不筛选）";
}

static AWESettingItemModel *DKFilterThresholdItem(void) {
    long long current = DKFilterCurrentConfig().minimumLikes;
    return DKMakeAction(DKKeyMinimumLikes, @"最低点赞数", DKFilterThresholdDetail(current),
        ^(AWESettingItemModel *item, UIViewController *presenter) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"最低点赞数"
            message:@"0 不筛选；设置从后续批次生效。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.keyboardType = UIKeyboardTypeNumberPad;
            field.text = [NSString stringWithFormat:@"%lld", DKFilterCurrentConfig().minimumLikes];
        }];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        __weak AWESettingItemModel *weakItem = item;
        __weak UIAlertController *weakAlert = alert;
        UIAlertAction *confirm = [UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault
            handler:^(__unused UIAlertAction *action) {
            long long value = 0;
            if (!DKFilterParseInteger(weakAlert.textFields.firstObject.text, &value)) return;
            [NSUserDefaults.standardUserDefaults setObject:@(value) forKey:DKKeyMinimumLikes];
            DKFilterPreferencesChanged();
            weakItem.detail = DKFilterThresholdDetail(value);
            DKSettingsReloadCurrentPage();
        }];
        [alert addAction:confirm];
        DKFilterNumberInput *input = [DKFilterNumberInput new];
        input.alert = alert;
        input.confirm = confirm;
        objc_setAssociatedObject(alert, &kDKFilterNumberInputKey, input, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [alert.textFields.firstObject addTarget:input action:@selector(changed:) forControlEvents:UIControlEventEditingChanged];
        [input changed:alert.textFields.firstObject];
        [presenter presentViewController:alert animated:YES completion:nil];
    });
}

%ctor {
    DKSettingsRegisterItem(@"内容过滤", ^AWESettingItemModel *{
        return DKFilterSwitch(DKKeyFilterLowLikes, @"低赞过滤", @"仅首页推荐；点赞数低于阈值的作品不进入后续批次");
    });
    DKSettingsRegisterItem(@"内容过滤", ^AWESettingItemModel *{ return DKFilterThresholdItem(); });
    DKSettingsRegisterItem(@"内容过滤", ^AWESettingItemModel *{
        return DKFilterSwitch(DKKeyRemoveRecommendedLive, @"推荐页移除直播", @"从后续推荐批次移除直播预览");
    });
    DKSettingsRegisterItem(@"内容过滤", ^AWESettingItemModel *{
        return DKFilterSwitch(DKKeyFilterAds, @"抖音过滤广告", @"过滤新载入的广告作品、搜索卡片及启动广告");
    });
}
