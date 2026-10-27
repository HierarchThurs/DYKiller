//
//  DKTabBarPageImmersion.xm
//  功能：底栏页面底部沉浸。悬浮玻璃底栏或视频全屏任一开启时，商城页（AWEECNewBottomMallViewController /
//  AWEECNewMallViewController）与个人主页二级分页容器（收藏页等 AWEProfileBaseContainerViewController）
//  不再扣除底栏高度，页面内容延伸到屏幕底边，在玻璃底栏或透明底栏下沉浸；两个开关都关闭时还原原生让位。
//
//  实现：
//   - 商城页：buildUI 挂载 self.mallMainVC.view（IESECMallCoreViewController.view）时用 Masonry 安装
//     bottom = self.view.bottom - 底栏高度 的约束；沉浸时把该约束的 constant 置 0，原值记在约束上，关闭时还原。
//   - 个人主页二级分页容器：isInUserHomePage && !isInLandingPage 时，原生在 heightForSectionController:
//     里扣除底栏高度、在 setupCollectionView: 里补同样大小的 contentInset.bottom。沉浸时让
//     heightForSectionController: 按非主页口径计算（不扣除），外层 AWEProfileStickCollectionView 的
//     contentInset.bottom 同步为 0（contentSize.height + bottomInset 不变，吸顶阈值不受影响），
//     再刷新 AWETabContainerSectionCell 与分页列表布局。
//   - 触发：两类页面各自的布局回调，以及两个开关改动时的 DKTabBarPageImmersionSetNeedsUpdate。
//

#import "DKTabBarPageImmersion.h"
#import "DKGlassTabBar.h"
#import "DKVideoFullscreen.h"
#import "DouyinHeaders.h"

#import <objc/runtime.h>

static NSHashTable<AWEECMallBaseViewController *> *gMallControllers;
static NSHashTable<AWEProfileBaseContainerViewController *> *gProfileContainers;
static BOOL gProfileSyncing;
static BOOL gImmersionScheduled;

static char kDKMallBottomConstantKey;
static char kDKProfileStickBottomInsetKey;
static char kDKProfileImmersionStateKey;

static BOOL DKBottomImmersionActive(void) {
    return DKGlassTabBarActive() || DKVideoFullscreenOn();
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

    NSLayoutConstraint *bottomConstraint = DKMallFindBottomConstraint(vc.view, mallMainVC.view);
    if (!bottomConstraint) return;

    NSNumber *savedConstant = objc_getAssociatedObject(bottomConstraint, &kDKMallBottomConstantKey);
    if (!savedConstant && fabs(bottomConstraint.constant) > 0.5) {
        savedConstant = @(bottomConstraint.constant);
        objc_setAssociatedObject(bottomConstraint, &kDKMallBottomConstantKey,
            savedConstant, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!savedConstant) return;

    // 约束常量改动后由 Auto Layout 排入下一轮布局，不在布局回调里强制重排。
    CGFloat targetConstant = DKBottomImmersionActive() ? 0.0 : savedConstant.doubleValue;
    if (fabs(bottomConstraint.constant - targetConstant) > 0.01) {
        bottomConstraint.constant = targetConstant;
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

void DKTabBarPageImmersionSetNeedsUpdate(void) {
    if (gImmersionScheduled) return;
    gImmersionScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        gImmersionScheduled = NO;
        for (AWEECMallBaseViewController *mallVC in [gMallControllers allObjects]) {
            DKMallSyncBottomImmersion(mallVC);
        }
        for (AWEProfileBaseContainerViewController *profileVC in [gProfileContainers allObjects]) {
            DKProfileSyncContainer(profileVC);
        }
    });
}

NSString *DKTabBarPageImmersionStatus(void) {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"玻璃底栏=%@ 视频全屏=%@ → 底部页面沉浸=%@\n",
        DKGlassTabBarActive() ? @"开" : @"关", DKVideoFullscreenOn() ? @"开" : @"关",
        DKBottomImmersionActive() ? @"开" : @"关"];
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
    if (gMallControllers.count == 0 && gProfileContainers.count == 0) {
        [out appendString:@"  还没有见到商城页或主页分页容器\n"];
    }
    return out;
}

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
