//
//  DKTopChannels.h
//  顶部频道：扫描目录与开关键的共享接口，过滤 hook 与设置页共用。
//

#ifndef DKTopChannels_h
#define DKTopChannels_h

#import <Foundation/Foundation.h>

// 目录项字段。
static NSString *const DKTopChannelFieldID      = @"id";       // channelID
static NSString *const DKTopChannelFieldName    = @"name";     // 频道模型的 title，如「同城」
static NSString *const DKTopChannelFieldTitle   = @"title";    // 顶栏实际文案，如「郑州」
static NSString *const DKTopChannelFieldLocked  = @"locked";   // 抖音标记为不可删除或主频道
static NSString *const DKTopChannelFieldPresent = @"present";  // 最近一次频道重建里出现过

#ifdef __cplusplus
extern "C" {
#endif

/// 扫描到的频道，按顶栏从左到右；只返回 id 为字符串的字典项。
NSArray<NSDictionary *> *DKTopChannelCatalog(void);

/// 该频道的移除开关键。
NSString *DKTopChannelHideKey(NSString *channelID);

/// 目录中已勾选移除且未锁定的频道数。
NSInteger DKTopChannelHiddenCount(void);

#ifdef __cplusplus
}
#endif

#endif /* DKTopChannels_h */
