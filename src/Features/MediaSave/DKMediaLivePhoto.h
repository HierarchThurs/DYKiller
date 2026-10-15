// 图片与视频配对成实况：两份文件写入同一个 content identifier。
#ifndef DKMediaLivePhoto_h
#define DKMediaLivePhoto_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// 在 directory 里生成配对后的 JPEG 与 MOV；completion 在后台队列回调，失败时 error 非空。
void DKMediaMakeLivePhoto(NSURL *image, NSURL *video, NSURL *directory,
                          void (^completion)(NSURL *photo, NSURL *movie, NSString *error));

#ifdef __cplusplus
}
#endif

#endif
