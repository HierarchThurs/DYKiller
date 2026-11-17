//
//  DKListenGlassPopup.xm
//  DYKiller
//
//  听抖音倍速与定时弹层：内容区换成悬浮玻璃卡片。弹层是一次性视图，开关只能在弹层关闭时改动，不做就地还原。
//  卡片下面是密集的控制区，清透材质会让文字和控件叠在一起，材质固定为模糊玻璃。
//

#import "DKListenGlass.h"
#import "DouyinHeaders.h"

static const CGFloat kDKListenPopupRadius = 28.0;
static const CGFloat kDKListenPopupEdge = 8.0;

%group DKListenGlassPopupHooks

%hook AWEListenFeedValueAdjustPopupView

- (void)layoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) {
        if (!DKListenGlassOn()) return;
        UIView *content = self.contentView;
        if (!content) return;
        DKChatGlassStore *store = [DKChatGlassStore storeForOwner:self create:YES];
        if (store.syncing) return;
        [store beginWithClear:NO style:UIUserInterfaceStyleDark];
        [store clearBackingOfView:content];
        // 原生用形状遮罩裁出顶部圆角，玻璃卡片不需要，而且上沿要越出内容区留出边距。
        content.layer.mask = nil;
        [store pinGlassFor:content in:content shape:DKChatGlassShapeCard radius:kDKListenPopupRadius interactive:NO
               constraints:^NSArray<NSLayoutConstraint *> *(UIView *glass) {
            return @[
                [glass.topAnchor constraintEqualToAnchor:content.topAnchor constant:-kDKListenPopupEdge],
                [glass.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:kDKListenPopupEdge],
                [glass.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-kDKListenPopupEdge],
                [glass.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-kDKListenPopupEdge],
            ];
        }];
        [store end];
    }
}

%end

%end

%ctor {
    if (DKGlassOSAvailable()) %init(DKListenGlassPopupHooks);
}
