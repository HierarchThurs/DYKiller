//
//  DKFriendCleanSettings.xm
//  DYKiller
//
//  朋友页精简设置：三档单选改值后立即刷新，推荐卡片过滤开关从下次加载生效。
//

#import "DKFriendClean.h"
#import "DKKeys.h"
#import "DKSettings.h"

static AWESettingItemModel *DKFriendCleanSettingItem(NSString *key, NSString *title, NSString *info) {
    AWESettingItemModel *item = DKMakeChoice(key, title, @[ @"显示", @"隐藏", @"移除" ]);
    DKSettingsOnChange(item, ^{ DKFriendCleanRefresh(); });
    return DKSettingsWithInfo(item, info);
}

%ctor {
    NSArray<NSArray<NSString *> *> *items = @[
        // 顶栏
        @[ DKKeyFriendAvatarEntryMode, @"头像和加号",
           @"朋友页顶栏左上角的头像和加号（日常相机入口）。隐藏：不显示，原位置仍可点击打开日常相机；移除：不显示、不可点击。" ],
        @[ DKKeyFriendDailyMode, @"限时日常",
           @"朋友页顶栏中间的「限时日常」胶囊。隐藏：不显示，原位置仍可点击展开，下拉与刷新后自动展开照常；移除：不显示、不可点击，点击、下拉与刷新后都不再展开限时日常。" ],
        @[ DKKeyFriendButtonMode, @"朋友按钮",
           @"朋友页顶栏右上角的朋友按钮（朋友申请，含未读角标）。隐藏：不显示，原位置仍可点击；移除：不显示、不可点击。" ],
        // 作品
        @[ DKKeyFriendRelationTagMode, @"朋友标记",
           @"朋友作品文案上方的「朋友」标记。隐藏：不显示，位置保留；移除：不显示，所在行收起。" ],
        @[ DKKeyFriendStoryTagMode, @"日常标签",
           @"作品昵称右侧的「日常」标签，凡出现处都生效。隐藏：不显示，位置保留；移除：不显示，同行内容随之收拢。" ],
        @[ DKKeyFriendFollowTagMode, @"关注标签",
           @"作品文案上方的「你的关注」「互相关注」等关注标签，凡出现处都生效。隐藏：不显示，位置保留；移除：不显示，所在行收起。" ],
        @[ DKKeyFriendFastReplyMode, @"私信面板",
           @"朋友作品文案下方的「私信 xxx」面板，凡出现处都生效。隐藏：不显示，原位置仍可点击；移除：不显示、不可点击，上方文案随之下移。" ],
        @[ DKKeyFriendSendMessageMode, @"私信图标",
           @"作品右侧头像下方的「私信」小飞机图标，凡出现处都生效。隐藏：不显示，原位置仍可点击打开私信；移除：不显示、不可点击。" ],
    ];
    for (NSArray<NSString *> *entry in items) {
        NSString *key = entry[0], *title = entry[1], *info = entry[2];
        DKSettingsRegister(key, ^AWESettingItemModel *{ return DKFriendCleanSettingItem(key, title, info); });
    }
    DKSettingsRegister(DKKeyFriendRemoveRecommendCard, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyFriendRemoveRecommendCard, @"移除看看朋友推荐的作品",
            @"移除朋友页内容流中整张「看看朋友推荐的作品」卡片，前后作品直接相连。从下一次加载或刷新起生效。关闭后同样需重新加载或刷新。");
    });
}
