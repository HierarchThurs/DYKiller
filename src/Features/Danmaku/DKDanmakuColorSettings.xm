#import "DKDanmakuColor.h"
#import "DKColorScheme.h"
#import "DKKeys.h"
#import "DKSettings.h"

// 样例按抖音原生弹幕不透明度显示。
static DKColorSample *DKDanmakuSample(void) {
    DKColorSample *sample = [DKColorSample new];
    sample.text = @"这是一条彩色弹幕";
    sample.alpha = ^CGFloat { return DKDanmakuNativeAlpha(); };
    sample.alphaNote = ^NSString *(CGFloat alpha) {
        return [NSString stringWithFormat:@"抖音原生不透明度 %.0f%%（只读），样例按此显示。", alpha * 100];
    };
    return sample;
}

static AWESettingItemModel *DKDanmakuRefreshing(AWESettingItemModel *item, NSString *info) {
    return DKSettingsOnChange(DKSettingsWithInfo(item, info), ^{ DKDanmakuColorRefresh(); });
}

%ctor {
    DKSettingsRegister(DKKeyDanmakuColorEnabled, ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(DKKeyDanmakuColorEnabled, @"启用弹幕改色",
            @"正文、点赞爱心与数字共用同一条弹幕的配色，渐变沿整条连续显示。开启后移除文字黑色描边，保留爱心形状与点赞动画；关闭后恢复原生颜色、描边与图案。"),
            ^{ DKDanmakuColorRefresh(); });
    });
    DKSettingsRegister(DKKeyDanmakuColorMode, ^AWESettingItemModel *{
        return DKDanmakuRefreshing(DKMakeChoice(DKKeyDanmakuColorMode, @"颜色模式", DKColorSchemeModeTitles()),
            @"六种模式互斥。固定颜色使用下方颜色面板；随机纯色每条生成一个随机 RGB 色；随机渐变每条生成三色渐变；"
            @"固定彩虹使用红橙黄绿青蓝紫；自定义渐变按输入顺序；旋转彩虹每条轮换七色起始色，不是逐帧动画。");
    });
    DKSettingsRegister(DKKeyDanmakuFixedColor, ^AWESettingItemModel *{
        return DKDanmakuRefreshing(DKMakeColorPicker(DKKeyDanmakuFixedColor, @"选择弹幕颜色", DKDanmakuSample()),
            @"打开颜色面板，通过色谱或 RGB 滑块连续选色。原生不透明度只读显示，样例继承该透明度；仅在总开关开启且模式为「固定颜色」时可用。");
    });
    DKSettingsRegister(DKKeyDanmakuHexColor, ^AWESettingItemModel *{
        return DKDanmakuRefreshing(DKMakeColorHexInput(DKKeyDanmakuHexColor, DKKeyDanmakuFixedColor, @"十六进制颜色入口", DKDanmakuSample()),
            @"支持 #RGB、#RRGGBB；弹幕不透明度继承抖音原生设置，这里只保存颜色。与颜色选择器共用固定颜色值。");
    });
    DKSettingsRegister(DKKeyDanmakuGradientColors, ^AWESettingItemModel *{
        return DKDanmakuRefreshing(DKMakeColorGradientInput(DKKeyDanmakuGradientColors, @"渐变颜色", DKDanmakuSample()),
            @"点「＋ 添加颜色」逐个选色，拖动排序决定从左至右的渐变顺序；弹幕不透明度继承抖音原生设置。仅在「自定义渐变」模式生效。");
    });
}
