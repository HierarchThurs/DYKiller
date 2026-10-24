//
//  DKTabBarBackdrop.xm
//  功能：底栏背景让位与底栏页面底部沉浸。
//   1. 视频全屏开启、悬浮玻璃底栏关闭时，抖音自绘底栏的背景在所有底栏页面透明，按钮与外观覆盖层保持不透明。
//   2. 悬浮玻璃底栏或视频全屏任一开启时，底栏商城页（AWEECNewBottomMallViewController / AWEECNewMallViewController）
//      与个人主页二级分页容器（收藏页 AWEProfileBaseContainerViewController）不再扣除 83pt 底栏高度，
//      使页面内容完整延伸至屏幕底边（y = 874），在液态玻璃底栏或透明底栏下正常折射沉浸；两个开关皆关闭时还原原生 83pt 让位。
//
//  实现：
//   - 背景层直读 ivar（_backgroundView / _awe_blurView / _skinContainerView / _separatorLine），不经 getter：
//     separatorLine 的 getter 会懒加载创建分隔线。遮挡视频的是 blur 层的不透明背景色。
//   - 透明靠挂自有的透明 mask，不改 alpha / hidden；抖音切页时只改 blur 层背景色，不会冲掉它。
//   - 判据只看两个开关：视频全屏开启、玻璃底栏未开启。mask 挂在背景层上，切页时不需要重判。
//   - 商城页：buildUI 在挂载 self.mallMainVC.view（IESECMallCoreViewController.view）时通过 Masonry
//     安装 bottom = self.view.bottom - 83.0 约束；沉浸开启时将该约束 constant 置为 0，关闭时还原原始值。
//   - 个人主页收藏页：AWEProfileBaseContainerViewController 在 heightForSectionController: 与
//     setupCollectionView: 中当 isInUserHomePage && !isInLandingPage 为真时扣除 83pt 底栏高度并补 83pt
//     contentInset.bottom；沉浸开启时在 heightForSectionController: 中跳过 83pt 扣除，同时把外层
//     AWEProfileStickCollectionView 的 contentInset.bottom 同步为 0（保持 contentSize.height + bottomInset
//     恒等，不破坏外层吸顶阈值），并刷新内部 AWETabContainerSectionCell 与分页列表布局。
//   - 触发：底栏 layoutSubviews，以及两个开关改动时的 DKTabBarBackdropSetNeedsUpdate。
//   - 玻璃底栏开启时背景归玻璃底栏管（它写 opacity），本模块摘掉自己的 mask。
//

#import "DKTabBarBackdrop.h"
#import "DKGlassTabBar.h"
#import "DKVideoFullscreen.h"
#import "DKViewAdjust.h"
#import "DouyinHeaders.h"

#import <objc/runtime.h>

static const char *const kDKBackdropIvars[] = {
    "_backgroundView", "_awe_blurView", "_skinContainerView", "_separatorLine",
};
static const NSUInteger kDKBackdropIvarCount = sizeof(kDKBackdropIvars) / sizeof(kDKBackdropIvars[0]);

static __weak AWENormalModeTabBar *gBackdropBar;
static BOOL gBackdropScheduled;
static NSHashTable<AWEECMallBaseViewController *> *gMallControllers;
static NSHashTable<AWEProfileBaseContainerViewController *> *gProfileContainers;
static BOOL gProfileSyncing;

static const char kDKMallBottomConstantKey = 0;
static const char kDKProfileStickBottomInsetKey = 0;
static const char kDKProfileImmersionStateKey = 0;

static UIView *DKBackdropView(id object, const char *name) {
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    if (!type || type[0] != '@') return nil;
    id value = object_getIvar(object, ivar);
    return [value isKindOfClass:UIView.class] ? value : nil;
}

static BOOL DKBackdropShouldHide(void) {
    return !DKGlassTabBarActive() && DKVideoFullscreenOn();
}

static BOOL DKBottomImmersionActive(void) {
    return DKGlassTabBarActive() || DKVideoFullscreenOn();
}

static void DKBackdropApply(AWENormalModeTabBar *bar) {
    if (!bar) return;
    gBackdropBar = bar;
    CGFloat factor = DKBackdropShouldHide() ? 0.0 : 1.0;
    for (NSUInteger i = 0; i < kDKBackdropIvarCount; i++) {
        UIView *view = DKBackdropView(bar, kDKBackdropIvars[i]);
        DKAdjustFade(view, factor, view.bounds.size);
    }
}

#pragma mark - 底栏商城页底部沉浸

static void DKMallTrackController(AWEECMallBaseViewController *vc) {
    if (!vc) return;
    if (!gMallControllers) {
        gMallControllers = [NSHashTable weakObjectsHashTable];
    }
    [gMallControllers addObject:vc];
}

static NSLayoutConstraint *DKMallFindBottomConstraint(UIView *hostView, UIView *mallView) {
    if (!hostView || !mallView) return nil;
    for (NSLayoutConstraint *constraint in hostView.constraints) {
        BOOL firstMatches = (constraint.firstItem == mallView && constraint.secondItem == hostView);
        BOOL secondMatches = (constraint.firstItem == hostView && constraint.secondItem == mallView);
        if (!firstMatches && !secondMatches) continue;
        if (constraint.firstAttribute == NSLayoutAttributeBottom &&
            constraint.secondAttribute == NSLayoutAttributeBottom) {
            return constraint;
        }
    }
    return nil;
}

static void DKMallSyncBottomImmersion(AWEECMallBaseViewController *vc) {
    if (!vc || !vc.isViewLoaded) return;
    DKMallTrackController(vc);
    UIViewController *mallMainVC = [vc respondsToSelector:@selector(mallMainVC)] ? vc.mallMainVC : nil;
    if (!mallMainVC || !mallMainVC.isViewLoaded) return;

    UIView *hostView = vc.view;
    UIView *mallView = mallMainVC.view;
    NSLayoutConstraint *bottomConstraint = DKMallFindBottomConstraint(hostView, mallView);
    if (!bottomConstraint) return;

    NSNumber *savedConstant = objc_getAssociatedObject(bottomConstraint, &kDKMallBottomConstantKey);
    if (!savedConstant && fabs(bottomConstraint.constant) > 0.5) {
        savedConstant = @(bottomConstraint.constant);
        objc_setAssociatedObject(bottomConstraint, &kDKMallBottomConstantKey,
            savedConstant, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!savedConstant) return;

    CGFloat targetConstant = DKBottomImmersionActive() ? 0.0 : savedConstant.doubleValue;
    if (fabs(bottomConstraint.constant - targetConstant) > 0.01) {
        bottomConstraint.constant = targetConstant;
        [hostView setNeedsUpdateConstraints];
        [hostView setNeedsLayout];
        [hostView layoutIfNeeded];
        [mallView setNeedsLayout];
        [mallView layoutIfNeeded];
    }
}

#pragma mark - 个人主页收藏页（二级分页容器）底部沉浸

static void DKProfileTrackContainer(AWEProfileBaseContainerViewController *vc) {
    if (!vc) return;
    if (!gProfileContainers) {
        gProfileContainers = [NSHashTable weakObjectsHashTable];
    }
    [gProfileContainers addObject:vc];
}

static void DKProfileSyncStickInset(AWEProfileBaseContainerViewController *vc, UICollectionView *collectionView) {
    if (!vc || !collectionView) return;
    if (!vc.isInUserHomePage || vc.isInLandingPage) return;

    UIEdgeInsets insets = collectionView.contentInset;
    NSNumber *savedBottom = objc_getAssociatedObject(collectionView, &kDKProfileStickBottomInsetKey);
    if (!savedBottom && insets.bottom > 0.5) {
        savedBottom = @(insets.bottom);
        objc_setAssociatedObject(collectionView, &kDKProfileStickBottomInsetKey,
            savedBottom, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!savedBottom) return;

    CGFloat targetBottom = DKBottomImmersionActive() ? 0.0 : savedBottom.doubleValue;
    if (fabs(insets.bottom - targetBottom) > 0.01) {
        insets.bottom = targetBottom;
        collectionView.contentInset = insets;
    }
}

static void DKProfileSyncContainer(AWEProfileBaseContainerViewController *vc) {
    if (!vc || !vc.isViewLoaded || gProfileSyncing) return;
    DKProfileTrackContainer(vc);
    if (!vc.isInUserHomePage || vc.isInLandingPage) return;

    UICollectionView *stickCV = [vc respondsToSelector:@selector(awe_baseCollectionView)]
        ? [vc awe_baseCollectionView] : nil;
    if (!stickCV) return;

    DKProfileSyncStickInset(vc, stickCV);

    BOOL active = DKBottomImmersionActive();
    NSNumber *lastState = objc_getAssociatedObject(vc, &kDKProfileImmersionStateKey);
    AWETabContainerSectionController *tabSection =
        [vc respondsToSelector:@selector(tabContainerSectionController)] ? vc.tabContainerSectionController : nil;
    CGFloat expectedHeight = [vc heightForSectionController:tabSection];

    Class tabSectionCellClass = NSClassFromString(@"AWETabContainerSectionCell");
    BOOL cellHeightMismatch = NO;
    for (UICollectionViewCell *cell in stickCV.visibleCells) {
        if (!tabSectionCellClass || [cell isKindOfClass:tabSectionCellClass]) {
            if (expectedHeight > 0.0 && fabs(CGRectGetHeight(cell.bounds) - expectedHeight) > 0.5) {
                cellHeightMismatch = YES;
                break;
            }
        }
    }

    if (lastState && lastState.boolValue == active && !cellHeightMismatch) {
        return;
    }
    objc_setAssociatedObject(vc, &kDKProfileImmersionStateKey, @(active), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    gProfileSyncing = YES;
    [stickCV.collectionViewLayout invalidateLayout];
    [stickCV layoutIfNeeded];
    for (UICollectionViewCell *cell in stickCV.visibleCells) {
        [cell setNeedsLayout];
        [cell layoutIfNeeded];
    }

    UIViewController *tabContentVC = [tabSection respondsToSelector:@selector(tabContentViewController)]
        ? [tabSection tabContentViewController] : nil;
    if (tabContentVC && tabContentVC.isViewLoaded) {
        [tabContentVC.view setNeedsLayout];
        [tabContentVC.view layoutIfNeeded];
        UICollectionView *pagerCV = [tabContentVC respondsToSelector:@selector(awe_baseCollectionView)]
            ? [(id)tabContentVC awe_baseCollectionView] : nil;
        if (pagerCV) {
            [pagerCV.collectionViewLayout invalidateLayout];
            [pagerCV layoutIfNeeded];
            for (UICollectionViewCell *itemCell in pagerCV.visibleCells) {
                [itemCell setNeedsLayout];
                [itemCell layoutIfNeeded];
            }
        }
    }
    gProfileSyncing = NO;
}

void DKTabBarBackdropSetNeedsUpdate(void) {
    if (gBackdropScheduled) return;
    gBackdropScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        gBackdropScheduled = NO;
        DKBackdropApply(gBackdropBar);
        for (AWEECMallBaseViewController *mallVC in [gMallControllers allObjects]) {
            DKMallSyncBottomImmersion(mallVC);
        }
        for (AWEProfileBaseContainerViewController *profileVC in [gProfileContainers allObjects]) {
            DKProfileSyncContainer(profileVC);
        }
    });
}

NSString *DKTabBarBackdropStatus(void) {
    AWENormalModeTabBar *bar = gBackdropBar;
    NSMutableString *out = [NSMutableString string];
    if (!bar) {
        [out appendString:@"还没有见到抖音底栏\n"];
        return out;
    }
    BOOL glass = DKGlassTabBarActive();
    BOOL fullscreen = DKVideoFullscreenOn();
    id progress = nil;
    @try {
        progress = [bar valueForKey:@"awe_lightModeProgress"];
    } @catch (__unused NSException *exception) {
    }
    [out appendFormat:@"玻璃底栏=%@ 视频全屏=%@ → 背景=%@  明暗进度=%@\n",
        glass ? @"开" : @"关", fullscreen ? @"开" : @"关",
        glass ? @"玻璃接管" : (DKBackdropShouldHide() ? @"透明" : @"原生"), progress ?: @"-"];
    for (NSUInteger i = 0; i < kDKBackdropIvarCount; i++) {
        UIView *view = DKBackdropView(bar, kDKBackdropIvars[i]);
        if (!view) {
            [out appendFormat:@"  %s = nil\n", kDKBackdropIvars[i]];
            continue;
        }
        [out appendFormat:@"  %s = %@ alpha=%.2f hidden=%d 本模块透明=%@ 背景色=%@\n", kDKBackdropIvars[i],
            NSStringFromClass(view.class), view.alpha, view.isHidden,
            DKAdjustFadeFactor(view) < 0.5 ? @"是" : @"否", view.backgroundColor ?: @"nil"];
    }
    [out appendFormat:@"底部页面沉浸=%@\n", DKBottomImmersionActive() ? @"开" : @"关"];
    for (AWEECMallBaseViewController *mallVC in [gMallControllers allObjects]) {
        UIView *hostView = mallVC.isViewLoaded ? mallVC.view : nil;
        UIView *mallView = (mallVC.mallMainVC && mallVC.mallMainVC.isViewLoaded) ? mallVC.mallMainVC.view : nil;
        NSLayoutConstraint *bottomConstraint = DKMallFindBottomConstraint(hostView, mallView);
        [out appendFormat:@"  商城容器 %@ host=%.0fx%.0f mall=%.0fx%.0f bottomConstant=%.1f\n",
            NSStringFromClass(mallVC.class),
            CGRectGetWidth(hostView.frame), CGRectGetHeight(hostView.frame),
            CGRectGetWidth(mallView.frame), CGRectGetHeight(mallView.frame),
            bottomConstraint ? bottomConstraint.constant : 0.0];
    }
    for (AWEProfileBaseContainerViewController *profileVC in [gProfileContainers allObjects]) {
        UICollectionView *stickCV = [profileVC respondsToSelector:@selector(awe_baseCollectionView)]
            ? [profileVC awe_baseCollectionView] : nil;
        AWETabContainerSectionController *tabSection =
            [profileVC respondsToSelector:@selector(tabContainerSectionController)]
            ? profileVC.tabContainerSectionController : nil;
        [out appendFormat:@"  主页分页容器 %p inHome=%d landing=%d sectionH=%.1f stickBottomInset=%.1f\n",
            profileVC, profileVC.isInUserHomePage, profileVC.isInLandingPage,
            [profileVC heightForSectionController:tabSection],
            stickCV ? stickCV.contentInset.bottom : 0.0];
    }
    return out;
}

%hook AWENormalModeTabBar

- (void)layoutSubviews {
    %orig;
    DKBackdropApply(self);
}

%end

%hook AWEECNewBottomMallViewController

- (void)buildUI {
    %orig;
    DKMallSyncBottomImmersion(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    DKMallSyncBottomImmersion(self);
}

%end

%hook AWEECNewMallViewController

- (void)buildUI {
    %orig;
    DKMallSyncBottomImmersion(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    DKMallSyncBottomImmersion(self);
}

%end

%hook AWEProfileBaseContainerViewController

- (void)setupCollectionView:(UICollectionView *)collectionView {
    %orig;
    DKProfileTrackContainer(self);
    DKProfileSyncStickInset(self, collectionView);
}

- (double)heightForSectionController:(id)sectionController {
    DKProfileTrackContainer(self);
    if (!DKBottomImmersionActive() || !self.isInUserHomePage || self.isInLandingPage) {
        return %orig;
    }
    self.isInUserHomePage = NO;
    double height = %orig;
    self.isInUserHomePage = YES;
    return height;
}

- (void)viewDidLayoutSubviews {
    %orig;
    DKProfileSyncContainer(self);
}

%end
