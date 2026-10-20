// 内容过滤开关、特殊卡类别与精确整数阈值输入。
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
    return DKSettingsOnChange(DKMakeSwitch(key, title, detail), ^{ DKFilterPreferencesChanged(); });
}

static NSString *DKFilterThresholdDetail(long long value) {
    return value ? [NSString stringWithFormat:@"%lld", value] : @"0（不筛选）";
}

static AWESettingItemModel *DKFilterThresholdItem(void) {
    long long current = DKFilterCurrentConfig().minimumLikes;
    AWESettingItemModel *threshold = DKMakeAction(DKKeyMinimumLikes, @"最低点赞数", DKFilterThresholdDetail(current),
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
    DKSettingsWithValues(threshold, @[ [DKSettingsValue integerWithKey:DKKeyMinimumLikes minimum:0 maximum:LLONG_MAX] ],
        ^NSString *(NSArray *values, __unused BOOL brief) {
            return DKFilterThresholdDetail(values[0] == NSNull.null ? 0 : [values[0] longLongValue]);
        });
    DKSettingsOnChange(threshold, ^{ DKFilterPreferencesChanged(); });
    return DKSettingsWithInfo(threshold,
        @"「低赞过滤」的阈值：首页推荐里点赞数低于该值的作品不再出现；填 0 不筛选，修改从后续批次生效。");
}

%ctor {
    DKSettingsRegister(DKKeyFilterLowLikes, ^AWESettingItemModel *{
        return DKFilterSwitch(DKKeyFilterLowLikes, @"低赞过滤", @"仅首页推荐；点赞数低于阈值的作品不进入后续批次");
    });
    DKSettingsRegister(DKKeyMinimumLikes, ^AWESettingItemModel *{ return DKFilterThresholdItem(); });
    DKSettingsRegister(DKKeyRemoveRecommendedLive, ^AWESettingItemModel *{
        return DKFilterSwitch(DKKeyRemoveRecommendedLive, @"推荐页移除直播", @"从后续推荐批次移除直播预览");
    });
    DKSettingsRegister(DKKeyFilterRecommendedMusic, ^AWESettingItemModel *{
        return DKFilterSwitch(DKKeyFilterRecommendedMusic, @"推荐过滤音乐", @"过滤首页推荐中的音乐卡片；从后续新载入批次生效，普通配乐作品保留。");
    });
    DKSettingsRegister(DKKeyFilterRecommendedArticle, ^AWESettingItemModel *{
        return DKFilterSwitch(DKKeyFilterRecommendedArticle, @"推荐过滤文章",
            @"过滤首页推荐中的文章作品（带「阅读文章」按钮的长文）；从后续新载入批次生效，视频与图文保留。");
    });
    DKSettingsRegister(DKKeyFilterRecommendedMerchantNote, ^AWESettingItemModel *{
        return DKFilterSwitch(DKKeyFilterRecommendedMerchantNote, @"推荐过滤商家笔记",
            @"过滤首页推荐中的商家笔记（带店铺与团购信息的图文卡片，如「XX店笔记」）；"
            @"从后续新载入批次生效，普通图文与带地点的视频保留。");
    });
    DKSettingsRegister(DKKeyFilterRecommendedSpecialCard, ^AWESettingItemModel *{
        return DKFilterSwitch(DKKeyFilterRecommendedSpecialCard, @"推荐过滤特殊卡片",
            @"过滤首页推荐中的全部整屏卡片：下方各类卡片，以及未单独列出的同类卡片（含抖音新下发的类型）。"
            @"开启后下方各项锁定为开启；关闭后各项按自己的设置生效。从后续新载入批次生效。");
    });
    for (NSUInteger kind = 0; kind < DKFilterCardOther; kind++) {
        NSString *key = DKFilterCardKindKey((DKFilterCardKind)kind);
        DKSettingsRegister(key, ^AWESettingItemModel *{
            return DKFilterSwitch(key, DKFilterCardKindTitle((DKFilterCardKind)kind),
                                  DKFilterCardKindInfo((DKFilterCardKind)kind));
        });
    }
    DKSettingsRegister(DKKeyFilterAds, ^AWESettingItemModel *{
        return DKFilterSwitch(DKKeyFilterAds, @"抖音过滤广告", @"过滤新载入的广告作品、搜索卡片及启动广告");
    });
}
