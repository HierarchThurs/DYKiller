//
//  DKChatFloatingGlass.xm
//  DYKiller
//
//  表情提示条芯片、最近照片条与列表底部提示的玻璃。芯片清掉自带的模糊与底色，垫一块胶囊玻璃；
//  照片条在父视图里垫一块左右内缩的卡片玻璃，照片条本身按卡片形状裁剪（照片列表会滚动，不能挂 mask）。
//  芯片与照片条都是先配置排版、再挂进浮动容器，进入窗口时各补一次同步。
//  底部提示（回到最新圆钮 / 新消息胶囊）每次出现才挂进列表、收起后移除，主题重载会重写白底。
//

#import "DKChatFloatingGlass.h"
#import "DKChatGlassStore.h"
#import "DKChatInput.h"
#import "DKChatInputLayout.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import "DouyinHeaders.h"

static const CGFloat kDKChatPhotoStripRadius = 12.0;

static NSHashTable<UIView *> *gDKChatChips;
static NSHashTable<UIView *> *gDKChatPhotoStrips;
static NSHashTable<UIView *> *gDKChatBottomTips;

// 宿主所在聊天页的输入控制器；功能对它生效时返回，否则返回 nil。
static UIViewController *DKChatFloatingInput(UIView *view, NSHashTable<UIView *> *seen) {
    UIViewController *input = DKChatInputControllerForPageView(view);
    if (!input) return nil;
    [seen addObject:view];
    return DKChatInputGlassWanted(input) && !CGRectIsEmpty(view.bounds) ? input : nil;
}

static void DKChatChipSync(UIView *cell) {
    if (@available(iOS 26.0, *)) {
        UIViewController *input = DKChatFloatingInput(cell, gDKChatChips);
        if (!input) {
            [DKChatGlassStore removeStoreForOwner:cell];
            return;
        }
        DKChatGlassStore *store = [DKChatGlassStore storeForOwner:cell create:YES];
        if (store.syncing) return;
        UIView *blur = DKChatInputObjectIvar(cell, "_blurView");
        UIView *carrier = blur.superview ?: ((UICollectionViewCell *)cell).contentView;
        CGRect frame = [cell convertRect:cell.bounds toView:carrier];
        [store beginWithClear:DKPrefBool(DKKeyChatInputGlassClear) style:DKChatInputStyle(input)];
        [store clearBackingOfView:blur];
        [store clearBackingOfView:DKChatInputObjectIvar(cell, "_backgroundAboveView")];
        [store placeGlassFor:cell in:carrier frame:frame shape:DKChatGlassShapeRounded
                      radius:CGRectGetHeight(frame) * 0.5 interactive:YES tint:nil];
        [store end];
    }
}

static void DKChatPhotoStripSync(UIView *picker) {
    if (@available(iOS 26.0, *)) {
        UIViewController *input = DKChatFloatingInput(picker, gDKChatPhotoStrips);
        UIView *host = picker.superview;
        if (!input || !host) {
            [DKChatGlassStore removeStoreForOwner:picker];
            return;
        }
        DKChatGlassStore *store = [DKChatGlassStore storeForOwner:picker create:YES];
        if (store.syncing) return;
        [store beginWithClear:DKPrefBool(DKKeyChatInputGlassClear) style:DKChatInputStyle(input)];
        [store clearBackingOfView:picker];
        [store clearBackingOfView:DKChatInputObjectIvar(picker, "_collectionView")];
        UIVisualEffectView *glass = [store placeGlassFor:picker in:host
                                                   frame:CGRectInset(picker.frame, kDKChatPanelInset, 0.0)
                                                   shape:DKChatGlassShapeRounded radius:kDKChatPhotoStripRadius
                                             interactive:NO tint:nil];
        if (glass) [store maskView:picker toGlass:glass];
        [store end];
    }
}

// 原生白底与外圈阴影换成同形玻璃：圆钮 40×40 为圆，新消息胶囊两端半圆；图标与文字保持原生。
static void DKChatBottomTipsSync(UIView *tips) {
    if (@available(iOS 26.0, *)) {
        UIViewController *input = DKChatFloatingInput(tips, gDKChatBottomTips);
        if (!input) {
            [DKChatGlassStore removeStoreForOwner:tips];
            return;
        }
        DKChatGlassStore *store = [DKChatGlassStore storeForOwner:tips create:YES];
        if (store.syncing) return;
        [store beginWithClear:DKPrefBool(DKKeyChatInputGlassClear) style:DKChatInputStyle(input)];
        [store clearBackingOfView:tips];
        [store clearShadowOfView:tips];
        [store placeGlassFor:tips in:tips frame:tips.bounds shape:DKChatGlassShapeRounded
                      radius:CGRectGetHeight(tips.bounds) * 0.5 interactive:YES tint:nil];
        [store end];
    }
}

void DKChatFloatingGlassRefresh(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKChatFloatingGlassRefresh(); });
        return;
    }
    for (UIView *cell in gDKChatChips.allObjects) DKChatChipSync(cell);
    for (UIView *picker in gDKChatPhotoStrips.allObjects) DKChatPhotoStripSync(picker);
    for (UIView *tips in gDKChatBottomTips.allObjects) DKChatBottomTipsSync(tips);
}

%group DKChatFloatingGlassHooks
// 芯片复用与样式刷新都会重写底色和模糊，布局、样式与进入窗口回调后各同步一次。
%hook AWEIMInputActionBarEntryItemCollectionViewCell
- (void)layoutSubviews {
    %orig;
    DKChatChipSync(self);
}
- (void)refreshStyle {
    %orig;
    DKChatChipSync(self);
}
- (void)didMoveToWindow {
    %orig;
    DKChatChipSync(self);
}
%end
%hook AWEIMQuickPhotoPickerView
- (void)layoutSubviews {
    %orig;
    DKChatPhotoStripSync(self);
}
- (void)refreshBackgroundColorWhileHasBackground:(BOOL)hasBackground {
    %orig;
    DKChatPhotoStripSync(self);
}
- (void)didMoveToWindow {
    %orig;
    DKChatPhotoStripSync(self);
}
%end
// 圆钮与胶囊切换时宽度变化触发布局；出现时重新挂进列表；主题重载经 setBackgroundColor: 重写白底。
%hook AWEIMBottomNewMessageTipsImageView
- (void)layoutSubviews {
    %orig;
    DKChatBottomTipsSync(self);
}
- (void)didMoveToWindow {
    %orig;
    DKChatBottomTipsSync(self);
}
- (void)setBackgroundColor:(UIColor *)color {
    %orig;
    DKChatBottomTipsSync(self);
}
%end
%end

%ctor {
    gDKChatChips = [NSHashTable weakObjectsHashTable];
    gDKChatPhotoStrips = [NSHashTable weakObjectsHashTable];
    gDKChatBottomTips = [NSHashTable weakObjectsHashTable];
    if (DKGlassOSAvailable()) {
        %init(DKChatFloatingGlassHooks);
    }
}
