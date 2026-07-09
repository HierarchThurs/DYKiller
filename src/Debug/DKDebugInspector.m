//
//  DKDebugInspector.m
//  DYKiller
//
//  全局扳手入口：独立高层级 window 承载调试按钮，点选页面元素后复用
//  DKDebugCapture / DKDebugExport 生成导出包。
//

#import "DKDebugInspector.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import "DKDebugCapture.h"
#import "DKDebugExport.h"

@interface DKDebugOverlayView : UIView
@end

@implementation DKDebugOverlayView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self) ? nil : hit;
}

@end

@interface DKDebugOverlayWindow : UIWindow
@end

@interface DKDebugOverlayViewController : UIViewController
@property (nonatomic, strong) UIButton *wrenchButton;
@property (nonatomic, assign) BOOL didPlaceButton;
- (BOOL)capturesOverlayTouches;
@end

@implementation DKDebugOverlayWindow

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    DKDebugOverlayViewController *controller = [self.rootViewController isKindOfClass:DKDebugOverlayViewController.class]
                                               ? (DKDebugOverlayViewController *)self.rootViewController
                                               : nil;
    if ([controller capturesOverlayTouches]) return [super pointInside:point withEvent:event];
    CGPoint p = [controller.wrenchButton convertPoint:point fromView:self];
    return [controller.wrenchButton pointInside:p withEvent:event];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    DKDebugOverlayViewController *controller = [self.rootViewController isKindOfClass:DKDebugOverlayViewController.class]
                                               ? (DKDebugOverlayViewController *)self.rootViewController
                                               : nil;
    if ([controller capturesOverlayTouches]) return hit ?: controller.view;
    if (!hit || hit == controller.view || hit == self) return nil;
    return hit;
}

@end

static DKDebugOverlayWindow *DKDebugWindow;
static DKDebugOverlayViewController *DKDebugController;
static BOOL DKDebugInstalled;

#pragma mark - UI 工具

static BOOL DKIsDebugOverlayWindow(UIWindow *window) {
    return [NSStringFromClass(window.class) hasPrefix:@"DKDebug"];
}

static void DKPresentError(UIViewController *presenter, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导出失败"
                                                                       message:message ?: @"未知错误"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
        [presenter presentViewController:alert animated:YES completion:nil];
    });
}

static void DKShareZip(NSURL *zipURL, UIViewController *presenter, UIView *sourceView) {
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[zipURL] applicationActivities:nil];
    if (activity.popoverPresentationController) {
        activity.popoverPresentationController.sourceView = sourceView ?: presenter.view;
        activity.popoverPresentationController.sourceRect = (sourceView ?: presenter.view).bounds;
    }
    [presenter presentViewController:activity animated:YES completion:nil];
}

static void DKStartExport(DKDebugExportContext *context, BOOL includeAppClasses) {
    UIViewController *presenter = context.presenter ?: DKDebugController;
    if (!presenter) return;

    UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:@"DYKiller"
                                                                           message:@"准备导出..."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
    [presenter presentViewController:progressAlert animated:YES completion:^{
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSURL *zipURL = DKDebugCreateExportZip(context, includeAppClasses, ^(NSString *text) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    progressAlert.message = text;
                });
            });
            dispatch_async(dispatch_get_main_queue(), ^{
                [progressAlert dismissViewControllerAnimated:YES completion:^{
                    if (zipURL) {
                        DKShareZip(zipURL, presenter, context.sourceView ?: presenter.view);
                    } else {
                        DKPresentError(presenter, @"没有生成 zip 文件");
                    }
                }];
            });
        });
    }];
}

static UIWindowScene *DKDebugForegroundScene(void) {
    if (@available(iOS 13.0, *)) {
        UIWindow *target = DKDebugTargetWindow();
        if (target.windowScene) return target.windowScene;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            if (scene.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)scene;
        }
    }
    return nil;
}

static CGRect DKDebugScreenBounds(void) {
    UIWindow *target = DKDebugTargetWindow();
    if (target) return target.bounds;
    return UIScreen.mainScreen.bounds;
}

static void DKEnsureDebugWindow(void) {
    if (DKDebugWindow && DKDebugController) {
        if (@available(iOS 13.0, *)) {
            UIWindowScene *scene = DKDebugForegroundScene();
            if (scene && DKDebugWindow.windowScene != scene) DKDebugWindow.windowScene = scene;
        }
        return;
    }

    DKDebugController = [DKDebugOverlayViewController new];
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = DKDebugForegroundScene();
        DKDebugWindow = scene ? [[DKDebugOverlayWindow alloc] initWithWindowScene:scene]
                              : [[DKDebugOverlayWindow alloc] initWithFrame:DKDebugScreenBounds()];
    } else {
        DKDebugWindow = [[DKDebugOverlayWindow alloc] initWithFrame:DKDebugScreenBounds()];
    }
    DKDebugWindow.backgroundColor = UIColor.clearColor;
    DKDebugWindow.opaque = NO;
    DKDebugWindow.windowLevel = UIWindowLevelAlert + 100000.0;
    DKDebugWindow.rootViewController = DKDebugController;
    DKDebugWindow.hidden = YES;
}

#pragma mark - 浮层控制器

@implementation DKDebugOverlayViewController

- (void)loadView {
    DKDebugOverlayView *view = [[DKDebugOverlayView alloc] initWithFrame:DKDebugScreenBounds()];
    view.backgroundColor = UIColor.clearColor;
    view.opaque = NO;
    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.wrenchButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.wrenchButton.frame = CGRectMake(0, 0, 48, 48);
    self.wrenchButton.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.82];
    self.wrenchButton.tintColor = UIColor.whiteColor;
    self.wrenchButton.layer.cornerRadius = 24;
    self.wrenchButton.layer.shadowColor = UIColor.blackColor.CGColor;
    self.wrenchButton.layer.shadowOpacity = 0.24;
    self.wrenchButton.layer.shadowRadius = 8;
    self.wrenchButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.wrenchButton.accessibilityLabel = @"DYKiller Debug";

    UIImage *image = nil;
    if ([UIImage respondsToSelector:@selector(systemImageNamed:)]) image = [UIImage systemImageNamed:@"wrench.fill"];
    if (image) {
        [self.wrenchButton setImage:image forState:UIControlStateNormal];
    } else {
        [self.wrenchButton setTitle:@"W" forState:UIControlStateNormal];
        self.wrenchButton.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    }
    [self.wrenchButton addTarget:self action:@selector(showDebugMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.wrenchButton];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleWrenchPan:)];
    [self.wrenchButton addGestureRecognizer:pan];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.didPlaceButton) {
        UIEdgeInsets insets = self.view.safeAreaInsets;
        CGFloat x = self.view.bounds.size.width - insets.right - 12.0 - 24.0;
        CGFloat y = insets.top + 12.0 + 24.0;
        self.wrenchButton.center = CGPointMake(x, y);
        self.didPlaceButton = YES;
    }
    [self clampWrenchButton];
}

- (void)clampWrenchButton {
    UIEdgeInsets insets = self.view.safeAreaInsets;
    CGFloat halfW = self.wrenchButton.bounds.size.width / 2.0;
    CGFloat halfH = self.wrenchButton.bounds.size.height / 2.0;
    CGFloat minX = insets.left + halfW + 6.0;
    CGFloat maxX = self.view.bounds.size.width - insets.right - halfW - 6.0;
    CGFloat minY = insets.top + halfH + 6.0;
    CGFloat maxY = self.view.bounds.size.height - insets.bottom - halfH - 6.0;
    CGPoint c = self.wrenchButton.center;
    c.x = MIN(MAX(c.x, minX), maxX);
    c.y = MIN(MAX(c.y, minY), maxY);
    self.wrenchButton.center = c;
}

- (void)handleWrenchPan:(UIPanGestureRecognizer *)pan {
    CGPoint delta = [pan translationInView:self.view];
    self.wrenchButton.center = CGPointMake(self.wrenchButton.center.x + delta.x,
                                           self.wrenchButton.center.y + delta.y);
    [pan setTranslation:CGPointZero inView:self.view];
    [self clampWrenchButton];
}

- (void)showDebugMenu {
    if (!DKPrefBool(DKKeyDebugInspectorEnabled)) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"DYKiller Debug"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"导出本页 zip"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [self exportWholePage:NO];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"导出全 App 类 zip"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [self exportWholePage:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = self.wrenchButton;
        alert.popoverPresentationController.sourceRect = self.wrenchButton.bounds;
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)exportWholePage:(BOOL)includeAppClasses {
    UIWindow *targetWindow = DKDebugTargetWindow();
    if (!targetWindow) {
        DKPresentError(self, @"没有找到可导出的 App 窗口");
        return;
    }

    // 调试浮层始终置顶、无需选元素：直接快照整页（selectedView=nil 即整窗）。
    DKDebugExportContext *context = DKDebugCaptureContext(targetWindow, CGPointZero, nil);
    context.presenter = self;
    context.sourceView = self.wrenchButton;
    DKStartExport(context, includeAppClasses);
}

- (BOOL)capturesOverlayTouches {
    return self.presentedViewController != nil;
}

@end

#pragma mark - 对外入口

void DKDebugInspectorRefreshOverlay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL enabled = DKPrefBool(DKKeyDebugInspectorEnabled);
        if (!enabled) {
            if (DKDebugWindow) {
                DKDebugWindow.hidden = YES;
                [DKDebugTargetWindow() makeKeyWindow];
            }
            return;
        }

        DKEnsureDebugWindow();
        DKDebugWindow.frame = DKDebugScreenBounds();
        DKDebugWindow.hidden = NO;
        UIWindow *targetWindow = DKDebugTargetWindow();
        if (targetWindow && !targetWindow.isKeyWindow) [targetWindow makeKeyWindow];
    });
}

void DKDebugInspectorInstall(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (DKDebugInstalled) {
            DKDebugInspectorRefreshOverlay();
            return;
        }
        DKDebugInstalled = YES;

        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserverForName:UIWindowDidBecomeKeyNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            if (DKIsDebugOverlayWindow((UIWindow *)note.object)) return;
            DKDebugInspectorRefreshOverlay();
        }];
        [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            DKDebugInspectorRefreshOverlay();
        }];
        DKDebugInspectorRefreshOverlay();
    });
}
