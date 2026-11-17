//
//  DKListenGlassPlayer.xm
//  DYKiller
//
//  听抖音播放区的玻璃面板：普通作品的封面外包一块玻璃，合集封面流每张封面各一块。
//  面板由约束贴住封面，文案展开时封面的布局动画会带着面板一起走。
//  开启时展开分类卡片不再改播放区：播放元素不接收展开事件，也不按展开状态排版。
//

#import "DKListenGlass.h"
#import "DouyinHeaders.h"

static const CGFloat kDKListenPanelOutset = 8.0;

static NSHashTable<AWEListenFeedPlayerElement *> *gDKListenPlayers;
static NSHashTable<AWEListenFeedExtendCoverCollectionViewCell *> *gDKListenCoverCells;

// 面板与封面同心，四边外扩固定量。
API_AVAILABLE(ios(26.0))
static void DKListenPanelPin(DKChatGlassStore *store, UIImageView *cover) {
    if (!cover.superview) return;
    [store pinGlassFor:cover in:cover.superview shape:DKChatGlassShapeRounded
                radius:cover.layer.cornerRadius + kDKListenPanelOutset interactive:NO
           constraints:^NSArray<NSLayoutConstraint *> *(UIView *glass) {
        return @[
            [glass.topAnchor constraintEqualToAnchor:cover.topAnchor constant:-kDKListenPanelOutset],
            [glass.leadingAnchor constraintEqualToAnchor:cover.leadingAnchor constant:-kDKListenPanelOutset],
            [glass.trailingAnchor constraintEqualToAnchor:cover.trailingAnchor constant:kDKListenPanelOutset],
            [glass.bottomAnchor constraintEqualToAnchor:cover.bottomAnchor constant:kDKListenPanelOutset],
        ];
    }];
}

// 展开分类时显示的贴顶圆角压暗层：直接挂在交互控制器根视图、不属于任何元素。
static UIView *DKListenFilterDimView(UIView *root) {
    for (UIView *child in root.subviews) {
        if ([child isMemberOfClass:UIView.class] && CGRectGetMinY(child.frame) == 0.0
            && child.layer.cornerRadius > 0.0 && CGRectGetMaxY(child.frame) < CGRectGetHeight(root.bounds)) {
            return child;
        }
    }
    return nil;
}

static void DKListenPlayerSync(AWEListenFeedPlayerElement *player) {
    if (@available(iOS 26.0, *)) {
        if (!DKListenGlassOn()) {
            [DKChatGlassStore removeStoreForOwner:player];
            return;
        }
        DKChatGlassStore *store = [DKChatGlassStore storeForOwner:player create:YES];
        if (store.syncing) return;
        DKListenGlassBegin(store);
        DKListenPanelPin(store, player.coverImageView);
        UIView *dim = DKListenFilterDimView(player.container.view);
        if (dim) [store clearBackingOfView:dim];
        [store end];
    }
}

static void DKListenCoverCellSync(AWEListenFeedExtendCoverCollectionViewCell *cell) {
    if (@available(iOS 26.0, *)) {
        BOOL on = DKListenGlassOn();
        // 封面容器原生按自身边界裁剪，面板外扩需要打开。
        DKListenGlassSetUnclipped(cell.containerView, on);
        if (!on) {
            [DKChatGlassStore removeStoreForOwner:cell];
            return;
        }
        DKChatGlassStore *store = [DKChatGlassStore storeForOwner:cell create:YES];
        if (store.syncing) return;
        DKListenGlassBegin(store);
        DKListenPanelPin(store, cell.coverImageView);
        [store end];
    }
}

void DKListenPlayerGlassRefresh(void) {
    for (AWEListenFeedPlayerElement *player in gDKListenPlayers.allObjects) DKListenPlayerSync(player);
    for (AWEListenFeedExtendCoverCollectionViewCell *cell in gDKListenCoverCells.allObjects) DKListenCoverCellSync(cell);
}

%group DKListenGlassPlayerHooks

%hook AWEListenFeedPlayerElement

- (void)viewDidLayoutSubviews {
    %orig;
    [gDKListenPlayers addObject:self];
    DKListenPlayerSync(self);
}

- (void)showContentFilterView:(BOOL)show {
    if (!DKListenGlassOn()) %orig;
}

- (BOOL)isContentFilterShowing {
    return DKListenGlassOn() ? NO : %orig;
}

%end

%hook AWEListenFeedExtendCoverCollectionViewCell

- (void)layoutSubviews {
    %orig;
    [gDKListenCoverCells addObject:self];
    DKListenCoverCellSync(self);
}

%end

%end

%ctor {
    gDKListenPlayers = [NSHashTable weakObjectsHashTable];
    gDKListenCoverCells = [NSHashTable weakObjectsHashTable];
    if (DKGlassOSAvailable()) %init(DKListenGlassPlayerHooks);
}
