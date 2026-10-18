//
//  DKMessageCleanList.xm
//  DYKiller
//
//  消息页精简 —— 列表顶部三项：头像行开头的业务入口（限时日常等）、头像行里的好友头像、互动消息会话。
//
//  实现：
//   - 头像行（AWEIMSkylightViewComponent）的全量结果、分区替换、删除刷新都经 applySnapshot:animatingDifferences:completion:
//     交给差异数据源。移除在 %orig 前从快照删掉对应条目，之后各路径都基于删过的快照，其余头像按原生排布左移。
//     条目判定：AWEIMSkylightBizViewModel 及其子类为业务入口；vmType 1 为好友（4 为状态设置，不处理）。
//   - 两项都移除时 AWEIMSkylightDataComponent shouldHidden 返回 YES，列表视图经代理写 hidden 并重排表头，整行收起。
//   - 互动消息（AWEIMOfficialChatModel，type 1003）：官方会话数据源的闸门 p_canShowOfficialChat: 返回 NO，
//     upsert 里已在列表的会话随之转为删除，下方会话按原生排布上移。闸门可能在后台线程调用，记录加锁。
//   - 隐藏：头像格子与会话行渲染后按条目类型给 contentView 挂全透明 mask，命中不受影响；复用时按新条目重挂或摘掉。
//   - 设置改动：快照重新 apply 一次、请求刷新（恢复时由抖音重建全量结果）、按设置收起或展开整行；
//     互动消息会话再 upsert 一次，由闸门决定加回或删除。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKMessageClean.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"
#import <objc/runtime.h>
#import <os/lock.h>

typedef NS_ENUM(NSInteger, DKMessageListItem) {
    DKMessageListItemNone = 0,
    DKMessageListItemDaily,
    DKMessageListItemFriend,
    DKMessageListItemInteraction,
};

static const NSUInteger kDKSkylightFriendType = 1;
static const NSInteger kDKInteractionChatType = 1003;
static NSString *const kDKInteractionSessionID = @"-1003";

static char kDKMessageListItemKey;
// 弱表（头像行列表视图、渲染过的格子与会话行），只在主线程读写。
static NSHashTable *gDKSkylightLists;
static NSHashTable *gDKMessageListCells;

static os_unfair_lock gDKInteractionLock = OS_UNFAIR_LOCK_INIT;
static NSHashTable<IESIMOfficialChatDataSource *> *gDKOfficialSources;
static __weak AWEIMChatModel *gDKInteractionChat;

static NSString *DKMessageListKey(DKMessageListItem item) {
    switch (item) {
        case DKMessageListItemDaily: return DKKeyMessageDailyMode;
        case DKMessageListItemFriend: return DKKeyMessageFriendAvatarMode;
        case DKMessageListItemInteraction: return DKKeyMessageInteractionMode;
        default: return nil;
    }
}

static NSString *DKMessageListName(DKMessageListItem item) {
    switch (item) {
        case DKMessageListItemDaily: return @"限时日常";
        case DKMessageListItemFriend: return @"好友大头像";
        case DKMessageListItemInteraction: return @"互动消息";
        default: return @"-";
    }
}

static DKDisplayMode DKMessageListMode(DKMessageListItem item) {
    NSString *key = DKMessageListKey(item);
    return key ? DKPrefDisplayMode(key) : DKDisplayModeShow;
}

static BOOL DKMessageListRemoved(DKMessageListItem item) {
    return DKMessageListMode(item) == DKDisplayModeRemove;
}

static BOOL DKMessageSkylightRowRemoved(void) {
    return DKMessageListRemoved(DKMessageListItemDaily) && DKMessageListRemoved(DKMessageListItemFriend);
}

static DKMessageListItem DKMessageSkylightItem(id model) {
    if ([model isKindOfClass:%c(AWEIMSkylightBizViewModel)]) return DKMessageListItemDaily;
    if ([model isKindOfClass:%c(AWEIMOnlineContactAvatarViewModel)] && [model respondsToSelector:@selector(vmType)] &&
        [(AWEIMOnlineContactAvatarViewModel *)model vmType] == kDKSkylightFriendType) return DKMessageListItemFriend;
    return DKMessageListItemNone;
}

static BOOL DKMessageChatIsInteraction(id chat) {
    return [chat isKindOfClass:%c(AWEIMChatModel)] && [chat respondsToSelector:@selector(type)] &&
        [(AWEIMChatModel *)chat type] == kDKInteractionChatType;
}

static void DKMessageTrack(NSHashTable * __strong *table, id object) {
    if (!object) return;
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKMessageTrack(table, object); });
        return;
    }
    if (!*table) *table = [NSHashTable weakObjectsHashTable];
    [*table addObject:object];
}

#pragma mark - 隐藏

static UIView *DKMessageCellContent(UIView *cell) {
    UIView *content = [cell respondsToSelector:@selector(contentView)] ? [(UITableViewCell *)cell contentView] : nil;
    return content ?: cell;
}

// 隐藏与移除都不绘制；移除时条目本就不在列表里，mask 只作兜底。
static void DKMessageListApplyCell(UIView *cell) {
    DKMessageListItem item = (DKMessageListItem)[objc_getAssociatedObject(cell, &kDKMessageListItemKey) integerValue];
    UIView *content = DKMessageCellContent(cell);
    DKAdjustFade(content, DKMessageListMode(item) == DKDisplayModeShow ? 1.0 : 0.0, content.bounds.size);
}

static void DKMessageListMarkCell(UIView *cell, DKMessageListItem item) {
    objc_setAssociatedObject(cell, &kDKMessageListItemKey, item ? @(item) : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (item != DKMessageListItemNone) DKMessageTrack(&gDKMessageListCells, cell);
    DKMessageListApplyCell(cell);
}

#pragma mark - 头像行

static void DKMessageSkylightFilter(RxDiffableDataSourceSnapshot *snapshot) {
    BOOL dropDaily = DKMessageListRemoved(DKMessageListItemDaily);
    BOOL dropFriend = DKMessageListRemoved(DKMessageListItemFriend);
    if (!dropDaily && !dropFriend) return;
    if (![snapshot respondsToSelector:@selector(itemIdentifiers)] ||
        ![snapshot respondsToSelector:@selector(deleteItemsWithIdentifiers:)]) return;

    NSMutableArray *drop = [NSMutableArray array];
    for (id model in [snapshot itemIdentifiers]) {
        DKMessageListItem item = DKMessageSkylightItem(model);
        if ((item == DKMessageListItemDaily && dropDaily) || (item == DKMessageListItemFriend && dropFriend)) [drop addObject:model];
    }
    if (drop.count) [snapshot deleteItemsWithIdentifiers:drop];
}

static void DKMessageSkylightRefresh(AWEIMSkylightListView *list) {
    AWEIMSkylightViewComponent *view = [list respondsToSelector:@selector(skylightInterface)] ? list.skylightInterface : nil;
    if ([view isKindOfClass:%c(AWEIMSkylightViewComponent)] && [view respondsToSelector:@selector(dataSource)]) {
        RxDiffableDataSourceSnapshot *snapshot = [view.dataSource snapshot];
        if (snapshot) [view applySnapshot:snapshot animatingDifferences:NO completion:^{}];
    }
    if ([list respondsToSelector:@selector(refreshWithIgnoreFrequency:)]) [list refreshWithIgnoreFrequency:YES];
    if ([list respondsToSelector:@selector(performShouldHiddenDelegate)]) [list performShouldHiddenDelegate];
}

#pragma mark - 互动消息

static void DKMessageRecordInteraction(IESIMOfficialChatDataSource *source, AWEIMChatModel *chat) {
    os_unfair_lock_lock(&gDKInteractionLock);
    if (!gDKOfficialSources) gDKOfficialSources = [NSHashTable weakObjectsHashTable];
    [gDKOfficialSources addObject:source];
    gDKInteractionChat = chat;
    os_unfair_lock_unlock(&gDKInteractionLock);
}

static void DKMessageInteractionRefresh(void) {
    os_unfair_lock_lock(&gDKInteractionLock);
    NSArray<IESIMOfficialChatDataSource *> *sources = gDKOfficialSources.allObjects;
    AWEIMChatModel *chat = gDKInteractionChat;
    os_unfair_lock_unlock(&gDKInteractionLock);
    if (!chat) return;
    for (IESIMOfficialChatDataSource *source in sources) {
        if ([source respondsToSelector:@selector(p_updateChatListWithUpsert:remove:)]) {
            [source p_updateChatListWithUpsert:@[ chat ] remove:@[]];
        }
    }
}

#pragma mark - 刷新与诊断

void DKMessageCleanListRefresh(void) {
    for (AWEIMSkylightListView *list in gDKSkylightLists.allObjects) DKMessageSkylightRefresh(list);
    DKMessageInteractionRefresh();
    for (UIView *cell in gDKMessageListCells.allObjects) DKMessageListApplyCell(cell);
}

NSString *DKMessageCleanListStatus(void) {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"已见头像行=%lu 整行移除=%d\n", (unsigned long)gDKSkylightLists.allObjects.count, DKMessageSkylightRowRemoved()];
    for (AWEIMSkylightListView *list in gDKSkylightLists.allObjects) {
        [out appendFormat:@"  头像行 在窗口=%d hidden=%d frame=%@\n", list.window != nil, list.isHidden,
            NSStringFromCGRect([list convertRect:list.bounds toView:nil])];
        AWEIMSkylightViewComponent *view = [list respondsToSelector:@selector(skylightInterface)] ? list.skylightInterface : nil;
        RxDiffableDataSourceSnapshot *snapshot = [view respondsToSelector:@selector(dataSource)] ? [view.dataSource snapshot] : nil;
        if (![snapshot respondsToSelector:@selector(sectionIdentifiers)]) continue;
        for (id section in [snapshot sectionIdentifiers]) {
            NSUInteger daily = 0, friends = 0, others = 0;
            for (id model in [snapshot itemIdentifiersInSectionWithIdentifier:section]) {
                DKMessageListItem item = DKMessageSkylightItem(model);
                if (item == DKMessageListItemDaily) daily++;
                else if (item == DKMessageListItemFriend) friends++;
                else others++;
            }
            [out appendFormat:@"    分区 %@：业务入口=%lu 好友=%lu 其他=%lu\n", section,
                (unsigned long)daily, (unsigned long)friends, (unsigned long)others];
        }
    }

    os_unfair_lock_lock(&gDKInteractionLock);
    NSArray<IESIMOfficialChatDataSource *> *sources = gDKOfficialSources.allObjects;
    AWEIMChatModel *chat = gDKInteractionChat;
    os_unfair_lock_unlock(&gDKInteractionLock);
    [out appendFormat:@"官方会话数据源=%lu 已见互动消息会话=%d\n", (unsigned long)sources.count, chat != nil];
    for (IESIMOfficialChatDataSource *source in sources) {
        BOOL listed = [source respondsToSelector:@selector(chatWithSession:)] && [source chatWithSession:kDKInteractionSessionID] != nil;
        [out appendFormat:@"  %@ 列表含互动消息=%d\n", NSStringFromClass(source.class), listed];
    }

    for (UIView *cell in gDKMessageListCells.allObjects) {
        if (!cell.window) continue;
        DKMessageListItem item = (DKMessageListItem)[objc_getAssociatedObject(cell, &kDKMessageListItemKey) integerValue];
        if (item == DKMessageListItemNone) continue;
        [out appendFormat:@"  %@ %@ frame=%@ 淡出=%.2f\n", DKMessageListName(item), NSStringFromClass(cell.class),
            NSStringFromCGRect([cell convertRect:cell.bounds toView:nil]), DKAdjustFadeFactor(DKMessageCellContent(cell))];
    }
    return out;
}

#pragma mark - Hook

%hook AWEIMSkylightViewComponent

- (void)applySnapshot:(RxDiffableDataSourceSnapshot *)snapshot animatingDifferences:(BOOL)animating completion:(id)completion {
    DKMessageSkylightFilter(snapshot);
    %orig;
}

%end

%hook AWEIMSkylightDataComponent

- (BOOL)shouldHidden {
    BOOL hidden = %orig;
    return hidden || DKMessageSkylightRowRemoved();
}

%end

%hook AWEIMSkylightListView

- (void)viewWillAppear {
    %orig;
    DKMessageTrack(&gDKSkylightLists, self);
}

- (void)performShouldHiddenDelegate {
    DKMessageTrack(&gDKSkylightLists, self);
    %orig;
}

%end

%hook AWEIMSkylightCommonCell

- (void)renderWithViewModel:(AWEIMSkylightCellViewModel *)viewModel {
    %orig;
    id model = [viewModel respondsToSelector:@selector(model)] ? viewModel.model : nil;
    DKMessageListMarkCell(self, DKMessageSkylightItem(model));
}

%end

%hook AWEIMChatListCommonCell

- (void)renderWithHolder:(id)holder {
    %orig;
    AWEIMChatCellViewModel *viewModel = [holder isKindOfClass:%c(AWEIMChatCellViewModel)] ? holder
        : ([self respondsToSelector:@selector(cellViewModel)] ? self.cellViewModel : nil);
    id chat = [viewModel respondsToSelector:@selector(chat)] ? viewModel.chat : nil;
    DKMessageListMarkCell(self, DKMessageChatIsInteraction(chat) ? DKMessageListItemInteraction : DKMessageListItemNone);
}

%end

%hook IESIMOfficialChatDataSource

- (BOOL)p_canShowOfficialChat:(AWEIMChatModel *)chat {
    BOOL show = %orig;
    if (!DKMessageChatIsInteraction(chat)) return show;
    DKMessageRecordInteraction(self, chat);
    return show && !DKMessageListRemoved(DKMessageListItemInteraction);
}

%end
