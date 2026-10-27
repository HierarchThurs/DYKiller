//
//  DKSettingsLayout.m
//  新增设置项：功能里 DKSettingsRegister 登记后，在下面对应分区加一行 DKRow；有前置开关再补进前置关系表
//  （DKSettingsLayoutRequires 为全部生效、DKSettingsLayoutRequiresAny 为任一生效）。
//  图标名取自抖音 IconSvgBundle.bundle（40.7.0 已核对存在）。
//

#import "DKSettingsLayout.h"
#import "DKKeys.h"

@implementation DKSettingsRow
- (instancetype)initWithKey:(NSString *)key icon:(NSString *)icon {
    if ((self = [super init])) { _key = [key copy]; _icon = [icon copy]; }
    return self;
}
@end

@implementation DKSettingsPage
- (instancetype)initWithTitle:(NSString *)title icon:(NSString *)icon
                   identifier:(NSString *)identifier sections:(NSArray *)sections {
    return [self initWithTitle:title icon:icon identifier:identifier note:nil sections:sections];
}

- (instancetype)initWithTitle:(NSString *)title icon:(NSString *)icon identifier:(NSString *)identifier
                         note:(NSString *)note sections:(NSArray *)sections {
    if ((self = [super init])) {
        _title = [title copy];
        _icon = [icon copy];
        _identifier = [(identifier ?: title) copy];
        _note = [note copy];
        _sections = [sections copy];
    }
    return self;
}
@end

@implementation DKSettingsLink
- (instancetype)initWithTitle:(NSString *)title icon:(NSString *)icon action:(DKSettingsLinkAction)action {
    if ((self = [super init])) { _title = [title copy]; _icon = [icon copy]; _action = action; }
    return self;
}
@end

@implementation DKSettingsBlocker
- (instancetype)initWithKey:(NSString *)key match:(DKSettingsBlockerMatch)match value:(NSInteger)value
                     reason:(NSString *)reason shownValue:(NSNumber *)shownValue {
    if ((self = [super init])) {
        _key = [key copy]; _match = match; _value = value; _reason = [reason copy]; _shownValue = shownValue;
    }
    return self;
}

- (instancetype)initWithKey:(NSString *)key match:(DKSettingsBlockerMatch)match value:(NSInteger)value
                     reason:(NSString *)reason {
    return [self initWithKey:key match:match value:value reason:reason shownValue:nil];
}
@end

@implementation DKSettingsSection
- (instancetype)initWithHeader:(NSString *)header footer:(NSString *)footer rows:(NSArray *)rows {
    if ((self = [super init])) { _header = [header copy]; _footer = [footer copy]; _rows = [rows copy]; }
    return self;
}
@end

static DKSettingsRow *DKRow(NSString *key, NSString *icon) {
    return [[DKSettingsRow alloc] initWithKey:key icon:icon];
}

static DKSettingsSection *DKSection(NSString *header, NSArray *rows) {
    return [[DKSettingsSection alloc] initWithHeader:header footer:nil rows:rows];
}

static DKSettingsSection *DKSectionWithFooter(NSString *header, NSString *footer, NSArray *rows) {
    return [[DKSettingsSection alloc] initWithHeader:header footer:footer rows:rows];
}

static DKSettingsPage *DKPage(NSString *title, NSString *icon, NSArray *sections) {
    return [[DKSettingsPage alloc] initWithTitle:title icon:icon identifier:nil sections:sections];
}

// 带顶部说明的子页；identifier 给前置关系表引用入口。
static DKSettingsPage *DKNotedPage(NSString *title, NSString *icon, NSString *identifier, NSString *note, NSArray *sections) {
    return [[DKSettingsPage alloc] initWithTitle:title icon:icon identifier:identifier note:note sections:sections];
}

// 与 README「免责声明」一致。
static NSString *const kDKDisclaimer =
    @"免责声明\n"
    @"本项目仅供学习、研究与测试使用，严禁用于任何商业用途或违法活动。使用者应自行遵守所在地法律法规及相关平台规则，"
    @"并自行承担因使用、修改或分发本项目所产生的一切风险与责任，包括但不限于账户异常、数据丢失、设备损坏及其他直接或间接损失。"
    @"项目作者及贡献者不对上述后果承担任何责任。下载或使用本项目即表示您已阅读并同意本声明。";

static NSArray<DKSettingsSection *> *DKBuildMain(void) {
    DKSettingsPage *interface = DKPage(@"界面精简", @"ic_eyeslash_outlined_20", @[
        DKSection(@"首页顶栏", @[
            DKRow(DKKeyTopBarSideBarMode, @"ic_hamburgernut_outlined_20"),
            DKRow(DKKeyBlockSideBarSwipe, @"ic_switch_outlined"),
            DKRow(DKKeyTopBarSearchMode, @"ic_videosearch_outlined_20"),
            DKRow(DKKeyTopChannels, @"ic_doublearrowup_outlined_20"),
            DKRow(DKKeyTopBarAlpha, @"ic_eyeslash_outlined_20"),
        ]),
        DKSection(@"未读红点", @[
            DKRow(DKKeyTabBarRemoveBadge, @"ic_bellslash_outlined"),
            DKRow(DKKeyTopBarRemoveBadge, @"ic_bellslash_outlined"),
            DKRow(DKKeySideBarRemoveBadge, @"ic_bellslash_outlined"),
        ]),
        DKSection(@"视频播放", @[
            DKPage(@"播放页精简", @"ic_eyeslash_outlined_20", @[
                DKSection(@"播放页元素", @[
                    DKRow(DKKeyPlaybackFullscreenMode, @"ic_fullscreen_outlined_16"),
                    DKRow(DKKeyPlaybackDanmakuMode, @"ic_comment_outlined_20"),
                ]),
                DKSection(@"作品详情页", @[
                    DKRow(DKKeyDetailReturnMode, @"ic_arrowleft_outlined_20"),
                    DKRow(DKKeyDetailSearchMode, @"ic_videosearch_outlined_20"),
                    DKRow(DKKeyDetailHideBottomBar, @"ic_xmark_outlined_20"),
                ]),
                DKSection(@"锚点标签", @[
                    DKRow(DKKeyPlaybackRemoveAllAnchors, @"ic_eyeslash_outlined_20"),
                    DKRow(DKKeyPlaybackGameTagMode, @"ic_module_outlined_20"),
                    DKRow(DKKeyPlaybackMusicAnchorMode, @"ic_quaver_outlined_20"),
                    DKRow(DKKeyPlaybackPropEffectMode, @"ic_cameralogo_outlined_20"),
                    DKRow(DKKeyPlaybackJianyingMode, @"ic_cameralogo_outlined_20"),
                    DKRow(DKKeyPlaybackPaidContentMode, @"ic_bag_outlined_20"),
                    DKRow(DKKeyPlaybackLocationMode, @"ic_location_outlined_20"),
                ]),
                DKSection(@"文案上方", @[
                    DKRow(DKKeyPlaybackOtherUserRecommendMode, @"ic_user_outlined_20"),
                    DKRow(DKKeyPlaybackFriendRecommendMode, @"ic_user_outlined_20"),
                    DKRow(DKKeyPlaybackFriendShareMode, @"ic_share_outlined"),
                    DKRow(DKKeyPlaybackSelectedMode, @"ic_magic_outlined_20"),
                    DKRow(DKKeyPlaybackStoreMode, @"ic_module_outlined_20"),
                ]),
                DKSection(@"昵称右侧", @[
                    DKRow(DKKeyPlaybackChapterHighlightsMode, @"ic_text_outlined_20"),
                    DKRow(DKKeyPlaybackCoCreatorMode, @"ic_personcircleclean_outlined_20"),
                    DKRow(DKKeyPlaybackSlidesTagMode, @"ic_image_outlined_20"),
                    DKRow(DKKeyPlaybackArticleTagMode, @"ic_text_outlined_20"),
                ]),
                DKSection(@"文案下方", @[
                    DKRow(DKKeyPlaybackRiskNoticeMode, @"ic_text_outlined_20"),
                    DKRow(DKKeyPlaybackMusicInfoMode, @"ic_quaver_outlined_20"),
                    DKRow(DKKeyPlaybackQuickReplyMode, @"ic_msg_outlined_20"),
                ]),
                DKSection(@"底部栏目", @[
                    DKRow(DKKeyPlaybackRemoveAllBottomBars, @"ic_eyeslash_outlined_20"),
                    DKRow(DKKeyPlaybackRelatedSearchMode, @"ic_videosearch_outlined_20"),
                    DKRow(DKKeyPlaybackRelatedVideoMode, @"ic_playsquarestack_outlined_20"),
                    DKRow(DKKeyPlaybackVideoCollectionMode, @"ic_playsquarestack_outlined_20"),
                    DKRow(DKKeyPlaybackHotspotMode, @"ic_module_outlined_20"),
                    DKRow(DKKeyPlaybackAppDownloadMode, @"ic_boxarrowdown_outlined"),
                ]),
            ]),
            DKPage(@"评论区精简", @"ic_comment_outlined_20", @[
                DKSection(@"评论区顶部标签", @[
                    DKRow(DKKeyCommentRemoveAllTopTags, @"ic_eyeslash_outlined_20"),
                    DKRow(DKKeyCommentSearchAnchorMode, @"ic_videosearch_outlined_20"),
                    DKRow(DKKeyCommentLunaAnchorMode, @"ic_quaver_outlined_20"),
                    DKRow(DKKeyCommentLocationMode, @"ic_location_outlined_20"),
                    DKRow(DKKeyCommentGameAnchorMode, @"ic_tag_outlined_20"),
                    DKRow(DKKeyCommentSeriesAnchorMode, @"ic_collection_outlined_20"),
                    DKRow(DKKeyCommentDramaAnchorMode, @"ic_video_outlined_20"),
                ]),
                DKSection(@"评论区分页", @[
                    DKRow(DKKeyCommentRemoveAllTabs, @"ic_eyeslash_outlined_20"),
                    DKRow(DKKeyCommentAIParseMode, @"ic_magic_outlined_20"),
                    DKRow(DKKeyCommentPlayerDiscussionMode, @"ic_bubbletwo_outlined_20"),
                    DKRow(DKKeyCommentStoreReviewMode, @"ic_star_outlined_20"),
                    DKRow(DKKeyCommentDramaReviewMode, @"ic_star_outlined_20"),
                ]),
                DKSection(@"评论区元素", @[
                    DKRow(DKKeyCommentReplyBottomBarMode, @"ic_comment_outlined_20"),
                    DKRow(DKKeyRemoveCommentSurvey, @"ic_emoji_outlined_20"),
                ]),
                DKSection(@"评论区图片", @[
                    DKRow(DKKeyCommentMediaCleanBottomBar, @"ic_image_outlined_20"),
                ]),
            ]),
            DKRow(DKKeyShareMenu, @"ic_share_outlined"),
        ]),
        DKSection(@"长按菜单", @[
            DKRow(DKKeyFeedMenu, @"ic_video_outlined_20"),
            DKRow(DKKeyCommentMenu, @"ic_comment_outlined_20"),
        ]),
        DKSection(@"朋友页", @[
            DKPage(@"朋友页精简", @"ic_user_outlined_20", @[
                DKSection(@"顶栏", @[
                    DKRow(DKKeyFriendAvatarEntryMode, @"ic_userplus_outlined_20"),
                    DKRow(DKKeyFriendDailyMode, @"ic_clock_outlined_20"),
                    DKRow(DKKeyFriendButtonMode, @"ic_userswitch_outlined_20"),
                ]),
                DKSection(@"作品", @[
                    DKRow(DKKeyFriendRelationTagMode, @"ic_tag_outlined_20"),
                    DKRow(DKKeyFriendStoryTagMode, @"ic_tag_outlined_20"),
                    DKRow(DKKeyFriendFollowTagMode, @"ic_tag_outlined_20"),
                    DKRow(DKKeyFriendFastReplyMode, @"ic_msg_outlined_20"),
                    DKRow(DKKeyFriendSendMessageMode, @"ic_airplane_outlined_20"),
                ]),
                DKSection(@"内容", @[
                    DKRow(DKKeyFriendRemoveRecommendCard, @"ic_user_outlined_20"),
                ]),
            ]),
        ]),
        DKSection(@"消息页", @[
            DKPage(@"消息页精简", @"ic_msg_outlined_20", @[
                DKSection(@"顶栏", @[
                    DKRow(DKKeyMessageSideBarMode, @"ic_hamburgernut_outlined_20"),
                    DKRow(DKKeyMessageSlotMode, @"ic_bag_outlined_20"),
                    DKRow(DKKeyMessageSearchMode, @"ic_videosearch_outlined_20"),
                    DKRow(DKKeyMessagePlusMode, @"ic_pluscircle_outlined_20"),
                ]),
                DKSection(@"列表顶部", @[
                    DKRow(DKKeyMessageDailyMode, @"ic_clock_outlined_20"),
                    DKRow(DKKeyMessageFriendAvatarMode, @"ic_personcircleclean_outlined_20"),
                    DKRow(DKKeyMessageInteractionMode, @"ic_msgheart_outlined_20"),
                ]),
                DKSection(@"聊天页", @[
                    DKRow(DKKeyChatRemoveEmojiSuggestions, @"ic_emoji_outlined_20"),
                    DKRow(DKKeyChatPlayEntryMode, @"ic_squaresplit_outlined_20"),
                    DKRow(DKKeyChatRemovePlusPhotos, @"ic_removeimage_outlined_20"),
                    DKRow(DKKeyChatRemoveBack, @"ic_arrowleft_outlined_20"),
                    DKRow(DKKeyChatRemoveUnread, @"ic_msg_outlined_20"),
                    DKRow(DKKeyChatRemoveOnline, @"ic_user_outlined_20"),
                    DKRow(DKKeyChatRemoveCall, @"ic_phoneup_outlined"),
                    DKRow(DKKeyChatRemoveMenu, @"ic_hamburgernut_outlined_20"),
                    DKRow(DKKeyChatGroupZoneNoAutoExpand, @"ic_hamburgeruparrow_outlined_20"),
                ]),
            ]),
        ]),
        DKSection(@"个人主页", @[
            DKPage(@"个人主页精简", @"ic_personcircleclean_outlined_20", @[
                DKSection(@"顶栏", @[
                    DKRow(DKKeyProfileAddFriendMode, @"ic_userplus_outlined_20"),
                    DKRow(DKKeyProfileVisitorMode, @"ic_user_outlined_20"),
                    DKRow(DKKeyProfileSearchMode, @"ic_videosearch_outlined_20"),
                    DKRow(DKKeyProfileSideBarMode, @"ic_hamburgernut_outlined_20"),
                ]),
                DKSection(@"头像与昵称", @[
                    DKRow(DKKeyProfileAvatarPlusMode, @"ic_pluscircle_outlined_20"),
                    DKRow(DKKeyProfileSwitchAccountMode, @"ic_userswitch_outlined_20"),
                    DKRow(DKKeyProfileCapsuleMode, @"ic_magic_outlined_20"),
                ]),
                DKSection(@"数据与按钮", @[
                    DKRow(DKKeyProfileStatsMode, @"ic_module_outlined_20"),
                    DKRow(DKKeyProfileEditMode, @"ic_pensketch_outlined_20"),
                ]),
                DKSection(@"功能区", @[
                    DKRow(DKKeyProfileRemoveServiceArea, @"ic_squaresplit_outlined_20"),
                ]),
                DKSection(@"内容", @[
                    DKRow(DKKeyProfileGuideBannerMode, @"ic_cameralogo_outlined_20"),
                    DKRow(DKKeyProfileHideUGCGuide, @"ic_user_outlined_20"),
                ]),
                DKSection(@"分页", @[
                    DKRow(DKKeyProfileRemovePostTab, @"ic_video_outlined_20"),
                    DKRow(DKKeyProfileRemoveDailyTab, @"ic_clock_outlined_20"),
                    DKRow(DKKeyProfileRemoveFavoriteTab, @"ic_star_outlined_20"),
                    DKRow(DKKeyProfileRemoveLikeTab, @"ic_msgheart_outlined_20"),
                    DKRow(DKKeyProfileRemoveFootprintTab, @"ic_location_outlined_20"),
                ]),
            ]),
        ]),
        DKSection(@"搜索页", @[
            DKPage(@"搜索页精简", @"ic_videosearch_outlined_20", @[
                DKSection(@"搜索历史", @[
                    DKRow(DKKeySearchRemoveHistory, @"ic_eyeslash_outlined_20"),
                ]),
                DKSection(@"推荐与榜单", @[
                    DKRow(DKKeySearchRemoveGuess, @"ic_eyeslash_outlined_20"),
                    DKRow(DKKeySearchRemoveAllRanks, @"ic_eyeslash_outlined_20"),
                    DKRow(DKKeySearchRemoveRankFooter, @"ic_eyeslash_outlined_20"),
                ]),
                DKSection(@"输入入口", @[
                    DKRow(DKKeySearchRemoveVoice, @"ic_eyeslash_outlined_20"),
                    DKRow(DKKeySearchCameraMode, @"ic_cameralogo_outlined_20"),
                ]),
            ]),
        ]),
    ]);

    DKSettingsPage *appearance = DKPage(@"外观定制", @"ic_magic_outlined_20", @[
        DKSection(@"底栏图标", @[
            DKRow(DKKeyBottomBar, @"ic_module_outlined_20"),
            DKRow(DKKeyTabBarStyle, @"ic_module_outlined_20"),
            DKRow(DKKeyPlusStyle, @"ic_cameralogo_outlined_20"),
            DKRow(DKKeyPlusIcon, @"ic_pensketch_outlined_20"),
            DKPage(@"修改底栏文字", @"ic_text_outlined_20", @[
                DKSectionWithFooter(@"底栏文字", @"留空为抖音默认文字，最多 6 个汉字。", @[
                    DKRow(DKKeyTabTitleHome, @"ic_text_outlined_20"),
                    DKRow(DKKeyTabTitleFriends, @"ic_text_outlined_20"),
                    DKRow(DKKeyTabTitleMall, @"ic_text_outlined_20"),
                    DKRow(DKKeyTabTitleNotification, @"ic_text_outlined_20"),
                    DKRow(DKKeyTabTitleProfile, @"ic_text_outlined_20"),
                ]),
            ]),
        ]),
        DKSection(@"视频播放", @[
            DKNotedPage(@"弹幕改色", @"ic_comment_outlined_20", nil,
                        @"调整视频滚动弹幕的文字颜色，保留原有内容、速度与显示开关。置灰的设置会保留存值，切回对应模式后继续使用。", @[
                DKSection(@"总开关", @[
                    DKRow(DKKeyDanmakuColorEnabled, @"ic_comment_outlined_20"),
                ]),
                DKSection(@"颜色模式", @[
                    DKRow(DKKeyDanmakuColorMode, @"ic_magic_outlined_20"),
                ]),
                DKSection(@"固定颜色", @[
                    DKRow(DKKeyDanmakuFixedColor, @"ic_pensketch_outlined_20"),
                    DKRow(DKKeyDanmakuHexColor, @"ic_text_outlined_20"),
                ]),
                DKSectionWithFooter(@"自定义渐变", @"关闭总开关时恢复抖音原生样式；开启后六种颜色模式互斥生效。随机颜色按每条弹幕生成，不按帧闪烁。固定色的两个入口共用一个值。透明度完全继承抖音，面板只读显示。", @[
                    DKRow(DKKeyDanmakuGradientColors, @"ic_magic_outlined_20"),
                ]),
            ]),
            DKPage(@"互动按钮", @"ic_squaresplit_outlined_20", @[
                DKSection(@"透明度", @[
                    DKRow(DKKeyInteractionIconAlpha, @"ic_module_outlined_20"),
                    DKRow(DKKeyInteractionLabelAlpha, @"ic_text_outlined_20"),
                    DKRow(DKKeyAvatarAlpha, @"ic_user_outlined_20"),
                    DKRow(DKKeyMusicAlpha, @"ic_quaver_outlined_20"),
                ]),
                DKSection(@"缩放", @[
                    DKRow(DKKeyInteractionScale, @"ic_module_outlined_20"),
                    DKRow(DKKeyAvatarScale, @"ic_user_outlined_20"),
                    DKRow(DKKeyMusicScale, @"ic_quaver_outlined_20"),
                ]),
                DKSection(@"位置", @[
                    DKRow(DKKeyInteractionOffset, @"ic_doublearrowup_outlined_20"),
                ]),
                DKSection(@"显示方式", @[
                    DKRow(DKKeyInteractionDisplay, @"ic_module_outlined_20"),
                    DKRow(DKKeyAvatarDisplay, @"ic_user_outlined_20"),
                    DKRow(DKKeyMusicDisplay, @"ic_quaver_outlined_20"),
                    DKRow(DKKeyFollowButtonDisplay, @"ic_userplus_outlined_20"),
                ]),
            ]),
            DKPage(@"互动按钮更换图标", @"ic_module_outlined_20", @[
                DKSectionWithFooter(@"图标", @"每个按钮可选：默认（抖音原样）/ 内置图标 / 自定义。首次选「自定义」时先选图。", @[
                    DKRow(DKKeyInteractionLikeStyle, @"ic_module_outlined_20"),
                    DKRow(DKKeyInteractionCommentStyle, @"ic_comment_outlined_20"),
                    DKRow(DKKeyInteractionFavoriteStyle, @"ic_module_outlined_20"),
                    DKRow(DKKeyInteractionShareStyle, @"ic_module_outlined_20"),
                ]),
                DKSectionWithFooter(@"自定义图片", @"支持 PNG 与 SVG。PNG 建议 108×108 像素、透明底；SVG 按画布等比显示。点赞、收藏的两种状态分别设置，未设置的状态保持抖音原样。", @[
                    DKRow(DKKeyInteractionLikeBeforeIcon, @"ic_module_outlined_20"),
                    DKRow(DKKeyInteractionLikeAfterIcon, @"ic_module_outlined_20"),
                    DKRow(DKKeyInteractionCommentIcon, @"ic_comment_outlined_20"),
                    DKRow(DKKeyInteractionFavoriteBeforeIcon, @"ic_module_outlined_20"),
                    DKRow(DKKeyInteractionFavoriteAfterIcon, @"ic_module_outlined_20"),
                    DKRow(DKKeyInteractionShareIcon, @"ic_module_outlined_20"),
                ]),
            ]),
            DKPage(@"昵称文案", @"ic_text_outlined_20", @[
                DKSection(@"透明度", @[
                    DKRow(DKKeyNicknameAlpha, @"ic_user_outlined_20"),
                    DKRow(DKKeyDescriptionAlpha, @"ic_text_outlined_20"),
                ]),
                DKSection(@"缩放", @[
                    DKRow(DKKeyNicknameScale, @"ic_user_outlined_20"),
                    DKRow(DKKeyDescriptionScale, @"ic_text_outlined_20"),
                ]),
                DKSection(@"位置", @[
                    DKRow(DKKeyInfoOffset, @"ic_doublearrowup_outlined_20"),
                ]),
            ]),
            DKRow(DKKeyProgressOffset, @"ic_doublearrowup_outlined_20"),
            DKRow(DKKeyStoryIndicatorOffset, @"ic_doublearrowup_outlined_20"),
        ]),
    ]);

    DKSettingsPage *glass = [[DKSettingsPage alloc] initWithTitle:@"液态玻璃 (iOS26+)"
                                                             icon:@"ic_rectangleonrectangleup_outlined_20"
                                                       identifier:DKKeySettingsPageGlass
                                                         sections:@[
        DKSection(@"底栏", @[
            DKRow(DKKeyGlassTabBar, @"ic_module_outlined_20"),
            DKRow(DKKeyGlassTabBarCapsuleHeight, @"ic_zoomout_outlined_20"),
            DKRow(DKKeyGlassTabBarCapsuleLength, @"ic_zoomoutrectangle_outlined"),
            DKRow(DKKeyGlassTabBarPlusSize, @"ic_camera_outlined"),
            DKRow(DKKeyGlassTabBarPadPosition, @"ic_squaresplit_outlined_20"),
        ]),
        DKSection(@"音频可视化", @[
            DKRow(DKKeyAudioVizPosition, @"ic_playbackquaver_outlined"),
            DKRow(DKKeyAudioVizStyle, @"ic_squaretriangle_outlined_20"),
        ]),
        DKSection(@"评论区", @[
            DKRow(DKKeyCommentGlass, @"ic_comment_outlined_20"),
        ]),
        DKSection(@"分享面板", @[
            DKRow(DKKeySharePanelGlass, @"ic_share_outlined"),
        ]),
        DKSection(@"聊天页", @[
            DKRow(DKKeyChatInputGlass, @"ic_msg_outlined_20"),
            DKNotedPage(@"聊天页顶栏自定义", @"ic_rectangleportraitmagic_outlined_20", DKKeyChatTopCustomPage,
                        @"调整聊天页顶栏的模糊效果与头像信息排列，需先开启「聊天页液态玻璃」。", @[
                DKSection(@"模糊", @[
                    DKRow(DKKeyChatTopBlur, @"ic_rectangleportraitwater_outlined_20"),
                ]),
                DKSection(@"头像与信息", @[
                    DKRow(DKKeyChatTopCenter, @"ic_personcircle_outlined"),
                    DKRow(DKKeyChatTopStreakPosition, @"ic_fire_outlined_20"),
                    DKRow(DKKeyChatTopOnlinePosition, @"ic_user_outlined_20"),
                ]),
            ]),
        ]),
        DKSection(@"长按菜单", @[
            DKRow(DKKeyFeedMenuGlass, @"ic_squaresplit_outlined_20"),
        ]),
        DKSection(@"应用内通知", @[
            DKRow(DKKeyInnerNotiGlass, @"ic_msg_outlined_20"),
            DKRow(DKKeyInnerNotiCorner, @"ic_circletop_outlined"),
            DKRow(DKKeyTipsGlass, @"ic_msg_outlined_20"),
            DKRow(DKKeyMediaSaveGlass, @"ic_boxarrowdown_outlined"),
        ]),
    ]];

    DKSettingsPage *enhance = DKPage(@"功能增强", @"ic_squaresplit_outlined_20", @[
        DKSection(@"视频", @[
            DKRow(DKKeyVideoFullscreen, @"ic_fullscreen_outlined_16"),
            DKRow(DKKeyProgressAlwaysVisible, @"ic_playertime_outlined_20"),
            DKRow(DKKeyProgressPlayedOnly, @"ic_playerarrow_outlined"),
            DKRow(DKKeyProgressTimeStyle, @"ic_clock_outlined_20"),
            DKPage(@"发布时间与地区", @"ic_clock_outlined_20", @[
                DKSection(@"显示内容", @[
                    DKRow(DKKeyPublishTimeEnabled, @"ic_clock_outlined_20"),
                    DKRow(DKKeyPublishLocationEnabled, @"ic_location_outlined_20"),
                ]),
                DKSectionWithFooter(@"主页作品", @"主页三列封面在点赞上方显示时间与地区；双列卡片把时间与地区并成两行，与点赞数同一行。", @[
                    DKRow(DKKeyProfilePublishTime, @"ic_clock_outlined_20"),
                    DKRow(DKKeyProfilePublishLocation, @"ic_location_outlined_20"),
                ]),
                DKSection(@"文字颜色", @[
                    DKNotedPage(@"文字颜色", @"ic_magic_outlined_20", DKKeyPublishTextColors,
                                @"时间文字与地区文字使用独立的颜色配置。仅在「显示具体发布时间」或「显示发布地区」任一项开启时可用；颜色功能默认关闭。", @[
                        DKSection(@"时间文字", @[
                            DKRow(DKKeyPublishTimeColorEnabled, @"ic_text_outlined_20"),
                            DKRow(DKKeyPublishTimeColorMode, @"ic_magic_outlined_20"),
                        ]),
                        DKSection(@"时间固定颜色", @[
                            DKRow(DKKeyPublishTimeFixedColor, @"ic_pensketch_outlined_20"),
                            DKRow(DKKeyPublishTimeHexColor, @"ic_text_outlined_20"),
                        ]),
                        DKSection(@"时间自定义渐变", @[
                            DKRow(DKKeyPublishTimeGradientColors, @"ic_magic_outlined_20"),
                        ]),
                        DKSection(@"地区文字", @[
                            DKRow(DKKeyPublishLocationColorEnabled, @"ic_location_outlined_20"),
                            DKRow(DKKeyPublishLocationColorMode, @"ic_magic_outlined_20"),
                        ]),
                        DKSection(@"地区固定颜色", @[
                            DKRow(DKKeyPublishLocationFixedColor, @"ic_pensketch_outlined_20"),
                            DKRow(DKKeyPublishLocationHexColor, @"ic_text_outlined_20"),
                        ]),
                        DKSectionWithFooter(@"地区自定义渐变", @"时间文字与地区文字分别保存颜色配置，互不覆盖。置灰的设置保留存值，切回对应模式后继续使用。随机颜色按作品生成，不是逐帧动画。", @[
                            DKRow(DKKeyPublishLocationGradientColors, @"ic_magic_outlined_20"),
                        ]),
                    ]),
                ]),
                DKSectionWithFooter(@"国外地区解析", @"国外地区解析使用 GeoNames 地名服务：先注册免费账号，再在账户管理页面启用 Free Web Services，然后在「国外解析账号」中填写用户名，无需提供密码。", @[
                    DKRow(DKKeyGeoNamesUsername, @"ic_user_outlined_20"),
                    DKRow(DKKeyGeoNamesRegister, @"ic_userplus_outlined_20"),
                    DKRow(DKKeyGeoNamesWebServices, @"ic_switch_outlined"),
                ]),
            ]),
        ]),
        DKSection(@"手势", @[
            DKRow(DKKeyDoubleTapOpenComment, @"ic_comment_outlined_20"),
            DKRow(DKKeyLongPressCopyNickname, @"ic_user_outlined_20"),
            DKRow(DKKeyLongPressCopyDescription, @"ic_text_outlined_20"),
        ]),
        DKSection(@"评论区", @[
            DKRow(DKKeyCommentCopyWithoutName, @"ic_text_outlined_20"),
        ]),
    ]);

    DKSettingsPage *media = DKPage(@"媒体保存", @"ic_boxarrowdown_outlined", @[
        DKSection(@"作品长按面板", @[
            DKRow(DKKeyMediaSaveVideo, @"ic_video_outlined_20"),
            DKRow(DKKeyMediaSaveCurrentImage, @"ic_image_outlined_20"),
            DKRow(DKKeyMediaSaveAllImages, @"ic_playsquarestack_outlined_20"),
            DKRow(DKKeyMediaSaveCover, @"ic_image_outlined"),
            DKRow(DKKeyMediaSaveMusic, @"ic_quaver_outlined_20"),
        ]),
        DKSection(@"评论区", @[
            DKRow(DKKeyMediaSaveComment, @"ic_comment_outlined_20"),
            DKRow(DKKeyMediaSaveCommentSticker, @"ic_emoji_outlined_20"),
            DKRow(DKKeyCommentImageNoWatermark, @"ic_removeimage_outlined_20"),
            DKRow(DKKeyCommentLivePhotoNoWatermark, @"ic_livephoto_outlined_20"),
        ]),
        DKSection(@"私信与表情面板", @[
            DKRow(DKKeyMediaSaveChatSticker, @"ic_msg_outlined_20"),
        ]),
        DKSection(@"反馈", @[
            DKRow(DKKeyMediaSaveHaptic, @"ic_bell_outlined_20"),
        ]),
    ]);

    DKSettingsPage *filter = DKPage(@"内容过滤", @"ic_funnel_outlined_20", @[
        DKSection(@"首页推荐", @[
            DKRow(DKKeyFilterLowLikes, @"ic_thumbsdown_outlined_20"),
            DKRow(DKKeyMinimumLikes, @"ic_thumbsup_outlined_20"),
            DKRow(DKKeyRemoveRecommendedLive, @"ic_tv_outlined_20"),
            DKRow(DKKeyFilterRecommendedMusic, @"ic_quaver_outlined_20"),
            DKRow(DKKeyFilterRecommendedArticle, @"ic_text_outlined_20"),
            DKRow(DKKeyFilterRecommendedMerchantNote, @"ic_location_outlined_20"),
        ]),
        DKSection(@"特殊卡片", @[
            DKRow(DKKeyFilterRecommendedSpecialCard, @"ic_squaresplit_outlined_20"),
            DKRow(DKKeyFilterRecommendedHotspot, @"ic_fire_outlined_20"),
            DKRow(DKKeyFilterRecommendedCreation, @"ic_cameralogo_outlined_20"),
            DKRow(DKKeyFilterRecommendedEcommerce, @"ic_bag_outlined_20"),
            DKRow(DKKeyFilterRecommendedGame, @"ic_squaretriangle_outlined_20"),
            DKRow(DKKeyFilterRecommendedSocial, @"ic_userplus_outlined_20"),
            DKRow(DKKeyFilterRecommendedInterest, @"ic_star_outlined_20"),
            DKRow(DKKeyFilterRecommendedMicroApp, @"ic_module_outlined_20"),
        ]),
        DKSection(@"广告", @[
            DKRow(DKKeyFilterAds, @"ic_ad_outlined_20"),
        ]),
    ]);

    DKSettingsPage *tools = DKPage(@"插件工具", @"ic_gearsimplify_outlined_20", @[
        DKSection(@"快捷入口", @[
            DKRow(DKKeyProfileSettingsEntry, @"ic_gearsimplify_outlined_20"),
            DKRow(DKKeyProfileSettingsEntryName, @"ic_text_outlined_20"),
        ]),
        DKSection(@"调试", @[
            DKRow(DKKeyDebugInspectorEnabled, @"ic_videosearch_outlined_20"),
        ]),
        DKSection(@"高级", @[
            DKRow(DKKeyAdjustRangeExtended, @"ic_fullscreen_outlined_16"),
        ]),
    ]);

    DKSettingsPage *backup = DKPage(@"备份工具", @"ic_memorycard_outlined_20", @[
        DKSectionWithFooter(@"备份与恢复",
            @"备份所有设置和自定义拍摄图标。卸载抖音后插件设置会一起清空，请把备份存到「文件」App 或其他设备。", @[
            DKRow(DKKeyBackupExport, @"ic_phonearrowup_outlined_20"),
            DKRow(DKKeyBackupRestore, @"ic_circlearrowin_outlined_20"),
            DKRow(DKKeyBackupUndo, @"ic_arrowcircleleft_outlined_16"),
        ]),
        DKSectionWithFooter(@"重置", @"所有设置回到默认，自定义图标一起清除；重置前会自动快照，可以撤销。", @[
            DKRow(DKKeyBackupReset, @"ic_trash_outlined_20"),
        ]),
    ]);

    DKSettingsLink *author = [[DKSettingsLink alloc] initWithTitle:@"作者信息"
                                                               icon:@"ic_personcircleclean_outlined_20"
                                                             action:DKSettingsLinkAuthor];

    return @[
        DKSection(@"功能", @[ interface, appearance, glass, enhance, media, filter ]),
        [[DKSettingsSection alloc] initWithHeader:@"DYKiller" footer:kDKDisclaimer
                                             rows:@[ tools, backup, author ]],
    ];
}

NSArray<DKSettingsSection *> *DKSettingsLayoutMain(void) {
    static NSArray<DKSettingsSection *> *main;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ main = DKBuildMain(); });
    return main;
}

// 布局表里的每一行设置：键、所在子页标题、图标，按页面从上到下。
@interface DKSettingsLayoutEntry : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *pageTitle;
@property (nonatomic, copy) NSString *icon;
@end

@implementation DKSettingsLayoutEntry
@end

static void DKCollectEntries(NSArray<DKSettingsSection *> *sections, NSString *pageTitle,
                             NSMutableArray<DKSettingsLayoutEntry *> *entries) {
    for (DKSettingsSection *section in sections) {
        for (id row in section.rows) {
            if ([row isKindOfClass:DKSettingsRow.class]) {
                DKSettingsLayoutEntry *entry = [[DKSettingsLayoutEntry alloc] init];
                entry.key = ((DKSettingsRow *)row).key;
                entry.pageTitle = pageTitle;
                entry.icon = ((DKSettingsRow *)row).icon;
                [entries addObject:entry];
            } else if ([row isKindOfClass:DKSettingsPage.class]) {
                DKCollectEntries(((DKSettingsPage *)row).sections, ((DKSettingsPage *)row).title, entries);
            }
        }
    }
}

static NSArray<DKSettingsLayoutEntry *> *DKLayoutEntries(void) {
    static NSArray<DKSettingsLayoutEntry *> *entries;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray<DKSettingsLayoutEntry *> *list = [NSMutableArray array];
        DKCollectEntries(DKSettingsLayoutMain(), @"DYKiller", list);
        entries = [list copy];
    });
    return entries;
}

static DKSettingsLayoutEntry *DKLayoutEntry(NSString *key) {
    static NSDictionary<NSString *, DKSettingsLayoutEntry *> *byKey;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *map = [NSMutableDictionary dictionary];
        for (DKSettingsLayoutEntry *entry in DKLayoutEntries()) {
            if (!map[entry.key]) map[entry.key] = entry;
        }
        byKey = [map copy];
    });
    return key ? byKey[key] : nil;
}

NSArray<NSString *> *DKSettingsLayoutOrderedKeys(void) {
    return [DKLayoutEntries() valueForKey:@"key"];
}

NSSet<NSString *> *DKSettingsLayoutKeys(void) {
    static NSSet<NSString *> *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ keys = [NSSet setWithArray:DKSettingsLayoutOrderedKeys()]; });
    return keys;
}

NSString *DKSettingsLayoutPageTitle(NSString *key) {
    return DKLayoutEntry(key).pageTitle;
}

NSString *DKSettingsLayoutIcon(NSString *key) {
    return DKLayoutEntry(key).icon;
}

NSArray<NSString *> *DKSettingsLayoutRequires(NSString *key) {
    static NSDictionary<NSString *, NSArray<NSString *> *> *requires;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        requires = @{
            DKKeyAudioVizPosition:       @[ DKKeyGlassTabBar ],
            DKKeyGlassTabBarPadPosition: @[ DKKeyGlassTabBar ],
            DKKeyGlassTabBarCapsuleHeight: @[ DKKeyGlassTabBar ],
            DKKeyGlassTabBarCapsuleLength: @[ DKKeyGlassTabBar ],
            DKKeyGlassTabBarPlusSize:    @[ DKKeyGlassTabBar ],
            DKKeyAudioVizStyle:          @[ DKKeyAudioVizPosition ],
            DKKeyInnerNotiCorner:        @[ DKKeyInnerNotiGlass ],
            DKKeyChatTopCustomPage:      @[ DKKeyChatInputGlass ],
            DKKeyChatTopBlur:            @[ DKKeyChatInputGlass ],
            DKKeyChatTopCenter:          @[ DKKeyChatInputGlass ],
            DKKeyChatTopStreakPosition:  @[ DKKeyChatTopCenter ],
            DKKeyChatTopOnlinePosition:  @[ DKKeyChatTopCenter ],
            DKKeyMinimumLikes:           @[ DKKeyFilterLowLikes ],
            DKKeyProfileSettingsEntryName: @[ DKKeyProfileSettingsEntry ],
            DKKeyDanmakuColorMode: @[ DKKeyDanmakuColorEnabled ],
            DKKeyDanmakuFixedColor: @[ DKKeyDanmakuColorEnabled ],
            DKKeyDanmakuHexColor: @[ DKKeyDanmakuColorEnabled ],
            DKKeyDanmakuGradientColors: @[ DKKeyDanmakuColorEnabled ],
            DKKeyPublishTimeColorMode: @[ DKKeyPublishTimeColorEnabled ],
            DKKeyPublishTimeFixedColor: @[ DKKeyPublishTimeColorEnabled ],
            DKKeyPublishTimeHexColor: @[ DKKeyPublishTimeColorEnabled ],
            DKKeyPublishTimeGradientColors: @[ DKKeyPublishTimeColorEnabled ],
            DKKeyPublishLocationColorMode: @[ DKKeyPublishLocationColorEnabled ],
            DKKeyPublishLocationFixedColor: @[ DKKeyPublishLocationColorEnabled ],
            DKKeyPublishLocationHexColor: @[ DKKeyPublishLocationColorEnabled ],
            DKKeyPublishLocationGradientColors: @[ DKKeyPublishLocationColorEnabled ],
        };
    });
    return (key ? requires[key] : nil) ?: @[];
}

NSArray<NSString *> *DKSettingsLayoutRequiresAny(NSString *key) {
    static NSDictionary<NSString *, NSArray<NSString *> *> *requires;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        requires = @{
            DKKeyPublishTextColors: @[ DKKeyPublishTimeEnabled, DKKeyPublishLocationEnabled ],
            DKKeyGeoNamesUsername: @[ DKKeyPublishLocationEnabled, DKKeyProfilePublishLocation ],
        };
    });
    return (key ? requires[key] : nil) ?: @[];
}

static DKSettingsBlocker *DKBlockOn(NSString *key, NSString *reason) {
    return [[DKSettingsBlocker alloc] initWithKey:key match:DKSettingsBlockerWhenOn value:0 reason:reason];
}

static DKSettingsBlocker *DKBlockEqual(NSString *key, NSInteger value, NSString *reason) {
    return [[DKSettingsBlocker alloc] initWithKey:key match:DKSettingsBlockerWhenEqual value:value reason:reason];
}

static DKSettingsBlocker *DKBlockNotEqual(NSString *key, NSInteger value, NSString *reason) {
    return [[DKSettingsBlocker alloc] initWithKey:key match:DKSettingsBlockerWhenNotEqual value:value reason:reason];
}

// 总开关：开启时子项锁定并按 shown 显示（子项的生效值由功能按总开关计算）。
static DKSettingsBlocker *DKBlockOnShowing(NSString *key, NSInteger shown, NSString *reason) {
    return [[DKSettingsBlocker alloc] initWithKey:key match:DKSettingsBlockerWhenOn value:0
                                           reason:reason shownValue:@(shown)];
}

static void DKAddMasterBlockers(NSMutableDictionary *table, NSString *master, NSArray<NSString *> *children,
                                NSInteger shown, NSString *reason) {
    for (NSString *child in children) {
        NSArray *existing = table[child] ?: @[];
        table[child] = [existing arrayByAddingObject:DKBlockOnShowing(master, shown, reason)];
    }
}

// 底栏文字：「单图标」不显示文字；该项被「移除底栏项目」移除时也无处显示。
static NSArray<DKSettingsBlocker *> *DKTitleBlockers(NSString *removalKey) {
    NSMutableArray<DKSettingsBlocker *> *list = [NSMutableArray arrayWithObject:
        DKBlockEqual(DKKeyTabBarStyle, 1, @"「单图标」样式不显示文字")];
    if (removalKey) [list addObject:DKBlockOn(removalKey, @"该项已在「移除底栏项目」中移除")];
    return list;
}

NSArray<DKSettingsBlocker *> *DKSettingsLayoutBlockers(NSString *key) {
    static NSDictionary<NSString *, NSArray<DKSettingsBlocker *> *> *blockers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *removedPlus = @"拍摄按钮已在「移除底栏项目」中移除";
        NSMutableDictionary *table = [NSMutableDictionary dictionary];
        [table addEntriesFromDictionary:@{
            DKKeySearchRemoveRankFooter: @[ DKBlockOn(DKKeySearchRemoveAllRanks, @"已移除全部榜单") ],
            DKKeyPlusStyle: @[ DKBlockOn(DKKeyHidePlusButton, removedPlus) ],
            DKKeyPlusIcon: @[ DKBlockNotEqual(DKKeyPlusStyle, 3, @"需先在「拍摄按钮」中选择「自定义图片」"),
                              DKBlockOn(DKKeyHidePlusButton, removedPlus) ],
            DKKeyGlassTabBarPlusSize: @[ DKBlockOn(DKKeyHidePlusButton, removedPlus) ],
            DKKeyTabTitleHome: DKTitleBlockers(nil),
            DKKeyTabTitleFriends: DKTitleBlockers([DKKeyBottomBarHidePrefix stringByAppendingString:@"homepage_familiar"]),
            DKKeyTabTitleMall: DKTitleBlockers([DKKeyBottomBarHidePrefix stringByAppendingString:@"homepage_mall"]),
            DKKeyTabTitleNotification: DKTitleBlockers([DKKeyBottomBarHidePrefix stringByAppendingString:@"homepage_notification"]),
            DKKeyTabTitleProfile: DKTitleBlockers([DKKeyBottomBarHidePrefix stringByAppendingString:@"homepage_profile"]),
            DKKeyProfileSettingsEntry: @[ DKBlockOn(DKKeyProfileRemoveServiceArea, @"主页功能区已在「个人主页精简」中移除") ],
            DKKeyChatTopOnlinePosition: @[ DKBlockOn(DKKeyChatRemoveOnline, @"在线状态已在「消息页精简」中移除") ],
            DKKeyChatGroupZoneNoAutoExpand: @[ DKBlockOn(DKKeyChatRemoveMenu, @"群功能栏已在「移除菜单按钮」中移除") ],
            DKKeyDanmakuFixedColor: @[ DKBlockNotEqual(DKKeyDanmakuColorMode, 0, @"当前颜色模式不是「固定颜色」") ],
            DKKeyDanmakuHexColor: @[ DKBlockNotEqual(DKKeyDanmakuColorMode, 0, @"当前颜色模式不是「固定颜色」") ],
            DKKeyDanmakuGradientColors: @[ DKBlockNotEqual(DKKeyDanmakuColorMode, 4, @"当前颜色模式不是「自定义渐变」") ],
            DKKeyPublishTimeFixedColor: @[ DKBlockNotEqual(DKKeyPublishTimeColorMode, 0, @"当前颜色模式不是「固定颜色」") ],
            DKKeyPublishTimeHexColor: @[ DKBlockNotEqual(DKKeyPublishTimeColorMode, 0, @"当前颜色模式不是「固定颜色」") ],
            DKKeyPublishTimeGradientColors: @[ DKBlockNotEqual(DKKeyPublishTimeColorMode, 4, @"当前颜色模式不是「自定义渐变」") ],
            DKKeyPublishLocationFixedColor: @[ DKBlockNotEqual(DKKeyPublishLocationColorMode, 0, @"当前颜色模式不是「固定颜色」") ],
            DKKeyPublishLocationHexColor: @[ DKBlockNotEqual(DKKeyPublishLocationColorMode, 0, @"当前颜色模式不是「固定颜色」") ],
            DKKeyPublishLocationGradientColors: @[ DKBlockNotEqual(DKKeyPublishLocationColorMode, 4, @"当前颜色模式不是「自定义渐变」") ],
        }];
        DKAddMasterBlockers(table, DKKeyFilterRecommendedSpecialCard, @[
            DKKeyFilterRecommendedHotspot, DKKeyFilterRecommendedCreation, DKKeyFilterRecommendedEcommerce,
            DKKeyFilterRecommendedGame, DKKeyFilterRecommendedSocial, DKKeyFilterRecommendedInterest,
            DKKeyFilterRecommendedMicroApp,
        ], 1, @"已由「推荐过滤特殊卡片」统一开启");
        DKAddMasterBlockers(table, DKKeyPlaybackRemoveAllAnchors, @[
            DKKeyPlaybackGameTagMode, DKKeyPlaybackMusicAnchorMode, DKKeyPlaybackPropEffectMode,
            DKKeyPlaybackJianyingMode, DKKeyPlaybackPaidContentMode, DKKeyPlaybackLocationMode,
        ], 2, @"已由「移除全部昵称上方标签」统一移除");
        DKAddMasterBlockers(table, DKKeyPlaybackRemoveAllBottomBars, @[
            DKKeyPlaybackRelatedSearchMode, DKKeyPlaybackRelatedVideoMode, DKKeyPlaybackVideoCollectionMode,
            DKKeyPlaybackHotspotMode, DKKeyPlaybackAppDownloadMode,
        ], 2, @"已由「移除全部底部栏目」统一移除");
        DKAddMasterBlockers(table, DKKeyCommentRemoveAllTopTags, @[
            DKKeyCommentSearchAnchorMode, DKKeyCommentLunaAnchorMode, DKKeyCommentLocationMode,
            DKKeyCommentGameAnchorMode, DKKeyCommentSeriesAnchorMode, DKKeyCommentDramaAnchorMode,
        ], 2, @"已由「移除全部评论区顶部标签」统一移除");
        DKAddMasterBlockers(table, DKKeyCommentRemoveAllTabs, @[
            DKKeyCommentAIParseMode, DKKeyCommentPlayerDiscussionMode, DKKeyCommentStoreReviewMode,
            DKKeyCommentDramaReviewMode,
        ], 2, @"已由「移除全部评论区分页」统一移除");
        blockers = [table copy];
    });
    return (key ? blockers[key] : nil) ?: @[];
}
