//
//  DKInfoAppearance.xm
//  DYKiller
//
//  视频左下昵称与文案区域的外观定制。
//
//  实现：
//   - 左侧栈与右侧栈同为交互层里的 AWEElementStackView；行（AWEBaseElementView）的 element 继承
//     AWEPlayInteractionLeftElement 即左侧栈的行。元素实现作者协议的是昵称行，其余左侧元素行归文案组；
//     不属于左侧元素的行（朋友页私信快捷回复栏）不改透明度与缩放，只随位置累计移动。
//   - 透明度：逐行挂半透明 mask，不改 alpha，命中不变；抖音打开文案面板时写的栈 alpha 与之相乘。
//   - 缩放：贴左缘逐行缩放，最底行以行内可见内容（非空文本、有图的图片）的底边为锚，
//     文案行文字下方的滚动余量不会把文字推进进度条触控区。
//   - 上移：整栈叠 transform。
//

#import "DKInfoAppearance.h"
#import "DouyinHeaders.h"
#import "DKAdjustRange.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"

typedef NS_ENUM(NSInteger, DKInfoRowKind) {
    DKInfoRowOther = 0,        // 非左侧元素行
    DKInfoRowNickname = 1,     // 作者昵称
    DKInfoRowDescription = 2,  // 文案及其余左侧信息
};

static NSHashTable<AWEElementStackView *> *gDKInfoStacks;

#pragma mark - 识别

static id DKInfoRowElement(UIView *row) {
    static Class rowClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ rowClass = NSClassFromString(@"AWEBaseElementView"); });
    if (!rowClass || ![row isKindOfClass:rowClass]) return nil;
    @try {
        return [row valueForKey:@"element"];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static DKInfoRowKind DKInfoKindOfRow(UIView *row) {
    static Class leftClass;
    static Protocol *authorProtocol;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        leftClass = NSClassFromString(@"AWEPlayInteractionLeftElement");
        authorProtocol = NSProtocolFromString(@"AWEPlayInteractionAuthorElementProtocol");
    });
    id element = DKInfoRowElement(row);
    if (!leftClass || ![element isKindOfClass:leftClass]) return DKInfoRowOther;
    if (authorProtocol && [element conformsToProtocol:authorProtocol]) return DKInfoRowNickname;
    return DKInfoRowDescription;
}

static BOOL DKInfoIsLeftStack(AWEElementStackView *stack) {
    if (!stack || !DKPlayInteractionControllerForView(stack)) return NO;
    for (UIView *row in stack.arrangedSubviews) {
        if (DKInfoKindOfRow(row) != DKInfoRowOther) return YES;
    }
    return NO;
}

#pragma mark - 取值

static CGFloat DKInfoAlpha(DKInfoRowKind kind) {
    switch (kind) {
        case DKInfoRowNickname: return DKPrefFraction(DKKeyNicknameAlpha, 100);
        case DKInfoRowDescription: return DKPrefFraction(DKKeyDescriptionAlpha, 100);
        default: return 1.0;
    }
}

static CGFloat DKInfoScale(DKInfoRowKind kind) {
    switch (kind) {
        case DKInfoRowNickname: return DKAdjustValue(DKKeyNicknameScale) / 100.0;
        case DKInfoRowDescription: return DKAdjustValue(DKKeyDescriptionScale) / 100.0;
        default: return 1.0;
    }
}

static CGFloat DKInfoOffset(void) {
    return DKAdjustValue(DKKeyInfoOffset);
}

#pragma mark - 内容底边

static BOOL DKInfoViewDrawsContent(UIView *view) {
    if ([view isKindOfClass:UIImageView.class]) return ((UIImageView *)view).image != nil;
    if ([view respondsToSelector:@selector(attributedText)]) {
        id text = [(id)view attributedText];
        return [text isKindOfClass:NSAttributedString.class] && [(NSAttributedString *)text length] > 0;
    }
    return NO;
}

static void DKInfoCollectContentBottom(UIView *view, UIView *row, CGFloat *bottom, BOOL *found) {
    for (UIView *subview in view.subviews) {
        if (subview.hidden || subview.alpha < 0.01 || CGRectIsEmpty(subview.bounds)) continue;
        if (DKInfoViewDrawsContent(subview)) {
            *bottom = MAX(*bottom, CGRectGetMaxY([subview convertRect:subview.bounds toView:row]));
            *found = YES;
        }
        DKInfoCollectContentBottom(subview, row, bottom, found);
    }
}

// 行内可见内容的最大底边（行坐标）：非空文本的标签与有图的图片视图；找不到时取行底。
static CGFloat DKInfoRowContentBottom(UIView *row) {
    CGFloat bottom = CGRectGetMinY(row.bounds);
    BOOL found = NO;
    DKInfoCollectContentBottom(row, row, &bottom, &found);
    return found ? MIN(bottom, CGRectGetMaxY(row.bounds)) : CGRectGetMaxY(row.bounds);
}

#pragma mark - 应用

void DKInfoAppearanceApplyStack(AWEElementStackView *stack) {
    if (!DKInfoIsLeftStack(stack)) return;
    if (!gDKInfoStacks) gDKInfoStacks = [NSHashTable weakObjectsHashTable];
    [gDKInfoStacks addObject:stack];

    // mask 向四周外扩栈的尺寸，覆盖缩放与上移后越出行 bounds 的内容。
    CGSize outset = stack.bounds.size;
    for (UIView *row in stack.arrangedSubviews) {
        DKAdjustFade(row, DKInfoAlpha(DKInfoKindOfRow(row)), outset);
    }
    DKAdjustStackRows(stack, DKStackEdgeLeft,
                      ^CGFloat(UIView *row) { return DKInfoScale(DKInfoKindOfRow(row)); },
                      ^CGFloat(UIView *row) { return DKInfoRowContentBottom(row); });
    DKAdjustTransform(stack, CGAffineTransformMakeTranslation(0, -DKInfoOffset()));
}

void DKInfoAppearanceRefresh(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKInfoAppearanceRefresh(); });
        return;
    }
    for (AWEElementStackView *stack in gDKInfoStacks.allObjects) {
        [stack setNeedsLayout];
        [stack layoutIfNeeded];
    }
}

#pragma mark - 诊断

static NSString *DKInfoKindText(DKInfoRowKind kind) {
    switch (kind) {
        case DKInfoRowNickname: return @"昵称";
        case DKInfoRowDescription: return @"文案";
        default: return @"其他";
    }
}

NSString *DKInfoAppearanceStatus(void) {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"昵称透明度=%.0f%% 缩放=%ld%% · 文案透明度=%.0f%% 缩放=%ld%% · 上移=%ldpt\n",
        DKInfoAlpha(DKInfoRowNickname) * 100.0, (long)DKAdjustValue(DKKeyNicknameScale),
        DKInfoAlpha(DKInfoRowDescription) * 100.0, (long)DKAdjustValue(DKKeyDescriptionScale),
        (long)DKAdjustValue(DKKeyInfoOffset)];
    [out appendFormat:@"可见左侧栈=%lu\n", (unsigned long)gDKInfoStacks.allObjects.count];
    for (AWEElementStackView *stack in gDKInfoStacks.allObjects) {
        [out appendFormat:@"  %@ frame=%@ transform.ty=%.1f\n", NSStringFromClass(stack.class),
            NSStringFromCGRect(stack.frame), stack.transform.ty];
        for (UIView *row in stack.arrangedSubviews) {
            DKInfoRowKind kind = DKInfoKindOfRow(row);
            id element = DKInfoRowElement(row);
            CGAffineTransform t = row.transform;
            [out appendFormat:@"    [%@] %@ bounds=%@ hidden=%d 内容底=%.1f 缩放=%.3f tx=%.1f ty=%.1f 淡出=%.2f\n",
                DKInfoKindText(kind), element ? NSStringFromClass([element class]) : @"-",
                NSStringFromCGSize(row.bounds.size), row.isHidden, DKInfoRowContentBottom(row),
                t.a, t.tx, t.ty, DKAdjustFadeFactor(row)];
        }
    }
    return out;
}
