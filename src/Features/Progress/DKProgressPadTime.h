#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// iPad 原生左右约束的时长让位；未采用此约束布局时返回 NO。
BOOL DKProgressPadTimeSync(UIView *slider, CGFloat inset, BOOL wakeup);

#ifdef __cplusplus
}
#endif
