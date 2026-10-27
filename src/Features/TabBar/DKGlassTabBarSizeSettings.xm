//
//  DKGlassTabBarSizeSettings.xm
//  功能：悬浮玻璃底栏尺寸 —— 胶囊高度（等比缩放）、胶囊长度、拍摄键大小的设置项。
//  几何见 DKGlassTabBar.xm 的 DKGlassLayoutGlass；范围登记在 DKAdjustRange.m。
//

#import "DKGlassTabBar.h"
#import "DKKeys.h"
#import "DKSettings.h"

static AWESettingItemModel *DKGlassTabBarSizeItem(NSString *key, NSString *title, NSString *message, NSString *info) {
    AWESettingItemModel *item = DKMakeAdjustSlider(key, title, message, ^(__unused NSInteger value) {
        DKGlassTabBarRefresh();
    });
    return DKSettingsWithInfo(item, info);
}

%ctor {
    DKSettingsRegister(DKKeyGlassTabBarCapsuleHeight, ^AWESettingItemModel *{
        return DKGlassTabBarSizeItem(DKKeyGlassTabBarCapsuleHeight, @"胶囊高度",
            @"100% 为默认大小，胶囊按比例缩放。",
            @"按比例缩放底栏胶囊，高度、长度与图标文字一起变化；胶囊底边离屏幕底边的距离不变。"
            @"需开启「悬浮玻璃底栏」。");
    });
    DKSettingsRegister(DKKeyGlassTabBarCapsuleLength, ^AWESettingItemModel *{
        return DKGlassTabBarSizeItem(DKKeyGlassTabBarCapsuleLength, @"胶囊长度",
            @"100% 为默认长度。",
            @"在「胶囊高度」的基础上单独缩短胶囊，各项按钮仍在胶囊内等距排开；移除部分底栏项目后，"
            @"剩余项目按同样的间距排开。系统胶囊放大到自然宽度后不再变长。需开启「悬浮玻璃底栏」。");
    });
    DKSettingsRegister(DKKeyGlassTabBarPlusSize, ^AWESettingItemModel *{
        return DKGlassTabBarSizeItem(DKKeyGlassTabBarPlusSize, @"拍摄键大小",
            @"100% 为默认直径。",
            @"调整右侧拍摄圆键的直径，图标随之缩放；圆键底边离屏幕底边的距离不变。需开启「悬浮玻璃底栏」。");
    });
}
