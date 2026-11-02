//
//  DKTopBarSettings.xm
//  功能：顶栏入口 —— 设置项注册：左侧栏入口、滑动展开屏蔽、搜索图标、顶栏透明度。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKTopBarAlpha.h"
#import "DKTopBarGlass.h"

static AWESettingItemModel *DKTopBarGlassSizeItem(NSString *key, NSString *title, NSString *message, NSString *info) {
    AWESettingItemModel *item = DKMakeAdjustSlider(key, title, message, ^(__unused NSInteger value) {
        DKTopBarGlassRefresh();
    });
    return DKSettingsWithInfo(item, info);
}

%ctor {
    DKSettingsRegister(DKKeyTopBarGlass, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeGlassChoice(DKKeyTopBarGlass, DKKeyTopBarGlassClear, @"顶栏液态玻璃", ^{
            DKTopBarGlassRefresh();
        });
        return DKSettingsWithInfo(item,
            @"首页顶栏的左侧栏与搜索入口改为圆形按钮，频道放进一条长胶囊：左右滑动浏览频道，点按切换；"
            @"按住选中的频道可拖动选择，松手切换；按住其它频道仍打开抖音的频道排序。"
            @"胶囊始终在屏幕居中：移除频道后随之变短，移除左侧栏或搜索入口只让对应按钮不再显示，胶囊位置不变。");
    });
    DKSettingsRegister(DKKeyTopBarGlassHeight, ^AWESettingItemModel *{
        return DKTopBarGlassSizeItem(DKKeyTopBarGlassHeight, @"按钮高度", @"100% 为默认高度。",
            @"同时调整两个圆形按钮与频道胶囊的高度，按钮图标随之缩放。放大后超出顶栏的部分不接收点击。"
            @"需开启「顶栏液态玻璃」。");
    });
    DKSettingsRegister(DKKeyTopBarGlassLength, ^AWESettingItemModel *{
        return DKTopBarGlassSizeItem(DKKeyTopBarGlassLength, @"胶囊长度", @"100% 为默认长度。",
            @"在贴合频道内容的基础上缩短胶囊，放不下的频道可在胶囊内滑动查看；胶囊最长贴合全部频道。"
            @"需开启「顶栏液态玻璃」。");
    });

    // 下标与 DKTopBarEntrance.xm 的显示模式一致：0 显示 / 1 隐藏 / 2 移除。
    NSArray<NSString *> *modes = @[ @"显示", @"隐藏", @"移除" ];
    DKSettingsRegister(DKKeyTopBarSideBarMode, ^AWESettingItemModel *{
        return DKSettingsWithInfo(DKMakeChoice(DKKeyTopBarSideBarMode, @"左侧栏入口", modes),
            @"首页顶栏左上角的侧边栏入口（≡）。隐藏：图标不显示，原位置仍可点击打开侧边栏；移除：不显示，点击也无反应。");
    });
    DKSettingsRegister(DKKeyBlockSideBarSwipe, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyBlockSideBarSwipe, @"屏蔽滑动展开左侧栏", @"在最左侧频道右滑不再拉出左侧栏");
    });
    DKSettingsRegister(DKKeyTopBarSearchMode, ^AWESettingItemModel *{
        return DKSettingsWithInfo(DKMakeChoice(DKKeyTopBarSearchMode, @"搜索图标", modes),
            @"首页顶栏右上角的搜索图标，打开评论区时右上角的搜索图标一并生效。隐藏：不显示，仍可点击进入搜索；移除：不显示，点击也无反应。");
    });
    DKSettingsRegister(DKKeyTopBarAlpha, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeRangeSlider(DKKeyTopBarAlpha, @"顶栏透明度",
                                                      @"透明度：0% 完全透明，100% 保持抖音原样。",
                                                      0, 100, 100, ^(__unused NSInteger value) {
            DKTopBarAlphaRefresh();
        });
        return DKSettingsWithInfo(item,
            @"同时调整首页顶栏左侧栏入口、全部频道与搜索图标的透明度；打开评论区时右上角的搜索图标一并生效。"
            @"透明后仍可点击。");
    });
}
