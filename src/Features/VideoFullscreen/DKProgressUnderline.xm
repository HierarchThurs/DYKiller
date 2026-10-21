//
//  DKProgressUnderline.xm
//  视频全屏开启时遮掉原生进度条底边背景；关闭时恢复原生绘制与显隐。
//

#import "DKVideoFullscreen.h"
#import "DouyinHeaders.h"
#import "DKViewAdjust.h"

static NSHashTable<AWEDProgressStateChangeContainer *> *gDKUnderlineStates;
static NSHashTable<AWEDProgressFeedContainer *> *gDKUnderlineFeeds;
static NSHashTable<UIView *> *gDKUnderlineViews;

void DKProgressUnderlineRefresh(void) {
    for (AWEDProgressFeedContainer *feed in gDKUnderlineFeeds.allObjects) {
        [feed progressSliderUnderView];
    }
    for (UIView *view in gDKUnderlineViews.allObjects) {
        DKAdjustFade(view, DKVideoFullscreenOn() ? 0 : 1, CGSizeZero);
    }
    for (AWEDProgressStateChangeContainer *state in gDKUnderlineStates.allObjects) {
        [state updateProgressSliderUnderView];
    }
}

%group DKProgressUnderlineStateHooks
%hook AWEDProgressStateChangeContainer

- (void)updateProgressSliderUnderView {
    [gDKUnderlineStates addObject:self];
    %orig;
    if (DKVideoFullscreenOn()) [self progressSliderUnderView].hidden = YES;
}

%end
%end

%group DKProgressUnderlineFeedHooks
%hook AWEDProgressFeedContainer

- (UIView *)progressSliderUnderView {
    UIView *view = %orig;
    [gDKUnderlineFeeds addObject:self];
    if (view) {
        [gDKUnderlineViews addObject:view];
        // 背景创建后即遮掉绘制，原生后续改色和显隐仍可照常执行。
        DKAdjustFade(view, DKVideoFullscreenOn() ? 0 : 1, CGSizeZero);
    }
    return view;
}

%end
%end

%ctor {
    Class feed = NSClassFromString(@"AWEDProgressFeedContainer");
    if ([feed instancesRespondToSelector:@selector(progressSliderUnderView)]) {
        gDKUnderlineFeeds = [NSHashTable weakObjectsHashTable];
        gDKUnderlineViews = [NSHashTable weakObjectsHashTable];
        %init(DKProgressUnderlineFeedHooks);
    }
    Class state = NSClassFromString(@"AWEDProgressStateChangeContainer");
    if ([state instancesRespondToSelector:@selector(updateProgressSliderUnderView)]
        && [state instancesRespondToSelector:@selector(progressSliderUnderView)]) {
        gDKUnderlineStates = [NSHashTable weakObjectsHashTable];
        %init(DKProgressUnderlineStateHooks);
    }
}
