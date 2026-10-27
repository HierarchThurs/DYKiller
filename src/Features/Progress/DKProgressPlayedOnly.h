//
//  DKProgressPlayedOnly.h
//  DYKiller
//
//  进度条只显示已播时长：隐去进度条上未播放的那段轨道。
//

#ifndef DKProgressPlayedOnly_h
#define DKProgressPlayedOnly_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 开关与已见进度条的轨道状态，一段多行文字，供探针输出。
NSString *DKProgressPlayedOnlyStatus(void);

#ifdef __cplusplus
}
#endif

#endif /* DKProgressPlayedOnly_h */
