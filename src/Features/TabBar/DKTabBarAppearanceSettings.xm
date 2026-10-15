//
//  DKTabBarAppearanceSettings.xm
//  功能：外观定制 —— 底栏样式、拍摄按钮与五项底栏文字的设置项。
//

#import "DKTabBarAppearance.h"
#import "DKPlusIcon.h"
#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"

// 底栏文字的显示宽度上限：6 个汉字（12 个字母数字）。
static const NSUInteger kDKTitleMaxWidth = 12;

static void DKRegisterTitle(NSString *key, NSString *name) {
    DKSettingsRegister(key, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeTextInput(key, name, name, kDKTitleMaxWidth);
        DKSettingsOnChange(item, ^{ DKTabBarAppearanceRefresh(); });
        return DKSettingsWithInfo(item, [NSString stringWithFormat:
            @"修改底栏「%@」显示的文字，最多 6 个汉字；留空为抖音默认。「图标+文字」样式下同样显示修改后的文字。", name]);
    });
}

%ctor {
    // 老版本只要有自定义图片就显示它；首次升级时按「自定义图片」接上，外观不变。
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (![defaults objectForKey:DKKeyPlusStyle] && DKPlusIconCustom()) {
        [defaults setInteger:DKPlusStyleCustom forKey:DKKeyPlusStyle];
    }

    DKSettingsRegister(DKKeyTabBarStyle, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeChoice(DKKeyTabBarStyle, @"底栏样式", @[ @"默认", @"单图标", @"图标 + 文字" ]);
        DKSettingsOnChange(item, ^{ DKTabBarAppearanceRefresh(); });
        return DKSettingsWithInfo(item,
            @"首页、朋友或商城、消息、我四项的显示方式：默认为抖音原样文字；单图标只显示图标；图标 + 文字在图标下方显示一行小字。"
            @"悬浮玻璃底栏与抖音原生底栏都生效。");
    });

    DKSettingsRegister(DKKeyPlusStyle, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeChoiceConfirm(DKKeyPlusStyle, @"拍摄按钮",
            @[ @"默认", @"新图标", @"新双色图标", @"自定义图片" ],
            ^(NSInteger index, UIViewController *presenter, dispatch_block_t commit) {
                // 还没有自定义图片时先选图，写盘成功才切过去；取消则保持原选项。
                if (index != DKPlusStyleCustom || DKPlusIconCustom()) {
                    commit();
                    return;
                }
                DKPlusIconPick(presenter, ^(BOOL picked) {
                    if (picked) commit();
                });
            });
        DKSettingsOnChange(item, ^{ DKTabBarAppearanceRefresh(); });
        return DKSettingsWithInfo(item,
            @"底栏中间拍摄按钮的图标：默认为抖音原样；新图标为实心照相机；新双色图标带抖音青红描边；"
            @"自定义图片使用「更换拍摄图标」里的图片，首次选择时会先打开相册。悬浮玻璃底栏与抖音原生底栏都生效。");
    });

    DKRegisterTitle(DKKeyTabTitleHome, @"首页");
    DKRegisterTitle(DKKeyTabTitleFriends, @"朋友");
    DKRegisterTitle(DKKeyTabTitleMall, @"商城");
    DKRegisterTitle(DKKeyTabTitleNotification, @"消息");
    DKRegisterTitle(DKKeyTabTitleProfile, @"我");
}
