//
//  DKPlaybackCleanSettings.xm
//  DYKiller
//
//  播放页精简各项的设置登记：三档单选（显示 / 隐藏 / 移除），改值后立即刷新当前页面。
//  昵称上方标签与底部相关栏目在各自目录子页登记。
//

#import "DKPlaybackClean.h"
#import "DKKeys.h"
#import "DKSettings.h"

static AWESettingItemModel *DKCleanSettingItem(NSString *key, NSString *title, NSString *info) {
    AWESettingItemModel *item = DKMakeChoice(key, title, @[ @"显示", @"隐藏", @"移除" ]);
    DKSettingsOnChange(item, ^{ DKPlaybackCleanRefresh(); });
    return DKSettingsWithInfo(item, info);
}

%ctor {
    NSArray<NSArray<NSString *> *> *items = @[
        // 播放页元素
        @[ DKKeyPlaybackFullscreenMode, @"全屏观看",
           @"播放页中部的「全屏观看」按钮。隐藏：只隐藏按钮内容，保留原位置和点击命中；移除：不显示、不响应点击，并移除按钮占位。" ],
        @[ DKKeyPlaybackDanmakuMode, @"弹幕按钮",
           @"播放页左下信息区的弹幕入口。隐藏：保留原位置和点击命中；移除：同时移除入口并阻止点击。" ],
        // 文案上方
        @[ DKKeyPlaybackOtherUserRecommendMode, @"其他用户推荐",
           @"文案上方的其他用户推荐入口。隐藏：保留原位置和点击入口；移除：同时移除该入口及其布局占位。" ],
        @[ DKKeyPlaybackFriendRecommendMode, @"好友推荐",
           @"文案上方的好友推荐入口。隐藏：保留原位置和点击入口；移除：同时移除该入口及其布局占位。" ],
        @[ DKKeyPlaybackFriendShareMode, @"好友分享",
           @"文案上方的「xxx分享给你」标签。隐藏：保留原位置和点击入口；移除：同时移除该标签及其布局占位。" ],
        @[ DKKeyPlaybackSelectedMode, @"抖音精选",
           @"文案上方的抖音精选入口。隐藏：保留原位置和点击入口；移除：同时移除该入口及其布局占位。" ],
        @[ DKKeyPlaybackStoreMode, @"作者店铺",
           @"昵称下方的「TA的店铺」入口。隐藏：保留原位置和点击入口；移除：同时移除该入口及其布局占位。" ],
        // 昵称右侧
        @[ DKKeyPlaybackChapterHighlightsMode, @"章节要点",
           @"昵称右侧的章节要点标签（含「下一章」）。隐藏：保留原位置和点击入口；移除：同时移除该标签及其布局占位。" ],
        @[ DKKeyPlaybackCoCreatorMode, @"共创信息",
           @"昵称右侧的「N人共创」标签。隐藏：保留原位置和点击入口；移除：同时移除该标签及其布局占位。" ],
        @[ DKKeyPlaybackSlidesTagMode, @"图文标签",
           @"昵称右侧的「图文」作品类型标签。隐藏保留原位置；移除同时移除该标签及其布局占位。" ],
        @[ DKKeyPlaybackArticleTagMode, @"文章标签",
           @"昵称右侧的「文章」作品类型标签。隐藏保留原位置；移除同时移除该标签及其布局占位。" ],
        // 文案下方
        @[ DKKeyPlaybackRiskNoticeMode, @"作者声明",
           @"作品页中的作者声明、AI 生成提示与风险提示。隐藏：保留原位置和点击行为；移除：同时移除元素及其布局占位。" ],
        @[ DKKeyPlaybackMusicInfoMode, @"文案下方“去汽水听”",
           @"视频文案下方的汽水音乐引导和歌曲信息。隐藏：保留原位置和点击入口；移除：同时移除该信息及其布局占位。" ],
        @[ DKKeyPlaybackQuickReplyMode, @"私信回复栏",
           @"朋友分享视频后文案下方的「私信 xxx」快捷回复栏。隐藏：保留原位置和点击入口；移除：同时移除该栏及其布局占位。" ],
    ];
    for (NSArray<NSString *> *entry in items) {
        NSString *key = entry[0], *title = entry[1], *info = entry[2];
        DKSettingsRegister(key, ^AWESettingItemModel *{ return DKCleanSettingItem(key, title, info); });
    }
}
