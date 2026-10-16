//
//  DKInfoAppearanceSettings.xm
//  视频左下昵称与文案区域的外观设置。
//

#import "DKInfoAppearance.h"
#import "DKKeys.h"
#import "DKSettings.h"

static AWESettingItemModel *DKInfoAlphaItem(NSString *key, NSString *title, NSString *info) {
    AWESettingItemModel *item = DKMakeRangeSlider(key, title, @"透明度：0% 完全透明，100% 保持抖音原样。",
                                                   0, 100, 100, ^(__unused NSInteger value) {
        DKInfoAppearanceRefresh();
    });
    return DKSettingsWithInfo(item, info);
}

static AWESettingItemModel *DKInfoScaleItem(NSString *key, NSString *title, NSString *info) {
    AWESettingItemModel *item = DKMakeAdjustSlider(key, title, @"缩放：25% 为四分之一大小，100% 为原始大小。",
                                                   ^(__unused NSInteger value) {
        DKInfoAppearanceRefresh();
    });
    return DKSettingsWithInfo(item, info);
}

%ctor {
    DKSettingsRegister(DKKeyNicknameAlpha, ^AWESettingItemModel *{
        return DKInfoAlphaItem(DKKeyNicknameAlpha, @"昵称透明度",
                               @"调整视频左下作者昵称一行（含标签与发布时间）的透明度；不影响点击进入作者主页。");
    });

    DKSettingsRegister(DKKeyDescriptionAlpha, ^AWESettingItemModel *{
        return DKInfoAlphaItem(DKKeyDescriptionAlpha, @"文案透明度",
                               @"调整作品文案及左下方其余信息（弹幕入口、话题、定位等）的透明度；不影响点击。"
                               @"朋友页的私信快捷回复栏不受影响。");
    });

    DKSettingsRegister(DKKeyNicknameScale, ^AWESettingItemModel *{
        return DKInfoScaleItem(DKKeyNicknameScale, @"昵称缩放",
                               @"缩小作者昵称一行。左下信息整列贴左排布，底部与进度条的间距不变，行间距随之等比缩小。");
    });

    DKSettingsRegister(DKKeyDescriptionScale, ^AWESettingItemModel *{
        return DKInfoScaleItem(DKKeyDescriptionScale, @"文案缩放",
                               @"缩小作品文案及左下方其余信息行。左下信息整列贴左排布，底部与进度条的间距不变，"
                               @"行间距随之等比缩小。朋友页的私信快捷回复栏不缩放。");
    });

    DKSettingsRegister(DKKeyInfoOffset, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeAdjustSlider(DKKeyInfoOffset, @"昵称文案上移",
                                                       @"上移：0 pt 为抖音原位。", ^(__unused NSInteger value) {
            DKInfoAppearanceRefresh();
        });
        return DKSettingsWithInfo(item, @"整体上移左下昵称、文案及其余信息，只增大与进度条的间距；0 pt 为抖音原位。");
    });
}
