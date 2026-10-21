//
//  DKGlassPadElements.xm
//  iPad 紧凑底栏：玻璃组的位置（默认 / 左端 / 右端）与两侧元素按钮（连播 / 弹幕 / 倍速等）的液态玻璃。
//
//  元素按钮（AWETabBarElementButton）的图标、文字、选中与折叠态全部由抖音绘制，这里只做三件事：
//  · 分段：相邻的纯图标按钮合成一个胶囊，带文字的按钮各自成胶囊，单个纯图标为圆；
//  · 落位：按位置设置重排容器与按钮原点，宽度保持抖音按当前文案算出的值；
//  · 材质：玻璃垫在容器下方，按钮自带的半透明底色在玻璃期间置透明。
//
//  写入点（40.7.0 iPad 实测，见 docs/ipad-tabbar-position.md）：容器 frame 由底栏 layoutSubviews 写入，
//  scrollView 与按钮 frame 由容器 p_refreshLayout 写入。容器 frame 在写入点换成方案值，避免每轮布局
//  原生值与方案值来回切换引起容器重排；容器内部在 p_refreshLayout 之后按方案补写。
//

#import "DKGlassPadElements.h"
#import "DKGlassTabBar.h"
#import "DKGlassFlexView.h"
#import "DKGlassGuard.h"
#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"

#import <math.h>
#import <objc/runtime.h>

typedef NS_ENUM(NSInteger, DKPadBarPosition) {
    DKPadBarPositionDefault = 0,
    DKPadBarPositionLeft = 1,
    DKPadBarPositionRight = 2,
};

// 合并胶囊里相邻图标的间距：HIG 最小触控尺寸。
static const CGFloat kDKPadIconPitch = 44.0;
// 相邻两块玻璃、玻璃组与按钮之间的间距；与胶囊到拍摄圆键的间距一致。
static const CGFloat kDKPadSegmentGap = 12.0;
// 贴边距下限：原生两侧容器距屏幕边缘的距离（40.7.0 实测）。
static const CGFloat kDKPadMinEdgeMargin = 16.0;

static char kDKPadContainerFrameKey;   // 容器在底栏内的方案 frame
static char kDKPadButtonFrameKey;      // 按钮在 scrollView 内的方案 frame
static char kDKPadButtonSlotKey;       // 按钮命中区（按钮自身坐标）
static char kDKPadHostBackgroundKey;   // 接管前的宿主底色（NSNull 表示 nil）
static char kDKPadGlassViewsKey;       // 底栏上的元素玻璃
static char kDKPadGlassSignatureKey;   // 玻璃当前材质的签名

static __weak UIView *gPadLastBar = nil;
static CGRect gPadLastGroupFrame;
static NSUInteger gPadLayoutCount = 0;
static NSUInteger gPadInnerApplyCount = 0;
static NSUInteger gPadRelayoutRequests = 0;
static NSUInteger gPadFallbackCount = 0;

static BOOL DKPadIsPad(void) {
    return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad;
}

static DKPadBarPosition DKPadPreferredPosition(void) {
    NSInteger value = DKPrefInteger(DKKeyGlassTabBarPadPosition);
    return (value == DKPadBarPositionLeft || value == DKPadBarPositionRight)
        ? (DKPadBarPosition)value : DKPadBarPositionDefault;
}

#pragma mark - 采集

// 左右两个容器，按视觉顺序；类结构不符时为空。
static NSArray<AWETabBarElementContainerView *> *DKPadContainers(UIView *bar) {
    if (![bar respondsToSelector:@selector(leftElementContainerView)]
        || ![bar respondsToSelector:@selector(rightElementContainerView)]) return @[];
    NSMutableArray *containers = [NSMutableArray arrayWithCapacity:2];
    for (id container in @[ ((AWENormalModeTabBar *)bar).leftElementContainerView ?: NSNull.null,
                            ((AWENormalModeTabBar *)bar).rightElementContainerView ?: NSNull.null ]) {
        if (![container isKindOfClass:UIView.class] || ((UIView *)container).superview != bar) continue;
        if (![container respondsToSelector:@selector(scrollView)]
            || ![container respondsToSelector:@selector(elementButtons)]) continue;
        [containers addObject:container];
    }
    return containers;
}

// 当前显示的按钮：复用池里不在当前列表的按钮被抖音设为 hidden。池的顺序即视觉顺序。
static NSArray<UIButton *> *DKPadVisibleButtons(AWETabBarElementContainerView *container) {
    UIScrollView *scroll = container.scrollView;
    if (!scroll || container.hidden) return @[];
    NSMutableArray *buttons = [NSMutableArray array];
    for (id object in container.elementButtons) {
        if (![object isKindOfClass:UIButton.class]) continue;
        UIButton *button = object;
        if (button.hidden || button.alpha < 0.01 || button.superview != scroll
            || CGRectIsEmpty(button.bounds)) continue;
        [buttons addObject:button];
    }
    return buttons;
}

// 按钮此刻是否在显示文字：只看抖音排出来的结果，不复刻折叠规则。
static BOOL DKPadShowsText(UIButton *button) {
    UILabel *label = [button respondsToSelector:@selector(elementLabel)]
        ? ((AWETabBarElementButton *)button).elementLabel : nil;
    return label && !label.hidden && label.alpha > 0.01 && label.text.length > 0
        && CGRectGetWidth(label.bounds) > 0.0;
}

#pragma mark - 方案

@interface DKPadSegment : NSObject
@property (nonatomic, copy) NSArray<UIButton *> *buttons;
@property (nonatomic) BOOL icons;     // 纯图标连成的一段
@property (nonatomic) CGFloat x;      // 底栏坐标
@property (nonatomic) CGFloat width;
@end

@implementation DKPadSegment
@end

typedef struct {
    CGFloat top;      // 玻璃在底栏内的 y，与玻璃胶囊同 top
    CGFloat height;   // 玻璃高，与玻璃胶囊同高
    CGFloat margin;   // 贴边距：与玻璃到屏幕底边的距离相同，不小于原生边距
} DKPadBand;

static DKPadBand DKPadBandFor(UIView *bar, CGRect groupFrame) {
    DKPadBand band = { CGRectGetMinY(groupFrame), CGRectGetHeight(groupFrame), 0.0 };
    band.margin = MAX(kDKPadMinEdgeMargin, CGRectGetHeight(bar.bounds) - CGRectGetMaxY(groupFrame));
    return band;
}

// 玻璃比按钮四周多出的量，使玻璃与按钮同心。
static CGFloat DKPadInset(UIView *button, CGFloat height) {
    return MAX((height - CGRectGetHeight(button.bounds)) / 2.0, 0.0);
}

static NSArray<DKPadSegment *> *DKPadSegments(NSArray<UIButton *> *buttons, CGFloat height) {
    NSMutableArray<DKPadSegment *> *segments = [NSMutableArray array];
    DKPadSegment *run = nil;
    for (UIButton *button in buttons) {
        BOOL icon = !DKPadShowsText(button);
        if (icon && run.icons) {
            run.buttons = [run.buttons arrayByAddingObject:button];
            continue;
        }
        run = [DKPadSegment new];
        run.icons = icon;
        run.buttons = @[ button ];
        [segments addObject:run];
    }
    for (DKPadSegment *segment in segments) {
        UIButton *first = segment.buttons.firstObject;
        segment.width = segment.icons
            ? height + (CGFloat)(segment.buttons.count - 1) * kDKPadIconPitch
            : CGRectGetWidth(first.bounds) + 2.0 * DKPadInset(first, height);
    }
    return segments;
}

static CGFloat DKPadRowWidth(NSArray<DKPadSegment *> *segments) {
    CGFloat width = 0.0;
    for (DKPadSegment *segment in segments) width += segment.width;
    return width + (segments.count > 1 ? (CGFloat)(segments.count - 1) * kDKPadSegmentGap : 0.0);
}

static void DKPadPlaceFrom(NSArray<DKPadSegment *> *segments, CGFloat x) {
    for (DKPadSegment *segment in segments) {
        segment.x = x;
        x += segment.width + kDKPadSegmentGap;
    }
}

static void DKPadPlaceTo(NSArray<DKPadSegment *> *segments, CGFloat maxX) {
    DKPadPlaceFrom(segments, maxX - DKPadRowWidth(segments));
}

// 一轮方案：各段落位与实际生效的位置。靠边后放不下时回到默认落位。
static NSArray<DKPadSegment *> *DKPadPlan(UIView *bar, CGRect groupFrame, DKPadBand band,
                                          DKPadBarPosition *position, BOOL *fellBack) {
    NSArray<AWETabBarElementContainerView *> *containers = DKPadContainers(bar);
    NSMutableArray<NSArray<UIButton *> *> *groups = [NSMutableArray array];
    NSMutableArray<UIButton *> *all = [NSMutableArray array];
    for (AWETabBarElementContainerView *container in containers) {
        NSArray<UIButton *> *buttons = DKPadVisibleButtons(container);
        [groups addObject:buttons];
        [all addObjectsFromArray:buttons];
    }

    CGFloat width = CGRectGetWidth(bar.bounds);
    *position = DKPadPreferredPosition();
    if (*position != DKPadBarPositionDefault) {
        NSArray<DKPadSegment *> *row = DKPadSegments(all, band.height);
        CGFloat need = 2.0 * band.margin + CGRectGetWidth(groupFrame)
            + (row.count ? kDKPadSegmentGap + DKPadRowWidth(row) : 0.0);
        if (need <= width) {
            if (*position == DKPadBarPositionLeft) DKPadPlaceTo(row, width - band.margin);
            else DKPadPlaceFrom(row, band.margin);
            return row;
        }
        *position = DKPadBarPositionDefault;
        if (fellBack) *fellBack = YES;
    }

    // 默认：左容器从左缘向右排，右容器从右缘向左排，两侧各自分段。
    UIView *leftContainer = ((AWENormalModeTabBar *)bar).leftElementContainerView;
    NSMutableArray<DKPadSegment *> *segments = [NSMutableArray array];
    for (NSUInteger i = 0; i < groups.count; i++) {
        NSArray<DKPadSegment *> *side = DKPadSegments(groups[i], band.height);
        if (containers[i] == leftContainer) DKPadPlaceFrom(side, band.margin);
        else DKPadPlaceTo(side, width - band.margin);
        [segments addObjectsFromArray:side];
    }
    return segments;
}

CGFloat DKGlassPadGroupLeft(UIView *douyinBar, CGRect groupFrame) {
    CGFloat centered = CGRectGetMinX(groupFrame);
    if (!DKPadIsPad() || !douyinBar) return centered;
    DKPadBand band = DKPadBandFor(douyinBar, groupFrame);
    DKPadBarPosition position;
    DKPadPlan(douyinBar, groupFrame, band, &position, NULL);
    switch (position) {
        case DKPadBarPositionLeft: return band.margin;
        case DKPadBarPositionRight:
            return CGRectGetWidth(douyinBar.bounds) - band.margin - CGRectGetWidth(groupFrame);
        case DKPadBarPositionDefault: break;
    }
    return centered;
}

#pragma mark - 写入

static BOOL DKPadRectChanged(CGRect a, CGRect b) {
    return fabs(a.origin.x - b.origin.x) > 0.25 || fabs(a.origin.y - b.origin.y) > 0.25
        || fabs(a.size.width - b.size.width) > 0.25 || fabs(a.size.height - b.size.height) > 0.25;
}

// 容器内部：scrollView 铺满容器，按钮按方案原点落位、宽高保持原生。原生宽度与方案不符
// （文案变化）或出现方案外的按钮时，请底栏重算一轮。
static void DKPadApplyInner(AWETabBarElementContainerView *container) {
    if (!objc_getAssociatedObject(container, &kDKPadContainerFrameKey)) return;
    gPadInnerApplyCount++;
    UIScrollView *scroll = container.scrollView;
    CGRect bounds = container.bounds;
    if (DKPadRectChanged(scroll.frame, bounds)) scroll.frame = bounds;
    if (!CGSizeEqualToSize(scroll.contentSize, bounds.size)) scroll.contentSize = bounds.size;
    if (!CGPointEqualToPoint(scroll.contentOffset, CGPointZero)) scroll.contentOffset = CGPointZero;

    BOOL stale = NO;
    for (UIButton *button in DKPadVisibleButtons(container)) {
        NSValue *planned = objc_getAssociatedObject(button, &kDKPadButtonFrameKey);
        if (!planned) {
            stale = YES;
            continue;
        }
        CGRect target = planned.CGRectValue;
        CGRect frame = button.frame;
        if (fabs(CGRectGetWidth(frame) - CGRectGetWidth(target)) > 0.5) stale = YES;
        frame.origin = target.origin;
        if (DKPadRectChanged(button.frame, frame)) button.frame = frame;
    }
    if (stale) {
        gPadRelayoutRequests++;
        [container.superview setNeedsLayout];
    }
}

static void DKPadTakeOverBackground(UIButton *button) {
    if (objc_getAssociatedObject(button, &kDKPadHostBackgroundKey)) return;
    objc_setAssociatedObject(button, &kDKPadHostBackgroundKey, button.backgroundColor ?: (id)NSNull.null,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // 经 setBackgroundColor: 的接管路径写入：记下宿主色、实际写透明。
    button.backgroundColor = button.backgroundColor;
}

static void DKPadRestoreBackground(UIButton *button) {
    id host = objc_getAssociatedObject(button, &kDKPadHostBackgroundKey);
    if (!host) return;
    objc_setAssociatedObject(button, &kDKPadHostBackgroundKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    button.backgroundColor = host == NSNull.null ? nil : host;
}

// 每段的按钮方案：合并段内图标按固定间距排开，命中区按相邻图标中点切分；独立段命中区为整段。
static void DKPadPlanButtons(DKPadSegment *segment, DKPadBand band,
                             NSMapTable<UIButton *, NSValue *> *frames,
                             NSMapTable<UIButton *, NSValue *> *slots) {
    NSUInteger count = segment.buttons.count;
    for (NSUInteger i = 0; i < count; i++) {
        UIButton *button = segment.buttons[i];
        CGSize size = button.bounds.size;
        CGFloat centerX = segment.icons
            ? segment.x + band.height / 2.0 + (CGFloat)i * kDKPadIconPitch
            : segment.x + segment.width / 2.0;
        CGRect frame = CGRectMake(centerX - size.width / 2.0, band.top + (band.height - size.height) / 2.0,
                                  size.width, size.height);
        CGFloat slotMinX = (!segment.icons || i == 0) ? segment.x : centerX - kDKPadIconPitch / 2.0;
        CGFloat slotMaxX = (!segment.icons || i + 1 == count)
            ? segment.x + segment.width : centerX + kDKPadIconPitch / 2.0;
        [frames setObject:[NSValue valueWithCGRect:frame] forKey:button];
        [slots setObject:[NSValue valueWithCGRect:CGRectMake(slotMinX, band.top, slotMaxX - slotMinX, band.height)]
                  forKey:button];
    }
}

static void DKPadSyncGlass(UIView *bar, NSArray<DKPadSegment *> *segments, DKPadBand band,
                           UIView *anchor) API_AVAILABLE(ios(26.0)) {
    NSMutableArray<DKGlassFlexView *> *glasses = objc_getAssociatedObject(bar, &kDKPadGlassViewsKey);
    if (!glasses) {
        glasses = [NSMutableArray array];
        objc_setAssociatedObject(bar, &kDKPadGlassViewsKey, glasses, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    while (glasses.count > segments.count) {
        [glasses.lastObject removeFromSuperview];
        [glasses removeLastObject];
    }

    UIUserInterfaceStyle style = bar.window.windowScene.traitCollection.userInterfaceStyle;
    BOOL clear = DKPrefBool(DKKeyGlassTabBarClear);
    for (NSUInteger i = 0; i < segments.count; i++) {
        DKPadSegment *segment = segments[i];
        if (i == glasses.count) {
            DKGlassFlexView *glass = [[DKGlassFlexView alloc] initWithFrame:CGRectZero];
            glass.userInteractionEnabled = NO;
            glass.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];
            [glasses addObject:glass];
        }
        DKGlassFlexView *glass = glasses[i];
        // 玻璃在两个容器之下；已经在下方就不再挪动层级。
        NSUInteger glassIndex = [bar.subviews indexOfObjectIdenticalTo:glass];
        NSUInteger anchorIndex = [bar.subviews indexOfObjectIdenticalTo:anchor];
        if (glass.superview != bar || glassIndex == NSNotFound || glassIndex > anchorIndex) {
            [bar insertSubview:glass belowSubview:anchor];
        }
        CGRect frame = CGRectMake(segment.x, band.top, segment.width, band.height);
        if (DKPadRectChanged(glass.frame, frame)) glass.frame = frame;

        // 单个按钮的玻璃随按压形变；合并胶囊只提供材质，各图标保留原生按压反馈。
        BOOL interactive = segment.buttons.count == 1;
        UIView *source = interactive ? segment.buttons.firstObject : nil;
        if (glass.flexSourceView != source) glass.flexSourceView = source;
        NSString *signature = [NSString stringWithFormat:@"%ld|%d|%d", (long)style, clear, interactive];
        if (![objc_getAssociatedObject(glass, &kDKPadGlassSignatureKey) isEqualToString:signature]) {
            objc_setAssociatedObject(glass, &kDKPadGlassSignatureKey, signature, OBJC_ASSOCIATION_COPY_NONATOMIC);
            glass.overrideUserInterfaceStyle = style;
            glass.effect = DKGlassTabBarMakeEffect(style, interactive);
        }
    }
}

// 玻璃底栏关闭：移除玻璃、还原底色与命中区，让抖音下一轮布局写回原生几何。
static void DKPadRestore(UIView *bar) {
    NSMutableArray<UIView *> *glasses = objc_getAssociatedObject(bar, &kDKPadGlassViewsKey);
    if (!glasses) return;
    for (UIView *glass in glasses) [glass removeFromSuperview];
    objc_setAssociatedObject(bar, &kDKPadGlassViewsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    for (AWETabBarElementContainerView *container in DKPadContainers(bar)) {
        objc_setAssociatedObject(container, &kDKPadContainerFrameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        for (id object in container.elementButtons) {
            if (![object isKindOfClass:UIButton.class]) continue;
            objc_setAssociatedObject(object, &kDKPadButtonFrameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(object, &kDKPadButtonSlotKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            DKPadRestoreBackground(object);
        }
        [container setNeedsLayout];
    }
    [bar setNeedsLayout];
}

void DKGlassPadElementsLayout(UIView *douyinBar, CGRect groupFrame) {
    if (!DKPadIsPad() || !douyinBar) return;
    if (CGRectIsNull(groupFrame)) {
        DKPadRestore(douyinBar);
        return;
    }

    gPadLayoutCount++;
    gPadLastBar = douyinBar;
    gPadLastGroupFrame = groupFrame;

    DKPadBand band = DKPadBandFor(douyinBar, groupFrame);
    DKPadBarPosition position;
    BOOL fellBack = NO;
    NSArray<DKPadSegment *> *segments = DKPadPlan(douyinBar, groupFrame, band, &position, &fellBack);
    if (fellBack) gPadFallbackCount++;

    NSMapTable<UIButton *, NSValue *> *frames = [NSMapTable strongToStrongObjectsMapTable];
    NSMapTable<UIButton *, NSValue *> *slots = [NSMapTable strongToStrongObjectsMapTable];
    for (DKPadSegment *segment in segments) DKPadPlanButtons(segment, band, frames, slots);

    NSArray<AWETabBarElementContainerView *> *containers = DKPadContainers(douyinBar);
    for (AWETabBarElementContainerView *container in containers) {
        NSArray<UIButton *> *buttons = DKPadVisibleButtons(container);
        CGRect area = CGRectNull;
        for (UIButton *button in buttons) area = CGRectUnion(area, [slots objectForKey:button].CGRectValue);
        if (CGRectIsNull(area)) {
            // 当前没有按钮（如「我」页）：交还原生几何。
            if (objc_getAssociatedObject(container, &kDKPadContainerFrameKey)) {
                objc_setAssociatedObject(container, &kDKPadContainerFrameKey, nil,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [douyinBar setNeedsLayout];
            }
            continue;
        }

        objc_setAssociatedObject(container, &kDKPadContainerFrameKey, [NSValue valueWithCGRect:area],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (DKPadRectChanged(container.frame, area)) container.frame = area;
        for (UIButton *button in buttons) {
            CGRect frame = [frames objectForKey:button].CGRectValue;
            CGRect slot = [slots objectForKey:button].CGRectValue;
            objc_setAssociatedObject(button, &kDKPadButtonFrameKey,
                [NSValue valueWithCGRect:CGRectOffset(frame, -CGRectGetMinX(area), -CGRectGetMinY(area))],
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(button, &kDKPadButtonSlotKey,
                [NSValue valueWithCGRect:CGRectOffset(slot, -CGRectGetMinX(frame), -CGRectGetMinY(frame))],
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            DKPadTakeOverBackground(button);
        }
        DKPadApplyInner(container);
    }

    if (@available(iOS 26.0, *)) {
        UIView *anchor = containers.firstObject;
        for (UIView *container in containers) {
            if ([douyinBar.subviews indexOfObjectIdenticalTo:container]
                < [douyinBar.subviews indexOfObjectIdenticalTo:anchor]) anchor = container;
        }
        if (anchor) DKPadSyncGlass(douyinBar, segments, band, anchor);
    }
}

NSString *DKGlassPadElementsStatus(void) {
    if (!DKPadIsPad()) return @"非 iPad，未启用";
    UIView *bar = gPadLastBar;
    if (!bar || !DKGlassTabBarActive()) return @"未布局（玻璃底栏关闭或尚未布局）";
    DKPadBand band = DKPadBandFor(bar, gPadLastGroupFrame);
    DKPadBarPosition position;
    NSArray<DKPadSegment *> *segments = DKPadPlan(bar, gPadLastGroupFrame, band, &position, NULL);
    static NSArray<NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ names = @[ @"默认", @"左端", @"右端" ]; });
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (DKPadSegment *segment in segments) {
        NSMutableArray<NSString *> *titles = [NSMutableArray array];
        for (UIButton *button in segment.buttons) {
            NSString *text = DKPadShowsText(button) ? ((AWETabBarElementButton *)button).elementLabel.text : @"图标";
            [titles addObject:text ?: @"图标"];
        }
        [parts addObject:[NSString stringWithFormat:@"%@[%@ %.1f–%.1f]",
                          [titles componentsJoinedByString:@"+"],
                          segment.icons ? (segment.buttons.count > 1 ? @"合并" : @"圆") : @"文字",
                          segment.x, segment.x + segment.width]];
    }
    return [NSString stringWithFormat:
            @"设置 %@ · 生效 %@ · 底栏宽 %.1f · 玻璃组 %.1f–%.1f · 高 %.1f 边距 %.1f\n"
            @"                       分段：%@\n"
            @"                       事件：布局 %lu · 容器补写 %lu · 请求重算 %lu · 放不下回落 %lu",
            names[DKPadPreferredPosition()], names[position], CGRectGetWidth(bar.bounds),
            CGRectGetMinX(gPadLastGroupFrame), CGRectGetMaxX(gPadLastGroupFrame), band.height, band.margin,
            parts.count ? [parts componentsJoinedByString:@"  "] : @"(无)",
            (unsigned long)gPadLayoutCount, (unsigned long)gPadInnerApplyCount,
            (unsigned long)gPadRelayoutRequests, (unsigned long)gPadFallbackCount];
}

#pragma mark - Hook

%group DKGlassPadElementHooks

%hook AWETabBarElementContainerView

// 底栏布局每轮先写原生 frame，这里换成方案值，容器尺寸不来回切换。
- (void)setFrame:(CGRect)frame {
    NSValue *planned = objc_getAssociatedObject(self, &kDKPadContainerFrameKey);
    %orig(planned ? planned.CGRectValue : frame);
}

- (void)p_refreshLayout {
    %orig;
    DKPadApplyInner(self);
}

%end

%hook AWETabBarElementButton

// 接管期间宿主底色只记录，实际保持透明；玻璃关闭时由 DKPadRestoreBackground 写回。
- (void)setBackgroundColor:(UIColor *)color {
    if (!objc_getAssociatedObject(self, &kDKPadHostBackgroundKey)) {
        %orig;
        return;
    }
    objc_setAssociatedObject(self, &kDKPadHostBackgroundKey, color ?: (id)NSNull.null,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(UIColor.clearColor);
}

// 命中区扩到按钮所在的玻璃槽位。
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    NSValue *slot = objc_getAssociatedObject(self, &kDKPadButtonSlotKey);
    if (slot) return CGRectContainsPoint(slot.CGRectValue, point);
    return %orig;
}

%end

%end

#pragma mark - 设置项注册

%ctor {
    DKSettingsRegister(DKKeyGlassTabBarPadPosition, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeChoice(DKKeyGlassTabBarPadPosition, @"iPad 底栏位置",
                                                 @[ @"默认", @"左端", @"右端" ]);
        DKSettingsOnChange(item, ^{ DKGlassTabBarRefresh(); });
        return DKSettingsWithInfo(item,
            @"默认时玻璃底栏居中，连播、弹幕在左，倍速在右。"
            @"左端 / 右端时玻璃底栏靠到该侧，连播、弹幕、倍速依次排到另一侧；空间不足时按默认排列。"
            @"开启玻璃底栏后这几个按钮同样变为玻璃：相邻的纯图标按钮合成一个胶囊，带文字的按钮各自成胶囊。");
    });

    if (DKGlassOSAvailable() && DKPadIsPad()) {
        %init(DKGlassPadElementHooks);
    }
}
