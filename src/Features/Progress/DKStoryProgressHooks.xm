//
//  DKStoryProgressHooks.xm
//  DYKiller
//
//  图片指示器 / 剧集分段条 AWEStoryProgressContainerView 的统一布局入口：清屏页让位与图片指示器上移共用。
//  两者作用于不同页面里的实例（清屏页 / 播放交互层），同一视图只由一方叠 transform。
//

#import "DouyinHeaders.h"
#import "DKPlaybackOverlay.h"
#import "DKProgressOffset.h"

%hook AWEStoryProgressContainerView

- (void)layoutSubviews {
    %orig;
    DKPlaybackOverlayLayoutProgress(self);
    DKStoryIndicatorLayout(self);
}

// 容器随 cell 平移时不重新布局，挂入窗口时也同步一次。
- (void)didMoveToWindow {
    %orig;
    DKPlaybackOverlayLayoutProgress(self);
    DKStoryIndicatorLayout(self);
}

%end
