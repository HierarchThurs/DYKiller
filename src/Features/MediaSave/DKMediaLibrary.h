// 相册写入（仅添加权限）、音频分享，以及无音轨视频合成背景音乐。
#ifndef DKMediaLibrary_h
#define DKMediaLibrary_h

#import <UIKit/UIKit.h>

typedef void (^DKMediaLibraryDone)(NSString *error);

#ifdef __cplusplus
extern "C" {
#endif

void DKMediaLibraryAuthorize(void (^done)(BOOL granted));
void DKMediaLibrarySaveVideo(NSURL *file, DKMediaLibraryDone done);
void DKMediaLibrarySavePhotoData(NSData *data, NSString *uti, DKMediaLibraryDone done);
void DKMediaLibrarySaveLivePhoto(NSURL *photo, NSURL *movie, DKMediaLibraryDone done);
// 视频轨来自 video、音轨来自 audio（截到视频时长），passthrough 输出 MOV。
void DKMediaComposeAudio(NSURL *video, NSURL *audio, NSURL *output, void (^done)(NSURL *result, NSString *error));
// 在当前最上层页面弹出系统分享面板；dismissed 在面板关闭后回调。
void DKMediaShareFile(NSURL *file, UIWindowScene *scene, dispatch_block_t dismissed);
UIWindow *DKMediaForegroundWindow(void);

#ifdef __cplusplus
}
#endif

#endif
