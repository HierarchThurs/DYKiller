//
//  DKTopChannelCapsule.h
//  DYKiller
//
//  顶栏频道胶囊：胶囊底板与玻璃选中块挂在原生频道条内，频道、滚动与切换全部沿用原生；
//  本类负责选中块跟随与按压、长按拖选两个手势。
//

#ifndef DKTopChannelCapsule_h
#define DKTopChannelCapsule_h

#import <UIKit/UIKit.h>

@class AWEFeedMultiTabSegmentedControl;

/// 顶栏玻璃的材质：Clear / Regular 两档，亮度按频道文字的明暗走（文字由抖音按页面底色决定）。
typedef struct {
    BOOL clear;
    BOOL lightContent;  // 文字为深色的浅色页面
} DKTopBarGlassMaterial;

#ifdef __cplusplus
extern "C" {
#endif

/// 写入材质；tint 为 nil 时取默认染色。材质没变不重写，明暗切换带过渡。
API_AVAILABLE(ios(26.0))
void DKTopBarGlassApplyMaterial(UIVisualEffectView *glass, DKTopBarGlassMaterial material, UIColor *tint,
                                BOOL interactive);

/// 建立一块胶囊形状的玻璃；touchSource 是驱动它按压形变的业务视图，为 nil 时不响应按压。
API_AVAILABLE(ios(26.0))
UIVisualEffectView *DKTopBarGlassMakeView(UIView *touchSource);

/// 「返回推荐」箭头的点击范围：换上玻璃圆钮后按圆钮判定；handled 为 NO 时箭头未接管，按原生判定。
BOOL DKTopChannelArrowContainsPoint(UIView *arrow, CGPoint point, BOOL *handled);

#ifdef __cplusplus
}
#endif

API_AVAILABLE(ios(26.0))
@interface DKTopChannelCapsule : NSObject

- (instancetype)initWithControl:(AWEFeedMultiTabSegmentedControl *)control;

/// 按胶囊 frame（频道条坐标）与选中块高度摆放，并把选中块对回当前选中频道。
- (void)layoutCapsuleFrame:(CGRect)capsuleFrame pillHeight:(CGFloat)pillHeight;

- (void)applyMaterial:(DKTopBarGlassMaterial)material;

/// 原生改了选中频道：选中块以弹簧动画移过去。
- (void)selectionDidChange;

/// 分页滑动时原生移动了选中线：选中块逐帧跟随。
- (void)selectionLineDidMove;

/// 频道条滚动：选中块留在原频道上；长按拖选中同步更新手指所指的频道。
- (void)channelsDidScroll;

/// 频道条开始被拖动滚动：撤销按压态，选中块回到选中频道。
- (void)channelsWillBeginDragging;

/// 还原：移除玻璃与手势，恢复原生选中线。
- (void)invalidate;

/// 是否正在长按拖选；期间拦下原生长按打开频道排序面板。
@property (class, nonatomic, readonly) BOOL dragging;

@property (nonatomic, readonly) UIView *pillView;

@end

#endif /* DKTopChannelCapsule_h */
