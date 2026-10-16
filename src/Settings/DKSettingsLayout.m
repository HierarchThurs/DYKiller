//
//  DKSettingsLayout.m
//  新增设置项：功能里 DKSettingsRegister 登记后，在下面对应分区加一行 DKRow；有前置开关再补进 DKRequires。
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
    if ((self = [super init])) {
        _title = [title copy];
        _icon = [icon copy];
        _identifier = [(identifier ?: title) copy];
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
                     reason:(NSString *)reason {
    if ((self = [super init])) { _key = [key copy]; _match = match; _value = value; _reason = [reason copy]; }
    return self;
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
        DKSection(@"视频播放", @[
            DKPage(@"播放页精简", @"ic_eyeslash_outlined_20", @[
                DKSection(@"播放页元素", @[
                    DKRow(DKKeyPlaybackFullscreenMode, @"ic_fullscreen_outlined_16"),
                    DKRow(DKKeyPlaybackDanmakuMode, @"ic_comment_outlined_20"),
                ]),
                DKSection(@"文案上方", @[
                    DKRow(DKKeyPlaybackOtherUserRecommendMode, @"ic_user_outlined_20"),
                    DKRow(DKKeyPlaybackFriendRecommendMode, @"ic_user_outlined_20"),
                    DKRow(DKKeyPlaybackFriendShareMode, @"ic_share_outlined"),
                    DKRow(DKKeyPlaybackSelectedMode, @"ic_magic_outlined_20"),
                    DKRow(DKKeyPlaybackGameTagMode, @"ic_module_outlined_20"),
                    DKRow(DKKeyPlaybackMusicAnchorMode, @"ic_quaver_outlined_20"),
                    DKRow(DKKeyPlaybackPropEffectMode, @"ic_cameralogo_outlined_20"),
                    DKRow(DKKeyPlaybackJianyingMode, @"ic_cameralogo_outlined_20"),
                    DKRow(DKKeyPlaybackLocationMode, @"ic_location_outlined_20"),
                    DKRow(DKKeyPlaybackStoreMode, @"ic_module_outlined_20"),
                ]),
                DKSection(@"昵称右侧", @[
                    DKRow(DKKeyPlaybackChapterHighlightsMode, @"ic_text_outlined_20"),
                    DKRow(DKKeyPlaybackCoCreatorMode, @"ic_personcircleclean_outlined_20"),
                    DKRow(DKKeyPlaybackSlidesTagMode, @"ic_image_outlined_20"),
                ]),
                DKSection(@"文案下方", @[
                    DKRow(DKKeyPlaybackRelatedSearchMode, @"ic_videosearch_outlined_20"),
                    DKRow(DKKeyPlaybackRiskNoticeMode, @"ic_text_outlined_20"),
                    DKRow(DKKeyPlaybackVideoCollectionMode, @"ic_playsquarestack_outlined_20"),
                    DKRow(DKKeyPlaybackHotspotMode, @"ic_module_outlined_20"),
                    DKRow(DKKeyPlaybackMusicInfoMode, @"ic_quaver_outlined_20"),
                    DKRow(DKKeyPlaybackQuickReplyMode, @"ic_msg_outlined_20"),
                    DKRow(DKKeyPlaybackAppDownloadMode, @"ic_boxarrowdown_outlined"),
                ]),
            ]),
            DKPage(@"评论区精简", @"ic_comment_outlined_20", @[
                DKSection(@"评论区顶部", @[
                    DKRow(DKKeyCommentAIParseMode, @"ic_magic_outlined_20"),
                    DKRow(DKKeyCommentPlayerDiscussionMode, @"ic_bubbletwo_outlined_20"),
                    DKRow(DKKeyCommentStoreReviewMode, @"ic_star_outlined_20"),
                    DKRow(DKKeyCommentSearchAnchorMode, @"ic_videosearch_outlined_20"),
                    DKRow(DKKeyCommentLunaAnchorMode, @"ic_quaver_outlined_20"),
                    DKRow(DKKeyCommentLocationMode, @"ic_location_outlined_20"),
                    DKRow(DKKeyCommentGameAnchorMode, @"ic_tag_outlined_20"),
                    DKRow(DKKeyCommentSeriesAnchorMode, @"ic_collection_outlined_20"),
                ]),
                DKSection(@"评论区元素", @[
                    DKRow(DKKeyCommentReplyBottomBarMode, @"ic_comment_outlined_20"),
                    DKRow(DKKeyRemoveCommentSurvey, @"ic_emoji_outlined_20"),
                ]),
                DKSection(@"评论区图片", @[
                    DKRow(DKKeyCommentMediaCleanBottomBar, @"ic_image_outlined_20"),
                ]),
            ]),
            DKRow(DKKeyDetailHideBottomBar, @"ic_xmark_outlined_20"),
        ]),
        DKSection(@"个人主页", @[
            DKRow(DKKeyProfileHideUGCGuide, @"ic_user_outlined_20"),
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
        ]),
    ]);

    DKSettingsPage *glass = [[DKSettingsPage alloc] initWithTitle:@"液态玻璃 (iOS26+)"
                                                             icon:@"ic_rectangleonrectangleup_outlined_20"
                                                       identifier:DKKeySettingsPageGlass
                                                         sections:@[
        DKSection(@"底栏", @[
            DKRow(DKKeyGlassTabBar, @"ic_module_outlined_20"),
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
        DKSection(@"应用内通知", @[
            DKRow(DKKeyInnerNotiGlass, @"ic_msg_outlined_20"),
            DKRow(DKKeyInnerNotiCorner, @"ic_circletop_outlined"),
            DKRow(DKKeyMediaSaveGlass, @"ic_boxarrowdown_outlined"),
        ]),
    ]];

    DKSettingsPage *enhance = DKPage(@"功能增强", @"ic_squaresplit_outlined_20", @[
        DKSection(@"视频", @[
            DKRow(DKKeyVideoFullscreen, @"ic_fullscreen_outlined_16"),
            DKRow(DKKeyProgressAlwaysVisible, @"ic_playertime_outlined_20"),
        ]),
        DKSection(@"手势", @[
            DKRow(DKKeyDoubleTapOpenComment, @"ic_comment_outlined_20"),
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
            DKRow(DKKeyFilterRecommendedHotspot, @"ic_fire_outlined_20"),
        ]),
        DKSection(@"广告", @[
            DKRow(DKKeyFilterAds, @"ic_ad_outlined_20"),
        ]),
    ]);

    DKSettingsPage *tools = DKPage(@"插件工具", @"ic_gearsimplify_outlined_20", @[
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
            DKKeyAudioVizStyle:          @[ DKKeyAudioVizPosition ],
            DKKeyInnerNotiCorner:        @[ DKKeyInnerNotiGlass ],
            DKKeyMinimumLikes:           @[ DKKeyFilterLowLikes ],
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
        blockers = @{
            DKKeyPlusStyle: @[ DKBlockOn(DKKeyHidePlusButton, removedPlus) ],
            DKKeyPlusIcon: @[ DKBlockNotEqual(DKKeyPlusStyle, 3, @"需先在「拍摄按钮」中选择「自定义图片」"),
                              DKBlockOn(DKKeyHidePlusButton, removedPlus) ],
            DKKeyTabTitleHome: DKTitleBlockers(nil),
            DKKeyTabTitleFriends: DKTitleBlockers([DKKeyBottomBarHidePrefix stringByAppendingString:@"homepage_familiar"]),
            DKKeyTabTitleMall: DKTitleBlockers([DKKeyBottomBarHidePrefix stringByAppendingString:@"homepage_mall"]),
            DKKeyTabTitleNotification: DKTitleBlockers([DKKeyBottomBarHidePrefix stringByAppendingString:@"homepage_notification"]),
            DKKeyTabTitleProfile: DKTitleBlockers([DKKeyBottomBarHidePrefix stringByAppendingString:@"homepage_profile"]),
        };
    });
    return (key ? blockers[key] : nil) ?: @[];
}
