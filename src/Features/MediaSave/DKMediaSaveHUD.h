// 媒体保存提示：屏幕上方的卡片（图标、标题、副标题、保存中的进度条），挂在前台 scene 的窗口上。
// 材质跟「媒体保存提示液态玻璃」：iOS 26+ 选了玻璃时为 Regular / Clear，否则为系统模糊。只在主线程调用。
#ifndef DKMediaSaveHUD_h
#define DKMediaSaveHUD_h

#import <UIKit/UIKit.h>

// 保存内容的类型，决定保存中的图标。
typedef NS_ENUM(NSInteger, DKMediaHUDScene) {
    DKMediaHUDSceneVideo,
    DKMediaHUDSceneImage,
    DKMediaHUDSceneLive,
    DKMediaHUDSceneAlbum,     // 多张图片
    DKMediaHUDSceneMixed,     // 图片、实况与视频混排
    DKMediaHUDSceneSticker,
    DKMediaHUDSceneMusic,
};

typedef NS_ENUM(NSInteger, DKMediaHUDState) {
    DKMediaHUDStateProgress,
    DKMediaHUDStateSuccess,
    DKMediaHUDStateCancelled,
    DKMediaHUDStateFailure,
};

#ifdef __cplusplus
extern "C" {
#endif

// 保存中：副标题为「点击取消」，点按调 onCancel。fraction 取 0–1。
void DKMediaHUDShowProgress(DKMediaHUDScene scene, NSString *title, double fraction, dispatch_block_t onCancel);
// 只在保存中卡片在屏时生效。
void DKMediaHUDUpdateProgress(NSString *title, double fraction);
// 结果：1.8 秒后收起，点按提前收起。subtitle 可空。
void DKMediaHUDShowResult(DKMediaHUDState state, NSString *title, NSString *subtitle);
// 保存中再次触发保存：保存中卡片轻弹一下。
void DKMediaHUDNudge(void);

#ifdef __cplusplus
}
#endif

#endif
