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
static NSString *const DKKeyCommentGlass         = @"DYKillerCommentGlass";

#pragma mark - 功能组：底栏

static NSString *const DKKeyGlassTabBar      = @"DYKillerGlassTabBar";
static NSString *const DKKeyGlassTabBarClear = @"DYKillerGlassTabBarClear";

#pragma mark - 功能组：播放体验

static NSString *const DKKeyDetailHideBottomBar = @"DYKillerHideChatVideoBottomBar";
static NSString *const DKKeyHideFollowButton     = @"DYKillerHideFollowButton";
static NSString *const DKKeyHideMusicInfo        = @"DYKillerHideMusicInfo";

#pragma mark - 功能组：个人主页

static NSString *const DKKeyProfileHideUGCGuide = @"DYKillerHideProfileUGCGuide";

#pragma mark - 功能组：调试工具

static NSString *const DKKeyDebugInspectorEnabled = @"DYKillerDebugInspectorEnabled";

#endif /* DKKeys_h */
