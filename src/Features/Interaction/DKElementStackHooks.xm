//
//  DKElementStackHooks.xm
//  DYKiller
//
//  播放交互层元素栈的统一布局入口：右侧互动区与左侧昵称文案共用一处 layoutSubviews，
//  各自判定是不是自己的栈。新增作用于元素栈的外观功能在这里追加一行。
//

#import "DouyinHeaders.h"
#import "DKInfoAppearance.h"
#import "DKInteractionAppearance.h"

%hook AWEElementStackView

- (void)layoutSubviews {
    %orig;
    DKInteractionAppearanceApplyStack(self);
    DKInfoAppearanceApplyStack(self);
}

%end
