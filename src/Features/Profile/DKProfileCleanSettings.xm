//
//  DKProfileCleanSettings.xm
//  DYKiller
//
//  个人主页精简设置：三档单选与分页移除开关，改值后立即刷新所属部分。
//

#import "DKProfileClean.h"
#import "DKKeys.h"
#import "DKSettings.h"

typedef void (*DKProfileCleanRefresher)(void);

static dispatch_block_t DKProfileCleanOnMain(DKProfileCleanRefresher refresh) {
    return ^{
        if (NSThread.isMainThread) refresh();
        else dispatch_async(dispatch_get_main_queue(), ^{ refresh(); });
    };
}

// 胶囊行移除后昵称区高度可能变化，重建组件后再让头部重算分区。
static void DKProfileCleanCapsuleRefresh(void) {
    DKProfileCleanNameAreaRefresh();
    DKProfileCleanHeaderRefresh();
}

static void DKProfileCleanServiceAreaRefresh(void) {
    DKProfileSettingsEntryRefresh();
    DKProfileCleanHeaderRefresh();
}

static DKProfileCleanRefresher DKProfileCleanRefresherForKey(NSString *key) {
    if ([key isEqualToString:DKKeyProfileAddFriendMode] || [key isEqualToString:DKKeyProfileVisitorMode] ||
        [key isEqualToString:DKKeyProfileSearchMode] || [key isEqualToString:DKKeyProfileSideBarMode]) {
        return DKProfileCleanTopBarRefresh;
    }
    if ([key isEqualToString:DKKeyProfileAvatarPlusMode] || [key isEqualToString:DKKeyProfileSwitchAccountMode]) {
        return DKProfileCleanNameAreaRefresh;
    }
    if ([key isEqualToString:DKKeyProfileCapsuleMode]) return DKProfileCleanCapsuleRefresh;
    return DKProfileCleanHeaderRefresh;
}

static AWESettingItemModel *DKProfileCleanChoiceItem(NSString *key, NSString *title, NSString *info) {
    AWESettingItemModel *item = DKMakeChoice(key, title, @[ @"显示", @"隐藏", @"移除" ]);
    DKSettingsOnChange(item, DKProfileCleanOnMain(DKProfileCleanRefresherForKey(key)));
    return DKSettingsWithInfo(item, info);
}

static AWESettingItemModel *DKProfileCleanTabItem(NSString *key, NSString *title, NSString *info) {
    AWESettingItemModel *item = DKMakeSwitch(key, title, info);
    DKSettingsOnChange(item, DKProfileCleanOnMain(DKProfileCleanTabsRefresh));
    return item;
}

%ctor {
    NSArray<NSArray<NSString *> *> *choices = @[
        // 顶栏
        @[ DKKeyProfileAddFriendMode, @"添加好友",
           @"个人主页顶栏左上角的「添加好友」。隐藏：不显示，原位置仍可点击；移除：不显示、不可点击。" ],
        @[ DKKeyProfileVisitorMode, @"访客",
           @"个人主页顶栏的「新访客」胶囊。隐藏：不显示，原位置仍可点击查看访客；移除：不显示、不可点击。" ],
        @[ DKKeyProfileSearchMode, @"搜索图标",
           @"个人主页顶栏右侧的搜索图标。隐藏：不显示，原位置仍可点击搜索；移除：不显示、不可点击，访客胶囊随之右移。" ],
        @[ DKKeyProfileSideBarMode, @"侧栏图标",
           @"个人主页顶栏右上角的侧栏图标（≡）。隐藏：不显示，原位置仍可点击打开侧栏；移除：不显示、不可点击，左侧图标随之右移。" ],
        // 头像与昵称
        @[ DKKeyProfileAvatarPlusMode, @"头像加号",
           @"头像右下角的加号（发日常）。隐藏：不显示，原位置仍可点击发日常；移除：不显示，点该处等同点头像。两档都不在头像上留加号的缺口。" ],
        @[ DKKeyProfileSwitchAccountMode, @"切换账号箭头",
           @"昵称后的下拉箭头（切换账号）及其未读点。隐藏：不显示，原位置仍可点击切换账号；移除：不显示、不可点击。" ],
        @[ DKKeyProfileCapsuleMode, @"昵称下方胶囊",
           @"抖音号下方的胶囊行（如「创建 AI 形象」），按所在位置识别，内容变化后同样生效。隐藏：不显示，原位置仍可点击；移除：不显示、不可点击，昵称区随之收拢。" ],
        // 数据与按钮
        @[ DKKeyProfileStatsMode, @"获赞与关注数据",
           @"获赞、互关、关注、粉丝整行。隐藏：不显示，原位置仍可点击；移除：不显示、不可点击，编辑主页保持原位；与编辑主页都移除时整行收起。" ],
        @[ DKKeyProfileEditMode, @"编辑主页",
           @"数据右侧的「编辑主页」按钮。隐藏：不显示，原位置仍可点击；移除：不显示、不可点击。" ],
        // 内容
        @[ DKKeyProfileGuideBannerMode, @"发布引导横幅",
           @"功能入口下方的发布引导横幅（如「记录下幸福瞬间」），按所在位置识别，内容变化后同样生效。隐藏：不显示，原位置仍可点击；移除：不显示、不可点击，下方分页栏随之上移。" ],
    ];
    for (NSArray<NSString *> *entry in choices) {
        NSString *key = entry[0], *title = entry[1], *info = entry[2];
        DKSettingsRegister(key, ^AWESettingItemModel *{ return DKProfileCleanChoiceItem(key, title, info); });
    }

    NSArray<NSArray<NSString *> *> *tabs = @[
        @[ DKKeyProfileRemovePostTab, @"移除作品", @"作品" ],
        @[ DKKeyProfileRemoveDailyTab, @"移除日常", @"日常" ],
        @[ DKKeyProfileRemoveFavoriteTab, @"移除收藏", @"收藏" ],
        @[ DKKeyProfileRemoveLikeTab, @"移除喜欢", @"喜欢" ],
        @[ DKKeyProfileRemoveFootprintTab, @"移除足迹", @"足迹" ],
    ];
    DKSettingsRegister(DKKeyProfileRemoveServiceArea, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(DKKeyProfileRemoveServiceArea, @"移除主页功能区",
            @"移除个人主页的功能区（观看历史、稍后再看、全部功能等入口所在的一整行），下方内容随之上移，不占位。"
            @"开启后「插件工具」里的 DYKiller 主页入口也不再显示。");
        DKSettingsOnChange(item, DKProfileCleanOnMain(DKProfileCleanServiceAreaRefresh));
        return item;
    });

    for (NSArray<NSString *> *entry in tabs) {
        NSString *key = entry[0], *title = entry[1];
        NSString *info = [NSString stringWithFormat:@"移除个人主页的「%@」分页，其余分页随之重排。全部分页都移除时保持原样。", entry[2]];
        DKSettingsRegister(key, ^AWESettingItemModel *{ return DKProfileCleanTabItem(key, title, info); });
    }
}
