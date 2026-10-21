#import "DKProfilePublishInfo.h"
#import "DKProfilePublishPrivate.h"
#import "DKPublishRegion.h"
#import "DKPublishInfo.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import <objc/runtime.h>

static char kDKProfileRows, kDKProfileBottomState, kDKProfileBottomHeight;
static NSHashTable<AWEUserWorkCellViewModel *> *gDKProfileModels;
static NSHashTable<UICollectionView *> *gDKProfileLists;

static BOOL DKProfilePublishWanted(void) {
    return DKPrefBool(DKKeyProfilePublishTime) || DKPrefBool(DKKeyProfilePublishLocation);
}

static NSString *DKProfileTime(AWEAwemeModel *model) {
    double seconds = model.createTime.doubleValue;
    if (!isfinite(seconds) || seconds <= 0) return nil;
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    });
    formatter.timeZone = NSTimeZone.localTimeZone;
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:seconds]];
}

static NSString *DKProfileLocation(AWEAwemeModel *model) {
    if (!DKPrefBool(DKKeyProfilePublishLocation)) return nil;
    NSString *username = [NSUserDefaults.standardUserDefaults stringForKey:DKKeyGeoNamesUsername];
    // 解析完成后重新读取各个作品当前绑定的数据，不保留旧 Cell 的写入回调。
    return DKPublishRegionName(model.cityCode, model.region, model.ipAttribution, username, ^(NSString *identifier) {
        DKPublishInfoRefresh();
        DKProfilePublishInfoRefresh();
    });
}

static UIFont *DKProfileFont(void) {
    return [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
}

static CGFloat DKProfileTextHeight(NSString *text, CGFloat width, UIFont *font) {
    if (!text.length || width <= 0) return 0;
    return ceil([text boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX)
        options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
        attributes:@{NSFontAttributeName:font} context:nil].size.height);
}

// 测量与绘制共用文字宽度；留白、图标和行距均随参考字体变化。
static CGFloat DKProfileRowHeight(void) {
    return ceil(DKProfileFont().lineHeight);
}

static CGFloat DKProfileRowGap(void) {
    return round(DKProfileFont().pointSize * 0.2);
}

// 双列卡片底部：时间与地区各占一行组成一块。时间开启时两行复用原生日期行的高度，
// 仅补少量余量；只开地区时地区行排在原生日期下方，需要一整行。
static CGFloat DKProfileBottomExtra(void) {
    if (!DKPrefBool(DKKeyProfilePublishLocation)) return 0;
    if (DKPrefBool(DKKeyProfilePublishTime)) return DKProfileRowGap() * 2;
    return DKProfileRowHeight() + DKProfileRowGap();
}

@interface DKProfilePublishRow : UIView
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UIImageView *icon;
- (instancetype)initWithSymbol:(NSString *)symbol;
- (void)arrangeWithTextInset:(CGFloat)inset;
@end

@implementation DKProfilePublishRow
- (instancetype)initWithSymbol:(NSString *)symbol {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.userInteractionEnabled = NO;
        _label = [UILabel new];
        _label.font = DKProfileFont();
        _label.numberOfLines = 0;
        _label.lineBreakMode = NSLineBreakByWordWrapping;
        _icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol
            withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:_label.font.pointSize
                weight:UIImageSymbolWeightRegular]]];
        _icon.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_label];
        [self addSubview:_icon];
    }
    return self;
}
- (void)arrangeWithTextInset:(CGFloat)inset {
    CGFloat edge = self.label.font.lineHeight;
    self.icon.frame = CGRectMake(0, 0, edge, edge);
    self.label.frame = CGRectMake(inset, 0, MAX(0, self.bounds.size.width - inset), self.bounds.size.height);
}
@end

@interface DKProfileCoverRows : UIView
@property (nonatomic, strong) DKProfilePublishRow *time;
@property (nonatomic, strong) DKProfilePublishRow *location;
@end

@implementation DKProfileCoverRows
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        _time = [[DKProfilePublishRow alloc] initWithSymbol:@"clock"];
        _location = [[DKProfilePublishRow alloc] initWithSymbol:@"mappin.and.ellipse"];
        for (DKProfilePublishRow *row in @[_time, _location]) {
            row.label.textColor = UIColor.whiteColor;
            row.icon.tintColor = UIColor.whiteColor;
            row.layer.shadowColor = UIColor.blackColor.CGColor;
            row.layer.shadowOpacity = 0.8;
            row.layer.shadowRadius = DKProfileFont().pointSize * 0.15;
            row.layer.shadowOffset = CGSizeMake(0, DKProfileFont().pointSize * 0.1);
            [self addSubview:row];
        }
    }
    return self;
}
@end

static id DKProfileComponent(NSArray *components, NSString *name) {
    for (id component in components) if ([NSStringFromClass([component class]) isEqualToString:name]) return component;
    return nil;
}

static void DKProfileCoverApply(AWEUserWorkCollectionViewComponentCell *cell) {
    DKProfileCoverRows *rows = objc_getAssociatedObject(cell, &kDKProfileRows);
    AWEUserWorkCellViewModel *vm = cell.viewModel;
    if (!DKProfilePublishWanted() || vm.cellContext.componentConfig.profileTabType != 0 || ![vm.rootComponent isKindOfClass:NSClassFromString(@"AWEUserWorkCellNormalRootComponent_NEWAPI")]) {
        [rows removeFromSuperview];
        objc_setAssociatedObject(cell, &kDKProfileRows, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    AWEUserWorkCellNormalRootComponent_NEWAPI *root = (id)vm.rootComponent;
    AWEUserWorkCellCoverContainerComponent_NEWAPI *coverComponent = DKProfileComponent(root.subComponents,
        @"AWEUserWorkCellCoverContainerComponent_NEWAPI");
    AWEUserWorkCellLeftBottomContainerComponent_NEWAPI *corner = DKProfileComponent(coverComponent.subComponents,
        @"AWEUserWorkCellLeftBottomContainerComponent_NEWAPI");
    AWEUserWorkCellIconLabelStarAtlasTagLabelComponent_NEWAPI *like = corner.componentDict[@"AWEUserWorkCellIconLabelStarAtlasTagLabelComponent_NEWAPI"];
    UIView *icon = like.iconViewVirtualView.renderedView;
    UILabel *label = (id)like.countLabelVirtualView.renderedView;
    UIView *cover = cell.coverContainerView;
    if (!icon.superview || !label.superview || !cover || ![label isKindOfClass:UILabel.class]) {
        [rows removeFromSuperview];
        return;
    }
    if (!rows) {
        rows = [DKProfileCoverRows new];
        objc_setAssociatedObject(cell, &kDKProfileRows, rows, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (rows.superview != cover) [cover addSubview:rows];
    CGRect iconRect = [icon convertRect:icon.bounds toView:cover];
    CGRect labelRect = [label convertRect:label.bounds toView:cover];
    CGFloat width = cover.bounds.size.width - iconRect.origin.x * 2;
    CGFloat inset = labelRect.origin.x - iconRect.origin.x;
    CGFloat textWidth = width - inset;
    if (textWidth <= 0) { rows.hidden = YES; return; }
    rows.hidden = NO;
    AWEAwemeModel *model = vm.cellContext.data;
    NSString *time = DKPrefBool(DKKeyProfilePublishTime) ? DKProfileTime(model) : nil;
    NSString *location = DKProfileLocation(model);
    UIFont *font = DKProfileFont();
    CGFloat gap = font.lineHeight * 0.25;
    UIFont *timeFont = font;
    if ([time sizeWithAttributes:@{NSFontAttributeName:font}].width > textWidth) {
        CGFloat low = 1, high = font.pointSize;
        for (NSUInteger i = 0; i < 10; i++) {
            CGFloat size = (low + high) / 2;
            UIFont *candidate = [font fontWithSize:size];
            if ([time sizeWithAttributes:@{NSFontAttributeName:candidate}].width <= textWidth) low = size;
            else high = size;
        }
        timeFont = [font fontWithSize:low];
    }
    rows.time.label.font = timeFont;
    rows.time.label.text = time;
    rows.time.label.numberOfLines = 1;
    rows.location.label.text = location;
    rows.location.label.font = font;
    CGFloat timeHeight = time.length ? ceil(font.lineHeight) : 0;
    CGFloat available = MAX(0, CGRectGetMinY(iconRect) - gap * 2 - timeHeight);
    CGFloat locationHeight = DKProfileTextHeight(location, textWidth, font);
    // 极长地区仍完整展示，按封面剩余高度寻找可容纳的字号。
    if (locationHeight > available && available > 0) {
        CGFloat low = 1, high = font.pointSize;
        for (NSUInteger i = 0; i < 10; i++) {
            CGFloat size = (low + high) / 2;
            if (DKProfileTextHeight(location, textWidth, [font fontWithSize:size]) <= available) low = size;
            else high = size;
        }
        rows.location.label.font = [font fontWithSize:low];
        locationHeight = DKProfileTextHeight(location, textWidth, rows.location.label.font);
    }
    CGFloat between = timeHeight && locationHeight ? gap : 0;
    CGFloat height = timeHeight + locationHeight + between;
    rows.frame = CGRectMake(iconRect.origin.x, CGRectGetMinY(iconRect) - gap - height, width, height);
    rows.location.frame = CGRectMake(0, 0, width, locationHeight);
    rows.time.frame = CGRectMake(0, locationHeight + between, width, timeHeight);
    [rows.location arrangeWithTextInset:inset];
    [rows.time arrangeWithTextInset:inset];
    rows.location.hidden = !location.length;
    rows.time.hidden = !time.length;
}

@interface DKProfileBottomState : NSObject
@property (nonatomic, weak) AWEUserWorkCellWaterFallBottomContainerComponent_NEWAPI *component;
@property (nonatomic, strong) DKProfilePublishRow *time;
@property (nonatomic, strong) DKProfilePublishRow *location;
@property (nonatomic, strong) UIFont *dateFont;
@property (nonatomic, copy) NSString *nativeDate;
@property (nonatomic) BOOL nativeAdjustsFont;
@property (nonatomic) CGFloat nativeMinimumScale;
@property (nonatomic) BOOL hiddenByUs;
@end
@implementation DKProfileBottomState
@end

static void DKProfileBottomApply(AWEUserWorkWaterFallBottomView *view) {
    DKProfileBottomState *state = objc_getAssociatedObject(view, &kDKProfileBottomState);
    if (!state) return;
    BOOL own = state.component.context.componentConfig.profileTabType == 0;
    NSString *time = own && DKPrefBool(DKKeyProfilePublishTime) ? DKProfileTime(state.component.data) : nil;
    NSString *location = own ? DKProfileLocation(state.component.data) : nil;
    UIFont *font = DKProfileFont();
    CGFloat rowHeight = DKProfileRowHeight();
    CGFloat gap = DKProfileRowGap();

    // 时间由自绘行展示时隐藏原生日期行；关闭时恢复原生相对时间。
    if (time.length) {
        view.dateLabel.hidden = YES;
        state.hiddenByUs = YES;
    } else {
        if (state.hiddenByUs) view.dateLabel.hidden = NO;
        state.hiddenByUs = NO;
        view.dateLabel.font = state.dateFont;
        view.dateLabel.adjustsFontSizeToFitWidth = state.nativeAdjustsFont;
        view.dateLabel.minimumScaleFactor = state.nativeMinimumScale;
        if (![view.dateLabel.text isEqualToString:state.nativeDate]) view.dateLabel.text = state.nativeDate;
    }

    if (!state.time) {
        state.time = [[DKProfilePublishRow alloc] initWithSymbol:@"clock"];
        [view addSubview:state.time];
    }
    if (!state.location) {
        state.location = [[DKProfilePublishRow alloc] initWithSymbol:@"mappin.and.ellipse"];
        [view addSubview:state.location];
    }
    UIColor *color = view.dateLabel.textColor;
    for (DKProfilePublishRow *row in @[state.time, state.location]) {
        row.label.font = font;
        row.label.numberOfLines = 1;
        row.label.adjustsFontSizeToFitWidth = YES;
        row.label.minimumScaleFactor = 0.5;
        row.label.textColor = color;
        row.icon.tintColor = color;
    }
    state.time.label.text = time;
    state.location.label.text = location;

    BOOL showTime = time.length > 0;
    BOOL showLocation = location.length > 0;
    CGFloat left = CGRectGetMinX(view.dateLabel.frame);
    CGFloat right = view.iconImageView ? CGRectGetMinX(view.iconImageView.frame) : CGRectGetMaxX(view.bounds) - left;
    CGFloat width = MAX(0, right - left - gap * 2);
    if (width <= 0) width = MAX(0, CGRectGetWidth(view.bounds) - left * 2);
    CGFloat inset = rowHeight + gap;
    CGFloat blockHeight = (showTime ? rowHeight : 0) + (showLocation ? rowHeight : 0)
        + (showTime && showLocation ? gap : 0);
    // 时间与地区两行的中点落在爱心图标中线上，与爱心加数字同一行。
    CGRect anchor = view.iconImageView ? view.iconImageView.frame : CGRectZero;
    if (CGRectGetHeight(anchor) <= 0) anchor = view.dateLabel.frame;
    CGFloat top = showTime ? CGRectGetMidY(anchor) - blockHeight / 2
                           : CGRectGetMaxY(view.dateLabel.frame) + gap;
    top = MAX(0, top);
    CGFloat y = top;
    if (showTime) {
        state.time.hidden = NO;
        state.time.frame = CGRectMake(left, y, width, rowHeight);
        [state.time arrangeWithTextInset:inset];
        y += rowHeight + gap;
    } else {
        state.time.hidden = YES;
    }
    if (showLocation) {
        state.location.hidden = NO;
        state.location.frame = CGRectMake(left, y, width, rowHeight);
        [state.location arrangeWithTextInset:inset];
    } else {
        state.location.hidden = YES;
    }
}

void DKProfilePublishInfoRefresh(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKProfilePublishInfoRefresh(); });
        return;
    }
    static BOOL queued;
    if (queued) return;
    queued = YES;
    // 合并同一轮解析回调，等当前绑定、布局结束后刷新列表。
    dispatch_async(dispatch_get_main_queue(), ^{
        queued = NO;
        for (AWEUserWorkCellViewModel *vm in gDKProfileModels.allObjects) {
            [vm refreshWithWidth:vm.width indexPath:vm.indexPath];
            [vm.rootComponent setNeedsUpdate];
        }
        for (UICollectionView *list in gDKProfileLists.allObjects) {
            [list.collectionViewLayout invalidateLayout];
            [list reloadData];
        }
    });
}

%hook AWEProfileWaterfallHelper
- (CGFloat)calculateCellHeight:(NSInteger)style model:(AWEAwemeModel *)model cellWidth:(CGFloat)width
                       isMine:(BOOL)mine interactionTopPadding:(CGFloat)padding
       forceHiddenInteraction:(BOOL)hidden profileTabType:(NSInteger)tabType {
    CGFloat height = %orig;
    if (tabType != 0 || hidden) return height;
    return height + DKProfileBottomExtra();
}
%end

%hook AWEUserWorkCellWaterFallBottomContainerComponent_NEWAPI
- (id)buildVirtualView:(id)data {
    CGFloat extra = self.context.componentConfig.profileTabType == 0 ? DKProfileBottomExtra() : 0;
    CGFloat previous = [objc_getAssociatedObject(self, &kDKProfileBottomHeight) doubleValue];
    if (fabs(extra - previous) > 0.5) {
        // 原生容器按宽度缓存尺寸；底部行数变化时让原生重新建立信息区。
        self.containerVirtualView = nil;
        objc_setAssociatedObject(self, &kDKProfileBottomHeight, @(extra), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return %orig;
}
- (void)configBottomView:(AWEUserWorkWaterFallBottomView *)view {
    %orig;
    DKProfileBottomState *state = objc_getAssociatedObject(view, &kDKProfileBottomState);
    if (!state && !DKProfilePublishWanted()) return;
    if (!state) {
        state = [DKProfileBottomState new];
        state.dateFont = view.dateLabel.font;
        state.nativeDate = view.dateLabel.text;
        state.nativeAdjustsFont = view.dateLabel.adjustsFontSizeToFitWidth;
        state.nativeMinimumScale = view.dateLabel.minimumScaleFactor;
        objc_setAssociatedObject(view, &kDKProfileBottomState, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    state.component = self;
    DKProfileBottomApply(view);
    [view setNeedsLayout];
}
%end

%hook AWEUserWorkWaterFallBottomView
- (void)setDateStringWith:(NSString *)date {
    %orig;
    DKProfileBottomState *state = objc_getAssociatedObject(self, &kDKProfileBottomState);
    state.nativeDate = self.dateLabel.text;
}
- (void)layoutSubviews {
    %orig;
    DKProfileBottomApply(self);
}
%end

static void DKProfileTrackCell(AWEUserWorkCollectionViewComponentCell *cell) {
    AWEUserWorkCellViewModel *vm = cell.viewModel;
    if (!vm || vm.cellContext.componentConfig.profileTabType != 0) return;
    if (!gDKProfileModels) gDKProfileModels = [NSHashTable weakObjectsHashTable];
    [gDKProfileModels addObject:vm];
    UIView *ancestor = cell.superview;
    while (ancestor && ![ancestor isKindOfClass:UICollectionView.class]) ancestor = ancestor.superview;
    if (ancestor) {
        if (!gDKProfileLists) gDKProfileLists = [NSHashTable weakObjectsHashTable];
        [gDKProfileLists addObject:(id)ancestor];
    }
}

%hook AWEUserWorkCollectionViewComponentCell
- (void)configWithViewModel:(AWEUserWorkCellViewModel *)vm {
    %orig;
    DKProfileTrackCell(self);
    DKProfileCoverApply(self);
}
- (void)layoutSubviews {
    %orig;
    DKProfileTrackCell(self);
    DKProfileCoverApply(self);
}
- (void)prepareForReuse {
    DKProfileCoverRows *rows = objc_getAssociatedObject(self, &kDKProfileRows);
    [rows removeFromSuperview];
    objc_setAssociatedObject(self, &kDKProfileRows, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
}
%end

%ctor {
    DKSettingsRegister(DKKeyProfilePublishTime, ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(DKKeyProfilePublishTime, @"显示作品发布时间",
            @"主页三列封面在点赞上方显示完整年月日与时分秒；双列卡片替换原生日期。按设备时区显示。"),
            ^{ DKProfilePublishInfoRefresh(); });
    });
    DKSettingsRegister(DKKeyProfilePublishLocation, ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(DKKeyProfilePublishLocation, @"显示作品发布地区",
            @"主页三列封面在时间与点赞上方显示地区；双列卡片在日期下方显示地区。长地区自动换行，无地区数据时不显示。国外解析共用「视频 → 发布时间与地区」中的 GeoNames 账号。"),
            ^{ DKProfilePublishInfoRefresh(); });
    });
}
