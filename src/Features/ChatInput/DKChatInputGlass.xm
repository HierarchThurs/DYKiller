//
//  DKChatInputGlass.xm
//  DYKiller
//
//  聊天输入区的玻璃：输入行的胶囊与圆钮、表情 / 加号面板卡片。
//  槽位、底色与 mask 由挂在输入布局对象上的 DKChatGlassStore 管理，关闭功能或离场时逐项还原。
//

#import "DKChatInputGlass.h"
#import "DKChatFloatingGlass.h"
#import "DKChatGlassStore.h"
#import "DKChatInput.h"
#import "DKChatInputLayout.h"
#import "DKChatInputList.h"
#import "DKChatInputPendant.h"
#import "DKChatEmojiTabGlass.h"
#import "DKGlassFlexView.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DouyinHeaders.h"

static NSHashTable<UIWindowScene *> *gDKChatGlassScenes;

static BOOL DKChatShown(UIView *view, UIView *root) {
    if (!view || !root || ![view isDescendantOfView:root]) return NO;
    for (UIView *node = view; node; node = node.superview) {
        if (node.hidden || node.alpha < 0.01) return NO;
        if (node == root) return YES;
    }
    return NO;
}

// 深浅色切换时整体刷新；每个场景只登记一次。
static void DKChatObserveScene(UIWindowScene *scene) API_AVAILABLE(ios(26.0)) {
    if (!scene || [gDKChatGlassScenes containsObject:scene]) return;
    [gDKChatGlassScenes addObject:scene];
    [scene registerForTraitChanges:@[ UITraitUserInterfaceStyle.class ]
                       withHandler:^(__unused UIWindowScene *changed, __unused UITraitCollection *previous) {
                           DKChatInputRefresh();
                       }];
}

#pragma mark - 原生底色

// 聊天页在输入行下方挂着一层 AWEUIDynamicBlurEffect（面板 / 键盘底板），开启时清掉 effect，关闭时原样放回。
static void DKChatClearNativeBlur(DKChatGlassStore *store, UIViewController *input) API_AVAILABLE(ios(26.0)) {
    for (UIView *sibling in input.view.superview.subviews) {
        if (![sibling isKindOfClass:UIVisualEffectView.class]) continue;
        UIVisualEffect *effect = ((UIVisualEffectView *)sibling).effect;
        BOOL dynamic = effect && [NSStringFromClass(effect.class) isEqualToString:@"AWEUIDynamicBlurEffect"];
        if (dynamic || [store tracksBackingOfView:sibling]) [store clearBackingOfView:sibling];
    }
}

// 加号宫格格子的方块底：底色、容器与模糊层（模糊层在配置之后才由 addBlurView 建出）。
static void DKChatClearPanelCell(DKChatGlassStore *store, UIView *cell) API_AVAILABLE(ios(26.0)) {
    for (NSString *name in @[ @"_backgroundColorView", @"_backgroundContainer", @"_blurView" ]) {
        [store clearBackingOfView:DKChatInputObjectIvar(cell, name.UTF8String)];
    }
}

// 面板满宽底色与加号宫格的方块底。
static void DKChatClearPanel(DKChatGlassStore *store, UIView *view, CGFloat width, NSUInteger depth)
    API_AVAILABLE(ios(26.0)) {
    if (!view || depth > 8 || [view isKindOfClass:DKGlassFlexView.class]
        || [view isKindOfClass:UIImageView.class] || [view isKindOfClass:UILabel.class]
        || [view isKindOfClass:UIControl.class]) return;
    if (CGRectGetWidth(view.bounds) >= width * 0.99) [store clearBackingOfView:view];
    if ([view isKindOfClass:UIVisualEffectView.class]) return;
    if (DKChatInputIsKind(view, @"AWEIMChatPanelCollectionViewCell")) DKChatClearPanelCell(store, view);
    for (UIView *child in view.subviews) DKChatClearPanel(store, child, width, depth + 1);
}

// 宫格格子配置、建模糊层或进入窗口时只清这一格；面板没在接管时不动。
static void DKChatPanelCellSync(UIView *cell) {
    if (@available(iOS 26.0, *)) {
        id layout = DKChatInputLayoutForView(cell);
        DKChatGlassStore *store = [DKChatGlassStore storeForOwner:layout create:NO];
        if (!store || store.syncing || !DKChatInputGlassWanted(DKChatInputController(layout))) return;
        DKChatClearPanelCell(store, cell);
    }
}

#pragma mark - 输入行

// 文字 / 语音胶囊一块玻璃，左右圆钮各一块；原生不透明底色的按钮（发送键）改用该色着色的玻璃。
static void DKChatApplyRowGlass(DKChatGlassStore *store, id layout) API_AVAILABLE(ios(26.0)) {
    UIView *elements = DKChatInputObjectIvar(layout, "_inputBarElementContainer");
    DKChatRowFrames frames;
    if (!DKChatInputRowFrames(layout, &frames)) return;
    id audioComponent = DKChatInputComponent(layout, @"IESIMInputAudioComponent");
    UIView *audio = DKChatInputObjectIvar(audioComponent, "_audioInputView");
    UIView *growing = DKChatInputObjectIvar(DKChatInputComponent(layout, @"IESIMInputTextComponent"), "_textView");
    if (DKChatShown(audio, elements)) {
        [store clearBackingOfView:audio];
        [store clearBackingOfView:DKChatInputObjectIvar(audioComponent, "_audioInputViewBlurView")];
        CGFloat radius = MIN(CGRectGetHeight(audio.bounds), kDKChatButtonDiameter) * 0.5;
        [store placeGlassFor:audio in:audio frame:audio.bounds shape:DKChatGlassShapeRounded radius:radius
                 interactive:YES tint:nil];
    } else if (DKChatShown(growing, elements)) {
        [store clearBackingOfView:growing];
        [store clearBackingOfView:DKChatInputObjectIvar(growing, "internalTextView")];
        // 多行只增加中段高度，端部保持单行胶囊的半径。
        CGFloat radius = MIN(CGRectGetHeight(frames.capsule), kDKChatButtonDiameter) * 0.5;
        [store placeGlassFor:growing in:growing frame:[elements convertRect:frames.capsule toView:growing]
                       shape:DKChatGlassShapeRounded radius:radius interactive:YES tint:nil];
    }
    NSArray<UIView *> *left, *right;
    DKChatInputRowButtons(layout, &left, &right);
    for (UIView *button in [left arrayByAddingObjectsFromArray:right]) {
        UIColor *native = [store clearBackingOfView:button];
        UIColor *tint = native && CGColorGetAlpha(native.CGColor) > 0.01 ? native : nil;
        CGFloat radius = MIN(CGRectGetWidth(button.bounds), CGRectGetHeight(button.bounds)) * 0.5;
        [store placeGlassFor:button in:button frame:button.bounds shape:DKChatGlassShapeRounded radius:radius
                 interactive:YES tint:tint];
    }
}

#pragma mark - 面板

// 面板里按卡片裁剪的那一层。表情面板只裁翻页区：顶部页签自带玻璃，祖先挂 mask 会让玻璃渲染失真。
static UIView *DKChatPanelClipView(UIView *panel) {
    if (!DKChatInputIsKind(panel, @"AWEIMEmoticonPanelContainerView")) return panel;
    for (UIView *child in panel.subviews) {
        if (DKChatInputIsKind(child, @"AWEIMEmoticonPanelBoxView")) return DKChatInputObjectIvar(child, "_panelCollectionView");
    }
    return nil;
}

// 面板 frame 保持原生；玻璃卡片挂在面板容器里、左右与底部内缩，面板内容按卡片形状裁剪。
static void DKChatApplyPanelGlass(DKChatGlassStore *store, id layout) API_AVAILABLE(ios(26.0)) {
    UIView *panels = DKChatInputObjectIvar(layout, "_panelsContainer");
    for (NSArray<NSString *> *entry in @[ @[ @"IESIMInputEmoticonComponent", @"_emoticonView" ],
                                          @[ @"IESIMInputPlusComponent", @"_chatPanelView" ] ]) {
        UIView *panel = DKChatInputObjectIvar(DKChatInputComponent(layout, entry[0]), [entry[1] UTF8String]);
        if (!DKChatShown(panel, panels) || panel.superview != panels || CGRectIsEmpty(panel.bounds)) continue;
        [store clearBackingOfView:panels];
        DKChatClearPanel(store, panel, CGRectGetWidth(panel.bounds), 0);
        CGRect card = panel.frame;
        card.origin.x += kDKChatPanelInset;
        card.size.width -= 2.0 * kDKChatPanelInset;
        card.size.height -= kDKChatPanelInset;
        UIVisualEffectView *glass = [store placeGlassFor:panel in:panels frame:card shape:DKChatGlassShapeCard
                                                  radius:kDKChatPanelRadius interactive:NO tint:nil];
        UIView *clip = DKChatPanelClipView(panel);
        if (glass && clip) [store maskView:clip toGlass:glass];
        return;
    }
}

#pragma mark - 入口

void DKChatInputGlassApply(id layout, BOOL clear, UIUserInterfaceStyle style) {
    if (!layout) return;
    if (@available(iOS 26.0, *)) {
        UIViewController *input = DKChatInputController(layout);
        UIView *plate = DKChatInputObjectIvar(layout, "_textViewBackgroundView");
        if (!input || !plate || CGRectIsEmpty(plate.bounds)) {
            DKChatInputGlassRestore(layout);
            return;
        }
        DKChatGlassStore *store = [DKChatGlassStore storeForOwner:layout create:YES];
        if (store.syncing) return;
        DKChatObserveScene(input.view.window.windowScene);
        [store beginWithClear:clear style:style];
        [store clearBackingOfView:input.view];
        for (NSString *name in @[ @"_inputBarContainer", @"_inputBarElementContainer", @"_textViewBackgroundView",
                                  @"_textViewAboveBackgroundView", @"_textViewBackgroundViewBlurView", @"_bottomBackgroundView" ]) {
            [store clearBackingOfView:DKChatInputObjectIvar(layout, name.UTF8String)];
        }
        DKChatClearNativeBlur(store, input);
        DKChatApplyRowGlass(store, layout);
        DKChatApplyPanelGlass(store, layout);
        [store end];
    }
}

void DKChatInputGlassRestore(id layout) {
    if (@available(iOS 26.0, *)) [DKChatGlassStore removeStoreForOwner:layout];
}

#pragma mark - Hook

%group DKChatInputGlassHooks
%hook IESIMInputViewController
// 进页转场开始前准备材质与几何，首帧直接使用悬浮输入区。
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [UIView performWithoutAnimation:^{
        DKChatInputSync(DKChatInputLayoutForController(self));
    }];
}
- (void)viewDidLayoutSubviews {
    %orig;
    DKChatInputSync(DKChatInputLayoutForController(self));
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!self.isViewLoaded) return;
    DKChatInputSync(DKChatInputLayoutForController(self));
    DKChatInputListRefresh();
    DKChatFloatingGlassRefresh();
    DKChatEmojiTabGlassRefresh();
    DKChatInputPendantRefresh();
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (self.isViewLoaded) DKChatInputRestore(DKChatInputLayoutForController(self));
}
%end
// 文字区 inset 的唯一写入点：按钮布局后与高度变化时原生都经这里写，左右换成胶囊内的留白。
%hook IESIMGrowingTextView
- (void)setContentInsetPurely:(UIEdgeInsets)insets {
    %orig(DKChatInputTextInsets(DKChatInputLayoutForView(self), self, insets));
}
%end
%hook IESIMInputLayoutComponent
- (void)refreshBackgroundWithBackGroundImage:(BOOL)hasImage {
    %orig;
    DKChatInputSync(self);
}
%end
%hook IESIMInputAudioComponent
- (void)refreshBackgroundWithBackGroundImage:(BOOL)hasImage {
    %orig;
    DKChatInputSync(DKChatInputComponent(self, @"IESIMInputLayoutComponent"));
}
%end
%hook AWEIMOptimizeAudioInputTouchView
- (void)refreshColor {
    %orig;
    DKChatInputSync(DKChatInputLayoutForView(self));
}
%end
%hook AWEIMEmoticonPanelContainerView
- (void)layoutSubviews {
    %orig;
    DKChatInputSync(DKChatInputLayoutForView(self));
}
- (void)refreshBackgroundColorWhileHasBackground:(BOOL)hasBackground {
    %orig;
    DKChatInputSync(DKChatInputLayoutForView(self));
}
%end
%hook AWEIMPlusPanelView
- (void)updatePanelVisible:(BOOL)visible {
    %orig;
    DKChatInputSync(DKChatInputLayoutForView(self));
}
%end
%hook IESIMInputPlusComponent
- (void)refreshBackgroundWithBackGroundImage:(BOOL)hasImage {
    %orig;
    DKChatInputSync(DKChatInputComponent(self, @"IESIMInputLayoutComponent"));
}
%end
%hook AWEIMEmoticonPanelBoxView
- (void)iesim_themeReload:(id)theme {
    %orig;
    DKChatInputSync(DKChatInputLayoutForView(self));
}
%end
// 格子的模糊层在 configWithModel: 返回之后才由 addBlurView 建出，各回调后都只清这一格。
%hook AWEIMChatPanelCollectionViewCell
- (void)configWithModel:(id)model {
    %orig;
    DKChatPanelCellSync(self);
}
- (void)addBlurView {
    %orig;
    DKChatPanelCellSync(self);
}
- (void)prepareForReuse {
    %orig;
    DKChatPanelCellSync(self);
}
- (void)didMoveToWindow {
    %orig;
    DKChatPanelCellSync(self);
}
%end
// 表情翻页区是滚动视图，卡片 mask 随可见区域移动。
%hook AWEIMEmoticonThemesCollectionView
- (void)layoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) {
        [[DKChatGlassStore storeForOwner:DKChatInputLayoutForView(self) create:NO] followBoundsOfMaskedView:self];
    }
}
%end
%end

#pragma mark - 设置

%ctor {
    gDKChatGlassScenes = [NSHashTable weakObjectsHashTable];
    DKSettingsRegister(DKKeyChatInputGlass, ^AWESettingItemModel *{
        return DKSettingsWithInfo(DKMakeGlassChoice(DKKeyChatInputGlass, DKKeyChatInputGlassClear,
            @"聊天页输入面板液态玻璃", ^{ DKChatInputRefresh(); }),
            @"普通私聊与群聊的输入区悬浮在消息上：消息铺到屏幕底部，未弹出键盘时滑动消息会从输入区下方经过。输入框与按住说话区为胶囊，独立按钮为圆形，发送键为粉色玻璃；表情 / 加号面板与最近照片为悬浮卡片，表情提示的每个芯片各自一块玻璃，表情面板的搜索为圆钮、页签为胶囊；小火人改趴在输入框中间。关闭时恢复原生外观。");
    });
    if (DKGlassOSAvailable()) {
        %init(DKChatInputGlassHooks);
    }
}
