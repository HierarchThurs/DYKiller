//
//  DKPublishInfoHooks.xm
//  DYKiller
//
//  播放页文案下方一行：具体发布时间与发布地区。
//
//  实现：
//   - 借用左侧栈的原生时间元素 AWEPlayInteractionTimestampElement。开启任一项时强制激活它，作为文案下方
//     独立一行参与原生排布与收拢；它是左侧元素，透明度与缩放随「昵称文案外观」的文案组。
//   - 原生只在少数页面激活这一行（shouldActiveWithData:context: 按页面判定）；换作品时先 setModel:，
//     再由 layoutElementView 重写文字。接管点就是 layoutElementView：能写出本功能的一行时不调原生实现，
//     原生与本功能不会在每轮布局里交替写入。
//   - 换作品时用原生激活判定记下原生是否本来显示这一行；原生显示的页面，未开启的一项保留原生内容
//     （原生日期、原生属地），原生不显示且本功能无内容时收起这一行。
//   - 一行为「时间  地区」，地区不带前缀。原生把标签宽度钉成行宽；文字更长时加大该约束常量向右延伸，
//     右界为交互层里与这一行垂直重叠的其他元素栈可见行（右侧互动区等），没有时为交互层右缘；
//     仍放不下的部分按原生截断。左侧栈排布后按最终几何重算。
//   - 时间与地区各自着色；随机与旋转彩虹的配色按作品生成一次。国外地名查到后只刷新该地名 ID 的元素。
//

#import "DKPublishInfo.h"
#import "DKPublishRegion.h"
#import "DouyinHeaders.h"
#import "DKColorScheme.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <math.h>

static char kDKPublishStateKey;

// 一段文字的配色：方案标识不变时沿用同一组颜色。
@interface DKPublishPartColor : NSObject
@property (nonatomic, copy) NSString *signature;
@property (nonatomic, copy) NSArray<UIColor *> *colors;
@end

@implementation DKPublishPartColor
@end

@interface DKPublishInfoState : NSObject
@property (nonatomic, weak) AWEAwemeModel *model;
@property (nonatomic) BOOL nativeActive;      // 原生对当前作品与页面是否显示这一行
@property (nonatomic) BOOL applied;           // 当前文字由本功能写入
// 原生标签样式：写富文本会改掉标签的 font / textColor，恢复原生文字前写回。
@property (nonatomic, strong) UIFont *baseFont;
@property (nonatomic, strong) UIColor *baseColor;
// 原生「标签宽 = 行宽」约束；文字更长时加大常量向右延伸，恢复原生时写回。
@property (nonatomic, weak) NSLayoutConstraint *widthConstraint;
@property (nonatomic) CGFloat baseWidthConstant;
@property (nonatomic, strong) DKPublishPartColor *timeColor;
@property (nonatomic, strong) DKPublishPartColor *locationColor;
@end

@implementation DKPublishInfoState
@end

static NSHashTable<AWEPlayInteractionTimestampElement *> *gDKPublishElements;
// 配色序号：旋转彩虹按它轮换起始色，时间与地区各自计数。
static NSUInteger gDKTimeSerial, gDKLocationSerial;
// 原生激活判定（安装 Hook 前取得的实现）。
static BOOL (*gDKNativeShouldActive)(id, SEL, id, id);

static BOOL DKPublishInfoWanted(void) {
    return DKPrefBool(DKKeyPublishTimeEnabled) || DKPrefBool(DKKeyPublishLocationEnabled);
}

static DKPublishInfoState *DKPublishState(AWEPlayInteractionTimestampElement *element) {
    return objc_getAssociatedObject(element, &kDKPublishStateKey);
}

#pragma mark - 字段

static id DKModelValue(AWEAwemeModel *model, SEL selector) {
    if (![model respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(model, selector);
}

static NSString *DKModelString(AWEAwemeModel *model, SEL selector) {
    id value = DKModelValue(model, selector);
    return [value isKindOfClass:NSString.class] ? value : nil;
}

// 作品创建时间（秒）；毫秒值按量级换算，缺失或非法返回 0。
static double DKCreateSeconds(AWEAwemeModel *model) {
    id value = DKModelValue(model, @selector(createTime));
    double seconds = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0;
    if (!isfinite(seconds) || seconds <= 0) return 0;
    return seconds > 1e11 ? seconds / 1000 : seconds;
}

static NSString *DKPublishTimeText(double seconds) {
    if (seconds <= 0) return nil;
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = NSTimeZone.localTimeZone;
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    });
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:seconds]];
}

static NSString *DKNativeDateText(AWEPlayInteractionTimestampElement *element, double seconds) {
    Class cls = element.class;
    if (seconds <= 0 || ![cls respondsToSelector:@selector(formattedDateForFullTimestamp:)]) return nil;
    NSString *text = [cls formattedDateForFullTimestamp:seconds];
    return [text isKindOfClass:NSString.class] && text.length ? text : nil;
}

static NSString *DKNativeAttribution(AWEAwemeModel *model) {
    return DKPublishRegionName(nil, nil, DKModelString(model, @selector(ipAttribution)), nil, nil);
}

static BOOL DKNativeActive(AWEPlayInteractionTimestampElement *element, AWEAwemeModel *model) {
    if (!gDKNativeShouldActive || !model) return NO;
    id context = [element respondsToSelector:@selector(context)] ? element.context : nil;
    return gDKNativeShouldActive(element.class, @selector(shouldActiveWithData:context:), model, context);
}

#pragma mark - 着色

static NSArray<UIColor *> *DKPartColors(DKPublishInfoState *state, BOOL location) {
    if (!DKPrefBool(location ? DKKeyPublishLocationColorEnabled : DKKeyPublishTimeColorEnabled)) return nil;
    DKColorSchemeMode mode = DKColorSchemeStoredMode(location ? DKKeyPublishLocationColorMode : DKKeyPublishTimeColorMode);
    NSString *fixed = DKColorSchemeStoredColor(location ? DKKeyPublishLocationFixedColor : DKKeyPublishTimeFixedColor, NO);
    NSString *gradient = DKColorSchemeStoredColor(location ? DKKeyPublishLocationGradientColors : DKKeyPublishTimeGradientColors, YES);
    NSString *signature = DKColorSchemeSignature(mode, fixed, gradient);
    DKPublishPartColor *part = location ? state.locationColor : state.timeColor;
    if (![part.signature isEqualToString:signature]) {
        part = [DKPublishPartColor new];
        part.signature = signature;
        part.colors = DKColorSchemePalette(mode, fixed, gradient, location ? gDKLocationSerial++ : gDKTimeSerial++);
        if (location) state.locationColor = part;
        else state.timeColor = part;
    }
    return part.colors;
}

// 追加一段文字；有配色时按这段在整行里的横向位置生成渐变。
static void DKAppendPart(NSMutableAttributedString *line, NSString *text, NSArray<UIColor *> *colors,
                         UIFont *font, UIColor *baseColor, CGFloat scale) {
    UIColor *color = baseColor;
    if (colors.count) {
        CGFloat start = ceil(line.size.width);
        CGFloat width = ceil([text sizeWithAttributes:@{ NSFontAttributeName: font }].width);
        color = DKColorSchemeRender(colors, start, MAX(1, width), scale);
    }
    [line appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: font, NSForegroundColorAttributeName: color,
    }]];
}

#pragma mark - 应用

static void DKPublishInfoRefreshGeoname(NSString *geonameId);

// 本功能要写的一行；两项都没有本功能的内容时返回 nil，保持原生。
static NSAttributedString *DKPublishLine(AWEPlayInteractionTimestampElement *element, DKPublishInfoState *state, UILabel *label) {
    AWEAwemeModel *model = state.model;
    double seconds = DKCreateSeconds(model);
    NSString *time = DKPrefBool(DKKeyPublishTimeEnabled) ? DKPublishTimeText(seconds) : nil;
    BOOL ownTime = time != nil;
    if (!time && state.nativeActive) time = DKNativeDateText(element, seconds);

    NSString *location = nil;
    if (DKPrefBool(DKKeyPublishLocationEnabled)) {
        location = DKPublishRegionName(DKModelString(model, @selector(cityCode)), DKModelString(model, @selector(region)),
                                       DKModelString(model, @selector(ipAttribution)),
                                       [NSUserDefaults.standardUserDefaults stringForKey:DKKeyGeoNamesUsername],
                                       ^(NSString *geonameId) { DKPublishInfoRefreshGeoname(geonameId); });
    }
    BOOL ownLocation = location != nil;
    if (!location && state.nativeActive) location = DKNativeAttribution(model);
    if (!ownTime && !ownLocation) return nil;

    UIFont *font = state.baseFont ?: [UIFont systemFontOfSize:12];
    UIColor *baseColor = state.baseColor ?: UIColor.whiteColor;
    CGFloat scale = label.traitCollection.displayScale > 0 ? label.traitCollection.displayScale : UIScreen.mainScreen.scale;
    NSMutableAttributedString *line = [NSMutableAttributedString new];
    if (time) DKAppendPart(line, time, ownTime ? DKPartColors(state, NO) : nil, font, baseColor, scale);
    if (location) {
        if (line.length) DKAppendPart(line, @"  ", nil, font, baseColor, scale);
        DKAppendPart(line, location, ownLocation ? DKPartColors(state, YES) : nil, font, baseColor, scale);
    }
    return line;
}

#pragma mark - 宽度

// 原生在 setUpUI 里把标签宽度钉成行宽（MAS：label.width == row.width）。
static NSLayoutConstraint *DKPublishWidthConstraint(UILabel *label) {
    UIView *row = label.superview;
    for (NSLayoutConstraint *constraint in row.constraints) {
        if (constraint.firstItem == label && constraint.firstAttribute == NSLayoutAttributeWidth
            && constraint.secondItem == row && constraint.secondAttribute == NSLayoutAttributeWidth
            && constraint.relation == NSLayoutRelationEqual && constraint.multiplier == 1) return constraint;
    }
    return nil;
}

// 标签可用的宽度（行坐标，从标签左缘起）：右界是交互层里其他元素栈中与标签垂直重叠、位于标签右侧的
// 可见行的左缘，没有时为交互层右缘；两者都再让出与左侧栈左边距相同的间距。取不到几何时返回 0。
static CGFloat DKPublishAvailableWidth(UILabel *label) {
    static Class stackClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ stackClass = NSClassFromString(@"AWEElementStackView"); });
    UIView *row = label.superview;
    UIView *stack = row.superview;
    UIView *root = stack.superview;
    if (!stackClass || ![stack isKindOfClass:stackClass] || !root || CGRectIsEmpty(row.bounds)) return 0;

    CGRect labelRect = [label convertRect:label.bounds toView:root];
    CGFloat margin = MAX(0, CGRectGetMinX([stack convertRect:stack.bounds toView:root]));
    CGFloat limit = CGRectGetMaxX(root.bounds) - margin;
    for (UIView *ancestor = row; ancestor != root; ancestor = ancestor.superview) {
        if (ancestor.clipsToBounds) limit = MIN(limit, CGRectGetMaxX([ancestor convertRect:ancestor.bounds toView:root]));
    }
    for (UIView *other in root.subviews) {
        if (other == stack || ![other isKindOfClass:stackClass] || other.hidden || other.alpha < 0.01) continue;
        for (UIView *item in ((UIStackView *)other).arrangedSubviews) {
            if (item.hidden || item.alpha < 0.01 || CGRectIsEmpty(item.bounds)) continue;
            CGRect rect = [item convertRect:item.bounds toView:root];
            if (CGRectGetMinX(rect) <= CGRectGetMinX(labelRect)
                || CGRectGetMaxY(rect) <= CGRectGetMinY(labelRect) || CGRectGetMinY(rect) >= CGRectGetMaxY(labelRect)) continue;
            limit = MIN(limit, CGRectGetMinX(rect) - margin);
        }
    }
    CGPoint end = [row convertPoint:CGPointMake(limit, CGRectGetMidY(labelRect)) fromView:root];
    return MAX(0, end.x - CGRectGetMinX(label.frame));
}

// 文字比原生宽度长时，在不碰到其他元素的范围内向右加宽；仍放不下的部分按原生截断。
static void DKPublishFitWidth(UILabel *label, DKPublishInfoState *state) {
    NSLayoutConstraint *constraint = state.widthConstraint;
    if (!constraint.active || constraint.firstItem != label) {
        constraint = DKPublishWidthConstraint(label);
        if (!constraint) return;
        state.widthConstraint = constraint;
        state.baseWidthConstant = constraint.constant;
    }
    CGFloat nativeWidth = CGRectGetWidth(label.superview.bounds) + state.baseWidthConstant;
    CGFloat needed = ceil(label.attributedText.size.width);
    CGFloat constant = state.baseWidthConstant;
    if (needed > nativeWidth) constant += MAX(0, MIN(needed, DKPublishAvailableWidth(label)) - nativeWidth);
    if (constraint.constant != constant) constraint.constant = constant;
}

static void DKPublishRestoreWidth(DKPublishInfoState *state) {
    NSLayoutConstraint *constraint = state.widthConstraint;
    if (constraint && constraint.constant != state.baseWidthConstant) constraint.constant = state.baseWidthConstant;
}

// 对齐当前作品：首次记下原生标签样式并登记；换作品时清掉配色，重新取原生的显示判定。
static DKPublishInfoState *DKPublishSync(AWEPlayInteractionTimestampElement *element) {
    DKPublishInfoState *state = DKPublishState(element);
    if (!state) {
        state = [DKPublishInfoState new];
        state.baseFont = element.timestampLabel.font;
        state.baseColor = element.timestampLabel.textColor;
        objc_setAssociatedObject(element, &kDKPublishStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!gDKPublishElements) gDKPublishElements = [NSHashTable weakObjectsHashTable];
        [gDKPublishElements addObject:element];
    }
    AWEAwemeModel *model = element.model;
    if (state.model != model) {
        state.model = model;
        state.timeColor = nil;
        state.locationColor = nil;
        state.nativeActive = DKNativeActive(element, model);
    }
    return state;
}

// 写入本功能的一行；写不出时返回 NO，并把标签样式还给原生。
static BOOL DKPublishApply(AWEPlayInteractionTimestampElement *element, DKPublishInfoState *state) {
    UILabel *label = element.timestampLabel;
    if (![label isKindOfClass:UILabel.class]) return NO;
    NSAttributedString *line = DKPublishInfoWanted() ? DKPublishLine(element, state, label) : nil;
    if (!line) {
        if (state.applied) {
            label.font = state.baseFont;
            label.textColor = state.baseColor;
            DKPublishRestoreWidth(state);
        }
        state.applied = NO;
        return NO;
    }
    state.applied = YES;
    if (!element.appear) element.appear = YES;
    if (![label.attributedText isEqualToAttributedString:line]) label.attributedText = line;
    DKPublishFitWidth(label, state);
    return YES;
}

void DKPublishInfoApplyStack(UIView *stack) {
    if (!DKPublishInfoWanted()) return;
    // 左栈或同层其他栈排布后，按最终几何重算已接管行的宽度。
    for (AWEPlayInteractionTimestampElement *element in gDKPublishElements.allObjects) {
        DKPublishInfoState *state = DKPublishState(element);
        UILabel *label = element.timestampLabel;
        UIView *left = label.superview.superview;
        if (state.applied && left && (left == stack || left.superview == stack.superview)) DKPublishFitWidth(label, state);
    }
}

static void DKPublishInfoRefreshGeoname(NSString *geonameId) {
    for (AWEPlayInteractionTimestampElement *element in gDKPublishElements.allObjects) {
        AWEAwemeModel *model = DKPublishState(element).model;
        if ([DKModelString(model, @selector(cityCode)) isEqualToString:geonameId]) [element layoutElementView];
    }
}

void DKPublishInfoRefresh(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKPublishInfoRefresh(); });
        return;
    }
    // 开启时写入本功能的一行；关闭时写回原生文字并恢复原生的显示判定。
    for (AWEPlayInteractionTimestampElement *element in gDKPublishElements.allObjects) [element layoutElementView];
}

#pragma mark - 诊断

NSString *DKPublishInfoStatus(void) {
    if (!NSThread.isMainThread) return @"（非主线程，未采集）\n";
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"时间=%d 地区=%d 时间改色=%d(模式 %ld) 地区改色=%d(模式 %ld) GeoNames 账号=%@ 原生判定=%@\n",
        DKPrefBool(DKKeyPublishTimeEnabled), DKPrefBool(DKKeyPublishLocationEnabled),
        DKPrefBool(DKKeyPublishTimeColorEnabled), (long)DKColorSchemeStoredMode(DKKeyPublishTimeColorMode),
        DKPrefBool(DKKeyPublishLocationColorEnabled), (long)DKColorSchemeStoredMode(DKKeyPublishLocationColorMode),
        [NSUserDefaults.standardUserDefaults stringForKey:DKKeyGeoNamesUsername].length ? @"已填写" : @"未填写",
        gDKNativeShouldActive ? @"已取得" : @"缺失"];
    [out appendString:DKPublishRegionStatus()];
    NSArray *elements = gDKPublishElements.allObjects;
    [out appendFormat:@"已登记时间元素=%lu\n", (unsigned long)elements.count];
    for (AWEPlayInteractionTimestampElement *element in elements) {
        DKPublishInfoState *state = DKPublishState(element);
        AWEAwemeModel *model = state.model;
        UILabel *label = element.timestampLabel;
        UIView *row = label.superview;
        [out appendFormat:@"  原生激活=%d appear=%d 接管=%d 行=%@ hidden=%d window=%d 标签宽=%.0f 需要=%.0f 延伸=%.0f 可用=%.0f\n",
            state.nativeActive, element.appear, state.applied, row ? NSStringFromCGRect(row.frame) : @"-", row.isHidden,
            row.window != nil, CGRectGetWidth(label.bounds), ceil(label.attributedText.size.width),
            state.widthConstraint.constant - state.baseWidthConstant, label ? DKPublishAvailableWidth(label) : 0];
        [out appendFormat:@"    createTime=%.0f city=%@ region=%@ ip=%@ 文字=%@\n", DKCreateSeconds(model),
            DKModelString(model, @selector(cityCode)) ?: @"-", DKModelString(model, @selector(region)) ?: @"-",
            DKNativeAttribution(model) ?: @"-", element.timestampLabel.text ?: @"-"];
    }
    return out;
}

#pragma mark - 钩子

%hook AWEPlayInteractionTimestampElement

+ (BOOL)shouldActiveWithData:(id)data context:(id)context {
    if (DKPublishInfoWanted()) return YES;
    return %orig;
}

- (void)layoutElementView {
    if (!DKPublishInfoWanted() && !DKPublishState(self)) {
        %orig;
        return;
    }
    DKPublishInfoState *state = DKPublishSync(self);
    if (DKPublishApply(self, state)) return;
    %orig;
    // 本功能无内容时按原生判定显示或收起这一行。
    if (self.appear != state.nativeActive) self.appear = state.nativeActive;
}

%end

%ctor {
    Class cls = objc_getClass("AWEPlayInteractionTimestampElement");
    Method method = cls ? class_getClassMethod(cls, @selector(shouldActiveWithData:context:)) : NULL;
    if (method) gDKNativeShouldActive = (BOOL (*)(id, SEL, id, id))method_getImplementation(method);
    %init;
}
