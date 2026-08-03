//
//  DKGlassFlexView.h
//  带触摸源重定向的液态玻璃视图。
//
//  玻璃垫在业务内容下方且不参与 hit-test；通过 UIKit 的 flex 触摸源方法，
//  将 interactive 玻璃的反馈区域指向真正接收触摸的槽位及其子树。
//

#ifndef DKGlassFlexView_h
#define DKGlassFlexView_h

#import <UIKit/UIKit.h>

@interface DKGlassFlexView : UIVisualEffectView

/// 触摸源。落在它及其子树上的触摸会驱动本玻璃的 flex 动效；为 nil 时退回默认行为。
@property (nonatomic, weak) UIView *flexSourceView;

@end

#ifdef __cplusplus
extern "C" {
#endif

/// UIKit 最终解析到的 flex 触摸源，供调试探针核对重写有没有被读到。
UIView *DKGlassFlexResolvedSource(UIView *glass);

/// 该视图上是否已挂上系统的 flex 交互（interactive 有没有真的生效）。
BOOL DKGlassFlexInstalled(UIView *glass);

#ifdef __cplusplus
}
#endif

#endif /* DKGlassFlexView_h */
