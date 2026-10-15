//
//  DKInteractionAppearanceSettings.xm
//  互动按钮、头像与听音乐组件的外观设置。
//

#import "DKInteractionAppearance.h"
#import "DKKeys.h"
#import "DKSettings.h"

static AWESettingItemModel *DKInteractionAlphaItem(NSString *key, NSString *title, NSString *info) {
    AWESettingItemModel *item = DKMakeRangeSlider(key, title, @"透明度：0% 完全透明，100% 保持抖音原样。",
                                                   0, 100, 100, ^(__unused NSInteger value) {
        DKInteractionAppearanceRefresh();
    });
    return DKSettingsWithInfo(item, info);
}

static AWESettingItemModel *DKInteractionScaleItem(NSString *key, NSString *title, NSString *info) {
    AWESettingItemModel *item = DKMakeRangeSlider(key, title, @"缩放：50% 为一半大小，100% 为原始大小。",
                                                   50, 100, 100, ^(__unused NSInteger value) {
        DKInteractionAppearanceRefresh();
    });
    return DKSettingsWithInfo(item, info);
}

static AWESettingItemModel *DKInteractionDisplayItem(NSString *key, NSString *title, NSString *info) {
    AWESettingItemModel *item = DKMakeChoice(key, title, @[ @"默认显示", @"隐藏可点击", @"隐藏不可点击" ]);
    DKSettingsOnChange(item, ^{ DKInteractionAppearanceRefresh(); });
    return DKSettingsWithInfo(item, info);
}

%ctor {
    DKSettingsRegister(DKKeyInteractionIconAlpha, ^AWESettingItemModel *{
        return DKInteractionAlphaItem(DKKeyInteractionIconAlpha, @"互动按钮图标透明度",
                                      @"调整点赞、评论、收藏、分享等互动按钮图标的透明度。设置值会乘在抖音当前透明度上。");
    });

    DKSettingsRegister(DKKeyInteractionLabelAlpha, ^AWESettingItemModel *{
        return DKInteractionAlphaItem(DKKeyInteractionLabelAlpha, @"互动按钮数字透明度",
                                      @"调整互动按钮下方数字文字的透明度；没有数字的按钮不受影响。");
    });

    DKSettingsRegister(DKKeyAvatarAlpha, ^AWESettingItemModel *{
        return DKInteractionAlphaItem(DKKeyAvatarAlpha, @"头像透明度",
                                      @"调整视频右侧头像（含描边和下方关注、私信小圆标）的透明度；不影响头像点击。");
    });

    DKSettingsRegister(DKKeyMusicAlpha, ^AWESettingItemModel *{
        return DKInteractionAlphaItem(DKKeyMusicAlpha, @"听音乐图标透明度",
                                      @"调整右侧栏底部音乐图标（听抖音、拍同款、音乐唱片等，静音播放时的「取消静音」按钮一并生效）及其文字的透明度；不影响点击。");
    });

    DKSettingsRegister(DKKeyInteractionScale, ^AWESettingItemModel *{
        return DKInteractionScaleItem(DKKeyInteractionScale, @"互动按钮缩放",
                                      @"缩小互动按钮的图标和数字。右侧栏整列贴右排布，底部与进度条的间距不变，元素间距随之等比缩小。");
    });

    DKSettingsRegister(DKKeyAvatarScale, ^AWESettingItemModel *{
        return DKInteractionScaleItem(DKKeyAvatarScale, @"头像缩放",
                                      @"缩小视频右侧头像及下方小圆标。右侧栏整列贴右排布，底部与进度条的间距不变，元素间距随之等比缩小。");
    });

    DKSettingsRegister(DKKeyMusicScale, ^AWESettingItemModel *{
        return DKInteractionScaleItem(DKKeyMusicScale, @"听音乐图标缩放",
                                      @"缩小右侧栏底部音乐图标及其文字（「取消静音」按钮一并生效）。右侧栏整列贴右排布，底部与进度条的间距不变，元素间距随之等比缩小。");
    });

    DKSettingsRegister(DKKeyInteractionOffset, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeUnitSlider(DKKeyInteractionOffset, @"互动区域上移",
                                                     @"上移：0 pt 为抖音原位，最大 100 pt。",
                                                     0, 100, 0, @" pt", ^(__unused NSInteger value) {
            DKInteractionAppearanceRefresh();
        });
        return DKSettingsWithInfo(item, @"整体上移右侧头像、互动按钮和音乐，只增大音乐与进度条的间距；0 pt 为抖音原位。");
    });

    DKSettingsRegister(DKKeyInteractionDisplay, ^AWESettingItemModel *{
        return DKInteractionDisplayItem(DKKeyInteractionDisplay, @"互动按钮显示方式",
                                        @"默认显示；隐藏可点击只隐藏按钮内容；隐藏不可点击同时阻止按钮命中。");
    });

    DKSettingsRegister(DKKeyAvatarDisplay, ^AWESettingItemModel *{
        return DKInteractionDisplayItem(DKKeyAvatarDisplay, @"头像显示方式",
                                        @"默认显示；隐藏可点击仍可进入头像；隐藏不可点击同时阻止头像及其小圆标命中。");
    });

    DKSettingsRegister(DKKeyMusicDisplay, ^AWESettingItemModel *{
        return DKInteractionDisplayItem(DKKeyMusicDisplay, @"听音乐图标显示方式",
                                        @"默认显示；隐藏可点击仍可打开音乐入口；隐藏不可点击同时阻止入口命中。「取消静音」按钮不受影响。");
    });
}
