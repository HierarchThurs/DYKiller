//
//  DKProgressTime.xm
//  功能：显示视频时长 —— 在进度条旁显示已播时长与总时长。
//
//  实现：
//   - 读数视图 DKProgressTimeView 铺满进度条容器 AWEDPlayerProgressContainerView、不接收触摸，按进度条 frame 摆放：
//     「右端」为一段「已播 / 总长」贴进度条右缘，「两端 · 上方 / 下方」为已播贴左缘、总长贴右缘；
//     上方基线 = 进度条底边 − 7pt，下方数字顶 = 进度条底边 + 4pt。暂停时进度条 2→4pt 加粗而底边不动，读数不跳。
//   - 「两端」：已播与总长分列进度条左右、与进度条同一行。进度条的常态 / 唤醒 frame 与 progressWidth 都由 feed 布局策略的
//     左右边距算出，Hook 该边距多让出「总长文字宽 + 间距」，按这条视频的作品时长现算（经策略的 edc 取），
//     抖音换视频、暂停、拖动时自己按收短后的几何写 frame、算已播段宽度、章节点与假进度条，读数按进度条实际 frame 排在两侧。
//     已播按总长的位数补零（总长 28:22:22 时为 00:00:22），两段文字等宽，进度条居中。
//     切换样式或作品时长晚到时，常态下请状态机重新套用当前外观以重新取边距；唤醒态（暂停、拖动）期间不动，
//     抖音拖动按手指在进度条自身坐标里的位移换算，进度条在手指下平移会被当成拖动。
//   - 「两端」下的章节点：章节控制器默认固定取屏宽 − 24，让它走抖音自带的「跟随进度条宽度」分支，宽度即收短后的 progressWidth。
//   - iPad 的原生约束让位与章节点宽度由 DKProgressPadTime 管理，复用本文件的文字宽度与状态刷新。
//   - 数据：AWEDProgressCoreContainer 的 updateProgressSliderWithTime:totalDuration: 送来播放时间（播放中约 0.5 s 一次）；
//     总长取作品时长 videoDuration（毫秒）向下取整，与抖音拖动读数同一口径。进度条 setValue:0（换视频、重播）时归零。
//   - 显隐跟随进度条的 alpha / hidden：抖音拖动时把进度条写成 alpha 0，读数随之让给原生的大号读数。
//     例外是常态（setProgressState: 为 1）下抖音按判定把较短视频的进度条设为透明：读数照常显示，不依赖「进度条常显」。
//   - setProgressState: 为 2（唤醒态：暂停、拖动）时随进度条一同提亮。
//   - 时长在上方时，昵称文案与互动区两栏至少上移 12pt，由两栏的外观模块经 DKProgressTimeLift 取用。
//   - 设置项登记在本文件 %ctor，布局见 DKSettingsLayout.m「功能增强 › 视频」。
//

#import "DKProgressTime.h"
#import "DKProgressPadTime.h"
#import <objc/runtime.h>
#import "DouyinHeaders.h"
#import "DKInfoAppearance.h"
#import "DKInteractionAppearance.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"

// 取值即设置项的选项序号，与 DKProgressTimeOptions 一一对应。
typedef NS_ENUM(NSInteger, DKProgressTimeStyle) {
    DKProgressTimeStyleOff = 0,
    DKProgressTimeStyleInline = 1,
    DKProgressTimeStyleTrailingAbove = 2,
    DKProgressTimeStyleTrailingBelow = 3,
    DKProgressTimeStyleSplitAbove = 4,
    DKProgressTimeStyleSplitBelow = 5,
};

static const CGFloat DKProgressTimeLiftHeight = 12;  // 上方读数需要两栏让出的高度
static const CGFloat DKProgressTimeAboveGap = 7;     // 上方：基线到进度条底边
static const CGFloat DKProgressTimeBelowGap = 4;     // 下方：数字顶到进度条底边
static const CGFloat DKProgressTimeInlineGap = 8;    // 两端：文字与进度条的间距
static const CGFloat DKProgressTimeInlineCenter = 1; // 两端：数字中线在进度条底边上方的距离（常态进度条的中线）
static const long long DKProgressStateWakeup = 2;    // setProgressState: 的唤醒态（暂停、拖动）

static const void *DKProgressTimeViewKey = &DKProgressTimeViewKey;
// 以下三项记在进度条的 edc 上（总控与布局策略共用同一个 edc）。
static const void *DKProgressTimeAppliedInsetKey = &DKProgressTimeAppliedInsetKey;     // 抖音最近一次取边距时多让出的宽度
static const void *DKProgressTimeRequestedInsetKey = &DKProgressTimeRequestedInsetKey; // 已请求重新取边距的目标宽度
static const void *DKProgressTimeKnownTotalKey = &DKProgressTimeKnownTotalKey;         // 读数视图已知的总长（作品无时长时用）
static NSHashTable<UIView *> *gDKProgressTimeContainers;

static NSArray<NSString *> *DKProgressTimeOptions(void) {
    return @[ @"关闭", @"两端", @"右端 · 上方", @"右端 · 下方", @"两端 · 上方", @"两端 · 下方" ];
}

static DKProgressTimeStyle DKProgressTimeCurrentStyle(void) {
    NSInteger value = DKPrefInteger(DKKeyProgressTimeStyle);
    return value > DKProgressTimeStyleOff && value <= DKProgressTimeStyleSplitBelow
        ? (DKProgressTimeStyle)value : DKProgressTimeStyleOff;
}

static BOOL DKProgressTimeStyleAbove(DKProgressTimeStyle style) {
    return style == DKProgressTimeStyleTrailingAbove || style == DKProgressTimeStyleSplitAbove;
}

// 已播与总长分成左右两段。
static BOOL DKProgressTimeStyleSplit(DKProgressTimeStyle style) {
    return style == DKProgressTimeStyleSplitAbove || style == DKProgressTimeStyleSplitBelow
        || style == DKProgressTimeStyleInline;
}

#pragma mark - 文字

// 不足 1 小时 m:ss，1 小时及以上 h:mm:ss。
static NSString *DKProgressTimeText(NSInteger seconds) {
    NSInteger h = seconds / 3600, m = seconds % 3600 / 60, s = seconds % 60;
    return h > 0 ? [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)h, (long)m, (long)s]
                 : [NSString stringWithFormat:@"%ld:%02ld", (long)m, (long)s];
}

// 按总长的字段与位数补零：总长 28:22:22 时为 00:00:22，16:57 时为 00:32，1:07 时为 0:32。
static NSString *DKProgressTimeTextMatching(NSInteger seconds, NSInteger total) {
    NSInteger h = seconds / 3600, m = seconds % 3600 / 60, s = seconds % 60;
    NSInteger totalHours = total / 3600, totalMinutes = total % 3600 / 60;
    if (totalHours > 0) {
        int digits = (int)[NSString stringWithFormat:@"%ld", (long)totalHours].length;
        return [NSString stringWithFormat:@"%0*ld:%02ld:%02ld", digits, (long)h, (long)m, (long)s];
    }
    return [NSString stringWithFormat:@"%0*ld:%02ld", totalMinutes >= 10 ? 2 : 1, (long)m, (long)s];
}

static UIFont *DKProgressTimeFont(void) {
    static UIFont *font;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightSemibold];
    });
    return font;
}

// 白字按 alpha 分层；只加文字阴影，不加底板。
static NSAttributedString *DKProgressTimeRun(NSString *text, CGFloat white) {
    static NSShadow *shadow;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shadow = [NSShadow new];
        shadow.shadowColor = [UIColor colorWithWhite:0 alpha:0.4];
        shadow.shadowOffset = CGSizeMake(0, 0.5);
        shadow.shadowBlurRadius = 2;
    });
    return [[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: DKProgressTimeFont(),
        NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:white],
        NSShadowAttributeName: shadow,
    }];
}

// 「两端」进度条每侧让给时长的宽度：总长文字宽 + 间距。已播按总长位数补零、两段等宽；
// 等宽数字下文字宽只取决于字数，按字数缓存（布局取边距时会频繁调用）。
static CGFloat DKProgressTimeInlineInset(NSInteger total) {
    static CGFloat cache[32];
    NSString *text = DKProgressTimeText(MAX(total, 0));
    NSUInteger length = MIN(text.length, (NSUInteger)31);
    if (cache[length] <= 0) {
        CGFloat width = [text sizeWithAttributes:@{ NSFontAttributeName: DKProgressTimeFont() }].width;
        cache[length] = ceil(width) + DKProgressTimeInlineGap;
    }
    return cache[length];
}

#pragma mark - 进度条与总控

static AWEFeedProgressSlider *DKProgressTimeSliderIn(UIView *container) {
    Class sliderClass = NSClassFromString(@"AWEFeedProgressSlider");
    for (UIView *subview in container.subviews) {
        if ([subview isKindOfClass:sliderClass]) return (AWEFeedProgressSlider *)subview;
    }
    return nil;
}

static AWEDProgressCoreContainer *DKProgressTimeCore(AWEFeedProgressSlider *slider) {
    id delegate = slider.progressSliderDelegate;
    return [delegate isKindOfClass:NSClassFromString(@"AWEDProgressCoreContainer")] ? delegate : nil;
}

static AWEArchEventDataController *DKProgressTimeEDCOf(AWEDProgressCoreContainer *core) {
    return [core respondsToSelector:@selector(edc)] ? [core edc] : nil;
}

// 作品时长（毫秒）向下取整到秒；作品没有时长时取播放器送来的总长。
static NSInteger DKProgressTimeTotal(AWEDProgressCoreContainer *core, double playerDuration) {
    double milliseconds = [core videoDuration];
    return (NSInteger)floor(milliseconds > 0 ? milliseconds / 1000.0 : playerDuration);
}

// 边距所属视频的总长：作品时长（共享数据 progressStatusVideoDuration，随当前作品现取）向下取整；
// 作品没有时长时取读数视图已知的总长。
static NSInteger DKProgressTimeTotalOfEDC(AWEArchEventDataController *edc) {
    Class dataIDs = NSClassFromString(@"AWEDProgressCoreDataID");
    if ([dataIDs respondsToSelector:@selector(progressStatusVideoDuration)]
        && [edc respondsToSelector:@selector(sharedDataOfID:)]) {
        id duration = [edc sharedDataOfID:[dataIDs progressStatusVideoDuration]];
        double milliseconds = [duration respondsToSelector:@selector(doubleValue)] ? [duration doubleValue] : 0;
        if (milliseconds > 0) return (NSInteger)floor(milliseconds / 1000.0);
    }
    return [objc_getAssociatedObject(edc, DKProgressTimeKnownTotalKey) integerValue];
}

// 抖音取进度条左右边距时多让出的宽度：「两端」为这条视频的读数宽度，其余为 0；记在 edc 上供读数视图核对。
static CGFloat DKProgressTimeMarginInset(AWEArchEventDataController *edc) {
    if (!edc) return 0;
    CGFloat inset = DKProgressTimeCurrentStyle() == DKProgressTimeStyleInline
        ? DKProgressTimeInlineInset(DKProgressTimeTotalOfEDC(edc)) : 0;
    objc_setAssociatedObject(edc, DKProgressTimeAppliedInsetKey, @(inset), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return inset;
}

// 下一轮主线程请状态机按当前状态重新套用外观（重新取边距、写 frame），再让章节点按新宽度重排
// （章节容器自己的布局回调：重置章节缩略图索引、重建章节点、续上章节循环；非章节视频内部直接返回）。
// 推迟一轮，不在抖音换视频（setValue:0）的调用链中途重入。
static void DKProgressTimeReapplyBar(AWEFeedProgressSlider *slider) {
    __weak AWEFeedProgressSlider *weakSlider = slider;
    dispatch_async(dispatch_get_main_queue(), ^{
        AWEDProgressCoreContainer *core = DKProgressTimeCore(weakSlider);
        AWEDProgressStateChangeContainer *state = [core respondsToSelector:@selector(stateChangeContainer)]
            ? [core stateChangeContainer] : nil;
        if ([state respondsToSelector:@selector(reapplyCurrentStateAppearance)]) [state reapplyCurrentStateAppearance];
        AWEDProgressChapterContainer *chapter = [core respondsToSelector:@selector(chapterContainer)]
            ? [core chapterContainer] : nil;
        if ([chapter respondsToSelector:@selector(progressTimingViewDidLayoutSubviews)]) {
            [chapter progressTimingViewDidLayoutSubviews];
        }
    });
}

// 进度条边距多让出的宽度与应有值不一致时（切换样式、作品时长晚到）请抖音重新取边距。
// 唤醒态不动；同一目标只请求一次，布局策略不经本 Hook（非 feed 布局）时不会反复重排。
static void DKProgressTimeSyncMargin(AWEFeedProgressSlider *slider, CGFloat desired, BOOL wakeup) {
    if (DKProgressPadTimeSync(slider, desired, wakeup)) return;
    AWEArchEventDataController *edc = DKProgressTimeEDCOf(DKProgressTimeCore(slider));
    if (!edc) return;
    CGFloat applied = [objc_getAssociatedObject(edc, DKProgressTimeAppliedInsetKey) doubleValue];
    if (applied == desired) {
        objc_setAssociatedObject(edc, DKProgressTimeRequestedInsetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    NSNumber *requested = objc_getAssociatedObject(edc, DKProgressTimeRequestedInsetKey);
    if (wakeup || (requested && requested.doubleValue == desired)) return;
    objc_setAssociatedObject(edc, DKProgressTimeRequestedInsetKey, @(desired), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKProgressTimeReapplyBar(slider);
}

#pragma mark - 读数视图

@interface DKProgressTimeView : UIView
@property (nonatomic, weak) AWEFeedProgressSlider *slider;
@property (nonatomic, readonly) NSInteger elapsed;
@property (nonatomic, readonly) NSInteger total;
@property (nonatomic) BOOL wakeup;  // 进度条处于唤醒态（暂停、拖动）
// 「两端」时进度条两侧放得下读数、与读数同一行；否则（进度条未收短）退到进度条下方。
@property (nonatomic, readonly) BOOL inlineFits;
@property (nonatomic, readonly) UILabel *leadingLabel;
@property (nonatomic, readonly) UILabel *trailingLabel;
- (void)setElapsed:(NSInteger)elapsed total:(NSInteger)total;
- (void)syncVisibility;
- (void)refresh;
- (void)layoutLabels;
@end

@implementation DKProgressTimeView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.accessibilityElementsHidden = YES;
        _leadingLabel = [UILabel new];
        _trailingLabel = [UILabel new];
        [self addSubview:_leadingLabel];
        [self addSubview:_trailingLabel];
    }
    return self;
}

- (void)setElapsed:(NSInteger)elapsed total:(NSInteger)total {
    if (elapsed == _elapsed && total == _total) return;
    if (total != _total) {
        AWEArchEventDataController *edc = DKProgressTimeEDCOf(DKProgressTimeCore(self.slider));
        if (edc) objc_setAssociatedObject(edc, DKProgressTimeKnownTotalKey, @(total), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    _elapsed = elapsed;
    _total = total;
    [self refresh];
}

// 唤醒态提亮，0.2 s 交叉淡入；常态与唤醒态的显隐口径不同，一并重算。
- (void)setWakeup:(BOOL)wakeup {
    if (wakeup == _wakeup) return;
    _wakeup = wakeup;
    [self syncVisibility];
    [UIView transitionWithView:self duration:0.2 options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{ [self refresh]; } completion:nil];
}

// 跟随进度条的 alpha / hidden；常态下进度条因抖音的透明判定而透明时照常显示。
- (void)syncVisibility {
    AWEFeedProgressSlider *slider = self.slider;
    if (!slider) return;
    BOOL stableTransparent = !_wakeup && [DKProgressTimeCore(slider) shouldTransparentProgressSliderOnStableState];
    self.alpha = stableTransparent ? 1 : slider.alpha;
    self.hidden = slider.hidden;
}

- (CGFloat)pixelAligned:(CGFloat)value {
    CGFloat scale = MAX(self.traitCollection.displayScale, 1);
    return round(value * scale) / scale;
}

- (void)refresh {
    AWEFeedProgressSlider *slider = self.slider;
    DKProgressTimeStyle style = DKProgressTimeCurrentStyle();
    if (!slider || style == DKProgressTimeStyleOff) return;

    NSInteger shownElapsed = _total > 0 ? MIN(_elapsed, _total) : _elapsed;
    NSString *elapsed = style == DKProgressTimeStyleInline ? DKProgressTimeTextMatching(shownElapsed, _total)
                                                           : DKProgressTimeText(shownElapsed);
    NSString *total = DKProgressTimeText(_total);
    CGFloat elapsedWhite = _wakeup ? 1.0 : 0.92;
    CGFloat totalWhite = _wakeup ? 0.72 : 0.55;
    BOOL split = DKProgressTimeStyleSplit(style);
    if (split) {
        _leadingLabel.attributedText = DKProgressTimeRun(elapsed, elapsedWhite);
        _trailingLabel.attributedText = DKProgressTimeRun(total, totalWhite);
    } else {
        NSMutableAttributedString *text = [[NSMutableAttributedString alloc] init];
        [text appendAttributedString:DKProgressTimeRun(elapsed, elapsedWhite)];
        [text appendAttributedString:DKProgressTimeRun(@" / ", 0.35)];
        [text appendAttributedString:DKProgressTimeRun(total, totalWhite)];
        _trailingLabel.attributedText = text;
    }
    _leadingLabel.hidden = !split;
    CGFloat desired = style == DKProgressTimeStyleInline ? DKProgressTimeInlineInset(_total) : 0;
    DKProgressTimeSyncMargin(slider, desired, _wakeup);
    [self layoutLabels];
}

// 按进度条实际 frame 摆放读数。「两端」排在进度条两侧（进度条两侧放不下时退到下方）。
- (void)layoutLabels {
    AWEFeedProgressSlider *slider = self.slider;
    DKProgressTimeStyle style = DKProgressTimeCurrentStyle();
    if (!slider || style == DKProgressTimeStyleOff) return;

    UIFont *font = DKProgressTimeFont();
    CGRect bar = [self convertRect:slider.bounds fromView:slider];
    BOOL split = DKProgressTimeStyleSplit(style);
    CGFloat trailingWidth = ceil([_trailingLabel sizeThatFits:CGSizeZero].width);
    CGFloat leadingWidth = split ? ceil([_leadingLabel sizeThatFits:CGSizeZero].width) : 0;
    _inlineFits = style == DKProgressTimeStyleInline
        && CGRectGetMinX(bar) - DKProgressTimeInlineGap - leadingWidth >= -0.5
        && CGRectGetMaxX(bar) + DKProgressTimeInlineGap + trailingWidth <= CGRectGetWidth(self.bounds) + 0.5;
    CGFloat baseline;
    if (_inlineFits) {
        baseline = CGRectGetMaxY(bar) - DKProgressTimeInlineCenter + font.capHeight / 2;
    } else if (DKProgressTimeStyleAbove(style)) {
        baseline = CGRectGetMaxY(bar) - DKProgressTimeAboveGap;
    } else {
        baseline = CGRectGetMaxY(bar) + DKProgressTimeBelowGap + font.capHeight;
    }
    CGFloat top = [self pixelAligned:baseline - font.ascender];
    CGFloat height = ceil(font.lineHeight);
    CGFloat trailingX = _inlineFits ? CGRectGetMaxX(bar) + DKProgressTimeInlineGap : CGRectGetMaxX(bar) - trailingWidth;
    _trailingLabel.frame = CGRectMake([self pixelAligned:trailingX], top, trailingWidth, height);
    if (split) {
        CGFloat leadingX = _inlineFits ? CGRectGetMinX(bar) - DKProgressTimeInlineGap - leadingWidth : CGRectGetMinX(bar);
        _leadingLabel.frame = CGRectMake([self pixelAligned:leadingX], top, leadingWidth, height);
    }
}

@end

static DKProgressTimeView *DKProgressTimeViewOf(UIView *container) {
    return container ? objc_getAssociatedObject(container, DKProgressTimeViewKey) : nil;
}

// 按当前设置给容器挂上、刷新或拆掉读数视图；拆掉时让进度条回到抖音的原边距。
static void DKProgressTimeSync(UIView *container) {
    DKProgressTimeView *view = DKProgressTimeViewOf(container);
    AWEFeedProgressSlider *slider = DKProgressTimeCurrentStyle() != DKProgressTimeStyleOff
        ? DKProgressTimeSliderIn(container) : nil;
    if (!slider) {
        if (!view) return;
        [view removeFromSuperview];
        objc_setAssociatedObject(container, DKProgressTimeViewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (view.slider) DKProgressTimeSyncMargin(view.slider, 0, view.wakeup);
        return;
    }
    if (!view) {
        view = [[DKProgressTimeView alloc] initWithFrame:container.bounds];
        objc_setAssociatedObject(container, DKProgressTimeViewKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [container addSubview:view];
        view.slider = slider;
        AWEDProgressCoreContainer *core = DKProgressTimeCore(slider);
        [view setElapsed:(NSInteger)floor([core lastProgressDuration]) total:DKProgressTimeTotal(core, 0)];
    }
    view.slider = slider;
    view.frame = container.bounds;
    [view syncVisibility];
    [view refresh];
}

static void DKProgressTimeRefresh(void) {
    for (UIView *container in gDKProgressTimeContainers.allObjects) DKProgressTimeSync(container);
    DKInteractionAppearanceRefresh();
    DKInfoAppearanceRefresh();
}

#pragma mark - 对外

CGFloat DKProgressTimeLift(UIView *view) {
    if (!DKProgressTimeStyleAbove(DKProgressTimeCurrentStyle())) return 0;
    Class containerClass = NSClassFromString(@"AWEDPlayerProgressContainerView");
    if ([view isKindOfClass:containerClass]) return DKProgressTimeSliderIn(view) ? DKProgressTimeLiftHeight : 0;
    for (UIView *sibling in view.superview.subviews) {
        if ([sibling isKindOfClass:containerClass] && DKProgressTimeSliderIn(sibling)) return DKProgressTimeLiftHeight;
    }
    return 0;
}

static NSString *DKProgressTimeLabelText(UILabel *label) {
    if (label.hidden || !label.attributedText.length) return @"—";
    return [NSString stringWithFormat:@"「%@」%@", label.attributedText.string,
        NSStringFromCGRect([label convertRect:label.bounds toView:nil])];
}

NSString *DKProgressTimeStatus(void) {
    DKProgressTimeStyle style = DKProgressTimeCurrentStyle();
    NSArray<UIView *> *containers = gDKProgressTimeContainers.allObjects;
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"显示视频时长=%@  已见进度条容器=%lu\n", DKProgressTimeOptions()[style], (unsigned long)containers.count];
    for (UIView *container in containers) {
        if (!container.window) continue;
        AWEFeedProgressSlider *slider = DKProgressTimeSliderIn(container);
        DKProgressTimeView *view = DKProgressTimeViewOf(container);
        AWEDProgressCoreContainer *core = DKProgressTimeCore(slider);
        [out appendFormat:@"  进度条=%@ alpha=%.2f hidden=%d  作品时长=%.0fms 最近播放时间=%.2fs  两栏保底上移=%.0fpt\n",
            slider ? NSStringFromCGRect([slider convertRect:slider.bounds toView:nil]) : @"无",
            slider.alpha, slider.hidden, [core videoDuration], [core lastProgressDuration], DKProgressTimeLift(container)];
        if (view) {
            [out appendFormat:@"    读数 已播=%lds 总长=%lds 唤醒态=%@ 常态透明判定=%@ alpha=%.2f hidden=%d 左=%@ 右=%@\n",
                (long)view.elapsed, (long)view.total, view.wakeup ? @"是" : @"否",
                [core shouldTransparentProgressSliderOnStableState] ? @"透明" : @"显示", view.alpha, view.hidden,
                DKProgressTimeLabelText(view.leadingLabel), DKProgressTimeLabelText(view.trailingLabel)];
            if (style == DKProgressTimeStyleInline) {
                AWEArchEventDataController *edc = DKProgressTimeEDCOf(core);
                NSNumber *applied = edc ? objc_getAssociatedObject(edc, DKProgressTimeAppliedInsetKey) : nil;
                NSNumber *requested = edc ? objc_getAssociatedObject(edc, DKProgressTimeRequestedInsetKey) : nil;
                [out appendFormat:@"    两端 策略附加边距=%@ 目标让位=%.1fpt 待重取=%@ 读数位置=%@\n",
                    applied ? [NSString stringWithFormat:@"%.1fpt", applied.doubleValue] : @"未取",
                    DKProgressTimeInlineInset(view.total), requested ?: @"无", view.inlineFits ? @"同行" : @"下方（进度条未收短）"];
                AWEDProgressChapterContainer *chapter = [core respondsToSelector:@selector(chapterContainer)]
                    ? [core chapterContainer] : nil;
                if ([chapter respondsToSelector:@selector(isChapterStyle)]) {
                    [out appendFormat:@"    章节点 章节样式=%d 跟随进度条宽=%d 章节宽度=%.1fpt 进度条实际宽=%.1fpt\n",
                        [chapter isChapterStyle], [chapter shouldFollowSliderWidthForChapterPoints],
                        [chapter progressWidth], CGRectGetWidth(slider.bounds)];
                }
            }
        } else {
            [out appendString:@"    读数=无\n"];
        }
    }
    return out;
}

void DKProgressTimeLayoutContainer(UIView *container) {
    if (!gDKProgressTimeContainers) gDKProgressTimeContainers = [NSHashTable weakObjectsHashTable];
    [gDKProgressTimeContainers addObject:container];
    DKProgressTimeSync(container);
}

#pragma mark - Hook

%hook AWEDProgressCoreContainer

- (void)updateProgressSliderWithTime:(double)time totalDuration:(double)duration {
    %orig;
    [DKProgressTimeViewOf(self.progressSlider.superview) setElapsed:(NSInteger)floor(time)
                                                              total:DKProgressTimeTotal(self, duration)];
}

- (void)setProgressState:(long long)state {
    %orig;
    DKProgressTimeViewOf(self.progressSlider.superview).wakeup = state == DKProgressStateWakeup;
}

%end

// 常态 / 唤醒 frame 与 progressWidth 都从这里取边距；「两端」多让出这条视频的读数宽度。
%hook AWEDProgressLayoutFeedStrategy

- (double)progressSliderLeftRightArea {
    double area = %orig;
    return area + DKProgressTimeMarginInset([self respondsToSelector:@selector(edc)] ? [self edc] : nil);
}

%end

%hook AWEFeedProgressSlider

// 进度条的 frame 由抖音按布局策略写入，读数随之重排。
- (void)setFrame:(CGRect)frame {
    %orig;
    [DKProgressTimeViewOf(self.superview) layoutLabels];
}

- (void)setAlpha:(CGFloat)alpha {
    %orig;
    [DKProgressTimeViewOf(self.superview) syncVisibility];
}

- (void)setHidden:(BOOL)hidden {
    %orig;
    [DKProgressTimeViewOf(self.superview) syncVisibility];
}

- (void)setValue:(float)value {
    %orig;
    if (value != 0) return;
    DKProgressTimeView *view = DKProgressTimeViewOf(self.superview);
    if (view) [view setElapsed:0 total:DKProgressTimeTotal(DKProgressTimeCore(self), 0)];
}

%end

// 章节控制器默认固定取屏宽 − 24；「两端」时改走「跟随进度条宽度」分支，宽度即布局策略收短后的 progressWidth。
%hook AWEDProgressChapterContainer

- (BOOL)shouldFollowSliderWidthForChapterPoints {
    return DKProgressTimeCurrentStyle() == DKProgressTimeStyleInline || %orig;
}

%end

%ctor {
    %init;
    DKSettingsRegister(DKKeyProgressTimeStyle, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKSettingsWithInfo(
            DKMakeChoice(DKKeyProgressTimeStyle, @"显示视频时长", DKProgressTimeOptions()),
            @"在进度条旁显示已播时长和总时长，所有视频都会显示，不依赖「进度条常显」。"
            @"两端：已播与总时长分列进度条左右、与进度条同一行，进度条按时长文字的宽度缩短；"
            @"右端：「已播 / 总时长」一段贴进度条右端；两端 · 上方 / 下方：已播贴左端、总时长贴右端，放在进度条上面或下面。"
            @"拖动进度条时让给抖音的大号读数。显示在上方时，昵称文案与互动区至少上移 12pt。");
        return DKSettingsOnChange(item, ^{
            DKProgressTimeRefresh();
        });
    });
}
