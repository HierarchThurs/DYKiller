//
//  DKMessageCleanSettings.xm
//  DYKiller
//
//  消息页精简各项的设置登记：三档单选（显示 / 隐藏 / 移除），改值后立即刷新消息页。
//

#import "DKMessageClean.h"
#import "DKKeys.h"
#import "DKSettings.h"

static AWESettingItemModel *DKMessageCleanSettingItem(NSString *key, NSString *title, NSString *info) {
    AWESettingItemModel *item = DKMakeChoice(key, title, @[ @"显示", @"隐藏", @"移除" ]);
    DKSettingsOnChange(item, ^{ DKMessageCleanRefresh(); });
    return DKSettingsWithInfo(item, info);
}

%ctor {
    NSArray<NSArray<NSString *> *> *items = @[
        // 顶栏
        @[ DKKeyMessageSideBarMode, @"左侧栏",
           @"消息页顶栏左上角的侧边栏入口（≡）。隐藏：图标不显示，原位置仍可点击打开侧边栏；移除：不显示、不可点击，右侧的装扮商店随之左移。" ],
        @[ DKKeyMessageSlotMode, @"装扮商店",
           @"消息页顶栏左侧的运营入口，当前为装扮商店，内容随活动变化。隐藏：不显示，原位置仍可点击；移除：不显示、不可点击。" ],
        @[ DKKeyMessageSearchMode, @"搜索图标",
           @"消息页顶栏右侧的搜索图标。隐藏：不显示，原位置仍可点击进入搜索；移除：不显示、不可点击。" ],
        @[ DKKeyMessagePlusMode, @"加号",
           @"消息页顶栏右上角的加号。隐藏：不显示，原位置仍可点击展开；移除：不显示、不可点击，搜索图标移到最右侧。" ],
        // 列表顶部
        @[ DKKeyMessageDailyMode, @"限时日常",
           @"消息列表上方头像行开头的业务入口：限时日常，以及轮换出现的音乐回忆、一起看直播、回忆等。隐藏：不显示，原位置仍可点击；移除：不显示、不可点击，好友头像随之左移。" ],
        @[ DKKeyMessageFriendAvatarMode, @"好友大头像",
           @"消息列表上方头像行里的好友头像。隐藏：不显示，原位置仍可点击；移除：不显示、不可点击。与「限时日常」都移除时整行收起，下方列表上移。" ],
        @[ DKKeyMessageInteractionMode, @"互动消息",
           @"消息列表里的「互动消息」会话。隐藏：不显示，原位置仍可点击进入；移除：从列表移除，下方会话随之上移。" ],
    ];
    for (NSArray<NSString *> *entry in items) {
        NSString *key = entry[0], *title = entry[1], *info = entry[2];
        DKSettingsRegister(key, ^AWESettingItemModel *{ return DKMessageCleanSettingItem(key, title, info); });
    }
}
