//
//  DKAudioRuntime.h
//  DYKiller
//
//  主线程采集当前媒体候选与玻璃底栏绘制几何。
//

#ifndef DKAudioRuntime_h
#define DKAudioRuntime_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

NSDictionary *DKAudioRuntimeMediaSnapshot(void);
NSDictionary *DKAudioRuntimeGlassTarget(void);

#ifdef __cplusplus
}
#endif

#endif /* DKAudioRuntime_h */
