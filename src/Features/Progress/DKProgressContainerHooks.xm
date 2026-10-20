//
//  DKProgressContainerHooks.xm
//  DYKiller
//
//  进度条容器 AWEDPlayerProgressContainerView 的统一布局入口：视频全屏清黑垫层与显示视频时长共用一处
//  layoutSubviews。新增作用于进度条容器布局的功能在这里追加一行。
//

#import "DouyinHeaders.h"
#import "DKProgressTime.h"
#import "DKVideoFullscreen.h"
#import "DKPlaybackOverlay.h"

%hook AWEDPlayerProgressContainerView

- (void)layoutSubviews {
    %orig;
    DKPlaybackOverlayLayoutProgress(self);
    DKProgressUnderlineApply(self);
    DKProgressTimeLayoutContainer(self);
}

%end
