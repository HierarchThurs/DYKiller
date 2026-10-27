//
//  DKProgressPlayedOnly.xm
//  功能：进度条只显示已播时长 —— 进度条只画已播放的部分，不显示未播放的轨道。
//
//  实现：
//   - AWEFeedProgressSlider 的整宽轨道是子视图 sliderRightView（底色即 maximumTrackTintColor），
//     已播段与拇指是叠在其上的图层。开关打开时给轨道挂全透明 mask（DKAdjustFade），
//     不改颜色、alpha、hidden 与 frame；关闭时摘掉自己的 mask。
//   - 进度条随 cell 复用，换视频不重建。布局时（首次布局、暂停加粗）套用并登记到弱引用表，
//     开关切换后对已登记的进度条即时刷新。
//   - 只改轨道的可见性：进度条何时显示仍由抖音与「进度条常显」决定；拖动时显示的
//     AWEFakeProgressSliderView 保持原生。
//   - 设置项登记在本文件 %ctor，布局见 DKSettingsLayout.m「功能增强 › 视频」。
//

#import "DKProgressPlayedOnly.h"
#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"

static NSHashTable<AWEFeedProgressSlider *> *gDKPlayedOnlySliders;

static UIView *DKProgressPlayedOnlyTrack(AWEFeedProgressSlider *slider) {
    return [slider respondsToSelector:@selector(sliderRightView)] ? slider.sliderRightView : nil;
}

static void DKProgressPlayedOnlyApply(AWEFeedProgressSlider *slider) {
    DKAdjustFade(DKProgressPlayedOnlyTrack(slider), DKPrefBool(DKKeyProgressPlayedOnly) ? 0.0 : 1.0, CGSizeZero);
}

static void DKProgressPlayedOnlyRefresh(void) {
    for (AWEFeedProgressSlider *slider in gDKPlayedOnlySliders.allObjects) {
        DKProgressPlayedOnlyApply(slider);
    }
}

NSString *DKProgressPlayedOnlyStatus(void) {
    NSArray<AWEFeedProgressSlider *> *sliders = gDKPlayedOnlySliders.allObjects;
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"只显示已播=%@  已见进度条=%lu\n",
        DKPrefBool(DKKeyProgressPlayedOnly) ? @"开" : @"关", (unsigned long)sliders.count];
    for (AWEFeedProgressSlider *slider in sliders) {
        if (!slider.window) continue;
        UIView *track = DKProgressPlayedOnlyTrack(slider);
        [out appendFormat:@"  进度条 frame=%@ alpha=%.2f  轨道=%@ frame=%@ 底色=%@ 遮罩系数=%.2f\n",
            NSStringFromCGRect(slider.frame), slider.alpha, track ? NSStringFromClass(track.class) : @"无",
            track ? NSStringFromCGRect(track.frame) : @"-", (id)track.backgroundColor ?: @"(nil)",
            DKAdjustFadeFactor(track)];
    }
    return out;
}

%hook AWEFeedProgressSlider

- (void)layoutSubviews {
    %orig;
    if (!gDKPlayedOnlySliders) gDKPlayedOnlySliders = [NSHashTable weakObjectsHashTable];
    [gDKPlayedOnlySliders addObject:self];
    DKProgressPlayedOnlyApply(self);
}

%end

%ctor {
    %init;
    DKSettingsRegister(DKKeyProgressPlayedOnly, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(DKKeyProgressPlayedOnly, @"进度条只显示已播时长",
            @"进度条只显示已经播放的部分，不显示未播放的轨道；播放中与暂停时生效，拖动时仍显示完整进度条。"
            @"只作用于抖音正在显示的进度条：较短的视频默认不显示进度条，仍不显示；开启「进度条常显」后所有视频都按此显示。");
        return DKSettingsOnChange(item, ^{
            DKProgressPlayedOnlyRefresh();
        });
    });
}
