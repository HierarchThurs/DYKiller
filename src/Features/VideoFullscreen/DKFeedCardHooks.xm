// 视频全屏下特殊卡、音乐卡与文章的内容视口及背景接入。
#import "DKFeedCardFit.h"
#import "DKVideoFullscreen.h"
#import <objc/runtime.h>

@interface AWESpecialCardTemplateLynxViewController : UIViewController
@end
@interface AWESearchFeedArticleViewController : UIViewController
@end
@interface DKMusicCardController : UIViewController
@end

static UIView *DKCardMusicLynxContainer(UIView *root) {
    Class containerClass = NSClassFromString(@"HunterBulletContainerView");
    for (UIView *subview in root.subviews) {
        if ([subview isKindOfClass:containerClass]) return subview;
    }
    return nil;
}

static void DKSpecialCardBackdrop(UIViewController *controller, BOOL refreshImage) {
    if (!DKVideoFullscreenOn()) return;
    UIView *root = controller.viewIfLoaded;
    UIView *host = root.superview;
    if (!host) return;
    // 约束已生效后才按实际内容底边铺背景，加载回调早于布局时保持空白。
    CGRect content = [root convertRect:root.bounds toView:host];
    CGFloat inset = DKFeedCardContainerIsFitted(root)
        ? MAX(CGRectGetMaxY(host.bounds) - CGRectGetMaxY(content), 0.0) : 0.0;
    DKFeedCardSyncBackdrop(host, inset, DKFeedCardTypeSpecial);
    if (refreshImage) DKFeedCardRequestBackdropSample(host);
}

%group DKSpecialCardFit
%hook AWESpecialCardTemplateLynxViewController
- (void)viewWillLayoutSubviews {
    if (DKVideoFullscreenOn()) {
        UIView *root = self.viewIfLoaded;
        DKFeedCardFitContainer(root, DKFeedCardInset(root.superview), DKFeedCardTypeSpecial);
    }
    %orig;
}
- (void)viewDidLayoutSubviews {
    %orig;
    DKSpecialCardBackdrop(self, NO);
}
- (void)viewDidAppear:(BOOL)animated { %orig; DKSpecialCardBackdrop(self, YES); }
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (DKVideoFullscreenOn()) DKFeedCardSyncBackdrop(self.viewIfLoaded.superview, 0.0, DKFeedCardTypeSpecial);
}
%end
%end

%group DKSpecialCardLoaded
%hook AWESpecialCardTemplateLynxViewController
- (void)hunterContainerDidFinishLoadWithURL:(id)url { %orig; DKSpecialCardBackdrop(self, YES); }
%end
%end

%group DKSpecialCardDisplay
%hook AWESpecialCardTemplateLynxViewController
- (void)willDisplay { %orig; DKSpecialCardBackdrop(self, YES); }
%end
%end

%group DKMusicCardFit
%hook DKMusicCardController
- (void)viewWillLayoutSubviews {
    if (DKVideoFullscreenOn()) {
        UIView *root = ((UIViewController *)self).viewIfLoaded;
        DKFeedCardFitContainer(DKCardMusicLynxContainer(root), DKFeedCardInset(root), DKFeedCardTypeMusic);
    }
    %orig;
}
%end
%end

static void DKArticleBackdrop(UIViewController *controller, BOOL refreshImage) {
    if (!DKVideoFullscreenOn()) return;
    UIView *root = controller.viewIfLoaded;
    DKFeedCardSyncBackdrop(root, DKFeedCardInset(root), DKFeedCardTypeArticle);
    if (refreshImage) DKFeedCardRequestBackdropSample(root);
}

%group DKArticleFit
%hook AWESearchFeedArticleViewController
- (void)viewDidLayoutSubviews { %orig; DKArticleBackdrop(self, NO); }
%end
%end

%group DKArticleMounted
%hook AWESearchFeedArticleViewController
- (void)lynxEngineDidMount:(id)engine { %orig; DKArticleBackdrop(self, YES); }
%end
%end

%group DKArticleModel
%hook AWESearchFeedArticleViewController
- (void)updateModel:(id)model { %orig; DKArticleBackdrop(self, YES); }
%end
%end

%ctor {
    Class special = NSClassFromString(@"AWESpecialCardTemplateLynxViewController");
    if ([special isSubclassOfClass:UIViewController.class]) {
        %init(DKSpecialCardFit);
        if (class_getInstanceMethod(special, @selector(hunterContainerDidFinishLoadWithURL:))) { %init(DKSpecialCardLoaded); }
        if (class_getInstanceMethod(special, @selector(willDisplay))) { %init(DKSpecialCardDisplay); }
    }
    Class music = NSClassFromString(@"AWEMusicStreamingSwiftImpl.MusicCardViewController");
    if ([music isSubclassOfClass:UIViewController.class]) { %init(DKMusicCardFit, DKMusicCardController = music); }
    Class article = NSClassFromString(@"AWESearchFeedArticleViewController");
    if ([article isSubclassOfClass:UIViewController.class]) {
        %init(DKArticleFit);
        if (class_getInstanceMethod(article, @selector(lynxEngineDidMount:))) { %init(DKArticleMounted); }
        if (class_getInstanceMethod(article, @selector(updateModel:))) { %init(DKArticleModel); }
    }
    DKVideoFullscreenRegisterRestore(DKFeedCardRestore);
}
