//
//  DKChatInputList.xm
//  DYKiller
//
//  原生布局读取当前几何并写回列表容器、表格与 inset。每轮快照计算前撤掉本模块的延伸，
//  布局后将列表上沿延伸到物理顶部，非键盘态再延伸到底部；inset 与 offset 同步补偿。
//  居中头像加高顶部区域时，top inset 再让出加高量。按列表上沿定位的未读提示补回上沿延伸与让位量。
//

#import "DKChatInputList.h"
#import "DKChatInput.h"
#import "DKChatTopBar.h"
#import "DKGlassGuard.h"
#import "DouyinHeaders.h"
#import <objc/runtime.h>

// 系统键盘输入形态，键盘弹出时列表保持原生（止于输入行上沿）。
static const long long kDKChatInputTypeKeyboard = 1;

static char kDKChatListExtensionKey;    // 表格上记本模块加上的延伸量
static char kDKChatListTopExtensionKey;
static char kDKChatListTopPadKey;
static char kDKChatListNativeLayoutKey;
static NSHashTable *gDKChatListComponents;

// 布局组件所在聊天页的消息表格与裁剪它的列表容器；结构不符时返回 nil。
static UITableView *DKChatListTable(id component, UIView **container) {
    AWEIMMessageBaseViewController *host = (id)((AWEIMComponentBase *)component).context.hostViewController;
    if (!DKChatInputIsKind(host, @"AWEIMMessageBaseViewController")) return nil;
    UIViewController *list = host.messageListVC;
    if (!DKChatInputIsKind(list, @"AWEIMMessageListViewController") || !list.isViewLoaded) return nil;
    UITableView *table = ((AWEIMMessageListViewController *)list).tableView;
    if (table.superview != list.view || list.view.superview != host.view) return nil;
    *container = list.view;
    return table;
}

static BOOL DKChatListWanted(id component) {
    IESIMInputViewController *input = (id)DKChatInputController(component);
    return DKChatInputGlassWanted(input) && input.currentInputType != kDKChatInputTypeKeyboard;
}

// 容器、表格高度与底部 inset 同步改变 delta，offset 写回原值（表格 setFrame: 触发的原生贴底会挪动它）。
static void DKChatListShift(UIView *container, UITableView *table, CGFloat delta) {
    CGPoint offset = table.contentOffset;
    CGRect containerFrame = container.frame;
    containerFrame.size.height += delta;
    CGRect tableFrame = table.frame;
    tableFrame.size.height += delta;
    UIEdgeInsets inset = table.contentInset;
    inset.bottom = MAX(0.0, inset.bottom + delta);
    UIEdgeInsets indicator = table.verticalScrollIndicatorInsets;
    indicator.bottom = MAX(0.0, indicator.bottom + delta);
    container.frame = containerFrame;
    table.frame = tableFrame;
    table.contentInset = inset;
    table.verticalScrollIndicatorInsets = indicator;
    if (!CGPointEqualToPoint(table.contentOffset, offset)) table.contentOffset = offset;
}

// 上沿延伸同时增加 top inset 并补偿 offset，消息的屏幕坐标保持不变。
static void DKChatListShiftTop(UIView *container, UITableView *table, CGFloat delta) {
    CGPoint offset = table.contentOffset;
    offset.y -= delta;
    CGRect frame = container.frame;
    frame.origin.y -= delta;
    frame.size.height += delta;
    CGRect tableFrame = table.frame;
    tableFrame.size.height += delta;
    UIEdgeInsets inset = table.contentInset;
    inset.top += delta;
    UIEdgeInsets indicator = table.verticalScrollIndicatorInsets;
    indicator.top += delta;
    container.frame = frame;
    table.frame = tableFrame;
    table.contentInset = inset;
    table.verticalScrollIndicatorInsets = indicator;
    table.contentOffset = offset;
}

// 只加 top inset、不动 frame：停在顶端时仍停在顶端，其余位置的消息不移动。
static void DKChatListPadTop(UITableView *table, CGFloat delta) {
    UIEdgeInsets inset = table.contentInset;
    BOOL atTop = table.contentOffset.y <= -inset.top + 0.5;
    inset.top += delta;
    UIEdgeInsets indicator = table.verticalScrollIndicatorInsets;
    indicator.top += delta;
    table.contentInset = inset;
    table.verticalScrollIndicatorInsets = indicator;
    if (atTop) table.contentOffset = CGPointMake(table.contentOffset.x, -inset.top);
}

static void DKChatListCollapse(UIView *container, UITableView *table) {
    CGFloat pad = [objc_getAssociatedObject(table, &kDKChatListTopPadKey) doubleValue];
    if (pad > 0.0) {
        objc_setAssociatedObject(table, &kDKChatListTopPadKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DKChatListPadTop(table, -pad);
    }
    CGFloat top = [objc_getAssociatedObject(table, &kDKChatListTopExtensionKey) doubleValue];
    if (top > 0.0) {
        objc_setAssociatedObject(table, &kDKChatListTopExtensionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DKChatListShiftTop(container, table, -top);
    }
    CGFloat extension = [objc_getAssociatedObject(table, &kDKChatListExtensionKey) doubleValue];
    if (extension <= 0.0) return;
    objc_setAssociatedObject(table, &kDKChatListExtensionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKChatListShift(container, table, -extension);
}

static void DKChatListExtend(id component, UIView *container, UITableView *table) {
    if (DKChatInputGlassWanted(DKChatInputController(component))) {
        CGFloat top = CGRectGetMinY(container.frame) - CGRectGetMinY(container.superview.bounds);
        if (top > 0.0) {
            objc_setAssociatedObject(table, &kDKChatListTopExtensionKey, @(top), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            DKChatListShiftTop(container, table, top);
        }
        CGFloat pad = DKChatTopHeaderExtra(((AWEIMComponentBase *)component).context.hostViewController);
        if (pad > 0.0) {
            objc_setAssociatedObject(table, &kDKChatListTopPadKey, @(pad), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            DKChatListPadTop(table, pad);
        }
    }
    if (!DKChatListWanted(component)) return;
    CGFloat extension = CGRectGetMaxY(container.superview.bounds) - CGRectGetMaxY(container.frame);
    if (extension < 1.0) return;
    objc_setAssociatedObject(table, &kDKChatListExtensionKey, @(extension), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKChatListShift(container, table, extension);
}

void DKChatInputListRefresh(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKChatInputListRefresh(); });
        return;
    }
    for (id component in gDKChatListComponents.allObjects) {
        UIView *container = nil;
        UITableView *table = DKChatListTable(component, &container);
        if (!table || objc_getAssociatedObject(component, &kDKChatListNativeLayoutKey)) continue;
        DKChatListCollapse(container, table);
        DKChatListExtend(component, container, table);
    }
}

// 原生在动画块里写 frame / contentOffset 时，UIKit 按属性追加增量动画（position、bounds.size、bounds.origin，
// 同名时 key 带 -2、-3 后缀）。返回的 block 移除本轮新增、且属性终值与调用前一致的动画：它们只是撤销与恢复之间的中间态。
static dispatch_block_t DKChatListTransientAnimationSweeper(CALayer *layer) {
    NSArray<NSString *> *keys = layer.animationKeys ?: @[];
    CGPoint position = layer.position;
    CGRect bounds = layer.bounds;
    return ^{
        for (NSString *key in layer.animationKeys) {
            CAAnimation *animation = [layer animationForKey:key];
            if ([keys containsObject:key] || ![animation isKindOfClass:CAPropertyAnimation.class]) continue;
            NSString *path = ((CAPropertyAnimation *)animation).keyPath;
            BOOL unchanged = [path isEqualToString:@"position"] ? CGPointEqualToPoint(layer.position, position)
                : [path isEqualToString:@"bounds.origin"] ? CGPointEqualToPoint(layer.bounds.origin, bounds.origin)
                : [path isEqualToString:@"bounds.size"] ? CGSizeEqualToSize(layer.bounds.size, bounds.size)
                : [path isEqualToString:@"bounds"] && CGRectEqualToRect(layer.bounds, bounds);
            if (unchanged) [layer removeAnimationForKey:key];
        }
    };
}

// 原生布局从快照计算开始，嵌套的页面写入共用同一轮撤销与延伸。
static void DKChatListNativeLayout(id component, void (^nativeLayout)(void)) {
    if (objc_getAssociatedObject(component, &kDKChatListNativeLayoutKey)) { nativeLayout(); return; }
    UIView *container = nil;
    UITableView *table = DKChatInputController(component) ? DKChatListTable(component, &container) : nil;
    if (!table) { nativeLayout(); return; }
    dispatch_block_t sweepContainer = DKChatListTransientAnimationSweeper(container.layer);
    dispatch_block_t sweepTable = DKChatListTransientAnimationSweeper(table.layer);
    objc_setAssociatedObject(component, &kDKChatListNativeLayoutKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [UIView performWithoutAnimation:^{ DKChatListCollapse(container, table); }];
    DKChatTopBarNativeLayout(((AWEIMComponentBase *)component).context.hostViewController, nativeLayout);
    [gDKChatListComponents addObject:component];
    [UIView performWithoutAnimation:^{ DKChatListExtend(component, container, table); }];
    objc_setAssociatedObject(component, &kDKChatListNativeLayoutKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // 视口与消息位置未变的属性不参与呈现；键盘带来的真实视口变化保留原生动画。
    if (DKChatInputGlassWanted(DKChatInputController(component))) {
        sweepContainer();
        sweepTable();
    }
}

// 聊天页消息列表当前的上沿延伸与让位量；原生布局期间已撤销，为 0。
static CGFloat DKChatListTopExtension(id component) {
    UIView *container = nil;
    UITableView *table = DKChatListTable(component, &container);
    return [objc_getAssociatedObject(table, &kDKChatListTopExtensionKey) doubleValue]
        + [objc_getAssociatedObject(table, &kDKChatListTopPadKey) doubleValue];
}

%group DKChatInputListHooks
%hook AWEIMMessageListLayoutComponent
- (void)p_layoutWithAnimation:(BOOL)animated coordinate:(id)coordinate {
    DKChatListNativeLayout(self, ^{ %orig; });
}
- (void)updatePageLayout:(id)layoutInfo {
    DKChatListNativeLayout(self, ^{ %orig; });
}
%end
// 未读提示的纵坐标从列表视图上沿算起，补回上沿延伸与让位量，落在顶部区域下方。
%hook AWEIMTopAnchorComponent
- (double)__bubbleYOrigin {
    return %orig + DKChatListTopExtension(self);
}
%end
%end

%ctor {
    gDKChatListComponents = [NSHashTable weakObjectsHashTable];
    if (DKGlassOSAvailable()) {
        %init(DKChatInputListHooks);
    }
}
