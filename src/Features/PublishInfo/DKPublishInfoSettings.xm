#import "DKPublishInfo.h"
#import "DKColorScheme.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"

// 样例按「文案透明度」显示：这一行属于文案组。
static DKColorSample *DKPublishSample(NSString *text) {
    DKColorSample *sample = [DKColorSample new];
    sample.text = text;
    sample.alpha = ^CGFloat { return DKPrefFraction(DKKeyDescriptionAlpha, 100); };
    sample.alphaNote = ^NSString *(CGFloat alpha) {
        return [NSString stringWithFormat:@"不透明度跟随「文案透明度」（当前 %.0f%%），样例按此显示。", alpha * 100];
    };
    return sample;
}

static AWESettingItemModel *DKPublishRefreshing(AWESettingItemModel *item, NSString *info) {
    return DKSettingsOnChange(DKSettingsWithInfo(item, info), ^{ DKPublishInfoRefresh(); });
}

// 时间、地区两段文字的颜色设置，结构相同。
static void DKRegisterPartColors(BOOL location) {
    NSString *part = location ? @"地区" : @"时间";
    NSString *subject = location ? @"发布地区" : @"具体发布时间";
    NSString *enabledKey = location ? DKKeyPublishLocationColorEnabled : DKKeyPublishTimeColorEnabled;
    NSString *modeKey = location ? DKKeyPublishLocationColorMode : DKKeyPublishTimeColorMode;
    NSString *fixedKey = location ? DKKeyPublishLocationFixedColor : DKKeyPublishTimeFixedColor;
    NSString *hexKey = location ? DKKeyPublishLocationHexColor : DKKeyPublishTimeHexColor;
    NSString *gradientKey = location ? DKKeyPublishLocationGradientColors : DKKeyPublishTimeGradientColors;
    NSString *sampleText = location ? @"四川 成都" : @"2026-07-25 03:03:47";

    DKSettingsRegister(enabledKey, ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(enabledKey, [NSString stringWithFormat:@"启用%@文字改色", part],
            [NSString stringWithFormat:@"接管%@的文字颜色。关闭后恢复默认颜色；%@颜色设置保留。", subject, part]),
            ^{ DKPublishInfoRefresh(); });
    });
    DKSettingsRegister(modeKey, ^AWESettingItemModel *{
        return DKPublishRefreshing(DKMakeChoice(modeKey, @"颜色模式", DKColorSchemeModeTitles()),
            @"六种模式互斥。固定颜色使用下方颜色面板；随机纯色、随机渐变按作品各生成一次；固定彩虹使用红橙黄绿青蓝紫；"
            @"自定义渐变按输入顺序；旋转彩虹每条作品轮换七色起始色，不是逐帧动画。");
    });
    DKSettingsRegister(fixedKey, ^AWESettingItemModel *{
        return DKPublishRefreshing(DKMakeColorPicker(fixedKey, [NSString stringWithFormat:@"选择%@文字颜色", part], DKPublishSample(sampleText)),
            [NSString stringWithFormat:@"通过色谱或 RGB 滑块选择%@文字颜色。仅在%@文字改色开启且颜色模式为「固定颜色」时可用。", part, part]);
    });
    DKSettingsRegister(hexKey, ^AWESettingItemModel *{
        return DKPublishRefreshing(DKMakeColorHexInput(hexKey, fixedKey, [NSString stringWithFormat:@"%@十六进制颜色入口", part], DKPublishSample(sampleText)),
            @"支持 #RGB、#RRGGBB 和 #AARRGGBB，# 可省略；八位输入忽略前两位透明度，仅保存 RGB。与颜色面板共用固定颜色值。");
    });
    DKSettingsRegister(gradientKey, ^AWESettingItemModel *{
        return DKPublishRefreshing(DKMakeColorGradientInput(gradientKey, [NSString stringWithFormat:@"%@渐变颜色", part], DKPublishSample(sampleText)),
            [NSString stringWithFormat:@"输入 2–8 个十六进制颜色并以英文逗号分隔，顺序即为从左至右的渐变顺序。仅在%@颜色模式为「自定义渐变」时生效。", part]);
    });
}

%ctor {
    DKSettingsRegister(DKKeyPublishTimeEnabled, ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(DKKeyPublishTimeEnabled, @"显示具体发布时间",
            @"在播放页显示作品发布的年月日与时分秒，按设备时区展示。"), ^{ DKPublishInfoRefresh(); });
    });
    DKSettingsRegister(DKKeyPublishLocationEnabled, ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(DKKeyPublishLocationEnabled, @"显示发布地区",
            @"根据抖音返回的地区信息显示发布地区，国内尽量显示省市，国外显示可解析的国家与地区。精度以数据为准，网络属地可能与实际所在位置不同。"),
            ^{ DKPublishInfoRefresh(); });
    });
    DKRegisterPartColors(NO);
    DKRegisterPartColors(YES);
    DKSettingsRegister(DKKeyGeoNamesUsername, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeTextInputWithPrompt(DKKeyGeoNamesUsername, @"国外解析账号", @"GeoNames 用户名", 40,
            @"填写 GeoNames 用户名，用于解析国外详细地区。留空时使用已有国家或属地信息。", @"未填写", @"清空账号");
        return DKPublishRefreshing(item,
            @"填写 GeoNames 用户名以解析国外详细地区；未填写或解析失败时，使用已有国家或属地信息。需先开启「显示发布地区」。");
    });
    DKSettingsRegister(DKKeyGeoNamesRegister, ^AWESettingItemModel *{
        return DKSettingsWithInfo(DKMakeWebLink(DKKeyGeoNamesRegister, @"注册 GeoNames 账号", @"https://www.geonames.org/login"),
            @"在系统浏览器中打开 GeoNames 官网注册页面，注册免费账号。");
    });
    DKSettingsRegister(DKKeyGeoNamesWebServices, ^AWESettingItemModel *{
        return DKSettingsWithInfo(DKMakeWebLink(DKKeyGeoNamesWebServices, @"启用 Web Services", @"https://www.geonames.org/manageaccount"),
            @"登录后在账户管理页面启用 Free Web Services，账号才能用于地名查询。");
    });
}
