// 媒体保存的展示适配：媒体类型、图标与取消操作接入通用提示会话。
#ifndef DKMediaSaveHUD_h
#define DKMediaSaveHUD_h
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, DKMediaHUDScene) {
    DKMediaHUDSceneVideo, DKMediaHUDSceneImage, DKMediaHUDSceneLive,
    DKMediaHUDSceneAlbum, DKMediaHUDSceneMixed, DKMediaHUDSceneSticker, DKMediaHUDSceneMusic,
};
typedef NS_ENUM(NSInteger, DKMediaHUDState) {
    DKMediaHUDStateProgress, DKMediaHUDStateSuccess, DKMediaHUDStateCancelled, DKMediaHUDStateFailure,
};

@interface DKMediaSaveHUD : NSObject
- (instancetype)initWithScene:(DKMediaHUDScene)scene windowScene:(UIWindowScene *)windowScene onCancel:(dispatch_block_t)onCancel;
- (void)showProgress:(NSString *)title fraction:(double)fraction;
- (void)updateProgress:(NSString *)title fraction:(double)fraction;
- (void)showResult:(DKMediaHUDState)state title:(NSString *)title subtitle:(NSString *)subtitle;
- (void)nudge;
@end
#endif
