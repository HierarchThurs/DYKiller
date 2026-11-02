//
//  DKTopBarGlassMetrics.h
//  DYKiller
//
//  顶栏液态玻璃的几何：圆钮固定在容器两侧，胶囊按频道内容收缩并在容器内居中。
//

#ifndef DKTopBarGlassMetrics_h
#define DKTopBarGlassMetrics_h

#import <CoreGraphics/CoreGraphics.h>

/// 原生槽位与胶囊的基准高度；圆钮内图标按 高度 / 基准 缩放。
static const CGFloat kDKTopBarGlassBaseHeight = 44.0;
/// 频道条与胶囊两端的距离，也是选中块与胶囊上下的距离。
static const CGFloat kDKTopBarGlassCapsuleInset = 4.0;

typedef struct {
    CGFloat containerWidth;
    CGFloat contentWidth;    // 频道内容的自然宽度
    CGFloat heightScale;     // 1 为基准高度
    CGFloat lengthScale;     // 1 为按内容收缩后的长度，超过 1 不再变长
} DKTopBarGlassInput;

typedef struct {
    CGFloat height;          // 圆钮直径与胶囊高度
    CGFloat capsuleX;        // 胶囊左边（容器坐标）
    CGFloat capsuleWidth;
    CGFloat slotWidth;       // 两侧槽位宽度：频道条从左槽位右缘排到右槽位左缘
    CGFloat leftCenterX;     // 左侧圆钮中心（左侧槽位坐标）
    CGFloat rightCenterX;    // 右侧圆钮中心（右侧槽位坐标）
} DKTopBarGlassMetrics;

#ifdef __cplusplus
extern "C" {
#endif

DKTopBarGlassMetrics DKTopBarGlassComputeMetrics(DKTopBarGlassInput input);

#ifdef __cplusplus
}
#endif

#endif /* DKTopBarGlassMetrics_h */
