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

#pragma mark - 功能组：聊天页视频

static NSString *const DKKeyChatVideoFullscreen    = @"DYKillerChatVideoFullscreen";
static NSString *const DKKeyChatVideoHideBottomBar = @"DYKillerHideChatVideoBottomBar";

#pragma mark - 功能组：播放体验

static NSString *const DKKeyHideFollowButton = @"DYKillerHideFollowButton";
static NSString *const DKKeyHideMusicInfo    = @"DYKillerHideMusicInfo";

#pragma mark - 功能组：调试工具

static NSString *const DKKeyDebugInspectorEnabled = @"DYKillerDebugInspectorEnabled";

#endif /* DKKeys_h */
