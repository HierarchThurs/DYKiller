//
//  DKFeedMenuClean.xm
//  长按菜单：作品长按菜单 —— 收录原生菜单项，按勾选移除。
//
//  实现：
//   - 面板每次装数据（首次加载、配置刷新）都经 -[AWELongPressPanelTableViewController setDataArray:]，
//     在这里收录与过滤，之后的取数与插件保存项都基于过滤后的分组。
//   - 原生项以 panelBizVMIdentifier 识别；插件加入的保存项没有该标识，不收录也不移除。
//   - 分组里的项全部移除时整组去掉；原生项全部移除时只留第一个普通分组（groupType 0）的空副本作面板结构，
//     插件保存项填入这一组，没有保存项时面板为空。
//   - 勾选在下一次打开菜单时生效。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKLongPressMenu.h"
#import "DKUtils.h"

static NSString *DKFeedItemID(id item) {
    if (![item respondsToSelector:@selector(panelBizVMIdentifier)]) return nil;
    id itemID = [item panelBizVMIdentifier];
    return [itemID isKindOfClass:NSString.class] && [itemID length] ? itemID : nil;
}

static NSString *DKFeedItemTitle(id item) {
    id title = [item respondsToSelector:@selector(describeString)] ? [item describeString] : nil;
    return [title isKindOfClass:NSString.class] && [title length] ? title : nil;
}

static NSArray *DKFeedGroupItems(id group) {
    id items = [group respondsToSelector:@selector(groupArr)] ? [group groupArr] : nil;
    return [items isKindOfClass:NSArray.class] ? items : nil;
}

static NSString *DKFeedScene(NSArray *groups) {
    for (id group in groups) {
        for (id item in DKFeedGroupItems(group)) {
            id scene = [item respondsToSelector:@selector(referString)] ? [(AWELongPressPanelBaseViewModel *)item referString] : nil;
            if ([scene isKindOfClass:NSString.class] && [scene length]) return scene;
        }
    }
    return @"-";
}

// 原生项全部移除后留下的面板结构：第一个普通分组的空副本。普通分组的行数随条目数，空组不出行。
static id DKFeedMenuEmptyGroup(NSArray *groups) {
    Class groupClass = NSClassFromString(@"AWELongPressPanelViewGroupModel");
    for (AWELongPressPanelViewGroupModel *group in groups) {
        if ([group isKindOfClass:groupClass] && group.groupType == 0) return DKFeedMenuCopyGroup(group, @[]);
    }
    return nil;
}

static NSArray *DKFeedMenuFilter(NSArray *groups) {
    if (![groups isKindOfClass:NSArray.class] || groups.count == 0) return groups;

    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    NSUInteger total = 0;
    BOOL anyHidden = NO;
    for (id group in groups) {
        for (id item in DKFeedGroupItems(group)) {
            total++;
            NSString *itemID = DKFeedItemID(item);
            if (!itemID) continue;
            [entries addObject:@{ DKLongPressMenuFieldID: itemID,
                                  DKLongPressMenuFieldTitle: DKFeedItemTitle(item) ?: itemID }];
            if (DKLongPressMenuHidden(DKLongPressMenuFeed, itemID)) anyHidden = YES;
        }
    }
    DKLongPressMenuRecord(DKLongPressMenuFeed, entries);

    NSString *head = [NSString stringWithFormat:@"%@  %lu 组 %lu 项", DKFeedScene(groups),
                      (unsigned long)groups.count, (unsigned long)total];
    if (!anyHidden) {
        DKLongPressMenuNote(DKLongPressMenuFeed, [head stringByAppendingString:@"，无移除"]);
        return groups;
    }

    NSMutableArray *result = [NSMutableArray arrayWithCapacity:groups.count];
    NSUInteger kept = 0, removed = 0;
    for (id group in groups) {
        NSArray *items = DKFeedGroupItems(group);
        NSMutableArray *keptItems = [NSMutableArray arrayWithCapacity:items.count];
        for (id item in items) {
            if (DKLongPressMenuHidden(DKLongPressMenuFeed, DKFeedItemID(item))) removed++;
            else [keptItems addObject:item];
        }
        kept += keptItems.count;
        if (!items || keptItems.count == items.count) {
            [result addObject:group];
        } else if (keptItems.count) {
            [result addObject:DKFeedMenuCopyGroup(group, keptItems) ?: group];
        }
    }
    if (kept == 0) {
        id empty = DKFeedMenuEmptyGroup(groups);
        DKLongPressMenuNote(DKLongPressMenuFeed, [head stringByAppendingFormat:@"，移除全部 %lu 项%@",
                                                  (unsigned long)removed, empty ? @"" : @"，无普通分组"]);
        return empty ? @[ empty ] : @[];
    }
    DKLongPressMenuNote(DKLongPressMenuFeed, [head stringByAppendingFormat:@"，移除 %lu 项，剩 %lu 组",
                                              (unsigned long)removed, (unsigned long)result.count]);
    return result;
}

%hook AWELongPressPanelTableViewController

- (void)setDataArray:(NSArray *)dataArray {
    %orig(DKFeedMenuFilter(dataArray));
}

%end
