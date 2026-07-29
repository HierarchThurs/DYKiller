//
//  DKProgressUnderline.xm
//  清除进度条底边压着的那条纯黑细垫层。视频撑满后它会横在视频与底栏之间形成割裂。
//
//  全项目唯一一处 AWEDPlayerProgressContainerView 的 hook：详情页全屏与首页/朋友页全屏
//  面对的是同一条黑边、同一套识别与还原逻辑，只是作用域来源不同，故合并在此。
//

#import "DKFeedVideoFullscreen.h"
#import "DouyinHeaders.h"
#import "DKUtils.h"
#import <objc/runtime.h>
#import <math.h>

// 覆盖 @3x 像素对齐与进度条收放时的亚像素漂移。
static const CGFloat kDKUnderlineTolerance = 0.5;

static char kDKUnderlineColorKey;
static char kDKUnderlineOpaqueKey;

// 签名：容器直属 + 普通 UIView + 满宽 + 极薄 + 紧贴容器底边 + 有背景色。
// 不用屏幕坐标做锚点（随页面 HUD 高度而变），但「贴容器底边」是稳定的相对关系：
// 实测该层 y 198.1 + 高 2 = 200.1，容器高 200，正好贴底；而进度条轨道既不满宽也不贴底。
// 不再限定纯黑——全屏态下任何一条贴着容器底边的满宽薄垫层都是多余的。
static BOOL DKIsUnderlineView(UIView *view, UIView *container) {
    if (object_getClass(view) != [UIView class]) return NO;
    if (!view.backgroundColor) return NO;

    CGRect frame = view.frame;
    CGFloat height = CGRectGetHeight(frame);
    return height > 0.0
        && height <= 2.0 + kDKUnderlineTolerance
        && fabs(CGRectGetMinX(frame)) <= kDKUnderlineTolerance
        && fabs(CGRectGetWidth(frame) - CGRectGetWidth(container.bounds)) <= kDKUnderlineTolerance
        && CGRectGetMaxY(frame) >= CGRectGetHeight(container.bounds) - kDKUnderlineTolerance;
}

static void DKClearUnderline(UIView *view) {
    if (!objc_getAssociatedObject(view, &kDKUnderlineColorKey)) {
        objc_setAssociatedObject(view, &kDKUnderlineColorKey, view.backgroundColor,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &kDKUnderlineOpaqueKey, @(view.opaque),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (![view.backgroundColor isEqual:UIColor.clearColor]) {
        view.backgroundColor = UIColor.clearColor;
    }
    if (view.opaque) view.opaque = NO;
}

static void DKRestoreUnderline(UIView *view) {
    UIColor *color = objc_getAssociatedObject(view, &kDKUnderlineColorKey);
    if (!color) return;

    view.backgroundColor = color;
    view.opaque = [objc_getAssociatedObject(view, &kDKUnderlineOpaqueKey) boolValue];
    objc_setAssociatedObject(view, &kDKUnderlineColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kDKUnderlineOpaqueKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook AWEDPlayerProgressContainerView

- (void)layoutSubviews {
    %orig;

    BOOL enabled = DKDetailPageFullscreenOn(DKDetailPageForResponder(self))
        || DKFeedFullscreenActiveForView(self);

    for (UIView *view in self.subviews) {
        // 已接管的视图只按开关决定去留：进度条收起时签名会漂移，据此还原会让黑边重现。
        if (objc_getAssociatedObject(view, &kDKUnderlineColorKey)) {
            enabled ? DKClearUnderline(view) : DKRestoreUnderline(view);
        } else if (enabled && DKIsUnderlineView(view, self)) {
            DKClearUnderline(view);
        }
    }
}

%end
