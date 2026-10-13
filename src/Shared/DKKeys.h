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
static NSString *const DKKeyCommentGlass         = @"DYKillerCommentGlass";
// 只在评论玻璃总开关开启时生效；默认关闭即使用系统 Regular 材质。
static NSString *const DKKeyCommentGlassClear    = @"DYKillerCommentGlassClear";

#pragma mark - 功能组：分享

static NSString *const DKKeySharePanelGlass      = @"DYKillerSharePanelGlass";
// 只在分享面板玻璃总开关开启时生效；默认关闭即使用系统 Regular 材质。
static NSString *const DKKeySharePanelGlassClear = @"DYKillerSharePanelGlassClear";

#pragma mark - 功能组：应用内通知

static NSString *const DKKeyInnerNotiGlass      = @"DYKillerInnerNotiGlass";
// 只在通知玻璃总开关开启时生效；默认关闭即使用系统 Regular 材质。
static NSString *const DKKeyInnerNotiGlassClear = @"DYKillerInnerNotiGlassClear";
// 0–100：0 为抖音原圆角，100 为胶囊。未写入时按 100。
static NSString *const DKKeyInnerNotiCorner     = @"DYKillerInnerNotiCorner";

#pragma mark - 功能组：底栏

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

#pragma mark - 功能组：个人主页

static NSString *const DKKeyProfileHideUGCGuide = @"DYKillerHideProfileUGCGuide";

#pragma mark - 功能组：调试工具

static NSString *const DKKeyDebugInspectorEnabled = @"DYKillerDebugInspectorEnabled";

#endif /* DKKeys_h */
