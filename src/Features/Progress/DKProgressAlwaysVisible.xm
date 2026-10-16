//
//  DKProgressAlwaysVisible.xm
//  功能：进度条常显 —— 所有视频常态下都显示底部进度条。
//
//  实现：
//   - 进度条常态（播放中、未触碰）的外观由状态机 AWEDProgressStateChangeContainer 套用，
//     是否透明经 AWEDProgressCoreContainer 转问 AWEDProgressHidePluginContainer；
//     后者按视频时长判定，较短的视频返回 YES，常态 alpha 写 0，暂停或拖动时才出现。
//   - 开关打开时该判定返回 NO，短视频与长视频套用同一套常态外观。只改判定、不写视图属性，
//     shouldHideProgressSlider 等隐藏路径仍按抖音原逻辑。
//   - 状态机每次取判定时登记到弱引用表；开关切换后对其调用 reapplyCurrentStateAppearance，
//     按当前状态重新套用外观，当前视频即时生效。
//   - 设置项登记在本文件 %ctor，布局见 DKSettingsLayout.m「功能增强 › 视频」。
//

#import "DKProgressAlwaysVisible.h"
#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"

static NSHashTable<AWEDProgressStateChangeContainer *> *gDKProgressStates;
// 诊断读取抖音原判定时置位，判定放行原值。
static BOOL gDKProgressNativeQuery;

static BOOL DKProgressAlwaysVisibleOn(void) {
    return DKPrefBool(DKKeyProgressAlwaysVisible) && !gDKProgressNativeQuery;
}

static void DKProgressAlwaysVisibleRefresh(void) {
    for (AWEDProgressStateChangeContainer *state in gDKProgressStates.allObjects) {
        if ([state respondsToSelector:@selector(reapplyCurrentStateAppearance)]) {
            [state reapplyCurrentStateAppearance];
        }
    }
}

static NSString *DKProgressTransparentText(BOOL transparent) {
    return transparent ? @"透明" : @"显示";
}

NSString *DKProgressAlwaysVisibleStatus(void) {
    NSArray<AWEDProgressStateChangeContainer *> *states = gDKProgressStates.allObjects;
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"进度条常显=%@  已见状态机=%lu  即时刷新入口=%@\n",
        DKPrefBool(DKKeyProgressAlwaysVisible) ? @"开" : @"关", (unsigned long)states.count,
        [NSClassFromString(@"AWEDProgressStateChangeContainer")
            instancesRespondToSelector:@selector(reapplyCurrentStateAppearance)] ? @"有" : @"无"];
    if (!states.count) {
        [out appendString:@"  未见状态机：尚未播放视频，或进度条结构已变\n"];
        return out;
    }
    for (AWEDProgressStateChangeContainer *state in states) {
        long long current = [state respondsToSelector:@selector(currentState)] ? [state currentState] : -1;
        gDKProgressNativeQuery = YES;
        BOOL native = [state shouldTransparentProgressSliderOnStableState];
        gDKProgressNativeQuery = NO;
        BOOL effective = [state shouldTransparentProgressSliderOnStableState];
        UIView *slider = [state respondsToSelector:@selector(progressSlider)] ? (UIView *)[state progressSlider] : nil;
        [out appendFormat:@"  状态=%lld 原判定=%@ 生效判定=%@", current,
            DKProgressTransparentText(native), DKProgressTransparentText(effective)];
        if (slider) {
            [out appendFormat:@" 进度条 alpha=%.2f hidden=%d frame=%@ 在窗口=%@\n", slider.alpha, slider.isHidden,
                NSStringFromCGRect(slider.frame), slider.window ? @"是" : @"否"];
        } else {
            [out appendString:@" 进度条=无\n"];
        }
    }
    return out;
}

%hook AWEDProgressHidePluginContainer

- (BOOL)shouldTransparentProgressSliderOnStableState {
    if (DKProgressAlwaysVisibleOn()) return NO;
    return %orig;
}

%end

%hook AWEDProgressStateChangeContainer

- (BOOL)shouldTransparentProgressSliderOnStableState {
    if (!gDKProgressStates) gDKProgressStates = [NSHashTable weakObjectsHashTable];
    [gDKProgressStates addObject:self];
    return %orig;
}

%end

%ctor {
    %init;
    DKSettingsRegister(DKKeyProgressAlwaysVisible, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(DKKeyProgressAlwaysVisible, @"进度条常显",
            @"所有视频播放时都显示底部进度条，样式与长视频一致。"
            @"抖音默认只为较长的视频常驻显示进度条，较短的视频要暂停或拖动时才出现。");
        return DKSettingsOnChange(item, ^{
            DKProgressAlwaysVisibleRefresh();
        });
    });
}
