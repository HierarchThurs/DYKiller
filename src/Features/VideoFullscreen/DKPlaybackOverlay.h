// 清屏与长按倍速的背景、原生控件和设置刷新入口。
#import <UIKit/UIKit.h>

@interface AFDPureModePageContainerViewController : UIViewController
- (CGRect)getPureModeContainerFrame;
@end

@interface AFDFastSpeedView : UIView
@property (nonatomic, strong) UIView *bottomBlackView;
@property (nonatomic, strong) UIView *bottomBackGroundView;
@property (nonatomic, strong) UIView *foldableBottomTextBackgroundView;
@property (nonatomic, strong) UILabel *bottomTextView;
@property (nonatomic, strong) UILabel *bottomSpeedTextView;
@property (nonatomic, strong) UILabel *drageToPureModeTextView;
@property (nonatomic, strong) UIView *bottomArrowView;
@property (nonatomic, strong) UIView *downLockArrowView;
@end

@interface AFDRoundRectangleBoxView : UIView
@property (nonatomic, strong) UIVisualEffectView *blurView;
@end

@interface AFDRoundRectangleButton : UIButton
@end

@interface AWEStoryProgressContainerView : UIView
@end

#ifdef __cplusplus
extern "C" {
#endif

BOOL DKPlaybackOverlayActive(void);
BOOL DKPlaybackOverlayIsPureControl(UIView *view);
/// 按清屏页保存的原生底部预留，将进度条或剧集分段条连同读数与触控范围整体上移；离开作用域时恢复。
void DKPlaybackOverlayLayoutProgress(UIView *container);
void DKPlaybackOverlayRefresh(void);
void DKPlaybackOverlayGlassRefresh(void);

#ifdef __cplusplus
}
#endif
