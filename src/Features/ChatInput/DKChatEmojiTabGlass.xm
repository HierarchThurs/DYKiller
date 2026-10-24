//
//  DKChatEmojiTabGlass.xm
//  DYKiller
//
//  表情面板顶部页签：搜索入口垫一枚圆形玻璃，每个页签垫一块胶囊玻璃（相邻留缝），
//  选中态读原生 userSelected，用着色玻璃表示；原生选中时铺的白底清掉，关闭功能时还原。
//  页签行统一用原生的居中形态（有聊天背景图时的排法），关闭功能时回到原生形态。
//

#import "DKChatEmojiTabGlass.h"
#import "DKChatGlassStore.h"
#import "DKChatInput.h"
#import "DKChatInputLayout.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"
#import "DouyinHeaders.h"
#import <objc/runtime.h>

// 相邻页签胶囊之间的间距。
static const CGFloat kDKChatEmojiTabGap = 4.0;
// 搜索圆钮整体右移的距离：圆钮按页签高度取直径后会越出面板卡片左缘，右移后与卡片、首个页签都留出间隙。
static const CGFloat kDKChatEmojiSearchShift = 4.0;

static NSHashTable<UIView *> *gDKChatEmojiTabs;
static NSHashTable<UIView *> *gDKChatEmojiBoxes;
// 盒视图 / 搜索入口 → 设置其纵向形态的原生对象（盒组件 / 固定入口），记下原生要求值与实际交给原生的值。
static NSMapTable<UIView *, id> *gDKChatEmojiAligners;
static char kDKChatEmojiNativeCenterKey;
static char kDKChatEmojiAppliedCenterKey;

// 视图所在的聊天输入页且功能生效时返回它；评论区等复用同一面板的场景返回 nil。
static UIViewController *DKChatEmojiInput(UIView *view, NSHashTable<UIView *> *seen) {
    UIViewController *input = DKChatInputController(DKChatInputLayoutForView(view));
    if (!input) return nil;
    [seen addObject:view];
    return DKChatInputGlassWanted(input) && !CGRectIsEmpty(view.bounds) ? input : nil;
}

// 玻璃生效的普通聊天里，页签行一律居中：玻璃卡片已接管面板底色，与有背景图时的原生排法一致。
static BOOL DKChatEmojiCenterWanted(UIView *view) {
    return DKChatInputGlassWanted(DKChatInputController(DKChatInputLayoutForView(view)));
}

// 记下原生要求的形态，需要时改为居中再交给原生。
static BOOL DKChatEmojiAlign(id owner, UIView *view, BOOL center) {
    [gDKChatEmojiAligners setObject:owner forKey:view];
    BOOL applied = center || DKChatEmojiCenterWanted(view);
    objc_setAssociatedObject(owner, &kDKChatEmojiNativeCenterKey, @(center), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(owner, &kDKChatEmojiAppliedCenterKey, @(applied), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return applied;
}

// 原生在面板挂进聊天页之前就定了形态；盒视图同步时按记录重放，与开关不一致的才重设。
static void DKChatEmojiAlignmentSync(UIView *box, NSArray<UIView *> *entries) {
    for (UIView *view in [@[ box ] arrayByAddingObjectsFromArray:entries]) {
        id owner = [gDKChatEmojiAligners objectForKey:view];
        if (!owner) continue;
        BOOL center = [objc_getAssociatedObject(owner, &kDKChatEmojiNativeCenterKey) boolValue];
        BOOL applied = [objc_getAssociatedObject(owner, &kDKChatEmojiAppliedCenterKey) boolValue];
        if (applied == (center || DKChatEmojiCenterWanted(view))) continue;
        if (view == box) [(AWEIMEmoticonPanelBoxComponent *)owner verticalAlignmentCenter:center boxView:box];
        else [(AWEIMEmoticonFixedTab *)owner verticalAlignmentCenter:center];
    }
    UIView *separator = DKChatInputObjectIvar(box, "_separator");
    if (separator) DKAdjustAlpha(separator, DKChatEmojiCenterWanted(box) ? 0.0 : 1.0);
}

// 选中页签的玻璃染色：浅色偏白、深色偏灰。
static UIColor *DKChatEmojiSelectedTint(UIUserInterfaceStyle style) {
    return [UIColor colorWithWhite:1.0 alpha:style == UIUserInterfaceStyleDark ? 0.12 : 0.18];
}

static void DKChatEmojiTabSync(UICollectionViewCell *cell) {
    if (@available(iOS 26.0, *)) {
        UIViewController *input = DKChatEmojiInput(cell, gDKChatEmojiTabs);
        if (!input) {
            [DKChatGlassStore removeStoreForOwner:cell];
            return;
        }
        DKChatGlassStore *store = [DKChatGlassStore storeForOwner:cell create:YES];
        if (store.syncing) return;
        UIUserInterfaceStyle style = DKChatInputStyle(input);
        UIView *content = cell.contentView;
        CGRect frame = CGRectInset(content.bounds, kDKChatEmojiTabGap * 0.5, 0.0);
        BOOL selected = ((AWEIMEmoticonTabCollectionViewCell *)cell).userSelected;
        [store beginWithClear:DKPrefBool(DKKeyChatInputGlassClear) style:style];
        [store clearBackingOfView:content];
        [store placeGlassFor:cell in:content frame:frame shape:DKChatGlassShapeRounded
                      radius:CGRectGetHeight(frame) * 0.5 interactive:YES
                        tint:selected ? DKChatEmojiSelectedTint(style) : nil];
        [store end];
    }
}

// 页签行里除页签集合视图之外的入口（搜索）。
static NSArray<UIView *> *DKChatEmojiEntries(UIView *box) {
    UIStackView *row = DKChatInputObjectIvar(box, "_horizontalStackView");
    UIView *tabs = DKChatInputObjectIvar(box, "_tabCollectionView");
    NSMutableArray<UIView *> *entries = [NSMutableArray array];
    for (UIView *view in row.arrangedSubviews) {
        if (view != tabs && !view.hidden && !CGRectIsEmpty(view.bounds)) [entries addObject:view];
    }
    return entries;
}

// 圆钮直径与页签胶囊同高；还没有页签时按入口短边。
static CGFloat DKChatEmojiButtonDiameter(UIView *box, UIView *entry) {
    UICollectionView *tabs = DKChatInputObjectIvar(box, "_tabCollectionView");
    UIView *tab = tabs.visibleCells.firstObject;
    return tab ? CGRectGetHeight(tab.bounds) : MIN(CGRectGetWidth(entry.bounds), CGRectGetHeight(entry.bounds));
}

static void DKChatEmojiSearchSync(UIView *box) {
    if (@available(iOS 26.0, *)) {
        UIViewController *input = DKChatEmojiInput(box, gDKChatEmojiBoxes);
        NSArray<UIView *> *entries = DKChatEmojiEntries(box);
        DKChatEmojiAlignmentSync(box, entries);
        if (!input) {
            [DKChatGlassStore removeStoreForOwner:box];
            for (UIView *entry in entries) DKAdjustTransform(entry, CGAffineTransformIdentity);
            return;
        }
        DKChatGlassStore *store = [DKChatGlassStore storeForOwner:box create:YES];
        if (store.syncing) return;
        [store beginWithClear:DKPrefBool(DKKeyChatInputGlassClear) style:DKChatInputStyle(input)];
        for (UIView *entry in entries) {
            CGFloat diameter = DKChatEmojiButtonDiameter(box, entry);
            CGRect frame = CGRectMake(CGRectGetMidX(entry.bounds) - diameter * 0.5, CGRectGetMidY(entry.bounds) - diameter * 0.5,
                                      diameter, diameter);
            [store clearBackingOfView:entry];
            UIVisualEffectView *glass = [store placeGlassFor:entry in:entry frame:frame shape:DKChatGlassShapeRounded radius:diameter * 0.5
                     interactive:YES tint:nil];
            // 横向栈在父级回调后仍会调整入口高度，圆片随入口尺寸保持居中。
            glass.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin
                | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
            DKAdjustTransform(entry, CGAffineTransformMakeTranslation(kDKChatEmojiSearchShift, 0.0));
        }
        [store end];
    }
}

void DKChatEmojiTabGlassRefresh(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKChatEmojiTabGlassRefresh(); });
        return;
    }
    for (UIView *cell in gDKChatEmojiTabs.allObjects) DKChatEmojiTabSync((UICollectionViewCell *)cell);
    for (UIView *box in gDKChatEmojiBoxes.allObjects) DKChatEmojiSearchSync(box);
}

%group DKChatEmojiTabGlassHooks
// 选中切换、按下高亮与复用都会重写白底，各回调后同步；进入窗口时补一次（格子可能在挂上页签栏之前配置）。
%hook AWEIMEmoticonTabCollectionViewCell
- (void)__refreshSelectedUI {
    %orig;
    DKChatEmojiTabSync(self);
}
- (void)setHighlighted:(BOOL)highlighted {
    %orig;
    DKChatEmojiTabSync(self);
}
- (void)layoutSubviews {
    %orig;
    DKChatEmojiTabSync(self);
}
- (void)didMoveToWindow {
    %orig;
    DKChatEmojiTabSync(self);
}
%end
%hook AWEIMEmoticonPanelBoxComponent
- (void)verticalAlignmentCenter:(BOOL)center boxView:(UIView *)boxView {
    %orig(boxView ? DKChatEmojiAlign(self, boxView, center) : center, boxView);
}
%end
%hook AWEIMEmoticonFixedTab
- (void)verticalAlignmentCenter:(BOOL)center {
    UIView *entry = self.entryView;
    %orig(entry ? DKChatEmojiAlign(self, entry, center) : center);
}
%end
%hook AWEIMEmoticonPanelBoxView
- (void)layoutSubviews {
    %orig;
    DKChatEmojiSearchSync(self);
}
- (void)didMoveToWindow {
    %orig;
    DKChatEmojiSearchSync(self);
    UICollectionView *tabs = DKChatInputObjectIvar(self, "_tabCollectionView");
    for (UICollectionViewCell *cell in tabs.visibleCells) {
        if (DKChatInputIsKind(cell, @"AWEIMEmoticonTabCollectionViewCell")) DKChatEmojiTabSync(cell);
    }
}
%end
%end

%ctor {
    gDKChatEmojiTabs = [NSHashTable weakObjectsHashTable];
    gDKChatEmojiBoxes = [NSHashTable weakObjectsHashTable];
    gDKChatEmojiAligners = [NSMapTable weakToWeakObjectsMapTable];
    if (DKGlassOSAvailable()) {
        %init(DKChatEmojiTabGlassHooks);
    }
}
