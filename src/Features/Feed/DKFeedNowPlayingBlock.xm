// 信息流和详情视频的正在播放信息写入开关。

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import <objc/runtime.h>

static NSHashTable<AWEFeedBackgroundPlayManager *> *gDKFeedNowPlayingManagers;
static BOOL gDKClearingFeedNowPlaying;

static BOOL DKFeedNowPlayingBlocked(void) {
    return DKPrefBool(DKKeyBlockFeedNowPlaying) && !(NSThread.isMainThread && gDKClearingFeedNowPlaying);
}

static BOOL DKTrackFeedManagerAndCheckBlock(AWEFeedBackgroundPlayManager *manager) {
    @synchronized (gDKFeedNowPlayingManagers) {
        [gDKFeedNowPlayingManagers addObject:manager];
    }
    return DKFeedNowPlayingBlocked();
}

static void DKClearFeedNowPlaying(void) {
    if (!DKPrefBool(DKKeyBlockFeedNowPlaying)) return;
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKClearFeedNowPlaying(); });
        return;
    }
    NSArray<AWEFeedBackgroundPlayManager *> *managers;
    @synchronized (gDKFeedNowPlayingManagers) {
        managers = gDKFeedNowPlayingManagers.allObjects;
    }
    gDKClearingFeedNowPlaying = YES;
    for (AWEFeedBackgroundPlayManager *manager in managers) {
        if ([manager respondsToSelector:@selector(clearNowPlayingInfo)]) [manager clearNowPlayingInfo];
    }
    gDKClearingFeedNowPlaying = NO;
}

%group DKFeedNowPlayingManager
%hook AWEFeedBackgroundPlayManager
- (void)updateNowPlayingInfoPlayback { if (!DKTrackFeedManagerAndCheckBlock(self)) %orig; }
- (void)refreshNowPlayingInfo { if (!DKTrackFeedManagerAndCheckBlock(self)) %orig; }
- (void)refreshNowPlayingInfoIsForce:(BOOL)force { if (!DKTrackFeedManagerAndCheckBlock(self)) %orig; }
%end
%end

%group DKFeedNowPlayingModule
%hook AWEAwemeBackgroundPlayModule
- (void)refreshNowPlayingInfoIfNeeded { if (!DKFeedNowPlayingBlocked()) %orig; }
- (void)updateNowPlayingInfoAfterSetModel { if (!DKFeedNowPlayingBlocked()) %orig; }
- (void)updateNowPlayingInfoPlayback { if (!DKFeedNowPlayingBlocked()) %orig; }
- (BOOL)updateNowPlayingInfoWhenResiginActive { return DKFeedNowPlayingBlocked() ? NO : %orig; }
%end
%end

%ctor {
    DKSettingsRegister(DKKeyBlockFeedNowPlaying, ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(DKKeyBlockFeedNowPlaying, @"屏蔽视频占用灵动岛",
            @"信息流和详情视频不再写入灵动岛与控制中心的正在播放信息。「听抖音」与音乐播放不受影响。"),
            ^{ DKClearFeedNowPlaying(); });
    });

    gDKFeedNowPlayingManagers = [NSHashTable weakObjectsHashTable];
    Class manager = NSClassFromString(@"AWEFeedBackgroundPlayManager");
    if (class_getInstanceMethod(manager, @selector(updateNowPlayingInfoPlayback))
        && class_getInstanceMethod(manager, @selector(refreshNowPlayingInfo))
        && class_getInstanceMethod(manager, @selector(refreshNowPlayingInfoIsForce:))) %init(DKFeedNowPlayingManager);

    Class module = NSClassFromString(@"AWEAwemeBackgroundPlayModule");
    Method resign = class_getInstanceMethod(module, @selector(updateNowPlayingInfoWhenResiginActive));
    if (!resign || !class_getInstanceMethod(module, @selector(refreshNowPlayingInfoIfNeeded))
        || !class_getInstanceMethod(module, @selector(updateNowPlayingInfoAfterSetModel))
        || !class_getInstanceMethod(module, @selector(updateNowPlayingInfoPlayback))) return;
    char type[8];
    method_getReturnType(resign, type, sizeof(type));
    if (strcmp(type, @encode(BOOL)) == 0) %init(DKFeedNowPlayingModule);
}
