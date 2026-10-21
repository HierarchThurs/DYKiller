//
//  DKProgressContainerHooks.xm
//  DYKiller
//
//  进度条容器 AWEDPlayerProgressContainerView 的统一布局入口：播放控件定位与显示视频时长共用一处
//  layoutSubviews。新增作用于进度条容器布局的功能在这里追加一行。
//

#import "DouyinHeaders.h"
#import "DKProgressTime.h"
#import "DKPlaybackOverlay.h"

%hook AWEDPlayerProgressContainerView

- (void)layoutSubviews {
    %orig;
    DKPlaybackOverlayLayoutProgress(self);
    DKProgressTimeLayoutContainer(self);
}

%end
