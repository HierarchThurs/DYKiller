//
//  DKTabBarRemovalSettings.xm
//  功能：底栏项目移除 —— 设置主页入口，以及逐项勾选的子页面。
//

#import "DKTabBarRemoval.h"
#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"

static NSString *DKBottomBarEntryDetail(void) {
    NSInteger count = DKTabBarRemovedCount();
    return count ? [NSString stringWithFormat:@"已移除 %ld 个", (long)count] : @"未移除";
}

static NSString *DKBottomBarRowInfo(NSString *tabID, NSString *title) {
    if ([tabID isEqualToString:@"homepage_publish"]) {
        return @"开启后从首页底栏移除「拍摄」按钮，勾选后立即生效；移除后无法从底栏进入拍摄页，"
               @"悬浮玻璃底栏的「更换拍摄图标」随之停用，恢复拍摄按钮后照原样生效。";
    }
    if ([tabID isEqualToString:@"homepage_mall"]) {
        return @"开启后从首页底栏移除「商城」，勾选后立即生效。仅部分账号的底栏有「商城」，没有时开启无影响。";
    }
    if ([tabID isEqualToString:@"homepage_profile"]) {
        return @"开启后从首页底栏移除「我」，勾选后立即生效。抖音设置页（含 DYKiller 设置）通常经「我 → ≡ → 设置」进入，"
               @"移除前请确认还有其他入口。";
    }
    return [NSString stringWithFormat:@"开启后从首页底栏移除「%@」，勾选后立即生效。", title];
}

static void DKBottomBarOpen(AWESettingItemModel *entryItem, UIViewController *presenter) {
    __weak AWESettingItemModel *weakEntry = entryItem;
    NSMutableArray<AWESettingItemModel *> *rows = [NSMutableArray array];
    for (NSString *tabID in DKTabBarRemovableTabIDs()) {
        NSString *title = DKTabBarRemovableTitle(tabID);
        AWESettingItemModel *row = DKMakeSwitch([DKKeyBottomBarHidePrefix stringByAppendingString:tabID],
                                                title, DKBottomBarRowInfo(tabID, title));
        // 主页入口的计数随页面返回时刷新显示。
        DKSettingsOnChange(row, ^{
            DKTabBarRemovalRefresh();
            weakEntry.detail = DKBottomBarEntryDetail();
        });
        [rows addObject:row];
    }
    DKSettingsPushPage(presenter, @"移除底栏项目", @"勾选后立即生效", rows);
}

// 按项目表顺序列出名字；表外的 ID 原样列出。
static NSString *DKBottomBarNames(NSArray<NSString *> *tabIDs) {
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:tabIDs.count];
    for (NSString *tabID in tabIDs) [names addObject:DKTabBarRemovableTitle(tabID) ?: tabID];
    return [names componentsJoinedByString:@"、"];
}

#pragma mark - 设置项注册

%ctor {
    DKSettingsRegister(DKKeyBottomBar, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeAction(DKKeyBottomBar, @"移除底栏项目", DKBottomBarEntryDetail(),
                                                 ^(AWESettingItemModel *it, UIViewController *presenter) {
            DKBottomBarOpen(it, presenter);
        });
        DKSettingsWithValues(item, @[ [DKSettingsValue idSetWithPrefix:DKKeyBottomBarHidePrefix] ],
            ^NSString *(NSArray *values, BOOL brief) {
                NSArray<NSString *> *tabIDs = values[0];
                if (tabIDs.count == 0) return @"未移除";
                return brief ? [NSString stringWithFormat:@"已移除 %lu 个", (unsigned long)tabIDs.count]
                             : DKBottomBarNames(tabIDs);
            });
        DKSettingsOnChange(item, ^{ DKTabBarRemovalRefresh(); });
        return DKSettingsWithInfo(item,
            @"逐项选择要从首页底栏移除的项目，勾选后立即生效；「首页」不可移除。"
            @"开启悬浮玻璃底栏时，剩余项目保持原有大小并整体居中。");
    });
}
