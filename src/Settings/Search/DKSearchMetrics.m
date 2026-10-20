// 搜索控件与结果面板按页面可用区域计算几何。
#import "DKSearchViews.h"
static const CGFloat kDKSearchDiameterRatio = 0.145;
static const CGFloat kDKSearchDiameterMin = 52.0;
static const CGFloat kDKSearchDiameterMax = 76.0;
static const CGFloat kDKSearchEdgeRatio = 0.045;
static const CGFloat kDKSearchEdgeMin = 16.0;
static const CGFloat kDKSearchEdgeMax = 28.0;
static const CGFloat kDKSearchGapRatio = 0.03;
static const CGFloat kDKSearchGapMin = 10.0;
static const CGFloat kDKSearchGapMax = 16.0;
static const CGFloat kDKSearchPanelRadiusRatio = 0.36;
static const CGFloat kDKSearchPanelRadiusMin = 16.0;
static const CGFloat kDKSearchPanelRadiusMax = 26.0;
static const CGFloat kDKSearchPanelTop = 8.0;
static const CGFloat kDKSearchPanelGap = 12.0;
static const CGFloat kDKSearchPanelMinHeight = 44.0;
static NSString *const kDKSearchNavBarClass = @"AWENavigationBar";
static CGFloat DKSearchClamp(CGFloat value, CGFloat low, CGFloat high) {
    return MIN(MAX(value, low), high);
}

// 页面实际可用区域：安全区、页面内的导航栏底边、页面内仍可见的底栏都算进来。
UIEdgeInsets DKSearchInsetsForHost(UIView *host) {
    UIEdgeInsets insets = host.safeAreaInsets;
    if (!host) return insets;
    UIWindow *window = host.window;
    CGFloat top = insets.top;
    CGFloat bottom = MAX(insets.bottom, window ? window.safeAreaInsets.bottom : 0.0);
    CGFloat barTop = CGFLOAT_MAX;
    for (UIView *subview in host.subviews) {
        if ([NSStringFromClass(subview.class) isEqualToString:kDKSearchNavBarClass]) {
            CGRect rect = [subview convertRect:subview.bounds toView:host];
            top = MAX(top, CGRectGetMaxY(rect));
            continue;
        }
        if (![subview isKindOfClass:UITabBar.class]) continue;
        if (subview.isHidden || subview.alpha < 0.01) continue;
        CGRect rect = [subview convertRect:subview.bounds toView:host];
        if (CGRectGetHeight(rect) < 1.0) continue;
        barTop = MIN(barTop, CGRectGetMinY(rect));
    }
    if (barTop < CGFLOAT_MAX) bottom = MAX(bottom, CGRectGetHeight(host.bounds) - barTop);
    return UIEdgeInsetsMake(top, insets.left, bottom, insets.right);
}

// keyboardTop <= 0 表示键盘不在屏上，按可用区域底边算。
DKSearchMetrics DKSearchMetricsMake(CGSize size, UIEdgeInsets insets, CGFloat keyboardTop) {
    DKSearchMetrics metrics = {0};
    CGFloat width = size.width, height = size.height;
    if (width < 1.0 || height < 1.0) return metrics;
    metrics.diameter = round(DKSearchClamp(MIN(width, height) * kDKSearchDiameterRatio,
                                           kDKSearchDiameterMin, kDKSearchDiameterMax));
    metrics.edge = round(DKSearchClamp(width * kDKSearchEdgeRatio, kDKSearchEdgeMin, kDKSearchEdgeMax));
    metrics.gap = round(DKSearchClamp(width * kDKSearchGapRatio, kDKSearchGapMin, kDKSearchGapMax));
    metrics.radius = round(DKSearchClamp(metrics.diameter * kDKSearchPanelRadiusRatio,
                                         kDKSearchPanelRadiusMin, kDKSearchPanelRadiusMax));

    metrics.fabFrame = CGRectMake(width - metrics.edge - metrics.diameter,
                                  height - insets.bottom - metrics.edge - metrics.diameter,
                                  metrics.diameter, metrics.diameter);

    CGFloat keyboard = (keyboardTop > 0.0 && keyboardTop < height - 1.0) ? keyboardTop : height - insets.bottom;
    CGFloat rowTop = keyboard - metrics.gap - metrics.diameter;
    metrics.closeFrame = CGRectMake(width - metrics.edge - metrics.diameter, rowTop,
                                    metrics.diameter, metrics.diameter);
    CGFloat capsuleWidth = MAX(width - 2.0 * metrics.edge - metrics.diameter - metrics.gap, metrics.diameter);
    metrics.capsuleFrame = CGRectMake(metrics.edge, rowTop, capsuleWidth, metrics.diameter);

    CGFloat panelTop = insets.top + kDKSearchPanelTop;
    metrics.resultsFrame = CGRectMake(metrics.edge, panelTop, width - 2.0 * metrics.edge,
                                      MAX(rowTop - kDKSearchPanelGap - panelTop, 0.0));
    return metrics;
}

