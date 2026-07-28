//
//  DKDetailVideoFullscreen.xm
//  聊天与搜索详情页 —— 竖屏视频画面填满整屏，HUD 原地不动。
//
//  仅拦截 AWEDPlayerViewController_Merge.view 的 frame 写入。视频子树随
//  Merge 容器自动伸展，HUD 位于兄弟层，不参与尺寸修改。
//

#import "DouyinHeaders.h"
#import "DKUtils.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import <objc/runtime.h>
#import <math.h>

typedef NS_ENUM(NSUInteger, DKVideoFullscreenContext) {
    DKVideoFullscreenContextNone = 0,
    DKVideoFullscreenContextChat,
    DKVideoFullscreenContextSearch,
};

// 高/宽达到此阈值才进入全屏处理。低比例竖屏与横屏保持原布局。
static const CGFloat kDKFullscreenMinAspect = 1.70;
static const long long kDKAwemeTypeImage = 68;

static Class DKMergeClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cls = NSClassFromString(@"AWEDPlayerViewController_Merge");
    });
    return cls;
}

static Class DKInteractionClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cls = NSClassFromString(@"AWEPlayInteractionViewController");
    });
    return cls;
}

static Class DKDetailTableClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cls = NSClassFromString(@"AWEAwemeDetailTableViewController");
    });
    return cls;
}

static Class DKSearchViewControllerClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cls = NSClassFromString(@"AWESearchViewController");
    });
    return cls;
}

static BOOL DKIsSearchReferString(NSString *referString) {
    if (![referString isKindOfClass:[NSString class]] || referString.length == 0) {
        return NO;
    }

    static NSSet<NSString *> *referStrings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        referStrings = [NSSet setWithArray:@[
            @"general_search",
            @"search_result",
            @"search_ecommerce",
            @"general_search_scan",
        ]];
    });
    return [referStrings containsObject:referString];
}

static AWEDPlayerViewController_Merge *DKMergeForView(UIView *view) {
    Class mergeCls = DKMergeClass();
    if (!mergeCls) return nil;

    UIResponder *responder = view.nextResponder;
    for (NSUInteger i = 0; responder && i < 40; i++) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            UIViewController *controller = (UIViewController *)responder;
            for (NSUInteger j = 0; controller && j < 12; j++) {
                if ([controller isKindOfClass:mergeCls]) {
                    return (AWEDPlayerViewController_Merge *)controller;
                }
                controller = controller.parentViewController;
            }
        }
        responder = responder.nextResponder;
    }
    return nil;
}

static AWEPlayInteractionViewController *DKSiblingInteractionController(
    AWEDPlayerViewController_Merge *merge
) {
    Class interactionCls = DKInteractionClass();
    UIViewController *parent = merge.parentViewController;
    if (!interactionCls || !parent) return nil;

    for (UIViewController *child in parent.childViewControllers) {
        if ([child isKindOfClass:interactionCls]) {
            return (AWEPlayInteractionViewController *)child;
        }
    }
    return nil;
}

static AWEAwemeDetailTableViewController *DKDetailControllerForMerge(
    AWEDPlayerViewController_Merge *merge
) {
    Class detailCls = DKDetailTableClass();
    UIViewController *controller = merge.parentViewController;
    for (NSUInteger i = 0; detailCls && controller && i < 12; i++) {
        if ([controller isKindOfClass:detailCls]) {
            return (AWEAwemeDetailTableViewController *)controller;
        }
        controller = controller.parentViewController;
    }
    return nil;
}

static BOOL DKDetailNavigationComesFromSearch(
    AWEAwemeDetailTableViewController *detail
) {
    Class searchCls = DKSearchViewControllerClass();
    NSArray<UIViewController *> *stack = detail.navigationController.viewControllers;
    NSUInteger index = [stack indexOfObjectIdenticalTo:detail];
    if (!searchCls || index == NSNotFound || index == 0) return NO;
    return [stack[index - 1] isKindOfClass:searchCls];
}

static BOOL DKMergeIsInSearchDetail(AWEDPlayerViewController_Merge *merge) {
    if (DKIsSearchReferString(merge.referString)) return YES;

    AWEPlayInteractionViewController *interaction =
        DKSiblingInteractionController(merge);
    if (DKIsSearchReferString(interaction.referString)) return YES;

    AWEAwemeDetailTableViewController *detail = DKDetailControllerForMerge(merge);
    if (!detail) return NO;
    if (DKIsSearchReferString(detail.referString)) return YES;
    if ([detail respondsToSelector:@selector(realReferString)]
        && DKIsSearchReferString([detail realReferString])) {
        return YES;
    }

    // referString 尚未传递到子控制器时，以紧邻的搜索页导航来源兜底。
    return DKDetailNavigationComesFromSearch(detail);
}

static DKVideoFullscreenContext DKContextForMerge(
    AWEDPlayerViewController_Merge *merge
) {
    if (!merge) return DKVideoFullscreenContextNone;
    if (DKVCInIMDetail(merge)) return DKVideoFullscreenContextChat;
    if (DKMergeIsInSearchDetail(merge)) return DKVideoFullscreenContextSearch;
    return DKVideoFullscreenContextNone;
}

static BOOL DKContextIsEnabled(DKVideoFullscreenContext context) {
    switch (context) {
        case DKVideoFullscreenContextChat:
            return DKPrefBool(DKKeyChatVideoFullscreen);
        case DKVideoFullscreenContextSearch:
            return DKPrefBool(DKKeySearchVideoFullscreen);
        case DKVideoFullscreenContextNone:
            return NO;
    }
    return NO;
}

static BOOL DKMergeHasEligibleVideo(AWEDPlayerViewController_Merge *merge) {
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

static BOOL DKMergeIsFullscreenTarget(AWEDPlayerViewController_Merge *merge) {
    DKVideoFullscreenContext context = DKContextForMerge(merge);
    return DKContextIsEnabled(context) && DKMergeHasEligibleVideo(merge);
}

#pragma mark - 视频容器

%hook UIView

- (void)setFrame:(CGRect)frame {
    Class mergeCls = DKMergeClass();
    UIResponder *nextResponder = self.nextResponder;
    if (!mergeCls || ![nextResponder isKindOfClass:mergeCls]) {
        %orig;
        return;
    }

    AWEDPlayerViewController_Merge *merge =
        (AWEDPlayerViewController_Merge *)nextResponder;
    if (!DKMergeIsFullscreenTarget(merge)) {
        %orig;
        return;
    }

    CGFloat fullHeight = DKFullCellHeight(self);
    CGFloat width = self.superview
        ? CGRectGetWidth(self.superview.bounds)
        : CGRectGetWidth(frame);
    if (fullHeight <= 0.0 || width <= 0.0) {
        %orig;
        return;
    }

    %orig(CGRectMake(0.0, 0.0, width, fullHeight));
}

%end

#pragma mark - 评论区开合

%hook AWEDPlayerViewController_Merge

- (void)videoDidShrink {
    if (!DKMergeIsFullscreenTarget(self)) {
        %orig;
        return;
    }

    UIView *gradient = self.gradientBackgroundView;
    if (gradient && gradient.alpha < 1.0) {
        gradient.alpha = 1.0;
    }
}

%end

#pragma mark - 评论态 HUD 顶部遮罩

static BOOL DKColorIsOpaqueBlack(UIColor *color) {
    if (!color) return NO;

    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    CGFloat alpha = 0.0;
    if ([color getRed:&red green:&green blue:&blue alpha:&alpha]) {
        return red <= 0.02
            && green <= 0.02
            && blue <= 0.02
            && alpha >= 0.98;
    }

    CGFloat white = 0.0;
    if ([color getWhite:&white alpha:&alpha]) {
        return white <= 0.02 && alpha >= 0.98;
    }
    return NO;
}

static UIView *DKFindHUDStatusBarCover(UIView *hudView) {
    CGFloat safeTop = hudView.safeAreaInsets.top;
    CGFloat width = CGRectGetWidth(hudView.bounds);
    if (safeTop <= 1.0 || width <= 0.0) return nil;

    for (UIView *view in hudView.subviews) {
        if (object_getClass(view) != [UIView class]) continue;
        if (!view.opaque || view.hidden) continue;

        CGRect frame = view.frame;
        if (fabs(CGRectGetMinX(frame)) > 1.0
            || fabs(CGRectGetMinY(frame)) > 1.0
            || fabs(CGRectGetWidth(frame) - width) > 1.0
            || fabs(CGRectGetHeight(frame) - safeTop) > 2.0) {
            continue;
        }
        if (DKColorIsOpaqueBlack(view.backgroundColor)) return view;
    }
    return nil;
}

static char kDKStatusBarCoverHiddenKey;

static void DKUpdateHUDStatusBarCover(
    AWEPlayInteractionViewController *interaction
) {
    AWEDPlayerViewController_Merge *merge = nil;
    Class mergeCls = DKMergeClass();
    UIViewController *parent = interaction.parentViewController;
    for (UIViewController *child in parent.childViewControllers) {
        if (mergeCls && [child isKindOfClass:mergeCls]) {
            merge = (AWEDPlayerViewController_Merge *)child;
            break;
        }
    }

    if (DKMergeIsFullscreenTarget(merge)) {
        UIView *cover = DKFindHUDStatusBarCover(interaction.view);
        if (cover) {
            cover.hidden = YES;
            objc_setAssociatedObject(
                cover,
                &kDKStatusBarCoverHiddenKey,
                @YES,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC
            );
        }
        return;
    }

    for (UIView *view in interaction.view.subviews) {
        if (!objc_getAssociatedObject(view, &kDKStatusBarCoverHiddenKey)) continue;
        view.hidden = NO;
        objc_setAssociatedObject(
            view,
            &kDKStatusBarCoverHiddenKey,
            nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }
}

%hook AWEPlayInteractionViewController

- (void)viewDidLayoutSubviews {
    %orig;
    DKUpdateHUDStatusBarCover(self);
}

%end

#pragma mark - 底部压暗渐变

static char kDKGradientTransformKey;

%hook AWEGradientView

- (void)layoutSubviews {
    %orig;

    BOOL applied =
        objc_getAssociatedObject(self, &kDKGradientTransformKey) != nil;
    AWEDPlayerViewController_Merge *merge = DKMergeForView(self);

    if (DKMergeIsFullscreenTarget(merge)) {
        UIView *container = self.superview;
        CGFloat height = CGRectGetHeight(self.bounds);
        if (container && height > 0.0) {
            CGFloat top = self.center.y - height / 2.0;
            CGFloat containerHeight = CGRectGetHeight(container.bounds);
            if (top > 1.0 && top + height < containerHeight - 1.0) {
                CGFloat scaleY = (containerHeight - top) / height;
                CGAffineTransform transform = CGAffineTransformMake(
                    1.0,
                    0.0,
                    0.0,
                    scaleY,
                    0.0,
                    (height / 2.0) * (scaleY - 1.0)
                );
                if (!CGAffineTransformEqualToTransform(self.transform, transform)) {
                    self.transform = transform;
                }
                if (!applied) {
                    objc_setAssociatedObject(
                        self,
                        &kDKGradientTransformKey,
                        @YES,
                        OBJC_ASSOCIATION_RETAIN_NONATOMIC
                    );
                }
                return;
            }
        }
    }

    if (applied) {
        self.transform = CGAffineTransformIdentity;
        objc_setAssociatedObject(
            self,
            &kDKGradientTransformKey,
            nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }
}

%end

#pragma mark - 设置项注册

%ctor {
    DKSettingsRegisterItem(@"聊天页", ^AWESettingItemModel *{
        return DKMakeSwitch(
            DKKeyChatVideoFullscreen,
            @"聊天页视频全屏",
            @"竖屏视频画面填满整屏，HUD 不变"
        );
    });

    DKSettingsRegisterItem(@"搜索页", ^AWESettingItemModel *{
        return DKMakeSwitch(
            DKKeySearchVideoFullscreen,
            @"搜索页视频全屏",
            @"搜索结果中的竖屏视频画面填满整屏，HUD 不变"
        );
    });
}
