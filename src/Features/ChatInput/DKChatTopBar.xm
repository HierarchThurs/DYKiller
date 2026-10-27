// 聊天顶栏和群功能栏的悬浮玻璃，复用原生控件位置与点击；可选居中头像与顶部渐变模糊。
#import "DKChatTopBar.h"
#import "DKChatInput.h"
#import "DKChatInputLayout.h"
#import "DKChatInputList.h"
#import "DKChatGlassStore.h"
#import "DKChatTopBlur.h"
#import "DKChatTopCenter.h"
#import "DKGlassGuard.h"
#import "DKImageOpaque.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"
#import "DouyinHeaders.h"
#import <objc/runtime.h>

static NSHashTable *gDKChatNaviComponents;
static char kDKChatMenuViewKey;
static const CGFloat kDKChatTopGap = 8.0;
static char kDKChatTopLayoutKey;
static char kDKChatTopExtraKey;
static char kDKChatTopNativeLayoutKey;

// 一块顶栏槽位：source 是玻璃身份、按压源与点击目标，frame（carrier 坐标）同时是点击范围。
@interface DKChatTopSlot : NSObject
@property (nonatomic, weak) UIView *source;
@property (nonatomic) CGRect frame;
@property (nonatomic) CGFloat radius;
@property (nonatomic) BOOL glass;
@end
@implementation DKChatTopSlot
@end

static DKChatTopSlot *DKChatTopSlotMake(UIView *source, CGRect frame, CGFloat radius, BOOL glass) {
    DKChatTopSlot *slot = [DKChatTopSlot new];
    slot.source = source;
    slot.frame = frame;
    slot.radius = radius;
    slot.glass = glass;
    return slot;
}

// 本轮写下的 transform 与放开的裁剪；每轮同步先还原再按原生几何重算。
@interface DKChatTopLayout : NSObject
@property (nonatomic, strong) NSArray<DKChatTopSlot *> *slots;
@property (nonatomic, strong) NSHashTable<UIView *> *moved;
@property (nonatomic, strong) NSMapTable<UIView *, NSNumber *> *clips;
@property (nonatomic, weak) UIView *onlineDot;
- (void)reset;
- (void)allowOverflow:(UIView *)view;
- (void)move:(UIView *)view content:(CGRect)content to:(CGPoint)target scale:(CGFloat)scale carrier:(UIView *)carrier;
@end
@implementation DKChatTopLayout
- (instancetype)init {
    if ((self = [super init])) {
        _moved = [NSHashTable weakObjectsHashTable];
        _clips = [NSMapTable weakToStrongObjectsMapTable];
    }
    return self;
}
- (void)reset {
    DKAdjustAlpha(self.onlineDot, 1.0);
    self.onlineDot = nil;
    for (UIView *view in self.moved) DKAdjustTransform(view, CGAffineTransformIdentity);
    [self.moved removeAllObjects];
    for (UIView *view in self.clips) if (!view.clipsToBounds) view.clipsToBounds = [[self.clips objectForKey:view] boolValue];
    [self.clips removeAllObjects];
    self.slots = nil;
}
- (void)allowOverflow:(UIView *)view {
    if (!view || [self.clips objectForKey:view]) return;
    [self.clips setObject:@(view.clipsToBounds) forKey:view];
    view.clipsToBounds = NO;
}
// content（carrier 坐标）按 scale 缩放后中心落到 target；缩放绕视图自身中心，平移量据此换算。
- (void)move:(UIView *)view content:(CGRect)content to:(CGPoint)target scale:(CGFloat)scale carrier:(UIView *)carrier {
    UIView *parent = view.superview;
    CGRect frame = [view convertRect:view.bounds toView:parent];
    CGPoint contentCenter = [carrier convertPoint:CGPointMake(CGRectGetMidX(content), CGRectGetMidY(content)) toView:parent];
    target = [carrier convertPoint:target toView:parent];
    CGFloat midX = CGRectGetMidX(frame), midY = CGRectGetMidY(frame);
    CGFloat tx = target.x - midX - scale * (contentCenter.x - midX);
    CGFloat ty = target.y - midY - scale * (contentCenter.y - midY);
    DKAdjustTransform(view, CGAffineTransformMake(scale, 0.0, 0.0, scale, tx, ty));
    [self.moved addObject:view];
    for (UIView *node = view.superview; node && node != carrier; node = node.superview) [self allowOverflow:node];
}
@end

static BOOL DKChatTopVisible(UIView *view) {
    return view && !view.hidden && view.alpha > 0.01 && !CGRectIsEmpty(view.bounds);
}

static CGPoint DKChatTopMid(CGRect rect) {
    return CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
}

static UIView *DKChatTopMenuView(UIView *view) {
    if (view) objc_setAssociatedObject(view, &kDKChatMenuViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return view;
}

// 原生左右容器都是横向栈，只选本行的语义控件。
static NSArray<UIView *> *DKChatTopItems(AWENavigationBar *bar) {
    NSMutableArray *items = [NSMutableArray array];
    for (UIView *container in @[ bar.leftBtnsContainerView ?: bar, bar.rightBtnsContainerView ?: bar ]) {
        for (UIView *view in container.subviews) {
            if (!DKChatTopVisible(view)) continue;
            if (DKChatInputIsKind(view, @"AWEIMNavigationUnreadView")
                || DKChatInputIsKind(view, @"AWEIMMessageListNaviBarTitleView")
                || DKChatInputIsKind(view, @"AWEIMMessageVoipEntranceView")
                || objc_getAssociatedObject(view, &kDKChatMenuViewKey)) [items addObject:view];
        }
    }
    return [items sortedArrayUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return [@([a convertPoint:CGPointZero toView:bar].x) compare:@([b convertPoint:CGPointZero toView:bar].x)];
    }];
}

// 返回按钮实际画出的箭头（carrier 坐标）：原生给图片加了水平偏移，图标里的箭头也不在画布中间。
// 先让按钮排版，首轮同步时 imageView 才有位置；没有位图时退回按钮或图片框。
static CGRect DKChatTopArrowRect(UIButton *button, UIView *carrier) {
    [button layoutIfNeeded];
    UIImageView *icon = button.imageView;
    UIImage *image = icon.image;
    if (!image || CGRectIsEmpty(icon.bounds)) return [button convertRect:button.bounds toView:carrier];
    CGRect pixels = DKImageOpaquePixelRect(image);
    if (CGRectIsNull(pixels)) return [icon convertRect:icon.bounds toView:carrier];
    CGFloat scaleX = CGRectGetWidth(icon.bounds) / (image.size.width * image.scale);
    CGFloat scaleY = CGRectGetHeight(icon.bounds) / (image.size.height * image.scale);
    CGRect visible = CGRectMake(CGRectGetMinX(pixels) * scaleX, CGRectGetMinY(pixels) * scaleY,
                                CGRectGetWidth(pixels) * scaleX, CGRectGetHeight(pixels) * scaleY);
    return [icon convertRect:visible toView:carrier];
}

// 把可见元素放进胶囊的圆端：元素两端的圆心与胶囊端部圆心重合（细长的箭头按中心，数字底板按其圆端）。
static CGRect DKChatTopRoundEnds(CGRect visible, CGFloat height) {
    CGFloat inset = MIN(CGRectGetWidth(visible), CGRectGetHeight(visible)) * 0.5 - height * 0.5;
    return CGRectInset(visible, inset, 0.0);
}

static CGRect DKChatTopContentRect(UIView *source, UIView *carrier) {
    if (DKChatInputIsKind(source, @"AWEIMNavigationUnreadView")) {
        AWEIMNavigationUnreadView *unread = (id)source;
        CGFloat height = CGRectGetHeight(carrier.bounds);
        CGRect rect = CGRectNull;
        if (!DKPrefBool(DKKeyChatRemoveBack)) rect = DKChatTopRoundEnds(DKChatTopArrowRect(unread.backButton, carrier), height);
        if (!DKPrefBool(DKKeyChatRemoveUnread) && DKChatTopVisible(unread.unreadCountView)) {
            CGRect count = [unread.unreadCountView convertRect:unread.unreadCountView.bounds toView:carrier];
            count = DKChatTopRoundEnds(count, height);
            rect = CGRectIsNull(rect) ? count : CGRectUnion(rect, count);
        }
        return rect;
    }
    return [source convertRect:source.bounds toView:carrier];
}

static BOOL DKChatTopIsTrailing(UIView *source) {
    return DKChatInputIsKind(source, @"AWEIMMessageVoipEntranceView") || objc_getAssociatedObject(source, &kDKChatMenuViewKey);
}

// 返回胶囊的内容区已含两端圆角，无数字时为正圆；通话与菜单为正圆。
static CGFloat DKChatTopButtonWidth(UIView *source, CGRect content, CGFloat height) {
    return DKChatInputIsKind(source, @"AWEIMNavigationUnreadView") ? CGRectGetWidth(content) : height;
}

// 栈里可见排列项在 carrier 中的并集；没有可见项时为 CGRectNull。
// 原生先排标题视图、后排内层栈，文字变长而标题尺寸不变时排列项还是旧宽度，先让栈排版再读。
static CGRect DKChatTopArrangedRect(UIStackView *stack, UIView *excluded, UIView *carrier, NSMutableArray *views) {
    CGRect rect = CGRectNull;
    if (!DKChatTopVisible(stack)) return rect;
    [stack layoutIfNeeded];
    for (UIView *view in stack.arrangedSubviews) {
        if (view == excluded || !DKChatTopVisible(view)) continue;
        [views addObject:view];
        rect = CGRectUnion(rect, [view convertRect:view.bounds toView:carrier]);
    }
    return rect;
}

#pragma mark 默认排列

// 拆分原生标题栈，头像保留独立的点击和在线标记。
static NSArray<UIView *> *DKChatTopSources(NSArray<UIView *> *items, UIView **information) {
    NSMutableArray *sources = [NSMutableArray array];
    for (UIView *item in items) {
        if (DKChatInputIsKind(item, @"AWEIMMessageListNaviBarTitleView")) {
            AWEIMMessageListNaviBarTitleView *title = (id)item;
            if (DKChatTopVisible(title.avatarStackView)) [sources addObject:title.avatarStackView];
            if (DKChatTopVisible(title.titleContainerStackView)) {
                [sources addObject:title.titleContainerStackView];
                *information = title.titleContainerStackView;
            }
        } else [sources addObject:item];
    }
    return sources;
}

// 返回、头像、信息胶囊从左排起，通话与菜单贴右；信息胶囊在剩余宽度内收放，短标题留下的空间在它与右侧之间。
static CGFloat DKChatTopDefaultLayout(DKChatTopLayout *layout, AWENavigationBar *bar, UIView *carrier) {
    CGRect row = carrier.bounds;
    CGFloat height = CGRectGetHeight(row);
    UIView *information = nil;
    NSMutableArray<UIView *> *sources = [NSMutableArray array];
    NSMutableArray<NSValue *> *contents = [NSMutableArray array];
    NSMutableArray<NSNumber *> *widths = [NSMutableArray array];
    CGFloat fixed = 0.0;
    for (UIView *source in DKChatTopSources(DKChatTopItems(bar), &information)) {
        CGRect content = DKChatTopContentRect(source, carrier);
        if (CGRectIsNull(content) || CGRectIsEmpty(content)) continue;
        CGFloat width = source == information ? MAX(height, CGRectGetWidth(content) + kDKChatTopGap * 2.0)
                                              : DKChatTopButtonWidth(source, content, height);
        if (source != information) fixed += width;
        [sources addObject:source];
        [contents addObject:[NSValue valueWithCGRect:content]];
        [widths addObject:@(width)];
    }
    CGFloat gaps = MAX(0.0, (CGFloat)sources.count - 1.0) * kDKChatTopGap;
    CGFloat available = CGRectGetWidth(row) - kDKChatTopGap * 2.0 - fixed - gaps;
    CGFloat used = gaps;
    for (NSUInteger i = 0; i < sources.count; i++) {
        if (sources[i] == information) widths[i] = @(MAX(0.0, MIN(widths[i].doubleValue, available)));
        used += widths[i].doubleValue;
    }
    CGFloat trailing = CGRectGetWidth(row) - kDKChatTopGap * 2.0 - used;
    NSMutableArray *slots = [NSMutableArray array];
    CGFloat x = kDKChatTopGap;
    for (NSUInteger i = 0; i < sources.count; i++) {
        UIView *source = sources[i];
        CGFloat width = widths[i].doubleValue;
        CGRect frame = CGRectMake(x + (DKChatTopIsTrailing(source) ? trailing : 0.0), CGRectGetMinY(row), width, height);
        [layout move:source content:contents[i].CGRectValue to:DKChatTopMid(frame) scale:1.0 carrier:carrier];
        [slots addObject:DKChatTopSlotMake(source, frame, height * 0.5, YES)];
        x += width + kDKChatTopGap;
    }
    layout.slots = slots;
    return CGRectGetMaxY(row);
}

#pragma mark 居中头像

static UIView *DKChatTopOnlineDot(UIView *avatar) {
    if (DKChatInputIsKind(avatar, @"AWEIMActiveUserIndicativeView")) return avatar;
    for (UIView *child in avatar.subviews) {
        UIView *dot = DKChatTopOnlineDot(child);
        if (dot) return dot;
    }
    return nil;
}

BOOL DKChatTopOnlineDotAway(UIView *dot) {
    for (UIView *node = dot.superview; node; node = node.superview) {
        DKChatTopLayout *layout = objc_getAssociatedObject(node, &kDKChatTopLayoutKey);
        if (layout) return layout.onlineDot == dot;
    }
    return NO;
}

static DKChatTopPlace DKChatTopPlaceOfKey(NSString *key) {
    NSInteger value = DKPrefInteger(key);
    return value == DKChatTopPlaceLeft || value == DKChatTopPlaceRight ? (DKChatTopPlace)value : DKChatTopPlaceCenter;
}

// 返回贴左、通话与菜单贴右；头像居中放大，名称胶囊在下方，火花与在线按设置进名称胶囊或两侧胶囊。
static CGFloat DKChatTopCenterLayout(DKChatTopLayout *layout, AWENavigationBar *bar, UIView *carrier) {
    CGRect row = carrier.bounds;
    CGFloat height = CGRectGetHeight(row);
    NSMutableArray *slots = [NSMutableArray array];
    NSMutableArray<UIView *> *trailing = [NSMutableArray array];
    AWEIMMessageListNaviBarTitleView *title = nil;
    CGFloat leftEdge = kDKChatTopGap;
    for (UIView *item in DKChatTopItems(bar)) {
        if (DKChatInputIsKind(item, @"AWEIMMessageListNaviBarTitleView")) { title = (id)item; continue; }
        if (DKChatTopIsTrailing(item)) { [trailing addObject:item]; continue; }
        CGRect content = DKChatTopContentRect(item, carrier);
        if (CGRectIsNull(content) || CGRectIsEmpty(content)) continue;
        CGRect frame = CGRectMake(leftEdge, CGRectGetMinY(row), DKChatTopButtonWidth(item, content, height), height);
        [layout move:item content:content to:DKChatTopMid(frame) scale:1.0 carrier:carrier];
        [slots addObject:DKChatTopSlotMake(item, frame, height * 0.5, YES)];
        leftEdge = CGRectGetMaxX(frame) + kDKChatTopGap;
    }
    CGFloat rightEdge = CGRectGetMaxX(row) - kDKChatTopGap;
    for (UIView *item in trailing.reverseObjectEnumerator) {
        CGRect content = DKChatTopContentRect(item, carrier);
        if (CGRectIsEmpty(content)) continue;
        CGRect frame = CGRectMake(rightEdge - height, CGRectGetMinY(row), height, height);
        [layout move:item content:content to:DKChatTopMid(frame) scale:1.0 carrier:carrier];
        [slots addObject:DKChatTopSlotMake(item, frame, height * 0.5, YES)];
        rightEdge = CGRectGetMinX(frame) - kDKChatTopGap;
    }
    layout.slots = slots;
    if (!title) return CGRectGetMaxY(row);

    UIView *avatar = DKChatTopVisible(title.avatarStackView) ? title.avatarStackView : nil;
    UIView *streak = nil;
    for (UIView *view in title.mainTitleStackView.arrangedSubviews) {
        if (DKChatInputIsKind(view, @"AWEIMStreakFlameView") && DKChatTopVisible(view)) streak = view;
    }
    NSMutableArray<UIView *> *names = [NSMutableArray array];
    CGRect nameRect = DKChatTopArrangedRect(title.mainTitleStackView, streak, carrier, names);
    CGRect onlineRect = DKChatTopArrangedRect(title.subtitleStackView, nil, carrier, [NSMutableArray array]);
    CGRect streakRect = streak ? [streak convertRect:streak.bounds toView:carrier] : CGRectNull;
    UIView *online = CGRectIsNull(onlineRect) ? nil : title.subtitleStackView;
    UIView *dot = DKChatTopOnlineDot(avatar);
    CGFloat dotSide = DKChatTopVisible(dot) && online ? CGRectGetHeight(onlineRect) * 0.65 : 0.0;
    CGFloat dotGap = dotSide > 0.0 ? kDKChatTopGap * 0.5 : 0.0;
    layout.onlineDot = dot;
    DKAdjustAlpha(dot, online ? 1.0 : 0.0);

    DKChatTopCenterSpec spec = {0};
    spec.row = row;
    spec.leftEdge = leftEdge;
    spec.rightEdge = rightEdge;
    spec.avatarSide = kDKChatTopAvatarSide;
    spec.name = CGRectIsNull(nameRect) ? CGSizeZero : nameRect.size;
    spec.streak.size = streak ? streakRect.size : CGSizeZero;
    spec.streak.place = DKChatTopPlaceOfKey(DKKeyChatTopStreakPosition);
    spec.online.size = online ? onlineRect.size : CGSizeZero;
    spec.online.size.width += dotSide + dotGap;
    spec.online.place = DKChatTopPlaceOfKey(DKKeyChatTopOnlinePosition);
    DKChatTopCenterFrames frames = DKChatTopCenterFramesMake(spec);

    if (avatar) {
        CGRect content = [avatar convertRect:avatar.bounds toView:carrier];
        CGFloat scale = CGRectGetWidth(frames.avatar) / MAX(1.0, CGRectGetWidth(content));
        [layout move:avatar content:content to:DKChatTopMid(frames.avatar) scale:scale carrier:carrier];
        [slots insertObject:DKChatTopSlotMake(avatar, frames.avatar, CGRectGetWidth(frames.avatar) * 0.5, NO) atIndex:0];
    }
    for (UIView *view in names) [layout move:view content:nameRect to:frames.nameCenter scale:1.0 carrier:carrier];
    if (names.count) {
        [slots addObject:DKChatTopSlotMake(title.mainTitleStackView, frames.capsule, frames.capsuleRadius, YES)];
    }
    if (streak) [layout move:streak content:streakRect to:frames.streak.center scale:frames.streak.scale carrier:carrier];
    if (online) {
        CGPoint textCenter = frames.online.center;
        textCenter.x += (dotSide + dotGap) * frames.online.scale * 0.5;
        [layout move:online content:onlineRect to:textCenter scale:frames.online.scale carrier:carrier];
        if (dotSide > 0.0) {
            CGRect dotRect = [dot convertRect:dot.bounds toView:carrier];
            CGPoint dotCenter = frames.online.center;
            dotCenter.x -= (CGRectGetWidth(onlineRect) + dotGap) * frames.online.scale * 0.5;
            [layout move:dot content:dotRect to:dotCenter
                   scale:dotSide * frames.online.scale / MAX(1.0, CGRectGetWidth(dotRect)) carrier:carrier];
        }
    }
    // 两侧胶囊以靠上的一项为身份：同侧合并时火花在上。
    for (NSNumber *place in @[ @(DKChatTopPlaceLeft), @(DKChatTopPlaceRight) ]) {
        CGRect frame = place.integerValue == DKChatTopPlaceLeft ? frames.left : frames.right;
        if (CGRectIsNull(frame) || CGRectIsEmpty(frame)) continue;
        UIView *source = streak && spec.streak.place == place.integerValue ? streak : online;
        [slots addObject:DKChatTopSlotMake(source, frame, CGRectGetHeight(frame) * 0.5, YES)];
    }
    layout.slots = slots;
    return MAX(CGRectGetMaxY(row), CGRectGetMaxY(names.count ? frames.capsule : frames.avatar));
}

#pragma mark 同步

static BOOL DKChatTopCentered(void) {
    return DKPrefInteger(DKKeyChatTopCenter) == 1;
}

// 聊天页布局模块里的原生组件。
static id DKChatPageComponent(UIViewController *host, NSString *moduleName, NSString *componentName) {
    id manager = DKChatInputObjectIvar(host, "_componentManager");
    for (id module in ((AWEIMComponentManager *)manager).components) {
        if (!DKChatInputIsKind(module, moduleName)) continue;
        id children = DKChatInputObjectIvar(module, "componentManager");
        for (id child in ((AWEIMComponentManager *)children).components) {
            if (DKChatInputIsKind(child, componentName)) return child;
        }
    }
    return nil;
}

static UITableView *DKChatTopTable(UIViewController *host) {
    UIViewController *list = ((AWEIMMessageBaseViewController *)host).messageListVC;
    if (!DKChatInputIsKind(list, @"AWEIMMessageListViewController") || !list.isViewLoaded) return nil;
    return ((AWEIMMessageListViewController *)list).tableView;
}

CGFloat DKChatTopHeaderExtra(UIViewController *host) {
    return host ? [objc_getAssociatedObject(host, &kDKChatTopExtraKey) doubleValue] : 0.0;
}

// 顶部区域比原生导航高出 extra 时，导航下方的群功能栏与顶部浮条整体下移，消息列表上沿随之让位。
static NSArray<UIView *> *DKChatTopExtraViews(UIViewController *host) {
    if (!host.isViewLoaded) return @[];
    NSMutableArray *views = [NSMutableArray array];
    AWEIMMessageListTopFloatingComponent *floating =
        DKChatPageComponent(host, @"IESIMConversationTopFloatingTipsModule", @"AWEIMMessageListTopFloatingComponent");
    for (UIView *child in host.view.subviews) {
        if (DKChatInputIsKind(child, @"AWEIMGroupImpl.GroupZoneEntryBarView") || child == floating.topFloatingContainer) {
            [views addObject:child];
        }
    }
    return views;
}

static void DKChatTopApplyExtra(UIViewController *host, CGFloat extra) {
    if (!host.isViewLoaded) return;
    CGFloat previous = DKChatTopHeaderExtra(host);
    if (extra <= 0.0 && previous <= 0.0) return;
    for (UIView *view in DKChatTopExtraViews(host)) {
        DKAdjustTransform(view, CGAffineTransformMakeTranslation(0.0, MAX(0.0, extra)));
    }
    if (fabs(previous - extra) < 0.5) return;
    objc_setAssociatedObject(host, &kDKChatTopExtraKey, extra > 0.0 ? @(extra) : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKChatInputListRefresh();
}

void DKChatTopBarSync(UIView *view) {
    if (@available(iOS 26.0, *)) {
        AWENavigationBar *bar = (id)view;
        UIViewController *input = DKChatInputControllerForPageView(bar);
        UIViewController *host = input.parentViewController;
        if (objc_getAssociatedObject(host, &kDKChatTopNativeLayoutKey)) return;
        DKChatTopLayout *layout = objc_getAssociatedObject(bar, &kDKChatTopLayoutKey);
        if (!DKChatInputGlassWanted(input)) {
            UIView *dot = layout.onlineDot;
            [layout reset];
            objc_setAssociatedObject(bar, &kDKChatTopLayoutKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            DKChatTopAvatarNotchSync(dot);
            [DKChatGlassStore removeStoreForOwner:bar];
            DKChatTopBlurSync(bar, nil, 0.0, UIUserInterfaceStyleUnspecified, NO);
            DKChatTopApplyExtra(host, 0.0);
            return;
        }
        DKChatGlassStore *store = [DKChatGlassStore storeForOwner:bar create:YES];
        if (store.syncing || CGRectIsEmpty(bar.contentView.bounds)) return;
        if (!layout) {
            layout = [DKChatTopLayout new];
            objc_setAssociatedObject(bar, &kDKChatTopLayoutKey, layout, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        __block CGFloat bottom = 0.0;
        UIView *previousDot = layout.onlineDot;
        [store beginWithClear:DKPrefBool(DKKeyChatInputGlassClear) style:DKChatInputStyle(input)];
        [UIView performWithoutAnimation:^{
            [layout reset];
            UIView *carrier = bar.contentView;
            [layout allowOverflow:bar];
            [layout allowOverflow:carrier];
            [store clearBackingOfView:bar];
            [store clearBackingOfView:carrier];
            [store clearBackingOfView:bar.bottomLineView];
            CGFloat carrierBottom = DKChatTopCentered() ? DKChatTopCenterLayout(layout, bar, carrier)
                                                        : DKChatTopDefaultLayout(layout, bar, carrier);
            bottom = [carrier convertPoint:CGPointMake(0.0, carrierBottom) toView:bar].y;
            for (DKChatTopSlot *slot in layout.slots) {
                if (!slot.glass) continue;
                UIView *source = slot.source;
                [store clearBackingOfView:source];
                if (DKChatInputIsKind(source, @"AWEIMNavigationUnreadView")) {
                    AWEIMNavigationUnreadView *unread = (id)source;
                    [store clearBackingOfView:unread.unreadCountView];
                    [store clearFillOfShapeLayer:unread.dotLayer];
                }
                [store placeGlassFor:source in:carrier frame:slot.frame shape:DKChatGlassShapeRounded
                             radius:slot.radius interactive:YES tint:nil];
            }
        }];
        [store end];
        // 圆点被居中布局接管或交还时，头像缺口随之撤掉或挂回。
        DKChatTopAvatarNotchSync(previousDot);
        if (layout.onlineDot != previousDot) DKChatTopAvatarNotchSync(layout.onlineDot);
        DKChatTopApplyExtra(host, MAX(0.0, bottom - CGRectGetHeight(bar.bounds)));
        DKChatTopBlurSync(bar, DKChatTopTable(host), bottom, DKChatInputStyle(input), DKPrefBool(DKKeyChatTopBlur));
    }
}

// 顶栏在原生动画事务里回到原位置再移回时，只清理本轮新增且最终屏幕几何未变的动画。
static dispatch_block_t DKChatTopGeometrySweeper(UIView *view) {
    UIView *parent = view.superview;
    CGRect before = [view convertRect:view.bounds toView:parent];
    NSArray *keys = view.layer.animationKeys ?: @[];
    return ^{
        if (view.superview != parent || !CGRectEqualToRect(before, [view convertRect:view.bounds toView:parent])) return;
        for (NSString *key in view.layer.animationKeys) {
            CAAnimation *animation = [view.layer animationForKey:key];
            if ([keys containsObject:key] || ![animation isKindOfClass:CAPropertyAnimation.class]) continue;
            NSString *path = ((CAPropertyAnimation *)animation).keyPath;
            if ([path isEqualToString:@"position"] || [path hasPrefix:@"bounds"] || [path hasPrefix:@"transform"]) {
                [view.layer removeAnimationForKey:key];
            }
        }
    };
}

void DKChatTopBarNativeLayout(UIViewController *host, dispatch_block_t nativeLayout) {
    if (!host || objc_getAssociatedObject(host, &kDKChatTopNativeLayoutKey)) { nativeLayout(); return; }
    NSMutableArray<dispatch_block_t> *sweepers = [NSMutableArray array];
    NSMutableArray<AWENavigationBar *> *bars = [NSMutableArray array];
    for (AWEIMMessageListNaviBarComponent *component in gDKChatNaviComponents.allObjects) {
        if (component.context.hostViewController != host) continue;
        AWENavigationBar *bar = component.naviBar;
        DKChatTopLayout *layout = objc_getAssociatedObject(bar, &kDKChatTopLayoutKey);
        if (!layout) continue;
        [bars addObject:bar];
        NSHashTable *views = [NSHashTable weakObjectsHashTable];
        for (UIView *moved in layout.moved) {
            for (UIView *view = moved; view && view != bar; view = view.superview) [views addObject:view];
        }
        for (UIView *view in views) [sweepers addObject:DKChatTopGeometrySweeper(view)];
    }
    if (!bars.count) { nativeLayout(); return; }
    objc_setAssociatedObject(host, &kDKChatTopNativeLayoutKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [UIView performWithoutAnimation:^{
        for (UIView *bar in bars) [(DKChatTopLayout *)objc_getAssociatedObject(bar, &kDKChatTopLayoutKey) reset];
        for (UIView *view in DKChatTopExtraViews(host)) DKAdjustTransform(view, CGAffineTransformIdentity);
    }];
    nativeLayout();
    objc_setAssociatedObject(host, &kDKChatTopNativeLayoutKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (UIView *bar in bars) DKChatTopBarSync(bar);
    for (dispatch_block_t sweep in sweepers) sweep();
}

// 落在槽位里的触摸交给槽位的原生视图：原生命中已在它里面时沿用；不可交互的原生内容（火花等）
// 直接作为命中视图，由祖先上的原生手势处理；原生禁用或隐藏时不接。
static UIView *DKChatTopTouchView(UIView *source, UIView *bar, UIView *carrier, UIEvent *event) {
    for (UIView *node = source; node && node != bar; node = node.superview) {
        if (node.hidden || node.alpha <= 0.01) return nil;
        if (node != source && !node.userInteractionEnabled) return nil;
    }
    if (!source.userInteractionEnabled) return source;
    CGPoint center = DKChatTopMid(DKChatTopContentRect(source, carrier));
    return [source hitTest:[carrier convertPoint:center toView:source] withEvent:event] ?: source;
}

static DKChatTopSlot *DKChatTopSlotAtPoint(AWENavigationBar *bar, CGPoint point) {
    if (!DKChatInputGlassWanted(DKChatInputControllerForPageView(bar))) return nil;
    DKChatTopLayout *layout = objc_getAssociatedObject(bar, &kDKChatTopLayoutKey);
    CGPoint local = [bar convertPoint:point toView:bar.contentView];
    for (DKChatTopSlot *slot in layout.slots) {
        if (slot.source && CGRectContainsPoint(slot.frame, local)) return slot;
    }
    return nil;
}

// 玻璃放在滚动列表后方，原生 cell 复用与过渡快照只承载内容。
static void DKChatGroupBarSync(UIView *bar, UICollectionViewCell *pendingCell) {
    if (@available(iOS 26.0, *)) {
        UIViewController *input = DKChatInputControllerForPageView(bar);
        if (!DKChatInputGlassWanted(input) || DKPrefBool(DKKeyChatRemoveMenu) || !DKChatTopVisible(bar)) {
            [DKChatGlassStore removeStoreForOwner:bar];
            return;
        }
        DKChatGlassStore *store = [DKChatGlassStore storeForOwner:bar create:YES];
        if (store.syncing) return;
        [store beginWithClear:DKPrefBool(DKKeyChatInputGlassClear) style:DKChatInputStyle(input)];
        [UIView performWithoutAnimation:^{
            [store clearBackingOfView:bar];
            for (UIView *child in bar.subviews.copy) {
                if (![child isKindOfClass:UICollectionView.class]) continue;
                [store clearBackingOfView:child];
                NSMutableArray *cells = [((UICollectionView *)child).visibleCells mutableCopy];
                if (pendingCell.superview == child && ![cells containsObject:pendingCell]) [cells addObject:pendingCell];
                for (UICollectionViewCell *cell in cells) {
                    if (!DKChatTopVisible(cell)) continue;
                    [store clearBackingOfView:cell];
                    [store clearBackingOfView:cell.contentView];
                    CGRect frame = [cell.contentView convertRect:cell.contentView.bounds toView:bar];
                    [store placeGlassFor:cell in:bar frame:frame shape:DKChatGlassShapeRounded
                                 radius:CGRectGetHeight(frame) * 0.5 interactive:YES tint:nil];
                }
            }
        }];
        [store end];
    }
}

static void DKChatGroupItemSync(UIView *cell) {
    for (UIView *bar = cell.superview; bar; bar = bar.superview) {
        if (!DKChatInputIsKind(bar, @"AWEIMGroupImpl.GroupZoneEntryBarView")) continue;
        DKChatGroupBarSync(bar, (id)cell);
        break;
    }
}

static void DKChatTopSyncAncestorBar(UIView *view) {
    for (UIView *bar = view.superview; bar; bar = bar.superview) {
        if (!DKChatInputIsKind(bar, @"AWENavigationBar")) continue;
        DKChatTopBarSync(bar);
        break;
    }
}

void DKChatTopBarRefresh(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DKChatTopBarRefresh(); }); return; }
    DKChatTopCleanRefresh();
    for (AWEIMMessageListNaviBarComponent *component in gDKChatNaviComponents.allObjects) {
        if (!DKChatInputController(component)) continue;
        UIViewController *host = component.context.hostViewController;
        [component setNeedsUpdateNaviBar];
        [component.naviBarTitleService setNeedsUpdateNaviBarTitle];
        AWEIMMessageListLayoutComponent *page =
            DKChatPageComponent(host, @"IESIMConversationLayoutModule", @"AWEIMMessageListLayoutComponent");
        [page p_layoutWithAnimation:NO coordinate:nil];
        [component.naviBar setNeedsLayout];
        [component.naviBar layoutIfNeeded];
        DKChatTopBarSync(component.naviBar);
        for (UIView *child in host.view.subviews) {
            if (DKChatInputIsKind(child, @"AWEIMGroupImpl.GroupZoneEntryBarView")) DKChatGroupBarSync(child, nil);
        }
    }
}

static void DKChatTopPageSync(UIViewController *host) {
    for (AWEIMMessageListNaviBarComponent *component in gDKChatNaviComponents.allObjects) {
        if (component.context.hostViewController == host) DKChatTopBarSync(component.naviBar);
    }
}

// 通用导航也被设置页复用，以普通聊天宿主和独立 store 限定处理范围。
%group DKChatTopGlassHooks
%hook AWENavigationBar
- (void)layoutSubviews { %orig; DKChatTopBarSync(self); }
- (void)didMoveToWindow { %orig; DKChatTopBarSync(self); }
// 居中后名称胶囊超出导航底边，槽位内的点也算在导航内。
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return %orig || DKChatTopSlotAtPoint(self, point) != nil;
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = %orig;
    if (!DKChatInputGlassWanted(DKChatInputControllerForPageView(self))) return hit;
    DKChatTopSlot *slot = DKChatTopSlotAtPoint(self, point);
    if (!slot) return nil;
    if ([hit isDescendantOfView:slot.source]) return hit;
    return DKChatTopTouchView(slot.source, self, self.contentView, event);
}
%end
%hook AWEIMMessageListNaviBarBackAndUnreadCountComponent
- (double)naviBarViewCustomSpacing {
    double spacing = %orig;
    return DKChatInputGlassWanted(DKChatInputController(self)) ? spacing + kDKChatTopGap : spacing;
}
%end
%hook AWEIMMessageListNaviBarGroupZoneToggleComponent
- (UIView *)naviBarView { return DKChatTopMenuView(%orig); }
%end
%hook AWEIMMessageListNaviBarChatDetailComponent
- (UIView *)naviBarView { return DKChatTopMenuView(%orig); }
%end
%hook AWEIMNavigationUnreadView
- (void)p_updateUI { %orig; DKChatTopSyncAncestorBar(self); }
%end
// 火花提示动画与在线文字变化只重排标题栈，不一定经过导航布局。
%hook AWEIMMessageListNaviBarTitleView
- (void)layoutSubviews { %orig; DKChatTopSyncAncestorBar(self); }
%end
%hook DKChatGroupEntryBar
- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)path {
    %orig;
    DKChatGroupBarSync(self, nil);
}
- (void)layoutSubviews { %orig; DKChatGroupBarSync(self, nil); }
- (void)didMoveToWindow { %orig; DKChatGroupBarSync(self, nil); }
- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)path {
    %orig;
    DKChatGroupItemSync(cell);
}
%end
%hook DKChatGroupEntryCell
- (void)layoutSubviews { %orig; DKChatGroupItemSync(self); }
- (void)didMoveToWindow { %orig; DKChatGroupItemSync(self); }
%end
%end

%group DKChatTopLifecycleHooks
%hook AWEIMMessageListNaviBarComponent
- (void)p_setupNaviBar {
    %orig;
    [gDKChatNaviComponents addObject:self];
}
- (void)messageListBackgroundImageDidUpdated:(id)info { %orig; DKChatTopBarSync(self.naviBar); }
%end
%hook AWEIMMessageBaseViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [UIView performWithoutAnimation:^{ DKChatTopBarRefresh(); DKChatTopPageSync(self); }];
}
- (void)viewDidLayoutSubviews { %orig; DKChatTopPageSync(self); }
%end
%end

%ctor {
    gDKChatNaviComponents = [NSHashTable weakObjectsHashTable];
    DKSettingsRegister(DKKeyChatTopBlur, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(DKKeyChatTopBlur, @"顶部渐变模糊",
            @"消息滑到聊天页顶部时逐渐模糊：从顶栏胶囊底边开始向上加深，居中显示头像时从名称胶囊底边开始；群功能栏不在模糊范围内。");
        DKSettingsOnChange(item, ^{ DKChatTopBarRefresh(); });
        return item;
    });
    DKSettingsRegister(DKKeyChatTopCenter, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKSettingsWithInfo(DKMakeChoice(DKKeyChatTopCenter, @"居中显示聊天头像", @[ @"默认", @"居中" ]),
            @"居中：头像放大居中，名称胶囊在头像下方，火花与在线信息按下方两项设置摆放；返回、通话与菜单仍在两侧。默认：保持返回、头像、名称、通话、菜单从左到右排列。");
        DKSettingsOnChange(item, ^{ DKChatTopBarRefresh(); });
        return item;
    });
    NSArray *places = @[ @"居中", @"左侧", @"右侧" ];
    NSString *placeInfo = @"居中时并入名称胶囊；左侧放在返回按钮右侧，右侧放在通话按钮左侧。火花与在线信息在同一侧时合并为一个胶囊，火花在上；"
                          @"空间不足时自动缩小字号以完整显示，移除顶栏按钮后空间变大则恢复原字号。";
    for (NSArray *row in @[ @[ DKKeyChatTopStreakPosition, @"火花位置" ], @[ DKKeyChatTopOnlinePosition, @"在线信息位置" ] ]) {
        DKSettingsRegister(row[0], ^AWESettingItemModel *{
            AWESettingItemModel *item = DKSettingsWithInfo(DKMakeChoice(row[0], row[1], places), placeInfo);
            DKSettingsOnChange(item, ^{ DKChatTopBarRefresh(); });
            return item;
        });
    }
    %init(DKChatTopLifecycleHooks);
    if (DKGlassOSAvailable()) {
        %init(DKChatTopGlassHooks,
            DKChatGroupEntryBar = NSClassFromString(@"AWEIMGroupImpl.GroupZoneEntryBarView"),
            DKChatGroupEntryCell = NSClassFromString(@"AWEIMGroupImpl.GroupZoneEntryItemCell"));
    }
}
