//
//  DKTopBarGlassMetrics.m
//  DYKiller
//

#import "DKTopBarGlassMetrics.h"

#import <math.h>

// 圆钮距屏幕两侧的距离。
static const CGFloat kDKTopBarGlassMargin = 12.0;
// 胶囊撑满时与圆钮的距离。
static const CGFloat kDKTopBarGlassCapsuleGap = 8.0;
static const CGFloat kDKTopBarGlassMinHeight = 24.0;

DKTopBarGlassMetrics DKTopBarGlassComputeMetrics(DKTopBarGlassInput input) {
    const CGFloat inset = kDKTopBarGlassCapsuleInset;
    const CGFloat width = input.containerWidth;
    const CGFloat height = fmax(kDKTopBarGlassMinHeight, kDKTopBarGlassBaseHeight * input.heightScale);

    // 两侧始终按圆钮占位，入口隐藏或移除都不影响胶囊。
    const CGFloat available = fmax(0.0, width - (kDKTopBarGlassMargin + height + kDKTopBarGlassCapsuleGap) * 2.0);
    const CGFloat natural = fmin(input.contentWidth + inset * 2.0, available);
    const CGFloat capsuleWidth = fmin(available, fmax(natural * fmin(1.0, input.lengthScale), height * 2.0));
    const CGFloat capsuleX = (width - capsuleWidth) / 2.0;

    DKTopBarGlassMetrics metrics;
    metrics.height = height;
    metrics.capsuleX = capsuleX;
    metrics.capsuleWidth = capsuleWidth;
    metrics.slotWidth = capsuleX + inset;
    metrics.leftCenterX = kDKTopBarGlassMargin + height / 2.0;
    metrics.rightCenterX = metrics.slotWidth - kDKTopBarGlassMargin - height / 2.0;
    return metrics;
}
