//
//  DKVideoGeometry.xm
//  视频几何的唯一拦截点，以及「视频全屏」这一个开关的注册处。
//
//  全项目**只剩这一个**全局 UIView 钩子（`setFrame:`）。分派按写入方的归属控制器，
//  不按视图在哪棵树里——归属是写入方自己的身份，不会串台：
//    · AWEDPlayerViewController_Merge  → 视频容器，一套规则通吃首页/朋友页/好友聊天/搜索/作品页；
//    · AWEPlayInteractionViewController → HUD，只有撑高过的表需要钉位，其余一律放行。
//
//  为什么这一处必须是写入时拦截、不能改成事后纠正：九份导出实测
//  `HUD setFrame=128~148` 对 `布局后兜底=4~11`，写入时拦截承担 95% 以上。
//  改成事后纠正等于把一百多次修正压给布局回合，必然可见跳动。
//
//  图文不在这里：它的缩放入口是 RichContentContainerViewController 的 updateShrinkState:，
//  一个精准钩子覆盖全部图文类型，见 DKVideoPageChrome.xm。
//

#import "DouyinHeaders.h"
#import "DKVideoFullscreen.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import <math.h>

// 高/宽达到此阈值才算「比例达标」，可以拉满整屏；低比例竖屏与横屏保持容器自然尺寸。
static const CGFloat kDKFullscreenMinAspect = 1.70;
static const long long kDKAwemeTypeImage = 68;
// 覆盖 @3x 像素对齐带来的亚像素漂移。
static const CGFloat kDKGeometryTolerance = 0.5;
// 关闭开关时要立刻还原的分支回调；分支不多，固定容量即可。
static void (*gRestoreHooks[4])(void);
static NSUInteger gRestoreCount = 0;

BOOL DKVideoFullscreenOn(void) {
    return DKPrefBool(DKKeyVideoFullscreen);
}

BOOL DKCommentFreezeOn(void) {
    return DKPrefBool(DKKeyCommentGlass);
}

void DKVideoFullscreenRegisterRestore(void (*restore)(void)) {
    if (!restore || gRestoreCount >= sizeof(gRestoreHooks) / sizeof(gRestoreHooks[0])) return;
    gRestoreHooks[gRestoreCount++] = restore;
}

#pragma mark - 类缓存

static Class DKMergeClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(@"AWEDPlayerViewController_Merge"); });
    return cls;
}

static Class DKPlayInteractionClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(@"AWEPlayInteractionViewController"); });
    return cls;
}

#pragma mark - 视频容器的钉位目标

// 拉满整屏只对比例达标的竖屏视频做：图文、横屏、低比例竖屏拉满会 aspect-fill 过裁。
// 它们只需保持容器自然满幅，背景延伸到底栏交给 DKVideoPageChrome.xm 的 DKSyncBackdrop。
static BOOL DKMergeCanCoverScreen(AWEDPlayerViewController_Merge *merge) {
    if (![merge isKindOfClass:DKMergeClass()]) return NO;

    AWEAwemeModel *model = merge.model;
    if (model.awemeType == kDKAwemeTypeImage) return NO;
    if (merge.hasInlandscape) return NO;
    if ([merge respondsToSelector:@selector(isInLandscapeFeedStatus)]
        && [merge isInLandscapeFeedStatus]) {
        return NO;
    }

    AWEVideoModel *video = model.video;
    double width = video.width.doubleValue;
    double height = video.height.doubleValue;
    return width <= 0.0
        || height <= 0.0
        || (height / width) >= kDKFullscreenMinAspect;
}

// 视频容器的唯一几何规则：
//   · 视频全屏 + 比例达标 → 钉到 Cell 满高，画面覆盖物理屏幕（好友聊天页比容器还高一个底栏）；
//   · 其余情况           → 钉到容器自然满幅，也就是「不许被评论区缩放平移」。
//
// 第二条对横屏同样成立：抖音展开评论区时直接改 frame 把横屏缩小上移（实测
// {{47.79,−128.07},{332.43,654.76}}，bounds 与 frame 同尺寸、不是 transform），
// 智能背景色的承载层会跟着漂移。拉满与冻结是两件事，只有拉满需要看比例。
//
// 「要不要拉满」是 model 的函数，而 model 可能晚于 frame 写入才绑定；
// 补算在 DKVideoPageChrome.xm 的 willDisplay 里。
CGRect DKVideoContainerTargetFrame(UIView *view) {
    if (!DKVideoFullscreenOn() && !DKCommentFreezeOn()) return CGRectNull;

    UIView *parent = view.superview;
    CGFloat width = CGRectGetWidth(parent.bounds);
    CGFloat height = CGRectGetHeight(parent.bounds);
    if (width <= 0.0 || height <= 0.0) return CGRectNull;

    if (DKVideoFullscreenOn()
        && DKMergeCanCoverScreen((AWEDPlayerViewController_Merge *)view.nextResponder)) {
        CGFloat full = DKFullCellHeight(view);
        if (full > height) height = full;
    }
    return CGRectMake(0.0, 0.0, width, height);
}

BOOL DKRectsClose(CGRect lhs, CGRect rhs) {
    return fabs(CGRectGetMinX(lhs) - CGRectGetMinX(rhs)) <= kDKGeometryTolerance
        && fabs(CGRectGetMinY(lhs) - CGRectGetMinY(rhs)) <= kDKGeometryTolerance
        && fabs(CGRectGetWidth(lhs) - CGRectGetWidth(rhs)) <= kDKGeometryTolerance
        && fabs(CGRectGetHeight(lhs) - CGRectGetHeight(rhs)) <= kDKGeometryTolerance;
}

// 这条钩子挂在全局 UIView 上，抖音每一次 frame 写入都会经过，守卫必须极便宜：
// 只取一次 nextResponder、最多两次类型判断，不是目标立刻放行。
// 视频表自己的撑高不走这里：它有类可挂，直接在 DKVideoFeedTable.xm 里拦。
static CGRect DKAdjustFrame(UIView *view, CGRect frame) {
    UIResponder *owner = view.nextResponder;
    if (!owner) return CGRectNull;

    if ([owner isKindOfClass:DKMergeClass()]) {
        CGRect target = DKVideoContainerTargetFrame(view);
        if (CGRectIsNull(target) || DKRectsClose(frame, target)) return CGRectNull;
        return target;
    }
    if ([owner isKindOfClass:DKPlayInteractionClass()]) {
        return DKFeedHUDAdjustFrame(view, frame);
    }
    return CGRectNull;
}

#pragma mark - 全局 UIView 钩子

%hook UIView

- (void)setFrame:(CGRect)frame {
    CGRect adjusted = DKAdjustFrame(self, frame);
    if (CGRectIsNull(adjusted)) {
        %orig;
        return;
    }
    %orig(adjusted);
}

%end

#pragma mark - 设置项注册

%ctor {
    DKSettingsRegisterItem(@"视频", ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(
            DKKeyVideoFullscreen,
            @"视频全屏",
            @"首页、朋友页、好友聊天页、搜索页、用户作品页统一铺满整屏；"
            @"其他比例视频的原生背景延伸至底栏，文案与进度条保持原位"
        );
        void (^origBlock)(void) = [item.switchChangedBlock copy];
        item.switchChangedBlock = ^{
            if (origBlock) origBlock();
            if (DKVideoFullscreenOn()) return;
            for (NSUInteger i = 0; i < gRestoreCount; i++) gRestoreHooks[i]();
        };
        return item;
    });
}
