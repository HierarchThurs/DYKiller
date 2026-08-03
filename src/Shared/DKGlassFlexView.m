//
//  DKGlassFlexView.m
//

#import "DKGlassFlexView.h"

// UIView 的内部方法：flex 交互问宿主「哪个视图上的触摸算我的」。
@interface UIView (DKFlexPrivate)
- (UIView *)_flexInteractionGestureView;
@end

@implementation DKGlassFlexView

- (UIView *)_flexInteractionGestureView {
    UIView *source = self.flexSourceView;
    // 源已销毁或已离开层级时退回默认，避免把触摸判给一个不在屏上的视图。
    if (source && source.window) return source;
    return [super _flexInteractionGestureView];
}

@end

UIView *DKGlassFlexResolvedSource(UIView *glass) {
    if (![glass respondsToSelector:@selector(_flexInteractionGestureView)]) return nil;
    return [glass _flexInteractionGestureView];
}

BOOL DKGlassFlexInstalled(UIView *glass) {
    for (id<UIInteraction> interaction in glass.interactions) {
        if ([NSStringFromClass([interaction class]) containsString:@"FlexInteraction"]) return YES;
    }
    return NO;
}
