//
//  DKHideMusicInfo.xm
//  功能：播放页精简 —— 文案下方「去汽水听」音乐信息栏的移除闸门。
//
//  实现：
//   - Hook AWEPlayInteractionViewController 的 hideMusicInfo getter。
//   - 「去汽水听」为移除时返回 YES，令抖音走自身隐藏逻辑；整行的隐藏 / 移除另由播放页精简处理。
//   - 设置项登记在 DKPlaybackCleanSettings.xm。
//

#import "DouyinHeaders.h"
#import "DKUtils.h"
#import "DKKeys.h"

%hook AWEPlayInteractionViewController

- (BOOL)hideMusicInfo {
    if (DKPrefDisplayMode(DKKeyPlaybackMusicInfoMode) == DKDisplayModeRemove) return YES;
    return %orig;
}

%end
