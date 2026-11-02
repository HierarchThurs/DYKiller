//
//  DKTabBarCollapse.xm
//  功能：底栏动态收缩 —— 上下滑判定、收缩后的点击穿透与设置项。
//  收缩与展开交给 DKGlassTabBar.xm 调系统入口；结构与实测见 docs/tab-bar-collapse.md。
//

#import "DKTabBarCollapse.h"
#import "DKGlassTabBar.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import "DouyinHeaders.h"

@interface _TtC5UIKit20_UITabBarPlatterView : UIView
@end

// 上滑累计到这个距离收缩，下滑累计到这个距离展开。
static const CGFloat kDKCollapseDistance = 48.0;
static const CGFloat kDKExpandDistance = 12.0;
static const CGFloat kDKFlickProjection = 0.1;

static BOOL DKCollapseSupported(void) {
    return DKGlassOSAvailable() && UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone;
}

DKTabBarCollapseSide DKTabBarCollapseCurrentSide(void) {
    if (!DKCollapseSupported()) return DKTabBarCollapseSideOff;
    NSInteger value = DKPrefInteger(DKKeyGlassTabBarCollapse);
    if (value == DKTabBarCollapseSideLeft || value == DKTabBarCollapseSideRight) {
        return (DKTabBarCollapseSide)value;
    }
    return DKTabBarCollapseSideOff;
}

#pragma mark - 上下滑判定

// 只旁听不抢手势：不取消、不延迟触摸，与页面自己的滚动同时识别。
// 每次手势最多触发一次，滚动容器由触摸点向上查，不依赖抖音的页面类名。
@interface DKTabBarCollapsePanTarget : NSObject <UIGestureRecognizerDelegate>
@end

@implementation DKTabBarCollapsePanTarget {
    BOOL _fired;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateBegan) _fired = NO;
    BOOL ended = pan.state == UIGestureRecognizerStateEnded;
    if ((pan.state != UIGestureRecognizerStateChanged && !ended) || _fired) return;

    CGPoint translation = [pan translationInView:pan.view];
    if (fabs(translation.y) <= fabs(translation.x)) return;
    // 短促快滑移动距离不够也能翻页，松手时把速度折算成距离。
    if (ended) translation.y += [pan velocityInView:pan.view].y * kDKFlickProjection;
    if (translation.y <= -kDKCollapseDistance) {
        _fired = YES;
        DKGlassTabBarSetCollapsed(YES);
    } else if (translation.y >= kDKExpandDistance) {
        _fired = YES;
        DKGlassTabBarSetCollapsed(NO);
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *bar = DKGlassBarHostCurrent().superview;
    if (!bar.window || bar.isHidden || bar.alpha < 0.01 || [touch.view isDescendantOfView:bar]) return NO;

    for (UIView *view = touch.view; view; view = view.superview) {
        if (![view isKindOfClass:UIScrollView.class]) continue;
        UIScrollView *scrollView = (UIScrollView *)view;
        if (scrollView.isScrollEnabled
            && (scrollView.alwaysBounceVertical
                || scrollView.contentSize.height > CGRectGetHeight(scrollView.bounds))) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

@end

static DKTabBarCollapsePanTarget *gPanTarget = nil;
static UIPanGestureRecognizer *gPan = nil;

void DKTabBarCollapseAttach(UIView *view) {
    if (gPan.view == view) return;
    if (!gPan) {
        gPanTarget = [[DKTabBarCollapsePanTarget alloc] init];
        gPan = [[UIPanGestureRecognizer alloc] initWithTarget:gPanTarget action:@selector(handlePan:)];
        gPan.delegate = gPanTarget;
        gPan.maximumNumberOfTouches = 1;
        gPan.cancelsTouchesInView = NO;
        gPan.delaysTouchesBegan = NO;
        gPan.delaysTouchesEnded = NO;
    }
    [view addGestureRecognizer:gPan];
}

void DKTabBarCollapseDetach(void) {
    [gPan.view removeGestureRecognizer:gPan];
}

#pragma mark - Hook

%group DKTabBarCollapseHooks

// 收缩后只有圆键接收触摸，其余位置交给底栏下方的内容。圆键可能在 UITabBar 之外，直接问它。
%hook AWENormalModeTabBar

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *circle = DKGlassTabBarCollapsedHitView();
    if (!circle) return %orig;
    return [circle hitTest:[self convertPoint:point toView:circle] withEvent:event];
}

%end

%hook _TtC5UIKit20_UITabBarPlatterView

// 收缩底板的尺寸与位置由 UIKit 按内部常量写入，这里换成实际值，系统形变以它为终点。
- (void)setBounds:(CGRect)bounds {
    if (self == DKGlassTabBarCollapsePlatter()) bounds.size = DKGlassTabBarCollapseFrame().size;
    %orig(bounds);
}

- (void)setCenter:(CGPoint)center {
    if (self == DKGlassTabBarCollapsePlatter()) {
        CGRect frame = DKGlassTabBarCollapseFrame();
        center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    }
    %orig(center);
}

- (void)setFrame:(CGRect)frame {
    %orig(self == DKGlassTabBarCollapsePlatter() ? DKGlassTabBarCollapseFrame() : frame);
}

// 系统展开时先显示胶囊再开始形变，收缩过程不会显示胶囊。
- (void)setHidden:(BOOL)hidden {
    %orig;
    if (!hidden) DKGlassTabBarPlatterDidShow(self);
}

%end

%end

#pragma mark - 设置项注册

%ctor {
    DKSettingsRegister(DKKeyGlassTabBarCollapse, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeChoice(DKKeyGlassTabBarCollapse, @"动态收缩底栏",
                                                 @[ @"关闭", @"左侧", @"右侧" ]);
        DKSettingsOnChange(item, ^{ DKGlassTabBarRefresh(); });
        return DKSettingsWithInfo(item,
            @"上滑时底栏收缩为一颗系统圆键，图标为当前页面；略微下滑或点圆键展开。"
            @"收缩后圆键以外的位置不拦截点击，拍摄键一起隐藏。需开启「悬浮玻璃底栏」，仅 iPhone 可用。");
    });

    if (DKCollapseSupported()) {
        %init(DKTabBarCollapseHooks);
    }
}
