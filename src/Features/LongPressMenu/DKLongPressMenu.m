//
//  DKLongPressMenu.m
//  长按菜单：菜单项目录、移除开关键、宫格列数、分组复制与诊断摘要。
//

#import "DKLongPressMenu.h"
#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKUtils.h"

static NSString *DKCatalogKey(DKLongPressMenuKind kind) {
    return kind == DKLongPressMenuComment ? DKKeyCommentMenuCatalog : DKKeyFeedMenuCatalog;
}

static NSString *DKHidePrefix(DKLongPressMenuKind kind) {
    return kind == DKLongPressMenuComment ? DKKeyCommentMenuHidePrefix : DKKeyFeedMenuHidePrefix;
}

static NSString *DKEntryID(id entry) {
    if (![entry isKindOfClass:NSDictionary.class]) return nil;
    id itemID = entry[DKLongPressMenuFieldID];
    return [itemID isKindOfClass:NSString.class] && [itemID length] ? itemID : nil;
}

NSArray<NSDictionary *> *DKLongPressMenuCatalog(DKLongPressMenuKind kind) {
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:DKCatalogKey(kind)];
    if (![stored isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *catalog = [NSMutableArray array];
    for (id entry in stored) {
        if (DKEntryID(entry)) [catalog addObject:entry];
    }
    return catalog;
}

void DKLongPressMenuRecord(DKLongPressMenuKind kind, NSArray<NSDictionary *> *entries) {
    if (entries.count == 0) return;
    NSArray<NSDictionary *> *old = DKLongPressMenuCatalog(kind);
    NSMutableSet<NSString *> *known = [NSMutableSet set];
    for (NSDictionary *entry in old) [known addObject:DKEntryID(entry)];

    NSMutableArray *catalog = [old mutableCopy];
    for (NSDictionary *entry in entries) {
        NSString *itemID = DKEntryID(entry);
        if (!itemID || [known containsObject:itemID]) continue;
        [known addObject:itemID];
        id title = entry[DKLongPressMenuFieldTitle];
        [catalog addObject:@{
            DKLongPressMenuFieldID: itemID,
            DKLongPressMenuFieldTitle: [title isKindOfClass:NSString.class] && [title length] ? title : itemID,
        }];
    }
    if (catalog.count == old.count) return;
    [NSUserDefaults.standardUserDefaults setObject:catalog forKey:DKCatalogKey(kind)];
}

NSString *DKLongPressMenuHideKey(DKLongPressMenuKind kind, NSString *itemID) {
    return [DKHidePrefix(kind) stringByAppendingString:itemID ?: @""];
}

BOOL DKLongPressMenuHidden(DKLongPressMenuKind kind, NSString *itemID) {
    return itemID.length && DKPrefBool(DKLongPressMenuHideKey(kind, itemID));
}

NSInteger DKLongPressMenuHiddenCount(DKLongPressMenuKind kind) {
    NSInteger count = 0;
    for (NSDictionary *entry in DKLongPressMenuCatalog(kind)) {
        if (DKLongPressMenuHidden(kind, DKEntryID(entry))) count++;
    }
    return count;
}

NSInteger DKLongPressMenuColumns(DKLongPressMenuKind kind) {
    NSString *key = kind == DKLongPressMenuComment ? DKKeyCommentMenuColumns : DKKeyFeedMenuColumns;
    NSInteger index = DKPrefInteger(key);
    return MIN(4, MAX(1, index + 1));
}

id DKFeedMenuCopyGroup(id source, NSArray *items) {
    Class cls = NSClassFromString(@"AWELongPressPanelViewGroupModel");
    if (!cls || ![source isKindOfClass:cls]) return nil;
    AWELongPressPanelViewGroupModel *original = source;
    AWELongPressPanelViewGroupModel *group = [cls new];
    group.groupType = original.groupType;
    group.isModern = original.isModern;
    group.cellHeight = original.cellHeight;
    group.hasMore = original.hasMore;
    long long rows = original.numberOfRowsInSection;
    NSArray *before = [original.groupArr isKindOfClass:NSArray.class] ? original.groupArr : nil;
    group.numberOfRowsInSection = rows == (long long)before.count ? (long long)items.count : rows;
    group.groupArr = items;
    return group;
}

#pragma mark - 诊断

static NSMutableDictionary<NSNumber *, NSString *> *DKNotes(void) {
    static NSMutableDictionary *notes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ notes = [NSMutableDictionary dictionary]; });
    return notes;
}

void DKLongPressMenuNote(DKLongPressMenuKind kind, NSString *note) {
    if (!note) return;
    @synchronized (DKNotes()) {
        DKNotes()[@(kind)] = [note copy];
    }
}

static void DKAppendKind(NSMutableString *out, DKLongPressMenuKind kind, NSString *name) {
    NSArray<NSDictionary *> *catalog = DKLongPressMenuCatalog(kind);
    [out appendFormat:@"%@：每行 %ld 个  目录 %lu 项  已移除 %ld 项\n", name, (long)DKLongPressMenuColumns(kind),
     (unsigned long)catalog.count, (long)DKLongPressMenuHiddenCount(kind)];
    for (NSDictionary *entry in catalog) {
        NSString *itemID = DKEntryID(entry);
        [out appendFormat:@"  %@ %@  %@\n", DKLongPressMenuHidden(kind, itemID) ? @"✕" : @"·", itemID,
         entry[DKLongPressMenuFieldTitle]];
    }
    NSString *note;
    @synchronized (DKNotes()) {
        note = DKNotes()[@(kind)];
    }
    [out appendFormat:@"  最近一次：%@\n", note ?: @"本次启动尚未打开"];
}

NSString *DKLongPressMenuStatus(void) {
    NSMutableString *out = [NSMutableString string];
    DKAppendKind(out, DKLongPressMenuFeed, @"作品长按菜单");
    DKAppendKind(out, DKLongPressMenuComment, @"评论长按菜单");
    [out appendFormat:@"作品长按菜单玻璃：%@\n", DKFeedMenuGlassStatus()];
    [out appendFormat:@"复制评论移除用户名：%@\n",
     DKPrefBool(DKKeyCommentCopyWithoutName) ? @"开" : @"关"];
    return out;
}
