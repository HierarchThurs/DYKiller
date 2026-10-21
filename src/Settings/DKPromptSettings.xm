#import "DKSettings.h"
#import "DKKeys.h"
#import "DKPromptInternal.h"

// 所有通用提示会话共用材质；存值由现有的开关与清透两个键提供。
%ctor {
    DKSettingsRegister(DKKeyMediaSaveGlass, ^AWESettingItemModel *{
        return DKSettingsWithInfo(
            DKMakeGlassChoice(DKKeyMediaSaveGlass, DKKeyMediaSaveGlassClear, @"提示面板材质", ^{
                [[DKPromptCoordinator shared] refreshAppearance];
            }),
            @"所有使用通用提示面板的业务共用此材质。关闭仅关闭玻璃效果，面板仍使用系统模糊；模糊玻璃使用 iOS 26 Regular；清透玻璃显示更多背后画面细节。");
    });
}
