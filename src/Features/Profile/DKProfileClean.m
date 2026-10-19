//
//  DKProfileClean.m
//  DYKiller
//
//  个人主页精简的诊断汇总。
//

#import "DKProfileClean.h"
#import "DKKeys.h"
#import "DKUtils.h"

static NSString *DKProfileCleanModeText(DKDisplayMode mode) {
    switch (mode) {
        case DKDisplayModeHide: return @"隐藏";
        case DKDisplayModeRemove: return @"移除";
        default: return @"显示";
    }
}

NSString *DKProfileCleanStatus(void) {
    NSArray<NSArray<NSString *> *> *modes = @[
        @[ DKKeyProfileAddFriendMode, @"添加好友" ],
        @[ DKKeyProfileVisitorMode, @"访客" ],
        @[ DKKeyProfileSearchMode, @"搜索图标" ],
        @[ DKKeyProfileSideBarMode, @"侧栏图标" ],
        @[ DKKeyProfileAvatarPlusMode, @"头像加号" ],
        @[ DKKeyProfileSwitchAccountMode, @"切换账号箭头" ],
        @[ DKKeyProfileCapsuleMode, @"胶囊行" ],
        @[ DKKeyProfileStatsMode, @"获赞与关注数据" ],
        @[ DKKeyProfileEditMode, @"编辑主页" ],
        @[ DKKeyProfileGuideBannerMode, @"发布引导横幅" ],
    ];
    NSArray<NSArray<NSString *> *> *tabs = @[
        @[ DKKeyProfileRemovePostTab, @"作品" ],
        @[ DKKeyProfileRemoveDailyTab, @"日常" ],
        @[ DKKeyProfileRemoveFavoriteTab, @"收藏" ],
        @[ DKKeyProfileRemoveLikeTab, @"喜欢" ],
        @[ DKKeyProfileRemoveFootprintTab, @"足迹" ],
    ];
    NSMutableArray<NSString *> *modeTexts = [NSMutableArray array];
    for (NSArray<NSString *> *item in modes) {
        [modeTexts addObject:[NSString stringWithFormat:@"%@=%@", item[1], DKProfileCleanModeText(DKPrefDisplayMode(item[0]))]];
    }
    NSMutableArray<NSString *> *removedTabs = [NSMutableArray array];
    for (NSArray<NSString *> *item in tabs) {
        if (DKPrefBool(item[0])) [removedTabs addObject:item[1]];
    }
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"档位：%@\n", [modeTexts componentsJoinedByString:@" "]];
    [out appendFormat:@"移除分页：%@\n", removedTabs.count ? [removedTabs componentsJoinedByString:@"、"] : @"无"];
    [out appendString:DKProfileCleanTopBarStatus()];
    [out appendString:DKProfileCleanNameAreaStatus()];
    [out appendString:DKProfileCleanHeaderStatus()];
    [out appendString:DKProfileCleanTabsStatus()];
    [out appendString:DKProfileSettingsEntryStatus()];
    return out;
}
