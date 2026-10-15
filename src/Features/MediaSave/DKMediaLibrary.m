#import "DKMediaLibrary.h"
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>

void DKMediaLibraryAuthorize(void (^done)(BOOL granted)) {
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly];
    if (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited) { done(YES); return; }
    if (status != PHAuthorizationStatusNotDetermined) { done(NO); return; }
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus result) {
        done(result == PHAuthorizationStatusAuthorized || result == PHAuthorizationStatusLimited);
    }];
}

static void DKPerform(void (^changes)(void), DKMediaLibraryDone done) {
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:changes completionHandler:^(BOOL success, NSError *error) {
        done(success ? nil : (error.localizedDescription ?: @"写入相册失败"));
    }];
}

void DKMediaLibrarySaveVideo(NSURL *file, DKMediaLibraryDone done) {
    DKPerform(^{
        [[PHAssetCreationRequest creationRequestForAsset] addResourceWithType:PHAssetResourceTypeVideo fileURL:file options:nil];
    }, done);
}

void DKMediaLibrarySavePhotoData(NSData *data, NSString *uti, DKMediaLibraryDone done) {
    if (!data.length) { done(@"图片数据为空"); return; }
    DKPerform(^{
        PHAssetResourceCreationOptions *options = [PHAssetResourceCreationOptions new];
        if (uti.length) options.uniformTypeIdentifier = uti;
        [[PHAssetCreationRequest creationRequestForAsset] addResourceWithType:PHAssetResourceTypePhoto data:data options:options];
    }, done);
}

void DKMediaLibrarySaveLivePhoto(NSURL *photo, NSURL *movie, DKMediaLibraryDone done) {
    if (![PHAssetCreationRequest supportsAssetResourceTypes:@[@(PHAssetResourceTypePhoto), @(PHAssetResourceTypePairedVideo)]]) {
        done(@"系统不支持写入实况");
        return;
    }
    DKPerform(^{
        PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
        [request addResourceWithType:PHAssetResourceTypePhoto fileURL:photo options:nil];
        [request addResourceWithType:PHAssetResourceTypePairedVideo fileURL:movie options:nil];
    }, done);
}

void DKMediaComposeAudio(NSURL *video, NSURL *audio, NSURL *output, void (^done)(NSURL *result, NSString *error)) {
    AVURLAsset *videoAsset = [AVURLAsset URLAssetWithURL:video options:nil];
    AVURLAsset *audioAsset = [AVURLAsset URLAssetWithURL:audio options:nil];
    AVAssetTrack *videoTrack = [videoAsset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    AVAssetTrack *audioTrack = [audioAsset tracksWithMediaType:AVMediaTypeAudio].firstObject;
    if (!videoTrack || !audioTrack) { done(nil, @"缺少可合成的轨道"); return; }
    AVMutableComposition *composition = [AVMutableComposition composition];
    CMTimeRange range = CMTimeRangeMake(kCMTimeZero, videoAsset.duration);
    AVMutableCompositionTrack *v = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    AVMutableCompositionTrack *a = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    NSError *error = nil;
    [v insertTimeRange:range ofTrack:videoTrack atTime:kCMTimeZero error:&error];
    CMTime audioDuration = CMTimeMinimum(videoAsset.duration, audioAsset.duration);
    if (!error) [a insertTimeRange:CMTimeRangeMake(kCMTimeZero, audioDuration) ofTrack:audioTrack atTime:kCMTimeZero error:&error];
    if (error) { done(nil, error.localizedDescription); return; }
    v.preferredTransform = videoTrack.preferredTransform;
    AVAssetExportSession *session = [AVAssetExportSession exportSessionWithAsset:composition presetName:AVAssetExportPresetPassthrough];
    session.outputURL = output;
    session.outputFileType = AVFileTypeQuickTimeMovie;
    [session exportAsynchronouslyWithCompletionHandler:^{
        BOOL ok = session.status == AVAssetExportSessionStatusCompleted;
        done(ok ? output : nil, ok ? nil : (session.error.localizedDescription ?: @"合成失败"));
    }];
}

UIWindow *DKMediaForegroundWindow(void) {
    UIWindow *fallback = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) return window;
            if (!fallback && !window.hidden && window.alpha > 0 && window.windowLevel == UIWindowLevelNormal
                && window.bounds.size.width > 1) fallback = window;
        }
    }
    return fallback;
}

static UIViewController *DKTopController(void) {
    UIViewController *top = DKMediaForegroundWindow().rootViewController;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
    return top;
}

void DKMediaShareFile(NSURL *file, dispatch_block_t dismissed) {
    UIViewController *top = DKTopController();
    if (!top) { if (dismissed) dismissed(); return; }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
    share.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *error) {
        if (dismissed) dismissed();
    };
    share.popoverPresentationController.sourceView = top.view;
    share.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMidY(top.view.bounds), 1, 1);
    [top presentViewController:share animated:YES completion:nil];
}
