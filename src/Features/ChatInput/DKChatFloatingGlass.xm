//
//  DKChatFloatingGlass.xm
//  DYKiller
//
//  表情提示条芯片、最近照片条与列表底部提示的玻璃。
//   - 芯片清掉自带的模糊与底色，垫一块胶囊玻璃。
//   - 最近照片条逐张垫玻璃：每张照片格（AWEIMAssetListCollectionViewCell）垫一块交互态圆角玻璃相框，
//     照片内容四周内缩出折射边框并取同心连续圆角，「动图」角标换为胶囊玻璃；「添加更多可访问照片」格
//     （AWEIMPhotoAddMoreCollectionViewCell）清掉原生灰底与模糊，垫同样的玻璃卡。
//   - 芯片与照片条都是先配置排版、再挂进浮动容器，进入窗口时各补一次同步。
//   - 底部提示（回到最新圆钮 / 新消息胶囊）每次出现才挂进列表、收起后移除，主题重载会重写白底。
//

#import "DKChatFloatingGlass.h"
#import "DKChatGlassStore.h"
#import "DKChatInput.h"
#import "DKChatInputLayout.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"
#import "DouyinHeaders.h"

#import <objc/runtime.h>

static const CGFloat kDKChatPhotoCardRadius = 14.0;
static const CGFloat kDKChatPhotoFrameInset = 4.0;

static NSHashTable<UIView *> *gDKChatChips;
static NSHashTable<UIView *> *gDKChatPhotoStrips;
static NSHashTable<UIView *> *gDKChatPhotoAssetCells;
static NSHashTable<UIView *> *gDKChatPhotoAddCells;
static NSHashTable<UIView *> *gDKChatBottomTips;
// 照片格与其内容视图在接管前的裁剪、圆角与圆角曲线，关闭时还原。
static char kDKChatPhotoClipsKey;
static char kDKChatPhotoRadiusKey;
static char kDKChatPhotoCurveKey;

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

static UIView *DKChatQuickPhotoPickerForCell(UIView *cell) {
    for (UIView *node = cell.superview; node; node = node.superview) {
        if (DKChatInputIsKind(node, @"AWEIMQuickPhotoPickerView")) return node;
    }
    return nil;
}

static void DKChatSaveViewClipState(UIView *view) {
    if (!view) return;
    if (!objc_getAssociatedObject(view, &kDKChatPhotoClipsKey)) {
        objc_setAssociatedObject(view, &kDKChatPhotoClipsKey, @(view.clipsToBounds), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!objc_getAssociatedObject(view, &kDKChatPhotoRadiusKey)) {
        objc_setAssociatedObject(view, &kDKChatPhotoRadiusKey, @(view.layer.cornerRadius), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!objc_getAssociatedObject(view, &kDKChatPhotoCurveKey)) {
        objc_setAssociatedObject(view, &kDKChatPhotoCurveKey, view.layer.cornerCurve, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void DKChatRestoreViewClipState(UIView *view) {
    if (!view) return;
    NSNumber *savedClips = objc_getAssociatedObject(view, &kDKChatPhotoClipsKey);
    if (savedClips) {
        view.clipsToBounds = savedClips.boolValue;
        objc_setAssociatedObject(view, &kDKChatPhotoClipsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSNumber *savedRadius = objc_getAssociatedObject(view, &kDKChatPhotoRadiusKey);
    if (savedRadius) {
        view.layer.cornerRadius = savedRadius.doubleValue;
        objc_setAssociatedObject(view, &kDKChatPhotoRadiusKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CALayerCornerCurve savedCurve = objc_getAssociatedObject(view, &kDKChatPhotoCurveKey);
    if (savedCurve) {
        view.layer.cornerCurve = savedCurve;
        objc_setAssociatedObject(view, &kDKChatPhotoCurveKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void DKChatPhotoAssetCellSync(UICollectionViewCell *cell) {
    if (@available(iOS 26.0, *)) {
        if (!DKChatQuickPhotoPickerForCell(cell)) return;
        UIViewController *input = DKChatFloatingInput(cell, gDKChatPhotoAssetCells);
        UIView *content = cell.contentView;
        if (!input) {
            [DKChatGlassStore removeStoreForOwner:cell];
            DKAdjustTransform(content, CGAffineTransformIdentity);
            DKChatRestoreViewClipState(cell);
            DKChatRestoreViewClipState(content);
            return;
        }
        DKChatGlassStore *store = [DKChatGlassStore storeForOwner:cell create:YES];
        if (store.syncing) return;

        DKChatSaveViewClipState(cell);
        DKChatSaveViewClipState(content);

        [store beginWithClear:DKPrefBool(DKKeyChatInputGlassClear) style:DKChatInputStyle(input)];
        [store clearBackingOfView:cell];
        [store clearBackingOfView:content];
        [store placeGlassFor:cell in:cell frame:cell.bounds shape:DKChatGlassShapeRounded
                      radius:kDKChatPhotoCardRadius interactive:YES tint:nil];

        UIView *liveTag = DKChatInputObjectIvar(cell, "_livePhotoTag");
        if (liveTag && !CGRectIsEmpty(liveTag.bounds)) {
            [store clearBackingOfView:liveTag];
            [store placeGlassFor:liveTag in:liveTag frame:liveTag.bounds shape:DKChatGlassShapeRounded
                          radius:CGRectGetHeight(liveTag.bounds) * 0.5 interactive:NO tint:nil];
        }
        [store end];

        cell.clipsToBounds = NO;
        cell.layer.cornerRadius = 0.0;

        CGFloat width = CGRectGetWidth(cell.bounds);
        CGFloat height = CGRectGetHeight(cell.bounds);
        if (width > kDKChatPhotoFrameInset * 2.0 && height > kDKChatPhotoFrameInset * 2.0) {
            CGFloat scaleX = (width - kDKChatPhotoFrameInset * 2.0) / width;
            CGFloat scaleY = (height - kDKChatPhotoFrameInset * 2.0) / height;
            CGFloat innerRadius = MAX(kDKChatPhotoCardRadius - kDKChatPhotoFrameInset, 4.0);
            DKAdjustTransform(content, CGAffineTransformMakeScale(scaleX, scaleY));
            content.clipsToBounds = YES;
            content.layer.cornerCurve = kCACornerCurveContinuous;
            content.layer.cornerRadius = innerRadius / MIN(scaleX, scaleY);
        }
    }
}

static void DKChatPhotoAddCellSync(UICollectionViewCell *cell) {
    if (@available(iOS 26.0, *)) {
        if (!DKChatQuickPhotoPickerForCell(cell)) return;
        UIViewController *input = DKChatFloatingInput(cell, gDKChatPhotoAddCells);
        if (!input) {
            [DKChatGlassStore removeStoreForOwner:cell];
            DKChatRestoreViewClipState(cell);
            return;
        }
        DKChatGlassStore *store = [DKChatGlassStore storeForOwner:cell create:YES];
        if (store.syncing) return;

        DKChatSaveViewClipState(cell);
        UIView *content = cell.contentView;
        [store beginWithClear:DKPrefBool(DKKeyChatInputGlassClear) style:DKChatInputStyle(input)];
        [store clearBackingOfView:cell];
        [store clearBackingOfView:content];
        [store clearBackingOfView:DKChatInputObjectIvar(cell, "_backgroundContainer")];
        [store clearBackingOfView:DKChatInputObjectIvar(cell, "_blurView")];
        [store placeGlassFor:cell in:content frame:content.bounds shape:DKChatGlassShapeRounded
                      radius:kDKChatPhotoCardRadius interactive:YES tint:nil];
        [store end];

        cell.clipsToBounds = NO;
        cell.layer.cornerRadius = 0.0;
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
        UICollectionView *collectionView = DKChatInputObjectIvar(picker, "_collectionView");
        [store beginWithClear:DKPrefBool(DKKeyChatInputGlassClear) style:DKChatInputStyle(input)];
        [store clearBackingOfView:picker];
        [store clearBackingOfView:collectionView];
        [store end];

        for (UICollectionViewCell *cell in collectionView.visibleCells) {
            if (DKChatInputIsKind(cell, @"AWEIMAssetListCollectionViewCell")) {
                DKChatPhotoAssetCellSync(cell);
            } else if (DKChatInputIsKind(cell, @"AWEIMPhotoAddMoreCollectionViewCell")) {
                DKChatPhotoAddCellSync(cell);
            }
        }
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
    for (UIView *cell in gDKChatPhotoAssetCells.allObjects) DKChatPhotoAssetCellSync((UICollectionViewCell *)cell);
    for (UIView *cell in gDKChatPhotoAddCells.allObjects) DKChatPhotoAddCellSync((UICollectionViewCell *)cell);
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
%hook AWEIMAssetListCollectionViewCell
- (void)layoutSubviews {
    if (DKChatQuickPhotoPickerForCell(self)) {
        DKAdjustTransform(self.contentView, CGAffineTransformIdentity);
    }
    %orig;
    DKChatPhotoAssetCellSync(self);
}
- (void)prepareForReuse {
    if (DKChatQuickPhotoPickerForCell(self)) {
        DKAdjustTransform(self.contentView, CGAffineTransformIdentity);
    }
    %orig;
}
- (void)didMoveToWindow {
    %orig;
    DKChatPhotoAssetCellSync(self);
}
%end
%hook AWEIMPhotoAddMoreCollectionViewCell
- (void)layoutSubviews {
    %orig;
    DKChatPhotoAddCellSync(self);
}
- (void)addBlurView {
    %orig;
    DKChatPhotoAddCellSync(self);
}
- (void)didMoveToWindow {
    %orig;
    DKChatPhotoAddCellSync(self);
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
    gDKChatPhotoAssetCells = [NSHashTable weakObjectsHashTable];
    gDKChatPhotoAddCells = [NSHashTable weakObjectsHashTable];
    gDKChatBottomTips = [NSHashTable weakObjectsHashTable];
    if (DKGlassOSAvailable()) {
        %init(DKChatFloatingGlassHooks);
    }
}
