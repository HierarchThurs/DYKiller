//
//  DKKeys.h
//  集中管理所有 NSUserDefaults 开关键与插件元信息。
//  开关键字符串用于 NSUserDefaults 持久化。
//

#ifndef DKKeys_h
#define DKKeys_h

#import <Foundation/Foundation.h>

#ifndef DK_VERSION
#error DK_VERSION must be injected by Makefile from control Version.
#endif

#pragma mark - 功能组：视频全屏

// 首页、朋友页、好友聊天页、搜索页、其他用户作品页统一由这一个开关控制。
static NSString *const DKKeyVideoFullscreen = @"DYKillerVideoFullscreen";

#pragma mark - 功能组：评论区

// 评论区回复底栏（单选，整数）：0 显示 / 1 隐藏（原位置可点击回复）/ 2 移除（点击交给列表）；后两档列表均铺满。
static NSString *const DKKeyCommentReplyBottomBarMode = @"DYKillerCommentReplyBottomBarMode";
static NSString *const DKKeyCommentAIParseMode = @"DYKillerCommentAIParseMode";
static NSString *const DKKeyCommentSearchAnchorMode = @"DYKillerCommentSearchAnchorMode";
static NSString *const DKKeyCommentLunaAnchorMode = @"DYKillerCommentLunaAnchorMode";
static NSString *const DKKeyCommentLocationMode = @"DYKillerCommentLocationMode";
static NSString *const DKKeyCommentGameAnchorMode = @"DYKillerCommentGameAnchorMode";
static NSString *const DKKeyCommentPlayerDiscussionMode = @"DYKillerCommentPlayerDiscussionMode";
static NSString *const DKKeyCommentStoreReviewMode = @"DYKillerCommentStoreReviewMode";
static NSString *const DKKeyCommentSeriesAnchorMode = @"DYKillerCommentSeriesAnchorMode";
static NSString *const DKKeyCommentDramaAnchorMode = @"DYKillerCommentDramaAnchorMode";
static NSString *const DKKeyCommentDramaReviewMode = @"DYKillerCommentDramaReviewMode";
static NSString *const DKKeyCommentRemoveAllTopTags = @"DYKillerCommentRemoveAllTopTags";
static NSString *const DKKeyCommentRemoveAllTabs = @"DYKillerCommentRemoveAllTabs";
// 移除评论列表中的「评论氛围是否满意」评价卡片。
static NSString *const DKKeyRemoveCommentSurvey = @"DYKillerRemoveCommentSurvey";
static NSString *const DKKeyCommentMediaCleanBottomBar = @"DYKillerCommentMediaCleanBottomBar";
// 材质单选（DKMakeGlassChoice）：总开关 + 清透档两个 BOOL，清透档关即系统 Regular。
static NSString *const DKKeyCommentGlass         = @"DYKillerCommentGlass";
static NSString *const DKKeyCommentGlassClear    = @"DYKillerCommentGlassClear";

#pragma mark - 功能组：分享

// 材质单选（DKMakeGlassChoice）：总开关 + 清透档两个 BOOL，清透档关即系统 Regular。
static NSString *const DKKeySharePanelGlass      = @"DYKillerSharePanelGlass";
static NSString *const DKKeySharePanelGlassClear = @"DYKillerSharePanelGlassClear";
// 分享面板精简：入口、累计功能目录、前缀 + shareType 的独立移除开关。
static NSString *const DKKeyShareMenu            = @"DYKillerShareMenu";
static NSString *const DKKeyShareMenuCatalog     = @"DYKillerShareMenuCatalog";
static NSString *const DKKeyShareMenuHidePrefix  = @"DYKillerHideShareMenu.";

#pragma mark - 功能组：搜索页精简

static NSString *const DKKeySearchRemoveHistory = @"DYKillerSearchRemoveHistory";
static NSString *const DKKeySearchRemoveGuess = @"DYKillerSearchRemoveGuess";
static NSString *const DKKeySearchRemoveAllRanks = @"DYKillerSearchRemoveAllRanks";
static NSString *const DKKeySearchRemoveRankFooter = @"DYKillerSearchRemoveRankFooter";
static NSString *const DKKeySearchRemoveVoice = @"DYKillerSearchRemoveVoice";
// 相机入口：0 显示 / 1 隐藏（保留位置与点击）/ 2 移除（原生布局收拢）。
static NSString *const DKKeySearchCameraMode = @"DYKillerSearchCameraMode";

#pragma mark - 功能组：应用内通知

// 材质单选（DKMakeGlassChoice）：总开关 + 清透档两个 BOOL，清透档关即系统 Regular。
static NSString *const DKKeyInnerNotiGlass      = @"DYKillerInnerNotiGlass";
static NSString *const DKKeyInnerNotiGlassClear = @"DYKillerInnerNotiGlassClear";
// 0–100：0 为抖音原圆角，100 为胶囊。未写入时按 100。
static NSString *const DKKeyInnerNotiCorner     = @"DYKillerInnerNotiCorner";
static NSString *const DKKeyTipsGlass          = @"DYKillerTipsGlass";
static NSString *const DKKeyTipsGlassClear     = @"DYKillerTipsGlassClear";

#pragma mark - 功能组：底栏

// 材质单选（DKMakeGlassChoice）：总开关 + 清透档两个 BOOL，清透档关即系统默认磨砂。
static NSString *const DKKeyGlassTabBar      = @"DYKillerGlassTabBar";
static NSString *const DKKeyGlassTabBarClear = @"DYKillerGlassTabBarClear";
// iPad 玻璃底栏位置（单选）：0 默认居中 / 1 左端 / 2 右端；仅 iPad 生效（见 DKGlassPadElements.xm）。
static NSString *const DKKeyGlassTabBarPadPosition = @"DYKillerGlassTabBarPadPosition";
// 自定义拍摄图标：图片本体存文件（见 DKPlusIcon.xm），这个键只作设置项 identifier，
// NSUserDefaults 里不写值。是否使用由「拍摄按钮」（DKKeyPlusStyle）选「自定义图片」决定。
static NSString *const DKKeyPlusIcon         = @"DYKillerPlusIcon";
// 底栏项目移除：每项一个 BOOL 键，前缀 + 抖音 tabID（见 DKTabBarRemoval.xm）。
static NSString *const DKKeyBottomBarHidePrefix = @"DYKillerHideBottomBar.";
static NSString *const DKKeyHidePlusButton      = @"DYKillerHideBottomBar.homepage_publish";
// 设置主页入口的 identifier，NSUserDefaults 里不写值。
static NSString *const DKKeyBottomBar           = @"DYKillerBottomBar";

#pragma mark - 功能组：外观定制

// 底栏样式（单选，整数）：0 默认 / 1 单图标 / 2 图标+文字，作用于首页、朋友或商城、消息、我。
static NSString *const DKKeyTabBarStyle = @"DYKillerTabBarStyle";
// 拍摄按钮（单选，整数）：0 默认 / 1 新图标 / 2 新双色图标 / 3 自定义图片（图片本体见 DKKeyPlusIcon）。
static NSString *const DKKeyPlusStyle   = @"DYKillerPlusStyle";
// 底栏文字：每项一个字符串键，前缀 + 抖音 tabID；未设置即抖音默认文字。
static NSString *const DKKeyTabTitlePrefix       = @"DYKillerTabBarTitle.";
static NSString *const DKKeyTabTitleHome         = @"DYKillerTabBarTitle.homepage_home";
static NSString *const DKKeyTabTitleFriends      = @"DYKillerTabBarTitle.homepage_familiar";
static NSString *const DKKeyTabTitleMall         = @"DYKillerTabBarTitle.homepage_mall";
static NSString *const DKKeyTabTitleNotification = @"DYKillerTabBarTitle.homepage_notification";
static NSString *const DKKeyTabTitleProfile      = @"DYKillerTabBarTitle.homepage_profile";

#pragma mark - 功能组：互动按钮

// 图标单选：0 默认 / 1 第一款内置 / 2 第二款内置 / 3 自定义；图片项标识只用于文件与备份。
static NSString *const DKKeyInteractionLikeStyle = @"DYKillerInteractionLikeStyle";
static NSString *const DKKeyInteractionCommentStyle = @"DYKillerInteractionCommentStyle";
static NSString *const DKKeyInteractionFavoriteStyle = @"DYKillerInteractionFavoriteStyle";
static NSString *const DKKeyInteractionShareStyle = @"DYKillerInteractionShareStyle";
static NSString *const DKKeyInteractionLikeBeforeIcon = @"DYKillerInteractionLikeBeforeIcon";
static NSString *const DKKeyInteractionLikeAfterIcon = @"DYKillerInteractionLikeAfterIcon";
static NSString *const DKKeyInteractionCommentIcon = @"DYKillerInteractionCommentIcon";
static NSString *const DKKeyInteractionFavoriteBeforeIcon = @"DYKillerInteractionFavoriteBeforeIcon";
static NSString *const DKKeyInteractionFavoriteAfterIcon = @"DYKillerInteractionFavoriteAfterIcon";
static NSString *const DKKeyInteractionShareIcon = @"DYKillerInteractionShareIcon";

// 透明度：0–100，默认 100；缩放：常规 50–100，默认 100；
// 显示方式：0 显示 / 1 隐藏（不显示、仍可点击）/ 2 移除（不显示、不可点击，所在行收拢）。
// 缩放与上移的范围登记在 DKAdjustRange.m，开启「扩展所有缩放与位移」后放宽。
static NSString *const DKKeyInteractionIconAlpha  = @"DYKillerInteractionIconAlpha";
static NSString *const DKKeyInteractionLabelAlpha = @"DYKillerInteractionLabelAlpha";
static NSString *const DKKeyAvatarAlpha           = @"DYKillerAvatarAlpha";
static NSString *const DKKeyMusicAlpha            = @"DYKillerMusicAlpha";
static NSString *const DKKeyInteractionScale      = @"DYKillerInteractionScale";
static NSString *const DKKeyAvatarScale            = @"DYKillerAvatarScale";
static NSString *const DKKeyMusicScale             = @"DYKillerMusicScale";
static NSString *const DKKeyInteractionDisplay    = @"DYKillerInteractionDisplay";
static NSString *const DKKeyAvatarDisplay         = @"DYKillerAvatarDisplay";
static NSString *const DKKeyMusicDisplay          = @"DYKillerMusicDisplay";
// 头像下方关注入口：0 显示 / 1 隐藏（仍可点击）/ 2 移除（与已关注作者时一致）。
static NSString *const DKKeyFollowButtonDisplay   = @"DYKillerFollowButtonDisplayMode";
// 互动区域上移：0–100 pt，默认 0（抖音原位）；头像、互动按钮、音乐整体上移。
static NSString *const DKKeyInteractionOffset     = @"DYKillerInteractionOffset";

#pragma mark - 功能组：昵称文案

// 视频左下昵称一行与文案及其余信息行。透明度：0–100，默认 100；缩放：常规 25–100，默认 100；
// 上移：常规 0–100 pt，默认 0。缩放与上移的范围登记在 DKAdjustRange.m。
static NSString *const DKKeyNicknameAlpha    = @"DYKillerNicknameAlpha";
static NSString *const DKKeyDescriptionAlpha = @"DYKillerDescriptionAlpha";
static NSString *const DKKeyNicknameScale    = @"DYKillerNicknameScale";
static NSString *const DKKeyDescriptionScale = @"DYKillerDescriptionScale";
static NSString *const DKKeyInfoOffset       = @"DYKillerInfoOffset";

#pragma mark - 功能组：进度条与图片指示器位置

// 视频进度条上移、图文图片指示器上移：常规 0–100 pt，默认 0。范围登记在 DKAdjustRange.m。
static NSString *const DKKeyProgressOffset       = @"DYKillerProgressOffset";
static NSString *const DKKeyStoryIndicatorOffset = @"DYKillerStoryIndicatorOffset";
// 本机实测缓存（不进备份）：进度条底边、图片指示器底边到交互层底边的原生距离（pt，不含本插件的上移），
// 供「位置同图片指示器」提示使用。
static NSString *const DKKeyProgressBaseBottom       = @"DYKillerProgressBaseBottom";
static NSString *const DKKeyStoryIndicatorBaseBottom = @"DYKillerStoryIndicatorBaseBottom";

#pragma mark - 功能组：弹幕改色

// 颜色模式：0 固定颜色 / 1 随机纯色 / 2 随机渐变 / 3 固定彩虹 / 4 自定义渐变 / 5 旋转彩虹。
static NSString *const DKKeyDanmakuColorEnabled = @"DYKillerEnableDanmakuColor";
static NSString *const DKKeyDanmakuColorMode = @"DYKillerDanmakuColorMode";
// 固定颜色的唯一规范存值；十六进制入口是同一值的另一个编辑入口。
static NSString *const DKKeyDanmakuFixedColor = @"DYKillerDanmakuFixedColor";
static NSString *const DKKeyDanmakuHexColor = @"DYKillerDanmakuHexColor";
static NSString *const DKKeyDanmakuGradientColors = @"DYKillerDanmakuGradientColors";

#pragma mark - 功能组：发布时间与地区

// 主页作品信息，与播放页的开关独立。
static NSString *const DKKeyProfilePublishTime = @"DYKillerProfileShowPublishTime";
static NSString *const DKKeyProfilePublishLocation = @"DYKillerProfileShowPublishLocation";
// 播放页文案下方一行：具体发布时间（作品创建时间，按设备时区）与发布地区（作品城市代码与国家地区码，不含作者自选地点）。
static NSString *const DKKeyPublishTimeEnabled = @"DYKillerShowPublishTime";
static NSString *const DKKeyPublishLocationEnabled = @"DYKillerShowPublishLocation";
// 国外地名解析用的 GeoNames 用户名；空串为未填写。两个网页入口只作行标识，不存值。
static NSString *const DKKeyGeoNamesUsername = @"DYKillerGeoNamesUsername";
static NSString *const DKKeyGeoNamesRegister = @"DYKillerGeoNamesRegister";
static NSString *const DKKeyGeoNamesWebServices = @"DYKillerGeoNamesWebServices";
// 「文字颜色」子页入口标识，不存值。
static NSString *const DKKeyPublishTextColors = @"DYKillerPublishTextColors";
// 时间、地区两段文字各一套颜色：改色开关 / 颜色模式（同弹幕改色六种）/ 固定颜色 / 十六进制入口 / 渐变颜色。
static NSString *const DKKeyPublishTimeColorEnabled = @"DYKillerPublishTimeColor";
static NSString *const DKKeyPublishTimeColorMode = @"DYKillerPublishTimeColorMode";
static NSString *const DKKeyPublishTimeFixedColor = @"DYKillerPublishTimeFixedColor";
static NSString *const DKKeyPublishTimeHexColor = @"DYKillerPublishTimeHexColor";
static NSString *const DKKeyPublishTimeGradientColors = @"DYKillerPublishTimeGradientColors";
static NSString *const DKKeyPublishLocationColorEnabled = @"DYKillerPublishLocationColor";
static NSString *const DKKeyPublishLocationColorMode = @"DYKillerPublishLocationColorMode";
static NSString *const DKKeyPublishLocationFixedColor = @"DYKillerPublishLocationFixedColor";
static NSString *const DKKeyPublishLocationHexColor = @"DYKillerPublishLocationHexColor";
static NSString *const DKKeyPublishLocationGradientColors = @"DYKillerPublishLocationGradientColors";

#pragma mark - 功能组：音频可视化

// 两项都是单选，用对话框选，故存整数而非 BOOL。
// 位置：0 关闭 / 1 胶囊上方水平 / 2 胶囊整栏环绕 / 3 拍摄圆键环绕
static NSString *const DKKeyAudioVizPosition = @"DYKillerAudioVizPosition";
// 形态：0 离散条 / 1 连续流体
static NSString *const DKKeyAudioVizStyle = @"DYKillerAudioVizStyle";

#pragma mark - 功能组：播放体验

static NSString *const DKKeyDoubleTapOpenComment = @"DYKillerDoubleTapOpenComment";
// 播放页长按左下昵称复制「@昵称」、长按文案复制作品完整文案。
static NSString *const DKKeyLongPressCopyNickname = @"DYKillerLongPressCopyNickname";
static NSString *const DKKeyLongPressCopyDescription = @"DYKillerLongPressCopyDescription";
static NSString *const DKKeyDetailHideBottomBar = @"DYKillerHideChatVideoBottomBar";
static NSString *const DKKeyDetailReturnMode = @"DYKillerDetailReturnMode";
static NSString *const DKKeyDetailSearchMode = @"DYKillerDetailSearchMode";
// 所有视频常态下都显示底部进度条。
static NSString *const DKKeyProgressAlwaysVisible = @"DYKillerProgressAlwaysVisible";
// 进度条旁的已播 / 总时长：0 关闭 / 1 两端（与进度条同一行）/ 2 右端 · 上方 / 3 右端 · 下方 / 4 两端 · 上方 / 5 两端 · 下方
static NSString *const DKKeyProgressTimeStyle = @"DYKillerProgressTimeStyle";

#pragma mark - 功能组：播放页精简

// 每项单选，存整数：0 显示 / 1 隐藏（不显示、仍可点击，位置保留）/ 2 移除（不显示、不可点击，按抖音原生排布收拢）。
static NSString *const DKKeyPlaybackFullscreenMode         = @"DYKillerPlaybackFullscreenMode";
static NSString *const DKKeyPlaybackDanmakuMode            = @"DYKillerPlaybackDanmakuMode";
// 锚点标签：同一种锚点元素，按锚点业务号区分。
// 总开关为 BOOL：开启后所有锚点行（含未登记的业务号）按「移除」处理，各锚点项锁定显示为「移除」，存值不动。
static NSString *const DKKeyPlaybackRemoveAllAnchors       = @"DYKillerPlaybackRemoveAllAnchors";
static NSString *const DKKeyPlaybackGameTagMode            = @"DYKillerPlaybackGameTagMode";
static NSString *const DKKeyPlaybackMusicAnchorMode        = @"DYKillerPlaybackMusicAnchorMode";
static NSString *const DKKeyPlaybackPropEffectMode         = @"DYKillerPlaybackPropEffectMode";
static NSString *const DKKeyPlaybackJianyingMode           = @"DYKillerPlaybackJianyingMode";
static NSString *const DKKeyPlaybackPaidContentMode        = @"DYKillerPlaybackPaidContentMode";
static NSString *const DKKeyPlaybackLocationMode           = @"DYKillerPlaybackLocationMode";
// 文案上方
static NSString *const DKKeyPlaybackOtherUserRecommendMode = @"DYKillerPlaybackOtherUserRecommendMode";
static NSString *const DKKeyPlaybackFriendRecommendMode    = @"DYKillerPlaybackFriendRecommendMode";
static NSString *const DKKeyPlaybackFriendShareMode        = @"DYKillerPlaybackFriendShareMode";
static NSString *const DKKeyPlaybackSelectedMode           = @"DYKillerPlaybackSelectedMode";
static NSString *const DKKeyPlaybackStoreMode              = @"DYKillerPlaybackStoreMode";
// 昵称右侧
static NSString *const DKKeyPlaybackChapterHighlightsMode  = @"DYKillerPlaybackChapterHighlightsMode";
static NSString *const DKKeyPlaybackCoCreatorMode          = @"DYKillerPlaybackCoCreatorMode";
static NSString *const DKKeyPlaybackSlidesTagMode          = @"DYKillerPlaybackSlidesTagMode";
static NSString *const DKKeyPlaybackArticleTagMode         = @"DYKillerPlaybackArticleTagMode";
// 文案下方
static NSString *const DKKeyPlaybackRiskNoticeMode         = @"DYKillerPlaybackRiskNoticeMode";
static NSString *const DKKeyPlaybackMusicInfoMode          = @"DYKillerPlaybackMusicInfoMode";
static NSString *const DKKeyPlaybackQuickReplyMode         = @"DYKillerPlaybackQuickReplyMode";
// 底部栏目：总开关覆盖原生底部容器中的全部业务行，单项存值保持不变。
static NSString *const DKKeyPlaybackRemoveAllBottomBars    = @"DYKillerPlaybackRemoveAllBottomBars";
static NSString *const DKKeyPlaybackRelatedSearchMode      = @"DYKillerPlaybackRelatedSearchMode";
static NSString *const DKKeyPlaybackRelatedVideoMode       = @"DYKillerPlaybackRelatedVideoMode";
static NSString *const DKKeyPlaybackVideoCollectionMode    = @"DYKillerPlaybackVideoCollectionMode";
static NSString *const DKKeyPlaybackHotspotMode            = @"DYKillerPlaybackHotspotMode";
static NSString *const DKKeyPlaybackAppDownloadMode        = @"DYKillerPlaybackAppDownloadMode";

#pragma mark - 功能组：内容过滤

static NSString *const DKKeyFilterLowLikes = @"DYKillerFilterLowLikes";
static NSString *const DKKeyMinimumLikes = @"DYKillerMinimumLikes";
static NSString *const DKKeyRemoveRecommendedLive = @"DYKillerRemoveRecommendedLive";
static NSString *const DKKeyFilterRecommendedMusic = @"DYKillerFilterRecommendedMusic";
static NSString *const DKKeyFilterRecommendedArticle = @"DYKillerFilterRecommendedArticle";
// 商家笔记：图文作品上的 POI 富内容卡片（店铺/团购笔记）。
static NSString *const DKKeyFilterRecommendedMerchantNote = @"DYKillerFilterRecommendedMerchantNote";
// 特殊卡片：总开关开启时全部类别（含未单独分类的业务）过滤，各类别开关锁定显示为开启，存值不动。
static NSString *const DKKeyFilterRecommendedSpecialCard = @"DYKillerFilterRecommendedSpecialCard";
static NSString *const DKKeyFilterRecommendedHotspot = @"DYKillerFilterRecommendedHotspot";
static NSString *const DKKeyFilterRecommendedCreation = @"DYKillerFilterRecommendedCreation";
static NSString *const DKKeyFilterRecommendedEcommerce = @"DYKillerFilterRecommendedEcommerce";
static NSString *const DKKeyFilterRecommendedGame = @"DYKillerFilterRecommendedGame";
static NSString *const DKKeyFilterRecommendedSocial = @"DYKillerFilterRecommendedSocial";
static NSString *const DKKeyFilterRecommendedInterest = @"DYKillerFilterRecommendedInterest";
static NSString *const DKKeyFilterRecommendedMicroApp = @"DYKillerFilterRecommendedMicroApp";
static NSString *const DKKeyFilterAds = @"DYKillerFilterAds";

#pragma mark - 功能组：顶部频道

// 每个频道一个 BOOL 键：前缀 + channelID。
static NSString *const DKKeyTopChannelHidePrefix = @"DYKillerHideTopChannel.";
// 扫描到的频道目录：NSArray<NSDictionary>，每项含 id/name/title/locked/present。
static NSString *const DKKeyTopChannelCatalog = @"DYKillerTopChannelCatalog";
// 设置主页入口的 identifier，NSUserDefaults 里不写值。
static NSString *const DKKeyTopChannels = @"DYKillerTopChannels";

#pragma mark - 功能组：顶栏入口

// 单选，存整数：0 显示 / 1 隐藏（不显示、仍可点击）/ 2 移除（不显示、不可点击）。
static NSString *const DKKeyTopBarSideBarMode = @"DYKillerTopBarSideBarMode";
static NSString *const DKKeyTopBarSearchMode  = @"DYKillerTopBarSearchMode";
// 屏蔽在最左侧频道右滑展开左侧栏。
static NSString *const DKKeyBlockSideBarSwipe = @"DYKillerBlockSideBarSwipe";
// 顶栏透明度：0–100，默认 100；作用于左侧栏入口、全部频道与搜索图标。
static NSString *const DKKeyTopBarAlpha       = @"DYKillerTopBarAlpha";

#pragma mark - 功能组：朋友页精简

// 每项单选，存整数：0 显示 / 1 隐藏（不显示、仍可点击，位置保留）/ 2 移除（不显示、不可点击，按抖音原生排布收拢）。
// 顶栏：左上角头像和加号（日常相机）、中间「限时日常」胶囊（移除时天窗也不再展开）、右上角朋友按钮。
static NSString *const DKKeyFriendAvatarEntryMode   = @"DYKillerFriendAvatarEntryMode";
static NSString *const DKKeyFriendDailyMode         = @"DYKillerFriendDailyMode";
static NSString *const DKKeyFriendButtonMode        = @"DYKillerFriendButtonMode";
// 作品：文案上方「朋友」标记、文案下方「私信 xxx」面板、头像下方「私信」图标；凡出现处都生效。
static NSString *const DKKeyFriendRelationTagMode   = @"DYKillerFriendRelationTagMode";
static NSString *const DKKeyFriendFastReplyMode     = @"DYKillerFriendFastReplyMode";
static NSString *const DKKeyFriendSendMessageMode   = @"DYKillerFriendSendMessageMode";
// 作品：昵称右侧「日常」标签、文案上方关注标签（你的关注 / 互相关注等关系文案）。
static NSString *const DKKeyFriendStoryTagMode      = @"DYKillerFriendStoryTagMode";
static NSString *const DKKeyFriendFollowTagMode     = @"DYKillerFriendFollowTagMode";
// 内容：移除朋友页内容流里的「看看朋友推荐的作品」卡片（开关）。
static NSString *const DKKeyFriendRemoveRecommendCard = @"DYKillerFriendRemoveRecommendCard";

#pragma mark - 功能组：消息页精简

// 每项单选，存整数：0 显示 / 1 隐藏（不显示、仍可点击，位置保留）/ 2 移除（不显示、不可点击，按抖音原生排布收拢）。
// 顶栏
static NSString *const DKKeyMessageSideBarMode      = @"DYKillerMessageSideBarMode";
static NSString *const DKKeyMessageSlotMode         = @"DYKillerMessageSlotMode";
static NSString *const DKKeyMessageSearchMode       = @"DYKillerMessageSearchMode";
static NSString *const DKKeyMessagePlusMode         = @"DYKillerMessagePlusMode";
// 列表顶部：头像行开头的业务入口、头像行里的好友头像、互动消息会话。
static NSString *const DKKeyMessageDailyMode        = @"DYKillerMessageDailyMode";
static NSString *const DKKeyMessageFriendAvatarMode = @"DYKillerMessageFriendAvatarMode";
static NSString *const DKKeyMessageInteractionMode  = @"DYKillerMessageInteractionMode";

#pragma mark - 功能组：聊天页输入区

static NSString *const DKKeyChatRemoveEmojiSuggestions = @"DYKillerChatRemoveEmojiSuggestions";
static NSString *const DKKeyChatPlayEntryMode           = @"DYKillerChatPlayEntryMode";
static NSString *const DKKeyChatRemovePlusPhotos        = @"DYKillerChatRemovePlusPhotos";
static NSString *const DKKeyChatInputGlass              = @"DYKillerChatInputGlass";
static NSString *const DKKeyChatInputGlassClear         = @"DYKillerChatInputGlassClear";
static NSString *const DKKeyChatRemoveBack              = @"DYKillerChatRemoveBack";
static NSString *const DKKeyChatRemoveUnread            = @"DYKillerChatRemoveUnread";
static NSString *const DKKeyChatRemoveOnline            = @"DYKillerChatRemoveOnline";
static NSString *const DKKeyChatRemoveCall              = @"DYKillerChatRemoveCall";
static NSString *const DKKeyChatRemoveMenu              = @"DYKillerChatRemoveMenu";
static NSString *const DKKeyChatGroupZoneNoAutoExpand   = @"DYKillerChatGroupZoneNoAutoExpand";
// 聊天页顶栏自定义：子页面入口、顶部渐变模糊、居中头像（0 默认 / 1 居中）、火花与在线位置（0 居中 / 1 左侧 / 2 右侧）。
static NSString *const DKKeyChatTopCustomPage           = @"DYKillerChatTopCustomPage";
static NSString *const DKKeyChatTopBlur                 = @"DYKillerChatTopBlur";
static NSString *const DKKeyChatTopCenter               = @"DYKillerChatTopCenter";
static NSString *const DKKeyChatTopStreakPosition       = @"DYKillerChatTopStreakPosition";
static NSString *const DKKeyChatTopOnlinePosition       = @"DYKillerChatTopOnlinePosition";

#pragma mark - 功能组：长按菜单

// 作品长按菜单：每个原生菜单项一个 BOOL 键，前缀 + 抖音菜单项标识（panelBizVMIdentifier）。
static NSString *const DKKeyFeedMenuHidePrefix    = @"DYKillerHideFeedMenu.";
// 打开过的作品长按菜单里出现的原生菜单项：NSArray<NSDictionary>，每项含 id/title。
static NSString *const DKKeyFeedMenuCatalog       = @"DYKillerFeedMenuCatalog";
// 宫格排列（单选，整数）：0 每行 1 个（抖音原生列表）/ 1 每行 2 个 / 2 每行 3 个 / 3 每行 4 个。
static NSString *const DKKeyFeedMenuColumns       = @"DYKillerFeedMenuColumns";
// 设置子页入口的 identifier，NSUserDefaults 里不写值。
static NSString *const DKKeyFeedMenu              = @"DYKillerFeedMenu";
// 评论长按菜单：每项一个 BOOL 键，前缀 + 菜单项标识（元素 elementType 数字，或分享行 share）。
static NSString *const DKKeyCommentMenuHidePrefix = @"DYKillerHideCommentMenu.";
static NSString *const DKKeyCommentMenuCatalog    = @"DYKillerCommentMenuCatalog";
static NSString *const DKKeyCommentMenuColumns    = @"DYKillerCommentMenuColumns";
static NSString *const DKKeyCommentMenu           = @"DYKillerCommentMenu";
// 作品长按菜单的材质单选（DKMakeGlassChoice）：总开关 + 清透档两个 BOOL，清透档关即系统 Regular。
static NSString *const DKKeyFeedMenuGlass         = @"DYKillerFeedMenuGlass";
static NSString *const DKKeyFeedMenuGlassClear    = @"DYKillerFeedMenuGlassClear";
// 复制评论时去掉开头的「@用户名: 」，只复制评论内容。
static NSString *const DKKeyCommentCopyWithoutName = @"DYKillerCommentCopyWithoutName";

#pragma mark - 功能组：个人主页

static NSString *const DKKeyProfileHideUGCGuide = @"DYKillerHideProfileUGCGuide";

// 个人主页精简，只作用于自己的主页。
// 每项单选，存整数：0 显示 / 1 隐藏（不显示、仍可点击，位置保留）/ 2 移除（不显示、不可点击，按抖音原生排布收拢）。
// 顶栏：添加好友、访客、搜索图标、侧栏图标。
static NSString *const DKKeyProfileAddFriendMode     = @"DYKillerProfileAddFriendMode";
static NSString *const DKKeyProfileVisitorMode       = @"DYKillerProfileVisitorMode";
static NSString *const DKKeyProfileSearchMode        = @"DYKillerProfileSearchMode";
static NSString *const DKKeyProfileSideBarMode       = @"DYKillerProfileSideBarMode";
// 头像与昵称：头像右下角加号、昵称后的切换账号箭头、抖音号下方的胶囊行。
static NSString *const DKKeyProfileAvatarPlusMode    = @"DYKillerProfileAvatarPlusMode";
static NSString *const DKKeyProfileSwitchAccountMode = @"DYKillerProfileSwitchAccountMode";
static NSString *const DKKeyProfileCapsuleMode       = @"DYKillerProfileCapsuleMode";
// 数据与按钮：获赞 / 互关 / 关注 / 粉丝整行、编辑主页；两者共用一行。
static NSString *const DKKeyProfileStatsMode         = @"DYKillerProfileStatsMode";
static NSString *const DKKeyProfileEditMode          = @"DYKillerProfileEditMode";
// 内容：「记录下幸福瞬间」等发布引导横幅（按所在分区识别）。
static NSString *const DKKeyProfileGuideBannerMode   = @"DYKillerProfileGuideBannerMode";
// 功能区（开关）：移除观看历史、全部功能等入口所在的整行，不占位。
static NSString *const DKKeyProfileRemoveServiceArea = @"DYKillerProfileRemoveServiceArea";
// 分页（开关）：开启即移除对应分页。
static NSString *const DKKeyProfileRemovePostTab      = @"DYKillerProfileRemovePostTab";
static NSString *const DKKeyProfileRemoveDailyTab     = @"DYKillerProfileRemoveDailyTab";
static NSString *const DKKeyProfileRemoveFavoriteTab  = @"DYKillerProfileRemoveFavoriteTab";
static NSString *const DKKeyProfileRemoveLikeTab      = @"DYKillerProfileRemoveLikeTab";
static NSString *const DKKeyProfileRemoveFootprintTab = @"DYKillerProfileRemoveFootprintTab";

#pragma mark - 功能组：媒体保存

// 作品长按面板里的保存项；保存视频 / 保存当前图片开启时移除原生「保存至相册」。
static NSString *const DKKeyMediaSaveVideo         = @"DYKillerMediaSaveVideo";
static NSString *const DKKeyMediaSaveCurrentImage  = @"DYKillerMediaSaveCurrentImage";
static NSString *const DKKeyMediaSaveAllImages     = @"DYKillerMediaSaveAllImages";
static NSString *const DKKeyMediaSaveCover         = @"DYKillerMediaSaveCover";
static NSString *const DKKeyMediaSaveMusic         = @"DYKillerMediaSaveMusic";
// 评论长按「保存到相册」改由插件保存图片、实况与视频评论。
static NSString *const DKKeyMediaSaveComment       = @"DYKillerMediaSaveComment";
// 评论表情：长按菜单与单击后的表情页增加「保存表情包」。
static NSString *const DKKeyMediaSaveCommentSticker = @"DYKillerMediaSaveCommentSticker";
// 抖音原生的评论图片 / 实况保存不带水印。
static NSString *const DKKeyCommentImageNoWatermark     = @"DYKillerCommentImageNoWatermark";
static NSString *const DKKeyCommentLivePhotoNoWatermark = @"DYKillerCommentLivePhotoNoWatermark";
// 私信表情消息长按菜单、单击后的表情页、表情面板长按预览增加「保存表情包」。
static NSString *const DKKeyMediaSaveChatSticker   = @"DYKillerMediaSaveChatSticker";
static NSString *const DKKeyMediaSaveHaptic        = @"DYKillerMediaSaveHaptic";
// 通用提示面板的材质单选：总开关关时为系统模糊，开时按清透档取 Regular / Clear。
static NSString *const DKKeyMediaSaveGlass         = @"DYKillerMediaSaveGlass";
static NSString *const DKKeyMediaSaveGlassClear    = @"DYKillerMediaSaveGlassClear";

#pragma mark - 功能组：备份工具

// 备份工具页的四个动作行，只作设置项 identifier，NSUserDefaults 里不写值。
static NSString *const DKKeyBackupExport  = @"DYKillerBackupExport";
static NSString *const DKKeyBackupRestore = @"DYKillerBackupRestore";
static NSString *const DKKeyBackupUndo    = @"DYKillerBackupUndo";
static NSString *const DKKeyBackupReset   = @"DYKillerBackupReset";
// 上次导出备份的时间（NSDate）。不属于任何设置项：不进备份，恢复默认也不清。
static NSString *const DKKeyBackupLastExportDate = @"DYKillerBackupLastExportDate";

#pragma mark - 设置页

// 「液态玻璃 (iOS26+)」子页入口的 identifier，供玻璃守卫在低系统灰显整个入口；不写值。
static NSString *const DKKeySettingsPageGlass = @"DYKillerPageLiquidGlass";

#pragma mark - 功能组：调整范围

// 扩展所有缩放与位移：开启后 DKAdjustRange 登记的各项按扩展范围生效。开启前须确认，不进备份。
static NSString *const DKKeyAdjustRangeExtended = @"DYKillerAdjustRangeExtended";

#pragma mark - 功能组：快捷入口

// 个人主页功能区末尾的 DYKiller 设置入口（开关，只作用于自己的主页）。
static NSString *const DKKeyProfileSettingsEntry     = @"DYKillerProfileSettingsEntry";
// 入口文字（单选，整数）：0「DYKiller」/ 1「插件设置」。
static NSString *const DKKeyProfileSettingsEntryName = @"DYKillerProfileSettingsEntryName";

#pragma mark - 功能组：调试工具

static NSString *const DKKeyDebugInspectorEnabled = @"DYKillerDebugInspectorEnabled";

#endif /* DKKeys_h */
