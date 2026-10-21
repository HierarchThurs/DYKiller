// 原生特殊卡面板的安全视口、背景延伸与共用 Cell 的换卡清理。
#import "DKFeedCardFit.h"
#import "DKVideoFullscreen.h"
#import <objc/runtime.h>

@interface AWESpecialCardTemplateNativeViewController : UIViewController
@property (nonatomic, strong) UIViewController *panelViewController;
@end
@interface AWESpecialCardTemplatePureCell : UITableViewCell
@property (nonatomic, strong) UIViewController *viewController;
@end

static UIView *DKNativeCardPanel(AWESpecialCardTemplateNativeViewController *controller) {
    UIView *root = controller.viewIfLoaded;
    UIView *panel = controller.panelViewController.viewIfLoaded;
    return root && panel.superview == root ? panel : nil;
}

static void DKNativeCardFit(AWESpecialCardTemplateNativeViewController *controller) {
    UIView *panel = DKNativeCardPanel(controller);
    if (panel) DKFeedCardFitNativePanel(panel, DKFeedCardInset(controller.viewIfLoaded));
}

static void DKNativeCardBackdrop(AWESpecialCardTemplateNativeViewController *controller, BOOL refresh) {
    UIView *root = controller.viewIfLoaded;
    UIView *panel = DKNativeCardPanel(controller);
    CGFloat inset = 0.0;
    if (panel && DKFeedCardInset(root) > 0.0 && CGRectGetHeight(panel.bounds) > 0.0) {
        CGRect content = [panel convertRect:panel.bounds toView:root];
        inset = MAX(CGRectGetMaxY(root.bounds) - CGRectGetMaxY(content), 0.0);
    }
    DKFeedCardSyncBackdrop(root, inset, DKFeedCardTypeSpecial);
    if (refresh) DKFeedCardRequestBackdropSample(root);
}

%group DKNativeCardFit
%hook AWESpecialCardTemplateNativeViewController
- (void)attachPanelViewControllerIfNeeded {
    %orig;
    DKNativeCardFit(self);
}
- (void)viewWillLayoutSubviews {
    DKNativeCardFit(self);
    %orig;
}
- (void)viewDidLayoutSubviews {
    %orig;
    DKNativeCardBackdrop(self, NO);
}
- (void)willDisplay {
    %orig;
    DKNativeCardBackdrop(self, YES);
}
- (void)didEndDisplaying {
    %orig;
    DKFeedCardSyncBackdrop(self.viewIfLoaded, 0.0, DKFeedCardTypeSpecial);
}
%end
%end

%group DKSpecialCardReuse
%hook AWESpecialCardTemplatePureCell
- (void)configureWithModel:(id)model {
    // Cell 更换内容前清除自己的背景条，旧采样任务随背景条身份失效。
    DKFeedCardSyncBackdrop(self.viewController.viewIfLoaded, 0.0, DKFeedCardTypeSpecial);
    DKFeedCardSyncBackdrop(self.contentView, 0.0, DKFeedCardTypeSpecial);
    %orig;
}
%end
%end

%ctor {
    Class native = NSClassFromString(@"AWESpecialCardTemplateNativeViewController");
    if ([native isSubclassOfClass:UIViewController.class]
        && class_getInstanceMethod(native, @selector(panelViewController))
        && class_getInstanceMethod(native, @selector(attachPanelViewControllerIfNeeded))
        && class_getInstanceMethod(native, @selector(willDisplay))
        && class_getInstanceMethod(native, @selector(didEndDisplaying))) {
        %init(DKNativeCardFit);
    }
    Class cell = NSClassFromString(@"AWESpecialCardTemplatePureCell");
    if ([cell isSubclassOfClass:UITableViewCell.class]
        && class_getInstanceMethod(cell, @selector(viewController))
        && class_getInstanceMethod(cell, @selector(configureWithModel:))) {
        %init(DKSpecialCardReuse);
    }
}
