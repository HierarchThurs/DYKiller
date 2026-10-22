//
//  DKChatInputList.xm
//  DYKiller
//
//  消息列表的延伸：原生在 -[AWEIMMessageListLayoutComponent updatePageLayout:] 里统一写列表容器与表格 frame，
//  表格 frame 变化后按高度差贴底，再把 contentInset 写回 0。每轮原生布局前先撤掉本模块的延伸，
//  让原生按自己的几何计算与贴底；布局后再把容器、表格与底部 inset 同步加上到聊天页底部的距离。
//  高度与 inset 同增同减时可滚范围不变，offset 保持原值即可让可见内容不动。
//

#import "DKChatInputList.h"
#import "DKChatInput.h"
#import "DKGlassGuard.h"
#import "DouyinHeaders.h"
#import <objc/runtime.h>

// 系统键盘输入形态，键盘弹出时列表保持原生（止于输入行上沿）。
static const long long kDKChatInputTypeKeyboard = 1;

static char kDKChatListExtensionKey;    // 表格上记本模块加上的延伸量
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

static void DKChatListCollapse(UIView *container, UITableView *table) {
    CGFloat extension = [objc_getAssociatedObject(table, &kDKChatListExtensionKey) doubleValue];
    if (extension <= 0.0) return;
    objc_setAssociatedObject(table, &kDKChatListExtensionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKChatListShift(container, table, -extension);
}

static void DKChatListExtend(id component, UIView *container, UITableView *table) {
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
        if (!table) continue;
        DKChatListCollapse(container, table);
        DKChatListExtend(component, container, table);
    }
}

%group DKChatInputListHooks
%hook AWEIMMessageListLayoutComponent
- (void)updatePageLayout:(id)layoutInfo {
    UIView *container = nil;
    UITableView *table = DKChatInputController(self) ? DKChatListTable(self, &container) : nil;
    if (table) DKChatListCollapse(container, table);
    %orig;
    if (!table) return;
    [gDKChatListComponents addObject:self];
    DKChatListExtend(self, container, table);
}
%end
%end

%ctor {
    gDKChatListComponents = [NSHashTable weakObjectsHashTable];
    if (DKGlassOSAvailable()) {
        %init(DKChatInputListHooks);
    }
}
