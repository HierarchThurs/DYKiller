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
#import "DKGlassFlexView.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"
#import "DouyinHeaders.h"
#import <objc/runtime.h>

// 相邻页签胶囊之间的间距。
static const CGFloat kDKChatEmojiTabGap = 4.0;
// 顶栏整体偏移：右移 14pt 使首枚胶囊左缘落在 x=16（距 x=8 面板左缘留 8pt，并与下方 x=16 表情网格左对齐），
// 下移 8pt 使 38pt 高的胶囊位于 y=9..47，距面板顶边（y=0）与下方托盘托手（y=56）各留 9pt 对称空隙。
static const CGFloat kDKChatEmojiRowShiftX = 14.0;
static const CGFloat kDKChatEmojiRowShiftY = 8.0;

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

static UIView *DKChatEmojiBoxForView(UIView *view) {
    for (UIView *node = view.superview; node; node = node.superview) {
        if (DKChatInputIsKind(node, @"AWEIMEmoticonPanelBoxView")) return node;
    }
    return nil;
}

static void DKChatEmojiSearchSync(UIView *box);

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
        UIView *box = DKChatEmojiBoxForView(cell);
        if (box) DKChatEmojiSearchSync(box);
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

// 搜索胶囊与右侧页签胶囊统一尺寸（48×38）；首帧尚未生成页签 cell 时按入口宽度与有效内容高度兜底。
static CGSize DKChatEmojiButtonSize(UIView *box, UIView *entry) {
    UICollectionView *tabs = DKChatInputObjectIvar(box, "_tabCollectionView");
    UIView *tab = tabs.visibleCells.firstObject;
    CGFloat width = tab && CGRectGetWidth(tab.bounds) > kDKChatEmojiTabGap
        ? CGRectGetWidth(tab.bounds) - kDKChatEmojiTabGap
        : MAX(CGRectGetWidth(entry.bounds) - kDKChatEmojiTabGap, 0.0);
    if (tab && CGRectGetHeight(tab.bounds) > 0.0) {
        return CGSizeMake(width, CGRectGetHeight(tab.bounds));
    }
    if (tabs) {
        UIEdgeInsets inset = tabs.contentInset;
        CGFloat contentHeight = CGRectGetHeight(tabs.bounds) - inset.top - inset.bottom - 2.0;
        if (contentHeight > 0.0) return CGSizeMake(width, contentHeight);
    }
    CGFloat side = MIN(CGRectGetWidth(entry.bounds), CGRectGetHeight(entry.bounds));
    return CGSizeMake(width > 0.0 ? width : side, side);
}

// 搜索入口（52×48）内部图标（im_emoticon_tab_search，{{12, 6}, {28, 28}}）与右侧页签 cell（{{x, 1}, {52, 38}}）
// 的中心均在 y = 20.0（而非 entry.bounds 的中点 y = 24.0）；按图标中心与页签中线对齐胶囊。
static CGPoint DKChatEmojiEntryCenter(UIView *box, UIView *entry) {
    CGPoint center = CGPointMake(CGRectGetMidX(entry.bounds), CGRectGetMidY(entry.bounds));
    for (UIView *subview in entry.subviews) {
        if ([subview isKindOfClass:DKGlassFlexView.class] || subview.hidden || CGRectIsEmpty(subview.bounds)) continue;
        center = subview.center;
        break;
    }
    UICollectionView *tabs = DKChatInputObjectIvar(box, "_tabCollectionView");
    UIView *tab = tabs.visibleCells.firstObject;
    if (tab) {
        center.y = tab.center.y - tabs.contentOffset.y;
    } else if (tabs) {
        UIEdgeInsets inset = tabs.contentInset;
        CGFloat contentHeight = CGRectGetHeight(tabs.bounds) - inset.top - inset.bottom;
        if (contentHeight > 0.0) center.y = inset.top + contentHeight * 0.5;
    }
    return center;
}

static void DKChatEmojiSearchSync(UIView *box) {
    if (@available(iOS 26.0, *)) {
        UIViewController *input = DKChatEmojiInput(box, gDKChatEmojiBoxes);
        UIView *tabs = DKChatInputObjectIvar(box, "_tabCollectionView");
        NSArray<UIView *> *entries = DKChatEmojiEntries(box);
        DKChatEmojiAlignmentSync(box, entries);
        if (!input) {
            [DKChatGlassStore removeStoreForOwner:box];
            DKAdjustTransform(tabs, CGAffineTransformIdentity);
            for (UIView *entry in entries) DKAdjustTransform(entry, CGAffineTransformIdentity);
            return;
        }
        DKChatGlassStore *store = [DKChatGlassStore storeForOwner:box create:YES];
        if (store.syncing) return;
        CGAffineTransform shift = CGAffineTransformMakeTranslation(kDKChatEmojiRowShiftX, kDKChatEmojiRowShiftY);
        [store beginWithClear:DKPrefBool(DKKeyChatInputGlassClear) style:DKChatInputStyle(input)];
        DKAdjustTransform(tabs, shift);
        for (UIView *entry in entries) {
            CGSize size = DKChatEmojiButtonSize(box, entry);
            CGPoint center = DKChatEmojiEntryCenter(box, entry);
            CGRect frame = CGRectMake(center.x - size.width * 0.5, center.y - size.height * 0.5,
                                      size.width, size.height);
            [store clearBackingOfView:entry];
            UIVisualEffectView *glass = [store placeGlassFor:entry in:entry frame:frame shape:DKChatGlassShapeRounded radius:size.height * 0.5
                     interactive:YES tint:nil];
            // 搜索图标（autoresizingMask = 0）与右侧页签均固定在顶部 40pt 行内，禁用纵向弹性边距以免被 48pt 栈高拉偏。
            glass.autoresizingMask = UIViewAutoresizingNone;
            DKAdjustTransform(entry, shift);
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
