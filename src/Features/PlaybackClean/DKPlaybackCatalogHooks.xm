// 作品开始展示时同步目录：晚到的行由既有元素栈布局入口补登。
// 滑回已构建的作品时元素只重写栏目底色、栈不重排，栏目背景透明在这里重新应用。
#import "DKPlaybackCatalog.h"
#import "DKRelatedBarBackground.h"
#import "DouyinHeaders.h"

%hook AWEPlayInteractionViewController
- (void)setIsDisplaying:(BOOL)displaying {
    %orig;
    if (!displaying) return;
    DKPlaybackCatalogRecordController(self);
    DKRelatedBarBackgroundApplyStack(self.bottomContainerView);
}
%end
