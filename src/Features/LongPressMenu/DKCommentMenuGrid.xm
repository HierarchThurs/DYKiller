//
//  DKCommentMenuGrid.xm
//  长按菜单：评论长按菜单的宫格排列 —— 普通分区内按设置把菜单项排成每行 2–4 个。
//
//  实现：
//   - 列表是 UICollectionViewFlowLayout：普通分区控制器按列返回格子尺寸，首列与末列各带 16pt 边距；
//     分区最后一项补满本行剩余宽度，流式布局不会把不满的一行拉开或居中。
//   - 每格仍是原生行 cell：配置时记下序号、项数与列数，布局后把行内卡片层（contentShapeLayer）
//     改成该格在分区卡片里的那一块（外角圆角），隐藏行间分割线。
//   - 二列沿用横排，补宽格的内容整体居中；三、四列将图标与文字上下排列，文字宽度由原生边距约束控制。
//   - 「分享面板液态玻璃」开启时卡片层左右各让 3pt，玻璃按卡片层几何挂成一格一枚；
//     本文件的布局钩子先于分享面板玻璃安装（源文件按路径排序，LongPressMenu 在 Share 之前），
//     玻璃读到的是改过的卡片层。
//   - 设置在下一次打开菜单时生效。
//

#import "DouyinHeaders.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKLongPressMenu.h"
#import "DKUtils.h"
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const kDKCommentNormalSectionClass = @"AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelNormalSectionController";
static const CGFloat kDKCommentCardInset = 16.0;
static const CGFloat kDKCommentCardRadius = 8.0;
static const CGFloat kDKCommentTileHeight = 73.0;
static const CGFloat kDKCommentTileTop = 12.0;
static const CGFloat kDKCommentTileGap = 6.0;
static const CGFloat kDKCommentLabelInset = 4.0;
static const CGFloat kDKCommentLabelMinScale = 0.75;
static const CGFloat kDKCommentGlassGap = 3.0;

static char kDKGridInfoKey;        // NSArray @[序号, 项数, 列数]
static char kDKGridAdjustedKey;    // 本 cell 上改过的视图与层
static char kDKGridLabelKey;       // 文字原排版

@interface DKCommentGridLabelState : NSObject
@property (nonatomic, weak) UILabel *label;
@property (nonatomic, weak) NSLayoutConstraint *leading;
@property (nonatomic, weak) NSLayoutConstraint *trailing;
@property (nonatomic) CGFloat nativeLeading;
@property (nonatomic) CGFloat nativeTrailing;
@property (nonatomic) CGFloat appliedLeading;
@property (nonatomic) CGFloat appliedTrailing;
@property (nonatomic) NSInteger lines;
@property (nonatomic) NSTextAlignment alignment;
@property (nonatomic) NSLineBreakMode lineBreakMode;
@property (nonatomic) BOOL adjustsFontSize;
@property (nonatomic) CGFloat minimumScale;
@end

@implementation DKCommentGridLabelState
@end

@interface DKCommentGridSection : NSObject
- (NSInteger)numberOfItems;
- (UIViewController *)viewController;
- (CGSize)sizeForItemAtIndex:(NSInteger)index model:(id)model collectionViewSize:(CGSize)size;
- (void)configCell:(id)cell index:(NSInteger)index model:(id)model;
@end

#pragma mark - 几何

typedef struct {
    NSInteger index, count, columns, column, row, rows;
    BOOL last;
} DKGridSlot;

static BOOL DKGridSlotFrom(NSArray *info, DKGridSlot *slot) {
    if (![info isKindOfClass:NSArray.class] || info.count != 3) return NO;
    slot->index = [info[0] integerValue];
    slot->count = [info[1] integerValue];
    slot->columns = [info[2] integerValue];
    if (slot->columns < 2 || slot->count <= 0 || slot->index < 0 || slot->index >= slot->count) return NO;
    slot->column = slot->index % slot->columns;
    slot->row = slot->index / slot->columns;
    slot->rows = (slot->count + slot->columns - 1) / slot->columns;
    slot->last = slot->index == slot->count - 1;
    return YES;
}

static CGFloat DKGridColumnWidth(CGFloat containerWidth, NSInteger columns) {
    return floor((containerWidth - kDKCommentCardInset * 2.0) / columns);
}

// 格子在分区内的宽度：首列含左边距；末列或分区最后一项补满到右边距外。
static CGFloat DKGridItemWidth(CGFloat containerWidth, DKGridSlot slot) {
    CGFloat column = DKGridColumnWidth(containerWidth, slot.columns);
    CGFloat left = kDKCommentCardInset + column * slot.column;
    if (slot.column == slot.columns - 1 || slot.last) return containerWidth - left + (slot.column == 0 ? kDKCommentCardInset : 0.0);
    return column + (slot.column == 0 ? kDKCommentCardInset : 0.0);
}

static BOOL DKGridReachesRight(DKGridSlot slot) {
    return slot.column == slot.columns - 1 || slot.last;
}

#pragma mark - cell 调整

static id DKCellIvar(UIView *cell, const char *name) {
    Class base = NSClassFromString(@"CommentLongPressPanelNormalBaseCell");
    Ivar ivar = base ? class_getInstanceVariable(base, name) : NULL;
    if (!ivar || ![cell isKindOfClass:base]) return nil;
    return (__bridge id)(*(void **)((uint8_t *)(__bridge void *)cell + ivar_getOffset(ivar)));
}

static NSMutableDictionary *DKGridAdjusted(UIView *cell, BOOL create) {
    NSMutableDictionary *adjusted = objc_getAssociatedObject(cell, &kDKGridAdjustedKey);
    if (!adjusted && create) {
        adjusted = [NSMutableDictionary dictionary];
        adjusted[@"views"] = [NSMapTable weakToStrongObjectsMapTable];
        adjusted[@"layers"] = [NSHashTable weakObjectsHashTable];
        objc_setAssociatedObject(cell, &kDKGridAdjustedKey, adjusted, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return adjusted;
}

static void DKGridRestoreLabel(UIView *cell, DKCommentGridLabelState *state) {
    if (!state) return;
    NSLayoutConstraint *leading = state.leading;
    NSLayoutConstraint *trailing = state.trailing;
    if (leading.constant == state.appliedLeading) leading.constant = state.nativeLeading;
    if (trailing.constant == state.appliedTrailing) trailing.constant = state.nativeTrailing;

    UILabel *label = state.label;
    label.numberOfLines = state.lines;
    label.textAlignment = state.alignment;
    label.lineBreakMode = state.lineBreakMode;
    label.adjustsFontSizeToFitWidth = state.adjustsFontSize;
    label.minimumScaleFactor = state.minimumScale;
    objc_setAssociatedObject(cell, &kDKGridLabelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DKGridRestoreCell(UIView *cell) {
    NSMutableDictionary *adjusted = DKGridAdjusted(cell, NO);
    if (!adjusted) return;
    NSMapTable<UIView *, NSValue *> *views = adjusted[@"views"];
    for (UIView *view in views) view.transform = [views objectForKey:view].CGAffineTransformValue;
    for (CALayer *layer in [adjusted[@"layers"] allObjects]) layer.hidden = NO;
    DKGridRestoreLabel(cell, objc_getAssociatedObject(cell, &kDKGridLabelKey));
    objc_setAssociatedObject(cell, &kDKGridAdjustedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL DKGridPrepareLabel(UIView *cell, UILabel *label, CGRect card) {
    UIView *parent = label.superview;
    DKCommentGridLabelState *state = objc_getAssociatedObject(cell, &kDKGridLabelKey);
    NSLayoutConstraint *leading = state.leading;
    NSLayoutConstraint *trailing = state.trailing;
    if (state.label != label || !leading.active || !trailing.active
        || leading.secondItem != parent || trailing.secondItem != parent) {
        DKGridRestoreLabel(cell, state);
        leading = nil;
        trailing = nil;
        for (NSLayoutConstraint *constraint in parent.constraints) {
            if (constraint.firstItem != label || constraint.secondItem != parent || constraint.multiplier != 1) continue;
            NSLayoutAttribute edge = constraint.firstAttribute;
            NSLayoutAttribute anchor = constraint.secondAttribute;
            if ((edge == NSLayoutAttributeLeft || edge == NSLayoutAttributeLeading)
                && (anchor == NSLayoutAttributeLeft || anchor == NSLayoutAttributeLeading)
                && constraint.relation == NSLayoutRelationEqual) leading = constraint;
            if ((edge == NSLayoutAttributeTrailing || edge == NSLayoutAttributeRight)
                && (anchor == NSLayoutAttributeTrailing || anchor == NSLayoutAttributeRight)
                && constraint.relation == NSLayoutRelationLessThanOrEqual) trailing = constraint;
        }
        if (!leading || !trailing) return NO;

        state = [DKCommentGridLabelState new];
        state.label = label;
        state.leading = leading;
        state.trailing = trailing;
        state.nativeLeading = leading.constant;
        state.nativeTrailing = trailing.constant;
        state.appliedLeading = leading.constant;
        state.appliedTrailing = trailing.constant;
        state.lines = label.numberOfLines;
        state.alignment = label.textAlignment;
        state.lineBreakMode = label.lineBreakMode;
        state.adjustsFontSize = label.adjustsFontSizeToFitWidth;
        state.minimumScale = label.minimumScaleFactor;
        objc_setAssociatedObject(cell, &kDKGridLabelKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // 宿主再次写入边距时，以该值作为下一次归还的基线。
    if (leading.constant != state.appliedLeading) state.nativeLeading = leading.constant;
    if (trailing.constant != state.appliedTrailing) state.nativeTrailing = trailing.constant;
    CGRect localCard = [parent convertRect:card fromView:cell];
    state.appliedLeading = CGRectGetMinX(localCard) - CGRectGetMinX(parent.bounds) + kDKCommentLabelInset;
    state.appliedTrailing = CGRectGetMaxX(localCard) - CGRectGetMaxX(parent.bounds) - kDKCommentLabelInset;
    if (leading.constant != state.appliedLeading) leading.constant = state.appliedLeading;
    if (trailing.constant != state.appliedTrailing) trailing.constant = state.appliedTrailing;
    if (label.numberOfLines != 1) label.numberOfLines = 1;
    if (label.textAlignment != NSTextAlignmentCenter) label.textAlignment = NSTextAlignmentCenter;
    if (label.lineBreakMode != NSLineBreakByTruncatingTail) label.lineBreakMode = NSLineBreakByTruncatingTail;
    if (!label.adjustsFontSizeToFitWidth) label.adjustsFontSizeToFitWidth = YES;
    if (label.minimumScaleFactor != kDKCommentLabelMinScale) label.minimumScaleFactor = kDKCommentLabelMinScale;
    [parent layoutIfNeeded];
    return YES;
}

static BOOL DKCommentGlassActive(void) {
    return DKGlassOSAvailable() && DKPrefBool(DKKeySharePanelGlass);
}

// 卡片层改成本格在分区卡片里的那一块；同一视图上的其它裸层（行间分割线）隐藏。
static void DKGridShapeCard(UIView *cell, DKGridSlot slot, CGRect card, NSMutableDictionary *adjusted) {
    CALayer *layer = DKCellIvar(cell, "contentShapeLayer");
    if (![layer isKindOfClass:CALayer.class] || !layer.superlayer) return;
    for (CALayer *sibling in layer.superlayer.sublayers) {
        if (sibling == layer || sibling.hidden || [sibling.delegate isKindOfClass:UIView.class]) continue;
        sibling.hidden = YES;
        [adjusted[@"layers"] addObject:sibling];
    }
    if (DKCommentGlassActive()) card = CGRectInset(card, kDKCommentGlassGap, 0.0);
    UIRectCorner corners = 0;
    if (slot.row == 0 && slot.column == 0) corners |= UIRectCornerTopLeft;
    if (slot.row == 0 && DKGridReachesRight(slot)) corners |= UIRectCornerTopRight;
    if (slot.row == slot.rows - 1 && slot.column == 0) corners |= UIRectCornerBottomLeft;
    if (slot.row == slot.rows - 1 && DKGridReachesRight(slot)) corners |= UIRectCornerBottomRight;
    CGRect rect = [cell.layer convertRect:card toLayer:layer];
    if ([layer isKindOfClass:CAShapeLayer.class]) {
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect byRoundingCorners:corners
                                                         cornerRadii:CGSizeMake(kDKCommentCardRadius, kDKCommentCardRadius)];
        ((CAShapeLayer *)layer).path = path.CGPath;
    } else {
        layer.frame = [layer.superlayer convertRect:rect fromLayer:layer];
        layer.cornerRadius = corners ? kDKCommentCardRadius : 0.0;
        CACornerMask mask = 0;
        if (corners & UIRectCornerTopLeft) mask |= kCALayerMinXMinYCorner;
        if (corners & UIRectCornerTopRight) mask |= kCALayerMaxXMinYCorner;
        if (corners & UIRectCornerBottomLeft) mask |= kCALayerMinXMaxYCorner;
        if (corners & UIRectCornerBottomRight) mask |= kCALayerMaxXMaxYCorner;
        layer.maskedCorners = mask;
    }
}

// 不含 transform 的 frame：transform 只改 frame，不改 center 与 bounds。
static CGRect DKGridPlainFrame(UIView *view, UIView *cell) {
    CGSize size = view.bounds.size;
    CGRect frame = CGRectMake(view.center.x - size.width / 2.0, view.center.y - size.height / 2.0, size.width, size.height);
    return [view.superview convertRect:frame toView:cell];
}

static void DKGridMove(UIView *view, CGPoint target, UIView *cell, NSMutableDictionary *adjusted) {
    if (!view.superview) return;
    NSMapTable<UIView *, NSValue *> *views = adjusted[@"views"];
    NSValue *base = [views objectForKey:view];
    if (!base) {
        base = [NSValue valueWithCGAffineTransform:view.transform];
        [views setObject:base forKey:view];
    }
    CGPoint localTarget = [view.superview convertPoint:target fromView:cell];
    CGAffineTransform transform = base.CGAffineTransformValue;
    transform.tx = localTarget.x - view.center.x;
    transform.ty = localTarget.y - view.center.y;
    if (!CGAffineTransformEqualToTransform(view.transform, transform)) view.transform = transform;
}

// 三、四列：图标和彩环移到卡片上部中央，单行文字按可用宽度放在下方，红点贴图标右上。
static void DKGridStackContent(UIView *cell, CGRect tile, NSMutableDictionary *adjusted) {
    UIView *main = DKCellIvar(cell, "$__lazy_storage_$_mainView");
    UIView *icon = DKCellIvar(cell, "$__lazy_storage_$_iconImage");
    UILabel *label = DKCellIvar(cell, "$__lazy_storage_$_contentLabel");
    UIView *dot = DKCellIvar(cell, "$__lazy_storage_$_redDot");
    if (![main isKindOfClass:UIView.class] || ![icon isKindOfClass:UIView.class] || ![label isKindOfClass:UILabel.class]) return;

    if (!DKGridPrepareLabel(cell, label, tile)) {
        DKGridRestoreCell(cell);
        return;
    }

    CGSize iconSize = icon.bounds.size;
    CGPoint iconTarget = CGPointMake(CGRectGetMidX(tile), CGRectGetMinY(tile) + kDKCommentTileTop + iconSize.height / 2.0);
    CGPoint iconCenter = [icon.superview convertPoint:icon.center toView:cell];
    CGPoint delta = CGPointMake(iconTarget.x - iconCenter.x, iconTarget.y - iconCenter.y);
    CGRect iconFrame = DKGridPlainFrame(icon, cell);
    for (UIView *view in main.subviews) {
        if (view == label || view == dot) continue;
        CGRect frame = DKGridPlainFrame(view, cell);
        if (view != icon && !CGRectIntersectsRect(CGRectInset(frame, -2.0, -2.0), iconFrame)) continue;
        CGPoint center = [view.superview convertPoint:view.center toView:cell];
        DKGridMove(view, CGPointMake(center.x + delta.x, center.y + delta.y), cell, adjusted);
    }

    CGSize labelSize = label.bounds.size;
    CGPoint labelTarget = CGPointMake(CGRectGetMidX(tile),
                                      iconTarget.y + iconSize.height / 2.0 + kDKCommentTileGap + labelSize.height / 2.0);
    DKGridMove(label, labelTarget, cell, adjusted);
    if ([dot isKindOfClass:UIView.class]) {
        CGPoint dotTarget = CGPointMake(iconTarget.x + iconSize.width / 2.0 + CGRectGetWidth(dot.bounds) / 2.0,
                                        iconTarget.y - iconSize.height / 2.0);
        DKGridMove(dot, dotTarget, cell, adjusted);
    }
}

static void DKGridLayoutCell(UIView *cell) {
    DKGridSlot slot;
    if (!DKGridSlotFrom(objc_getAssociatedObject(cell, &kDKGridInfoKey), &slot)) return;
    CGFloat containerWidth = CGRectGetWidth(cell.superview.bounds);
    if (containerWidth < 100.0) return;
    CGRect bounds = cell.bounds;
    CGFloat left = slot.column == 0 ? kDKCommentCardInset : 0.0;
    CGFloat right = DKGridReachesRight(slot) ? kDKCommentCardInset : 0.0;
    CGRect card = CGRectMake(left, 0.0, CGRectGetWidth(bounds) - left - right, CGRectGetHeight(bounds));

    NSMutableDictionary *adjusted = DKGridAdjusted(cell, YES);
    DKGridShapeCard(cell, slot, card, adjusted);
    if (slot.columns > 2) {
        DKGridStackContent(cell, card, adjusted);
        return;
    }
    // 二列保留原生横排；补宽的尾格按可见内容整体居中。
    UIView *main = DKCellIvar(cell, "$__lazy_storage_$_mainView");
    if (![main isKindOfClass:UIView.class]) return;
    [main layoutIfNeeded];
    CGRect frame = DKGridPlainFrame(main, cell);
    CGPoint center = [main.superview convertPoint:main.center toView:cell];
    CGFloat offset = CGRectGetMinX(card) - CGRectGetMinX(frame);
    if (slot.last && slot.column < slot.columns - 1) {
        CGRect content = CGRectNull;
        const char *ivars[] = {"$__lazy_storage_$_iconImage", "$__lazy_storage_$_contentLabel",
                              "$__lazy_storage_$_redDot"};
        for (const char *ivar : ivars) {
            UIView *view = DKCellIvar(cell, ivar);
            if ([view isKindOfClass:UIView.class] && !view.hidden && view.alpha > 0 && view.superview) {
                content = CGRectUnion(content, [view.superview convertRect:view.frame toView:main]);
            }
        }
        if (!CGRectIsEmpty(content)) {
            content = [main convertRect:content toView:cell];
            // 当前读数包含上一次居中位移；按原生主视图的横坐标计算下一次位移。
            CGPoint midpoint = CGPointMake(CGRectGetMidX(main.bounds), CGRectGetMidY(main.bounds));
            CGFloat previousOffset = [main convertPoint:midpoint toView:cell].x - center.x;
            offset = CGRectGetMidX(card) - CGRectGetMidX(content) + previousOffset;
        }
    }
    DKGridMove(main, CGPointMake(center.x + offset, center.y), cell, adjusted);
}

static void DKGridResetCell(UIView *cell) {
    DKGridRestoreCell(cell);
    objc_setAssociatedObject(cell, &kDKGridInfoKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - 钩子

%group DKCommentMenuGridHooks

%hook DKCommentGridSection

- (CGSize)sizeForItemAtIndex:(NSInteger)index model:(id)model collectionViewSize:(CGSize)size {
    CGSize original = %orig;
    NSInteger columns = DKLongPressMenuColumns(DKLongPressMenuComment);
    NSInteger count = [self numberOfItems];
    if (columns < 2 || count <= 0 || size.width < 100.0) return original;
    DKGridSlot slot;
    if (!DKGridSlotFrom(@[ @(index), @(count), @(columns) ], &slot)) return original;
    CGFloat height = columns > 2 ? kDKCommentTileHeight : original.height;
    return CGSizeMake(DKGridItemWidth(size.width, slot), height);
}

- (void)configCell:(id)cell index:(NSInteger)index model:(id)model {
    if ([cell isKindOfClass:UIView.class]) DKGridResetCell(cell);
    %orig;
    if (![cell isKindOfClass:UIView.class]) return;
    NSInteger columns = DKLongPressMenuColumns(DKLongPressMenuComment);
    NSArray *info = columns > 1 ? @[ @(index), @([self numberOfItems]), @(columns) ] : nil;
    objc_setAssociatedObject(cell, &kDKGridInfoKey, info, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [(UIView *)cell setNeedsLayout];
}

%end

%hook CommentLongPressPanelNormalBaseCell

- (void)layoutSubviews {
    NSArray *info = objc_getAssociatedObject(self, &kDKGridInfoKey);
    if (info && [info.lastObject integerValue] != DKLongPressMenuColumns(DKLongPressMenuComment)) {
        DKGridResetCell(self);
    }
    %orig;
    if (objc_getAssociatedObject(self, &kDKGridInfoKey)) {
        [self.contentView layoutIfNeeded];
        DKGridLayoutCell(self);
    }
}

- (void)prepareForReuse {
    DKGridResetCell(self);
    %orig;
}

%end

%end

%ctor {
    Class section = NSClassFromString(kDKCommentNormalSectionClass);
    SEL size = @selector(sizeForItemAtIndex:model:collectionViewSize:);
    SEL config = @selector(configCell:index:model:);
    BOOL ready = section && NSClassFromString(@"CommentLongPressPanelNormalBaseCell")
        && class_getInstanceMethod(section, size) && class_getInstanceMethod(section, config)
        && class_getInstanceVariable(NSClassFromString(@"CommentLongPressPanelNormalBaseCell"), "contentShapeLayer");
    if (ready) %init(DKCommentMenuGridHooks, DKCommentGridSection = section);
}
