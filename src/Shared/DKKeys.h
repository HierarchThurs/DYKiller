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

static NSString *const DKKeyCommentHideBottomBar = @"DYKillerHideCommentBottomBar";
static NSString *const DKKeyCommentMediaCleanBottomBar = @"DYKillerCommentMediaCleanBottomBar";
// 材质单选（DKMakeGlassChoice）：总开关 + 清透档两个 BOOL，清透档关即系统 Regular。
static NSString *const DKKeyCommentGlass         = @"DYKillerCommentGlass";
static NSString *const DKKeyCommentGlassClear    = @"DYKillerCommentGlassClear";

#pragma mark - 功能组：分享

// 材质单选（DKMakeGlassChoice）：总开关 + 清透档两个 BOOL，清透档关即系统 Regular。
static NSString *const DKKeySharePanelGlass      = @"DYKillerSharePanelGlass";
static NSString *const DKKeySharePanelGlassClear = @"DYKillerSharePanelGlassClear";

#pragma mark - 功能组：应用内通知

// 材质单选（DKMakeGlassChoice）：总开关 + 清透档两个 BOOL，清透档关即系统 Regular。
static NSString *const DKKeyInnerNotiGlass      = @"DYKillerInnerNotiGlass";
static NSString *const DKKeyInnerNotiGlassClear = @"DYKillerInnerNotiGlassClear";
// 0–100：0 为抖音原圆角，100 为胶囊。未写入时按 100。
static NSString *const DKKeyInnerNotiCorner     = @"DYKillerInnerNotiCorner";

#pragma mark - 功能组：底栏

// 材质单选（DKMakeGlassChoice）：总开关 + 清透档两个 BOOL，清透档关即系统默认磨砂。
static NSString *const DKKeyGlassTabBar      = @"DYKillerGlassTabBar";
static NSString *const DKKeyGlassTabBarClear = @"DYKillerGlassTabBarClear";
// 自定义拍摄图标：图片本体存文件（见 DKPlusIcon.xm），这个键只作设置项 identifier，
// 供液态玻璃守卫认出并在低系统上灰显，NSUserDefaults 里不写值。
static NSString *const DKKeyPlusIcon         = @"DYKillerPlusIcon";

#pragma mark - 功能组：音频可视化

// 两项都是单选，用对话框选，故存整数而非 BOOL。
// 位置：0 关闭 / 1 胶囊上方水平 / 2 胶囊整栏环绕 / 3 拍摄圆键环绕
static NSString *const DKKeyAudioVizPosition = @"DYKillerAudioVizPosition";
// 形态：0 离散条 / 1 连续流体
static NSString *const DKKeyAudioVizStyle = @"DYKillerAudioVizStyle";

#pragma mark - 功能组：播放体验

static NSString *const DKKeyDoubleTapOpenComment = @"DYKillerDoubleTapOpenComment";
static NSString *const DKKeyDetailHideBottomBar = @"DYKillerHideChatVideoBottomBar";
static NSString *const DKKeyHideFollowButton     = @"DYKillerHideFollowButton";
static NSString *const DKKeyHideMusicInfo        = @"DYKillerHideMusicInfo";

#pragma mark - 功能组：内容过滤

static NSString *const DKKeyFilterLowLikes = @"DYKillerFilterLowLikes";
static NSString *const DKKeyMinimumLikes = @"DYKillerMinimumLikes";
static NSString *const DKKeyRemoveRecommendedLive = @"DYKillerRemoveRecommendedLive";
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

#pragma mark - 功能组：个人主页

static NSString *const DKKeyProfileHideUGCGuide = @"DYKillerHideProfileUGCGuide";

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
// 保存提示的材质单选（DKMakeGlassChoice）：总开关关时为普通模糊提示，开时按清透档取 Regular / Clear。
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

#pragma mark - 功能组：调试工具

static NSString *const DKKeyDebugInspectorEnabled = @"DYKillerDebugInspectorEnabled";

#endif /* DKKeys_h */
