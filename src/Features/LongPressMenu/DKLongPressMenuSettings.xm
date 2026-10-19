//
//  DKLongPressMenuSettings.xm
//  长按菜单：设置入口 —— 「作品长按菜单」「评论长按菜单」两个子页入口（与「播放页精简」一样只有标题），
//  子页含宫格排列与按目录逐项的移除开关。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKLongPressMenu.h"
#import "DKSettings.h"

static NSArray<NSString *> *DKColumnOptions(void) {
    return @[ @"每行 1 个", @"每行 2 个", @"每行 3 个", @"每行 4 个" ];
}

static NSString *DKMenuName(DKLongPressMenuKind kind) {
    return kind == DKLongPressMenuComment ? @"评论长按菜单" : @"作品长按菜单";
}

static NSString *DKColumnsKey(DKLongPressMenuKind kind) {
    return kind == DKLongPressMenuComment ? DKKeyCommentMenuColumns : DKKeyFeedMenuColumns;
}

static NSString *DKSummary(NSInteger columns, NSInteger hidden, BOOL brief) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (columns > 1) [parts addObject:[NSString stringWithFormat:@"每行 %ld 个", (long)columns]];
    if (hidden > 0) [parts addObject:[NSString stringWithFormat:@"已移除 %ld 项", (long)hidden]];
    if (parts.count == 0) return brief ? @"未调整" : @"原生列表，未移除";
    return [parts componentsJoinedByString:@" · "];
}

// 按目录里记下的文案列出被移除的项；目录外的标识原样列出。
static NSString *DKHiddenNames(DKLongPressMenuKind kind, NSArray<NSString *> *itemIDs) {
    NSMutableDictionary<NSString *, NSString *> *titles = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in DKLongPressMenuCatalog(kind)) {
        titles[entry[DKLongPressMenuFieldID]] = entry[DKLongPressMenuFieldTitle];
    }
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:itemIDs.count];
    for (NSString *itemID in itemIDs) [names addObject:titles[itemID] ?: itemID];
    return [names componentsJoinedByString:@"、"];
}

static NSString *DKColumnsInfo(DKLongPressMenuKind kind) {
    if (kind == DKLongPressMenuComment) {
        return @"把评论长按菜单的每个分组排成每行多个：每行 1 个为抖音原生列表；每行 2 个保持「图标在左、文字在右」；"
               @"每行 3–4 个为「图标在上、文字在下」。移除部分菜单项后，分组内剩余项自动依次补位。下次打开菜单时生效。";
    }
    return @"把视频与图文长按菜单的单按钮排成每行多个：每行 1 个为抖音原生列表；每行 2 个保持「图标在左、文字在右」；"
           @"每行 3–4 个为「图标在上、文字在下」。每行 2–4 个时，所有单按钮按原顺序集中在上方宫格区，"
           @"倍速、带开关或设置入口的整行项（如弹幕、自动连播）按原顺序排在最下方。"
           @"移除部分菜单项后，剩余项自动依次补位。下次打开菜单时生效。";
}

static NSString *DKRowInfo(DKLongPressMenuKind kind, NSString *title) {
    return [NSString stringWithFormat:@"开启后从%@移除「%@」，下次打开菜单时生效。", DKMenuName(kind), title];
}

static void DKOpenMenuPage(DKLongPressMenuKind kind, UIViewController *presenter) {
    AWESettingItemModel *columns = DKSettingsWithInfo(DKMakeChoice(DKColumnsKey(kind), @"宫格排列", DKColumnOptions()),
                                                      DKColumnsInfo(kind));

    NSMutableArray<AWESettingItemModel *> *rows = [NSMutableArray array];
    for (NSDictionary *entry in DKLongPressMenuCatalog(kind)) {
        NSString *itemID = entry[DKLongPressMenuFieldID];
        NSString *title = entry[DKLongPressMenuFieldTitle] ?: itemID;
        [rows addObject:DKMakeSwitch(DKLongPressMenuHideKey(kind, itemID), title, DKRowInfo(kind, title))];
    }

    NSString *source = kind == DKLongPressMenuComment ? @"长按一次评论" : @"长按一次视频或图文";
    NSString *note = nil;
    if (!rows.count) {
        note = [NSString stringWithFormat:@"尚未收录菜单项：先%@，再回到这里勾选要移除的项。", source];
    } else if (kind == DKLongPressMenuComment) {
        note = @"「移除菜单项」列出打开过的评论长按菜单里出现的项，新出现的项会自动补进来。勾选后下次打开菜单生效。";
    } else {
        note = @"「移除菜单项」列出打开过的长按菜单里出现的原生项，新出现的项会自动补进来；插件加入的保存项在「媒体保存」中设置。勾选后下次打开菜单生效。";
    }
    NSMutableArray<AWESettingSectionModel *> *sections = [NSMutableArray array];
    [sections addObject:DKSettingsMakeSection(@"排列", nil, @[ columns ])];
    if (rows.count) [sections addObject:DKSettingsMakeSection(@"移除菜单项", nil, rows)];
    DKSettingsPushNotedSections(presenter, DKMenuName(kind), note, sections);
}

static void DKRegisterMenu(DKLongPressMenuKind kind, NSString *key, NSString *hidePrefix) {
    DKSettingsRegister(key, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeAction(key, DKMenuName(kind), nil,
                                                 ^(__unused AWESettingItemModel *it, UIViewController *presenter) {
            DKOpenMenuPage(kind, presenter);
        });
        DKSettingsWithValues(item, @[ [DKSettingsValue integerWithKey:DKColumnsKey(kind) minimum:0 maximum:3],
                                      [DKSettingsValue idSetWithPrefix:hidePrefix] ],
            ^NSString *(NSArray *values, BOOL brief) {
                NSInteger index = values[0] == NSNull.null ? 0 : [values[0] integerValue];
                NSArray<NSString *> *itemIDs = [values[1] isKindOfClass:NSArray.class] ? values[1] : @[];
                if (brief || itemIDs.count == 0) return DKSummary(index + 1, (NSInteger)itemIDs.count, brief);
                NSString *head = index > 0 ? [NSString stringWithFormat:@"每行 %ld 个 · ", (long)index + 1] : @"";
                return [head stringByAppendingFormat:@"移除 %@", DKHiddenNames(kind, itemIDs)];
            });
        return item;
    });
}

%ctor {
    DKRegisterMenu(DKLongPressMenuFeed, DKKeyFeedMenu, DKKeyFeedMenuHidePrefix);
    DKRegisterMenu(DKLongPressMenuComment, DKKeyCommentMenu, DKKeyCommentMenuHidePrefix);
}
