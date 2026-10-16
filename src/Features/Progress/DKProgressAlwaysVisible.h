//
//  DKProgressAlwaysVisible.h
//  DYKiller
//
//  进度条常显：所有视频常态下都显示底部进度条。
//

#ifndef DKProgressAlwaysVisible_h
#define DKProgressAlwaysVisible_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 开关与已见进度条状态机的判定、外观，一段多行文字，供探针输出。
NSString *DKProgressAlwaysVisibleStatus(void);

#ifdef __cplusplus
}
#endif

#endif /* DKProgressAlwaysVisible_h */
