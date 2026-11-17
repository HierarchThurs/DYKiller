//
//  DKListenGlassPage.xm
//  DYKiller
//
//  听抖音页顶部与分类卡片的液态玻璃。
//   - 返回键与标题由 DKListenGlassSyncNav 同步。
//   - 展开的分类卡片各自一块玻璃。玻璃在祖先 maskView 下不渲染，所以撤掉原生遮罩展开，
//     原生动画块里改为淡入并从标题下方放大；关闭功能时走原生遮罩动画。
//

#import "DKListenGlass.h"
#import "DKSettings.h"
#import "DouyinHeaders.h"

#import <objc/runtime.h>

static const CGFloat kDKListenFilterPoseScale = 0.92;

static NSHashTable<AWEListenFeedViewController *> *gDKListenPages;
static NSHashTable<AWEListenFeedContentFilterContainerView *> *gDKListenFilterContainers;

static void DKListenPageSync(AWEListenFeedViewController *page) {
    UIButton *button = page.titleButton;
    UIView *title = page.secondPageTitleLabel;
    CGFloat extra = 0.0;
    if (button && !button.hidden) {
        title = button;
        extra = MAX(0.0, CGRectGetMaxX(page.titleArrowImageView.frame) - CGRectGetWidth(button.bounds));
    }
    DKListenGlassSyncNav(page.view, page.backButton, title, extra);
}

static void DKListenFilterCardsSync(AWEListenFeedContentFilterContainerView *container) {
    if (@available(iOS 26.0, *)) {
        BOOL on = DKListenGlassOn();
        DKChatGlassStore *store = [DKChatGlassStore storeForOwner:container create:on];
        if (!store || store.syncing) return;
        if (on) DKListenGlassBegin(store);
        Class cardClass = objc_getClass("AWEListenFeedContentFilterView");
        for (UIView *card in container.contentFilterScrollView.subviews) {
            if (![card isKindOfClass:cardClass]) continue;
            // 卡片原生底是一层渐变，有玻璃时不显示。
            for (CALayer *sublayer in card.layer.sublayers) {
                if ([sublayer isKindOfClass:CAGradientLayer.class]) sublayer.hidden = on;
            }
            if (on) {
                [store placeGlassFor:card in:card frame:card.bounds shape:DKChatGlassShapeRounded
                              radius:card.layer.cornerRadius interactive:YES tint:nil];
            }
        }
        if (on) {
            [store end];
        } else {
            [DKChatGlassStore removeStoreForOwner:container];
        }
    }
}

// 收起姿态：以标题胶囊下沿中点为锚缩小。
static CGAffineTransform DKListenFilterCollapsedTransform(AWEListenFeedViewController *page) {
    UIView *container = page.contentFilterContainerView;
    CGFloat anchorY = CGRectGetMaxY(page.titleButton.frame);
    CGFloat shift = (1.0 - kDKListenFilterPoseScale) * (anchorY - CGRectGetMidY(container.bounds));
    return CGAffineTransformMake(kDKListenFilterPoseScale, 0.0, 0.0, kDKListenFilterPoseScale, 0.0, shift);
}

static void DKListenFilterRefresh(void) {
    for (AWEListenFeedViewController *page in gDKListenPages.allObjects) DKListenPageSync(page);
    for (AWEListenFeedContentFilterContainerView *container in gDKListenFilterContainers.allObjects) DKListenFilterCardsSync(container);
}

%group DKListenGlassPageHooks

%hook AWEListenFeedViewController

- (void)viewDidLayoutSubviews {
    %orig;
    [gDKListenPages addObject:self];
    DKListenPageSync(self);
}

- (void)prepareFilterViewShow:(BOOL)show {
    %orig;
    if (!DKListenGlassOn()) return;
    UIView *container = self.contentFilterContainerView;
    container.maskView = nil;
    if (show) {
        container.alpha = 0.0;
        container.transform = DKListenFilterCollapsedTransform(self);
    }
}

// 原生在动画块里调用，这里写的终态随同一个动画过渡。
- (void)realShowFilterView:(BOOL)show {
    %orig;
    if (!DKListenGlassOn()) return;
    UIView *container = self.contentFilterContainerView;
    container.alpha = show ? 1.0 : 0.0;
    container.transform = show ? CGAffineTransformIdentity : DKListenFilterCollapsedTransform(self);
}

- (void)finishFilterViewShow:(BOOL)show {
    %orig;
    self.contentFilterContainerView.transform = CGAffineTransformIdentity;
}

%end

%hook AWEListenFeedContentFilterContainerView

- (void)layoutSubviews {
    %orig;
    [gDKListenFilterContainers addObject:self];
    DKListenFilterCardsSync(self);
}

- (void)updateByModelArray:(id)models context:(id)context {
    %orig;
    [gDKListenFilterContainers addObject:self];
    DKListenFilterCardsSync(self);
}

%end

%end

%ctor {
    gDKListenPages = [NSHashTable weakObjectsHashTable];
    gDKListenFilterContainers = [NSHashTable weakObjectsHashTable];
    DKSettingsRegister(DKKeyListenFeedGlass, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeGlassChoice(DKKeyListenFeedGlass, DKKeyListenFeedGlassClear, @"听抖音液态玻璃", ^{
            DKListenFilterRefresh();
            DKListenPlayerGlassRefresh();
            DKListenControlGlassRefresh();
            DKListenFilterListGlassRefresh();
        });
        return DKSettingsWithInfo(item,
            @"听抖音页：返回、倍速、顺序、定时换成玻璃圆钮，标题、互动按钮、进度条和播放控制换成玻璃胶囊，封面外包一块玻璃面板。点击标题展开的卡片悬浮显示，播放区不缩小。倍速与定时弹层（固定模糊玻璃）、长按快进提示、分类列表页同步换成玻璃。关闭时保持抖音原生样式。");
    });
    if (DKGlassOSAvailable()) %init(DKListenGlassPageHooks);
}
