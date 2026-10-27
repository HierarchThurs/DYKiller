//
//  DKElementStackHooks.xm
//  DYKiller
//
//  播放交互层元素栈的统一布局入口：右侧互动区、左侧昵称文案、长按复制与播放页精简共用一处 layoutSubviews，
//  各自判定是不是自己的栈。新增作用于元素栈的功能在这里追加一行。
//  行内新增子视图时让所在栈重排一次，入口按行的新内容重新应用。
//

#import "DouyinHeaders.h"
#import "DKInfoAppearance.h"
#import "DKInfoLongPressCopy.h"
#import "DKInteractionAppearance.h"
#import "DKPlaybackClean.h"
#import "DKPublishInfo.h"

%hook AWEElementStackView

- (void)layoutSubviews {
    // 行的显隐在布局前落定，栈按最终的可见行排布一次。
    DKPlaybackCleanApplyStack(self);
    %orig;
    DKInteractionAppearanceApplyStack(self);
    DKInfoAppearanceApplyStack(self);
    DKInfoLongPressCopyApplyStack(self);
    DKPublishInfoApplyStack(self);
}

%end

%hook AWEBaseElementView

// 元素在已有行内换内容时（如解除静音后「取消静音」换成音乐组件）行尺寸不变，抖音不重排栈。
- (void)didAddSubview:(UIView *)subview {
    %orig;
    UIView *stack = self.superview;
    if ([stack isKindOfClass:%c(AWEElementStackView)]) [stack setNeedsLayout];
}

%end
