//
//  DKDoubleColumnFeed.h
//  DYKiller
//
//  首页双列作品流：列表铺满整屏（顶栏与底栏悬浮其上）、移除 AI 按钮。
//

#ifndef DKDoubleColumnFeed_h
#define DKDoubleColumnFeed_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 顶栏玻璃、悬浮玻璃底栏或视频全屏变了，让见过的双列列表重新布局。
void DKDoubleColumnImmersionSetNeedsUpdate(void);

/// 各双列列表的铺满判据与几何，一段多行文字，供探针输出。
NSString *DKDoubleColumnImmersionStatus(void);

/// AI 按钮的移除开关与各控制器的状态，一段多行文字，供探针输出。
NSString *DKDoubleColumnCopilotStatus(void);

#ifdef __cplusplus
}
#endif

#endif /* DKDoubleColumnFeed_h */
