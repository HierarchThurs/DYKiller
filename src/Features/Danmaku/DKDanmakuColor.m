#import "DKDanmakuColor.h"
#import "DKColorScheme.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import <objc/runtime.h>
#import <math.h>

static char kDKStateKey, kDKUpdateDepthKey, kDKWriteKey, kDKDrawDepthKey, kDKIdentityKey, kDKImageStateKey;

// 配色序号：每生成一次配色加一，旋转彩虹按它轮换起始色。配色只在新条目或方案改变时生成，均在主线程。
static NSUInteger gDKPaletteSerial;

@interface DKDanmakuIdentity : NSObject
@property(nonatomic, weak) id model;
@end
@implementation DKDanmakuIdentity @end

@interface DKDanmakuLabelState : NSObject
@property(nonatomic, copy) NSAttributedString *nativeAttributed;
@property(nonatomic, copy) NSString *nativeText;
@property(nonatomic, strong) UIColor *nativeColor;
@property(nonatomic, strong) UIColor *nativeStrokeColor;
@property(nonatomic) double nativeStrokeWidth;
@property(nonatomic, copy) NSArray<UIColor *> *palette;
@property(nonatomic, copy) NSString *configuration;
@property(nonatomic, copy) NSString *renderKey;
@property(nonatomic) BOOL applied;
@end
@implementation DKDanmakuLabelState @end

@interface DKDanmakuImageState : NSObject
@property(nonatomic, strong) UIImage *nativeImage;
@property(nonatomic, strong) UIImage *appliedImage;
@property(nonatomic, copy) NSString *renderKey;
@end
@implementation DKDanmakuImageState @end

static NSHashTable *DKViews(void) {
    static NSHashTable *views;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ views = [NSHashTable weakObjectsHashTable]; });
    return views;
}

static DKDanmakuLabelState *DKState(UILabel *label) {
    return objc_getAssociatedObject(label, &kDKStateKey);
}

AWEDanmakuItemCommonView *DKDanmakuDiggOwner(AWEDanmakuDiggNumView *view) {
    UIView *parent = view.superview;
    Class cls = NSClassFromString(@"AWEDanmakuItemCommonView");
    if (!cls || ![parent isKindOfClass:cls]) return nil;
    AWEDanmakuItemCommonView *owner = (id)parent;
    return [owner respondsToSelector:@selector(diggNumView)] && owner.diggNumView == view ? owner : nil;
}

static AWEDanmakuItemCommonView *DKOwner(UILabel *label) {
    UIView *parent = label.superview;
    Class cls = NSClassFromString(@"AWEDanmakuItemCommonView");
    if (cls && [parent isKindOfClass:cls]) return ((AWEDanmakuItemCommonView *)parent).contentLabel == label ? (id)parent : nil;
    Class diggClass = NSClassFromString(@"AWEDanmakuDiggNumView");
    if (diggClass && [parent isKindOfClass:diggClass] && ((AWEDanmakuDiggNumView *)parent).diggNumLabel == label)
        return DKDanmakuDiggOwner((id)parent);
    return nil;
}

static AWEDanmakuDiggNumView *DKDigg(AWEDanmakuItemCommonView *owner) {
    AWEDanmakuDiggNumView *view = [owner respondsToSelector:@selector(diggNumView)] ? owner.diggNumView : nil;
    return view && DKDanmakuDiggOwner(view) == owner ? view : nil;
}

static void DKCapture(AWEDanmakuContentLabel *label, DKDanmakuLabelState *state) {
    state.nativeAttributed = label.attributedText;
    state.nativeText = label.text;
    state.nativeColor = label.textColor;
    state.nativeStrokeColor = label.strokeColor;
    state.nativeStrokeWidth = label.strokeWidth;
}

static void DKRestore(AWEDanmakuContentLabel *label, DKDanmakuLabelState *state) {
    if (!state.applied) return;
    objc_setAssociatedObject(label, &kDKWriteKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        label.textColor = state.nativeColor;
        if (state.nativeAttributed) label.attributedText = state.nativeAttributed;
        else label.text = state.nativeText;
        label.strokeColor = state.nativeStrokeColor;
        label.strokeWidth = state.nativeStrokeWidth;
        state.applied = NO;
        [label setNeedsDisplay];
    } @finally {
        objc_setAssociatedObject(label, &kDKWriteKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void DKRestoreEntry(AWEDanmakuItemCommonView *owner) {
    DKRestore(owner.contentLabel, DKState(owner.contentLabel));
    AWEDanmakuDiggNumView *digg = DKDigg(owner);
    DKRestore(digg.diggNumLabel, DKState(digg.diggNumLabel));
    UIImageView *heart = digg.diggImageView;
    DKDanmakuImageState *imageState = objc_getAssociatedObject(heart, &kDKImageStateKey);
    if (imageState.appliedImage && heart.image == imageState.appliedImage) heart.image = imageState.nativeImage;
    imageState.appliedImage = nil;
    imageState.renderKey = nil;
}

// offset 与 span 使用当前控件的绘制坐标，三个控件沿条目横向位置取同一条色带。
static void DKDrawPalette(NSArray<UIColor *> *palette, CGRect rect, CGFloat offset, CGFloat span) {
    if (palette.count == 1) { [palette.firstObject setFill]; CGContextFillRect(UIGraphicsGetCurrentContext(), rect); return; }
    NSMutableArray *colors = [NSMutableArray array];
    for (UIColor *color in palette) [colors addObject:(__bridge id)color.CGColor];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, NULL);
    CGContextDrawLinearGradient(UIGraphicsGetCurrentContext(), gradient, CGPointMake(-offset, 0), CGPointMake(span - offset, 0),
                                kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
}

static UIColor *DKSpanColor(NSArray<UIColor *> *palette, CGFloat offset, CGFloat width, CGFloat span, CGFloat scale) {
    if (palette.count == 1) return palette.firstObject;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = scale;
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(MAX(1, width), 1 / scale) format:format];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        DKDrawPalette(palette, CGRectMake(0, 0, MAX(1, width), 1 / scale), offset, span);
    }];
    return [UIColor colorWithPatternImage:image];
}

static NSString *DKRenderKey(NSString *configuration, CGFloat offset, CGFloat width, CGFloat span, CGFloat scale) {
    return [NSString stringWithFormat:@"%@/%.4f/%.4f/%.4f/%.2f", configuration, offset, width, span, scale];
}

static void DKApplyLabel(AWEDanmakuContentLabel *label, DKDanmakuLabelState *state, NSArray<UIColor *> *palette,
                         NSString *configuration, CGFloat offset, CGFloat width, CGFloat span, CGFloat scale) {
    NSString *key = DKRenderKey(configuration, offset, width, span, scale);
    if (state.applied && [state.renderKey isEqual:key]) return;
    NSAttributedString *native = state.nativeAttributed ?: [[NSAttributedString alloc] initWithString:state.nativeText ?: @""
        attributes:@{ NSFontAttributeName: label.font ?: [UIFont systemFontOfSize:14] }];
    if (!native.length) return;
    UIColor *color = DKSpanColor(palette, offset, width, span, scale);
    NSMutableAttributedString *text = [native mutableCopy];
    NSRange range = NSMakeRange(0, text.length);
    [text addAttribute:NSForegroundColorAttributeName value:color range:range];
    [text removeAttribute:NSStrokeWidthAttributeName range:range];
    [text removeAttribute:NSStrokeColorAttributeName range:range];
    objc_setAssociatedObject(label, &kDKWriteKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        label.textColor = color;
        label.attributedText = text;
        label.strokeWidth = 0;
        label.strokeColor = nil;
        state.applied = YES;
        state.renderKey = key;
    } @finally {
        objc_setAssociatedObject(label, &kDKWriteKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [label setNeedsDisplay];
}

static void DKApplyHeart(UIImageView *heart, NSArray<UIColor *> *palette, NSString *configuration,
                         CGFloat offset, CGFloat span, CGFloat width, CGFloat scale) {
    if (!heart.image || width <= 0) return;
    DKDanmakuImageState *state = objc_getAssociatedObject(heart, &kDKImageStateKey);
    if (!state) {
        state = [DKDanmakuImageState new];
        objc_setAssociatedObject(heart, &kDKImageStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSString *key = DKRenderKey(configuration, offset, width, span, scale);
    if (heart.image == state.appliedImage && [state.renderKey isEqual:key]) return;
    if (heart.image != state.appliedImage) state.nativeImage = heart.image;
    UIImage *native = state.nativeImage;
    if (native.size.width <= 0 || native.size.height <= 0) return;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = native.scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:native.size format:format];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGRect rect = (CGRect){ CGPointZero, native.size };
        [[native imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] drawInRect:rect];
        CGContextSetBlendMode(ctx.CGContext, kCGBlendModeSourceIn);
        CGFloat ratio = native.size.width / width;
        DKDrawPalette(palette, rect, offset * ratio, span * ratio);
    }];
    state.appliedImage = [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    state.renderKey = key;
    heart.image = state.appliedImage;
}

static NSString *DKFixedColor(void) { return DKColorSchemeStoredColor(DKKeyDanmakuFixedColor, NO); }
static NSString *DKGradientColors(void) { return DKColorSchemeStoredColor(DKKeyDanmakuGradientColors, YES); }

static NSString *DKConfiguration(DKColorSchemeMode mode) {
    return DKColorSchemeSignature(mode, DKFixedColor(), DKGradientColors());
}

// create 为 NO 时只更新已接管的条目：上轨道、原生单独写入这类时机不新建状态，配色只随新条目或设置刷新生成。
static void DKApply(AWEDanmakuItemCommonView *owner, BOOL create) {
    if (!NSThread.isMainThread || !owner || [objc_getAssociatedObject(owner, &kDKUpdateDepthKey) unsignedIntegerValue]) return;
    AWEDanmakuContentLabel *label = owner.contentLabel;
    if (!label || DKOwner(label) != owner) return;
    DKDanmakuLabelState *state = DKState(label);
    AWEDanmakuDiggNumView *digg = DKDigg(owner);
    if (!DKPrefBool(DKKeyDanmakuColorEnabled)) {
        DKRestoreEntry(owner);
        objc_setAssociatedObject(label, &kDKStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(digg.diggNumLabel, &kDKStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(digg.diggImageView, &kDKImageStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (!state) {
        if (!create) return;
        state = [DKDanmakuLabelState new];
        DKCapture(label, state);
        objc_setAssociatedObject(label, &kDKStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSAttributedString *native = state.nativeAttributed;
    if (!native) native = [[NSAttributedString alloc] initWithString:state.nativeText ?: @"" attributes:@{ NSFontAttributeName: label.font ?: [UIFont systemFontOfSize:14] }];
    if (!native.length) return;
    DKColorSchemeMode mode = DKColorSchemeStoredMode(DKKeyDanmakuColorMode);
    NSString *configuration = DKConfiguration(mode);
    BOOL configurationChanged = ![state.configuration isEqual:configuration];
    if (configurationChanged) {
        state.palette = DKColorSchemePalette(mode, DKFixedColor(), DKGradientColors(), gDKPaletteSerial++);
        state.configuration = configuration;
    }
    CGFloat width = [native boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)
                                        options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading context:nil].size.width;
    CGRect body = [label convertRect:label.bounds toView:owner];
    CGFloat start = CGRectGetMinX(body);
    CGFloat span = MAX(1, width);
    BOOL showDigg = digg && !digg.hidden && digg.alpha > 0 && !CGRectIsEmpty(digg.bounds);
    AWEDanmakuContentLabel *count = showDigg && !digg.diggNumLabel.hidden ? digg.diggNumLabel : nil;
    UIImageView *heart = showDigg && !digg.diggImageView.hidden ? digg.diggImageView : nil;
    CGRect countRect = count ? [count convertRect:count.bounds toView:owner] : CGRectZero;
    CGRect heartRect = heart ? [heart convertRect:heart.bounds toView:owner] : CGRectZero;
    if (showDigg) {
        span = MAX(span, CGRectGetWidth(body));
        if (count) span = MAX(span, CGRectGetMaxX(countRect) - start);
        if (heart) span = MAX(span, CGRectGetMaxX(heartRect) - start);
    }
    CGFloat scale = label.traitCollection.displayScale > 0 ? label.traitCollection.displayScale : UIScreen.mainScreen.scale;
    DKApplyLabel(label, state, state.palette, configuration, 0, MAX(width, CGRectGetWidth(body)), span, scale);
    if (count) {
        DKDanmakuLabelState *countState = DKState(count);
        if (!countState) {
            countState = [DKDanmakuLabelState new];
            DKCapture(count, countState);
            objc_setAssociatedObject(count, &kDKStateKey, countState, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        DKApplyLabel(count, countState, state.palette, configuration, CGRectGetMinX(countRect) - start, CGRectGetWidth(countRect), span, scale);
    }
    if (heart) DKApplyHeart(heart, state.palette, configuration, CGRectGetMinX(heartRect) - start, span, CGRectGetWidth(heartRect), scale);
}

void DKDanmakuLayoutDigg(AWEDanmakuDiggNumView *view) { DKApply(DKDanmakuDiggOwner(view), NO); }

void DKDanmakuBeginEntry(AWEDanmakuItemCommonView *view, id descriptor) {
    if (!NSThread.isMainThread) return;
    // 同一作品弹幕也会因点赞或原生样式更新重新绑定 descriptor；只在模型变更或复用后换色。
    id model = [descriptor respondsToSelector:@selector(danmakuModel)] ? [(AWEDanmakuItemDescriptor *)descriptor danmakuModel] : descriptor;
    DKDanmakuIdentity *identity = objc_getAssociatedObject(view, &kDKIdentityKey);
    BOOL newEntry = !identity || identity.model != model;
    if (!identity) identity = [DKDanmakuIdentity new];
    identity.model = model;
    objc_setAssociatedObject(view, &kDKIdentityKey, identity, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKDanmakuBeginUpdate(view, newEntry);
}

void DKDanmakuBeginUpdate(AWEDanmakuItemCommonView *view, BOOL newEntry) {
    if (!NSThread.isMainThread) return;
    NSUInteger depth = [objc_getAssociatedObject(view, &kDKUpdateDepthKey) unsignedIntegerValue];
    // 更新期间原生对正文的各次写入不单独着色，最外层更新结束时统一着色一次。
    objc_setAssociatedObject(view, &kDKUpdateDepthKey, @(depth + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!depth) {
        [DKViews() addObject:view];
        AWEDanmakuContentLabel *label = view.contentLabel;
        DKRestoreEntry(view);
        if (newEntry) {
            objc_setAssociatedObject(label, &kDKStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(DKDigg(view).diggNumLabel, &kDKStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(DKDigg(view).diggImageView, &kDKImageStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

void DKDanmakuEndUpdate(AWEDanmakuItemCommonView *view) {
    if (!NSThread.isMainThread) return;
    NSUInteger depth = [objc_getAssociatedObject(view, &kDKUpdateDepthKey) unsignedIntegerValue];
    objc_setAssociatedObject(view, &kDKUpdateDepthKey, @(depth ? depth - 1 : 0), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (depth == 1) {
        AWEDanmakuContentLabel *label = view.contentLabel;
        if (DKState(label)) DKCapture(label, DKState(label));
        AWEDanmakuContentLabel *count = DKDigg(view).diggNumLabel;
        if (DKState(count)) DKCapture(count, DKState(count));
        DKApply(view, YES);
    }
}

void DKDanmakuResetView(AWEDanmakuItemCommonView *view) {
    if (!NSThread.isMainThread) return;
    AWEDanmakuContentLabel *label = view.contentLabel;
    DKRestoreEntry(view);
    objc_setAssociatedObject(label, &kDKStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(DKDigg(view).diggNumLabel, &kDKStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(DKDigg(view).diggImageView, &kDKImageStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kDKUpdateDepthKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kDKIdentityKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [DKViews() removeObject:view];
}

BOOL DKDanmakuViewEngaged(AWEDanmakuItemCommonView *view) {
    return DKPrefBool(DKKeyDanmakuColorEnabled) || objc_getAssociatedObject(view, &kDKIdentityKey) != nil;
}

BOOL DKDanmakuLabelEngaged(UILabel *label) {
    return DKPrefBool(DKKeyDanmakuColorEnabled) || DKState(label) != nil;
}

void DKDanmakuTrackView(AWEDanmakuItemCommonView *view) {
    if (!NSThread.isMainThread) return;
    [DKViews() addObject:view];
    if (view.window) DKApply(view, NO);
}

BOOL DKDanmakuOwnWrite(UILabel *label) {
    return !NSThread.isMainThread || [objc_getAssociatedObject(label, &kDKWriteKey) boolValue]
        || [objc_getAssociatedObject(label, &kDKDrawDepthKey) unsignedIntegerValue] > 0
        || [objc_getAssociatedObject(DKOwner(label), &kDKUpdateDepthKey) unsignedIntegerValue] > 0;
}

void DKDanmakuNativeWriteBegin(AWEDanmakuContentLabel *label) {
    if (DKDanmakuOwnWrite(label)) return;
    DKRestore(label, DKState(label));
    // 原生 setter 可能继续调用其他文字 setter，整个写入事务只在外层捕获一次。
    objc_setAssociatedObject(label, &kDKWriteKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void DKDanmakuNativeWriteFinished(AWEDanmakuContentLabel *label) {
    objc_setAssociatedObject(label, &kDKWriteKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    AWEDanmakuItemCommonView *owner = DKOwner(label);
    if (!owner) return;
    DKDanmakuLabelState *state = DKState(label);
    if (state) DKCapture(label, state);
    DKApply(owner, NO);
}

void DKDanmakuBeginDraw(UILabel *label) {
    NSUInteger depth = [objc_getAssociatedObject(label, &kDKDrawDepthKey) unsignedIntegerValue];
    objc_setAssociatedObject(label, &kDKDrawDepthKey, @(depth + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
void DKDanmakuEndDraw(UILabel *label) {
    NSUInteger depth = [objc_getAssociatedObject(label, &kDKDrawDepthKey) unsignedIntegerValue];
    objc_setAssociatedObject(label, &kDKDrawDepthKey, @(depth ? depth - 1 : 0), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void DKDanmakuColorRefresh(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DKDanmakuColorRefresh(); }); return; }
    NSString *configuration = DKConfiguration(DKColorSchemeStoredMode(DKKeyDanmakuColorMode));
    for (AWEDanmakuItemCommonView *view in DKViews().allObjects) {
        DKDanmakuLabelState *state = DKState(view.contentLabel);
        if (state && ![state.configuration isEqual:configuration]) DKRestoreEntry(view);
        DKApply(view, YES);
    }
}

double DKDanmakuNativeAlpha(void) {
    Class cls = NSClassFromString(@"AWEDanmakuConfigSettingManager");
    if (![cls respondsToSelector:@selector(sharedInstance)]) return 1;
    AWEDanmakuConfigSettingManager *manager = [cls sharedInstance];
    if (![manager respondsToSelector:@selector(verticalStylesInfo)]) return 1;
    AWEPlayInteractionDanmakuStylesInfo *style = manager.verticalStylesInfo;
    if (![style respondsToSelector:@selector(danmakuAlpha)]) return 1;
    double alpha = style.danmakuAlpha;
    return isfinite(alpha) && alpha >= 0 && alpha <= 1 ? alpha : 1;
}

NSString *DKDanmakuColorStatus(void) {
    if (!NSThread.isMainThread) return @"（非主线程，未采集）\n";
    DKColorSchemeMode mode = DKColorSchemeStoredMode(DKKeyDanmakuColorMode);
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"开关=%d 模式=%@ 固定色=%@ 渐变=%@ 原生不透明度=%.3f 配色序号=%lu\n",
        DKPrefBool(DKKeyDanmakuColorEnabled), DKColorSchemeModeTitles()[mode], DKFixedColor(), DKGradientColors(),
        DKDanmakuNativeAlpha(), (unsigned long)gDKPaletteSerial];
    NSArray *views = DKViews().allObjects;
    NSUInteger applied = 0;
    for (AWEDanmakuItemCommonView *view in views) applied += DKState(view.contentLabel).applied ? 1 : 0;
    [out appendFormat:@"已登记条目=%lu 已着色=%lu\n", (unsigned long)views.count, (unsigned long)applied];
    NSUInteger listed = 0;
    for (AWEDanmakuItemCommonView *view in views) {
        if (listed++ >= 12) break;
        AWEDanmakuContentLabel *label = view.contentLabel;
        DKDanmakuLabelState *state = DKState(label);
        NSString *text = label.attributedText.string ?: label.text ?: @"";
        if (text.length > 16) text = [[text substringToIndex:16] stringByAppendingString:@"…"];
        AWEDanmakuDiggNumView *digg = DKDigg(view);
        DKDanmakuImageState *imageState = objc_getAssociatedObject(digg.diggImageView, &kDKImageStateKey);
        [out appendFormat:@"  %@ window=%d alpha=%.3f 着色=%d 方案=%@ 原生描边=%.1f 文字=%@ 点赞=%@ 数字着色=%d 爱心着色=%d\n", NSStringFromClass(view.class),
            view.window != nil, view.alpha, state.applied, state.configuration ?: @"-", state.nativeStrokeWidth, text,
            digg.diggNumLabel.text ?: @"-", DKState(digg.diggNumLabel).applied,
            imageState.appliedImage && digg.diggImageView.image == imageState.appliedImage];
    }
    return out;
}
