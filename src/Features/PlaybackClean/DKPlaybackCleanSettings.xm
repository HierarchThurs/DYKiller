//
//  DKPlaybackCleanSettings.xm
//  DYKiller
//
//  播放页精简各项的设置登记：三档单选（显示 / 隐藏 / 移除），改值后立即刷新当前页面。
//  锚点标签与底部栏目各有总开关，子项锁定显示由设置布局的阻断表给出。
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
    DKSettingsRegister(DKKeyPlaybackRemoveAllAnchors, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(DKKeyPlaybackRemoveAllAnchors, @"移除全部昵称上方标签",
            @"昵称上方的锚点标签（游戏标签、汽水音乐、拍同款、剪映、付费内容、地理定位，以及抖音新增的同类标签）一律移除，"
            @"下方各项锁定为「移除」；关闭后各项按自己的设置生效。");
        return DKSettingsOnChange(item, ^{ DKPlaybackCleanRefresh(); });
    });
    DKSettingsRegister(DKKeyPlaybackRemoveAllBottomBars, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(DKKeyPlaybackRemoveAllBottomBars, @"移除全部底部栏目",
            @"移除播放页底部的整行栏目，包含相关搜索、相关视频、视频合集、热点、应用下载引导，以及新增的同类栏目。"
            @"下方各项锁定为「移除」；关闭后各项按自己的设置生效。");
        return DKSettingsOnChange(item, ^{ DKPlaybackCleanRefresh(); });
    });
    NSArray<NSArray<NSString *> *> *items = @[
        // 播放页元素
        @[ DKKeyPlaybackFullscreenMode, @"全屏观看",
           @"播放页中部的「全屏观看」按钮。隐藏：只隐藏按钮内容，保留原位置和点击命中；移除：不显示、不响应点击，并移除按钮占位。" ],
        @[ DKKeyPlaybackDanmakuMode, @"弹幕按钮",
           @"播放页左下信息区的弹幕入口。隐藏：保留原位置和点击命中；移除：同时移除入口并阻止点击。" ],
        // 锚点标签
        @[ DKKeyPlaybackGameTagMode, @"游戏标签",
           @"文案上方的游戏标签。隐藏：保留原位置和点击入口；移除：同时移除标签及其布局占位。" ],
        @[ DKKeyPlaybackMusicAnchorMode, @"汽水音乐",
           @"文案上方的汽水音乐入口。隐藏：保留原位置和点击入口；移除：同时移除该入口及其布局占位。" ],
        @[ DKKeyPlaybackPropEffectMode, @"拍同款",
           @"文案上方的拍同款入口。隐藏：保留原位置和点击入口；移除：同时移除该入口及其布局占位。" ],
        @[ DKKeyPlaybackJianyingMode, @"剪映标签",
           @"文案上方的剪映模板入口。隐藏保留原位置和点击；移除同时移除入口及其布局占位。" ],
        @[ DKKeyPlaybackPaidContentMode, @"付费内容",
           @"昵称上方的「视频｜xxx的付费视频」等付费内容标签。隐藏：保留原位置和点击入口；移除：同时移除该标签及其布局占位。" ],
        @[ DKKeyPlaybackLocationMode, @"地理定位",
           @"文案上方的地理定位信息。隐藏：保留原位置和点击入口；移除：同时移除该信息及其布局占位。" ],
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
        // 文案下方
        @[ DKKeyPlaybackRiskNoticeMode, @"作者声明",
           @"作品页中的作者声明、AI 生成提示与风险提示。隐藏：保留原位置和点击行为；移除：同时移除元素及其布局占位。" ],
        @[ DKKeyPlaybackMusicInfoMode, @"文案下方“去汽水听”",
           @"视频文案下方的汽水音乐引导和歌曲信息。隐藏：保留原位置和点击入口；移除：同时移除该信息及其布局占位。" ],
        @[ DKKeyPlaybackQuickReplyMode, @"私信回复栏",
           @"朋友分享视频后文案下方的「私信 xxx」快捷回复栏。隐藏：保留原位置和点击入口；移除：同时移除该栏及其布局占位。" ],
        // 底部栏目
        @[ DKKeyPlaybackRelatedSearchMode, @"相关搜索",
           @"播放页底部的相关搜索条。隐藏：保留整行布局和搜索跳转；移除：移除整行及其布局占位。" ],
        @[ DKKeyPlaybackRelatedVideoMode, @"相关视频",
           @"播放页底部的相关视频入口。隐藏：保留整行布局和跳转入口；移除：移除整行及其布局占位。" ],
        @[ DKKeyPlaybackVideoCollectionMode, @"视频合集",
           @"文案下方的视频合集入口。隐藏：保留原位置和点击入口；移除：同时移除该入口及其布局占位。" ],
        @[ DKKeyPlaybackHotspotMode, @"热点",
           @"文案下方的热点信息。隐藏：保留原位置和点击入口；移除：同时移除该信息及其布局占位。" ],
        @[ DKKeyPlaybackAppDownloadMode, @"应用下载引导",
           @"播放页底部的应用下载导流条（如「抖音精选｜立即下载」）。隐藏：保留整行布局和点击入口；移除：移除整行，上方信息随之下移。" ],
    ];
    for (NSArray<NSString *> *entry in items) {
        NSString *key = entry[0], *title = entry[1], *info = entry[2];
        DKSettingsRegister(key, ^AWESettingItemModel *{ return DKCleanSettingItem(key, title, info); });
    }
}
