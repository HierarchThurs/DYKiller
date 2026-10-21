#import "DKMediaSaveTask.h"
#import "DKMediaDownloader.h"
#import "DKMediaFormat.h"
#import "DKMediaLibrary.h"
#import "DKMediaLivePhoto.h"
#import "DKMediaSaveDiagnostics.h"
#import "DKMediaSaveHUD.h"
#import "DKPrompt.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import <UIKit/UIKit.h>

__attribute__((constructor)) static void DKMediaSaveRegisterHaptic(void) {
    DKSettingsRegister(DKKeyMediaSaveHaptic, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyMediaSaveHaptic, @"保存完成震动", @"媒体保存成功完成时轻震一下；失败或取消时不震。");
    });
}

static NSString *const DKImageAccept = @"image/heic,image/heif,image/webp,image/jpeg,image/*;q=0.8,*/*;q=0.5";

@interface DKMediaSaveTask : NSObject
@property (nonatomic, copy) NSArray<DKMediaSaveItem *> *items;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, strong) NSURL *directory;
@property (nonatomic, strong) DKMediaDownloader *downloader;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) NSUInteger index, saved, failed;
// 已开始下载的单元下标；下载器的进度只在它等于 index 时属于当前单元。
@property (nonatomic, assign) NSInteger fetchingIndex;
@property (nonatomic, copy) NSString *lastError;
@property (atomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL audioOnly;
@property (nonatomic, assign) DKMediaHUDScene scene;
@property (nonatomic, weak) UIWindowScene *windowScene;
@property (nonatomic, strong) DKMediaSaveHUD *hud;
@end

static DKMediaSaveTask *gDKActiveTask;

static NSString *DKVideoCheck(NSURL *file) {
    DKMediaFileType type = DKMediaSniff(file);
    if (type != DKMediaFileVideo) return [NSString stringWithFormat:@"不是视频（%@）", DKMediaFileTypeName(type)];
    NSString *codec = nil;
    return DKMediaVideoPlayable(file, &codec) ? nil : [NSString stringWithFormat:@"编码 %@ 无法存入相册", codec];
}

static NSString *DKImageCheck(NSURL *file) {
    DKMediaFileType type = DKMediaSniff(file);
    return DKMediaIsImageType(type) ? nil : [NSString stringWithFormat:@"格式 %@ 无法存入相册", DKMediaFileTypeName(type)];
}

// 单项按类型；多项全是图片为多图，否则为混排。
static DKMediaHUDScene DKMediaHUDSceneForItems(NSArray<DKMediaSaveItem *> *items) {
    if (items.count > 1) {
        for (DKMediaSaveItem *item in items) {
            if (item.kind != DKMediaKindImage) return DKMediaHUDSceneMixed;
        }
        return DKMediaHUDSceneAlbum;
    }
    switch (items.firstObject.kind) {
        case DKMediaKindVideo: return DKMediaHUDSceneVideo;
        case DKMediaKindImage: return DKMediaHUDSceneImage;
        case DKMediaKindLivePhoto: return DKMediaHUDSceneLive;
        case DKMediaKindAnimated: return DKMediaHUDSceneSticker;
        case DKMediaKindAudio: return DKMediaHUDSceneMusic;
    }
    return DKMediaHUDSceneVideo;
}

static NSString *DKFileSize(NSURL *file) {
    NSNumber *size = nil;
    [file getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    return [NSByteCountFormatter stringFromByteCount:size.longLongValue countStyle:NSByteCountFormatterCountStyleFile];
}

@implementation DKMediaSaveTask

- (void)start {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"DYKillerMediaSave" stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    self.directory = [NSURL fileURLWithPath:path isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:self.directory withIntermediateDirectories:YES attributes:nil error:nil];
    self.downloader = [[DKMediaDownloader alloc] initWithDirectory:self.directory];
    self.fetchingIndex = -1;
    self.audioOnly = YES;
    for (DKMediaSaveItem *item in self.items) self.audioOnly = self.audioOnly && item.kind == DKMediaKindAudio;
    self.scene = DKMediaHUDSceneForItems(self.items);

    __weak typeof(self) weakSelf = self;
    self.hud = [[DKMediaSaveHUD alloc] initWithScene:self.scene windowScene:self.windowScene onCancel:^{ [weakSelf cancel]; }];
    [self.hud showProgress:[self progressTitle] fraction:[self progressFraction]];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
        [weakSelf.hud updateProgress:[weakSelf progressTitle] fraction:[weakSelf progressFraction]];
    }];
    if (self.audioOnly) { [self next]; return; }
    DKMediaLibraryAuthorize(^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (granted) [weakSelf next];
            else { weakSelf.lastError = @"需要允许抖音添加照片"; weakSelf.failed = weakSelf.items.count; [weakSelf finish]; }
        });
    });
}

- (NSString *)progressTitle {
    if (self.audioOnly) return @"正在下载";
    NSUInteger total = self.items.count;
    if (total <= 1) return @"正在保存";
    return [NSString stringWithFormat:@"正在保存 %lu/%lu", (unsigned long)MIN(self.index + 1, total), (unsigned long)total];
}

// 整体进度：已完成单元数加当前单元的下载进度，再按单元总数归一。
- (double)progressFraction {
    NSUInteger total = self.items.count;
    if (!total) return 0;
    double current = self.fetchingIndex == (NSInteger)self.index ? self.downloader.fraction : 0;
    return MIN(1.0, (MIN(self.index, total) + current) / total);
}

- (NSString *)successTitle {
    if (self.saved > 1) return [NSString stringWithFormat:@"已保存 %lu 项", (unsigned long)self.saved];
    switch (self.scene) {
        case DKMediaHUDSceneImage: return @"图片已保存";
        case DKMediaHUDSceneLive: return @"实况已保存到相册";
        case DKMediaHUDSceneSticker: return @"表情包已保存";
        default: return @"已保存到相册";
    }
}

- (void)cancel {
    self.cancelled = YES;
    [self.downloader cancel];
}

- (void)next {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.cancelled || self.index >= self.items.count) { [self finish]; return; }
        [self.hud updateProgress:[self progressTitle] fraction:[self progressFraction]];
        DKMediaSaveItem *item = self.items[self.index];
        void (^done)(NSString *, NSString *) = ^(NSString *error, NSString *detail) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) { self.failed++; self.lastError = error; }
                else self.saved++;
                DKMediaSaveNote([NSString stringWithFormat:@"[%@] %@ %@ %@", self.source, DKMediaKindName(item.kind),
                                 error ? @"失败" : @"成功", error ?: (detail ?: @"")]);
                self.index++;
                [self next];
            });
        };
        switch (item.kind) {
            case DKMediaKindVideo: [self saveVideo:item done:done]; break;
            case DKMediaKindLivePhoto: [self saveLivePhoto:item done:done]; break;
            case DKMediaKindAudio: [self shareAudio:item done:done]; break;
            case DKMediaKindImage:
            case DKMediaKindAnimated: [self savePhoto:item done:done]; break;
        }
        self.fetchingIndex = (NSInteger)self.index;
    });
}

- (void)savePhoto:(DKMediaSaveItem *)item done:(void (^)(NSString *, NSString *))done {
    [self downloadPhoto:item preferGIF:item.kind == DKMediaKindAnimated done:done];
}

- (void)downloadPhoto:(DKMediaSaveItem *)item preferGIF:(BOOL)preferGIF done:(void (^)(NSString *, NSString *))done {
    if (self.cancelled) { done(@"已取消", nil); return; }
    [self.downloader fetch:item.primary accept:preferGIF ? @"image/gif" : DKImageAccept validate:^NSString *(NSURL *file) {
        return preferGIF ? (DKMediaGIFValid(file) ? nil : @"响应不是完整 GIF") : DKImageCheck(file);
    }
                completion:^(NSURL *file, DKMediaCandidate *candidate, NSString *url, NSString *error) {
        if (self.cancelled) { done(@"已取消", nil); return; }
        if (error && preferGIF) {
            DKMediaSaveNote([NSString stringWithFormat:@"[%@] 网络 GIF 未取得，进入本地转换：%@", self.source, error]);
            [self downloadPhoto:item preferGIF:NO done:done];
            return;
        }
        if (error) { done(error, nil); return; }
        DKMediaFileType type = DKMediaSniff(file);
        NSString *uti = nil;
        NSData *data = DKMediaPhotoData(file, type, &uti);
        if (self.cancelled) { done(@"已取消", nil); return; }
        if (!data.length) { done([NSString stringWithFormat:@"本地转换失败（%@ 解码或图片编码失败）", DKMediaFileTypeName(type)], nil); return; }
        NSString *path = type == DKMediaFileGIF ? @"网络 GIF 原样保存"
            : ((type == DKMediaFileWebP || [uti isEqualToString:@"com.compuserve.gif"]) ? @"本地转换" : @"原图写入");
        NSString *detail = [NSString stringWithFormat:@"%@ %@ → %@ %@ 输入%@ 输出%@", path, candidate.tag, DKMediaFileTypeName(type), uti ?: @"", DKFileSize(file),
                            [NSByteCountFormatter stringFromByteCount:data.length countStyle:NSByteCountFormatterCountStyleFile]];
        DKMediaLibrarySavePhotoData(data, uti, ^(NSString *saveError) {
            done(saveError ? [NSString stringWithFormat:@"相册写入失败（%@）：%@", path, saveError] : nil, detail);
        });
    }];
}

- (void)saveVideo:(DKMediaSaveItem *)item done:(void (^)(NSString *, NSString *))done {
    [self.downloader fetch:item.primary accept:nil validate:^NSString *(NSURL *file) { return DKVideoCheck(file); }
                completion:^(NSURL *file, DKMediaCandidate *candidate, NSString *url, NSString *error) {
        if (error) { done(error, nil); return; }
        NSString *detail = [NSString stringWithFormat:@"%@ %@", candidate.tag, DKFileSize(file)];
        if (!item.music.count || DKMediaVideoHasAudio(file)) {
            DKMediaLibrarySaveVideo(file, ^(NSString *saveError) { done(saveError, detail); });
            return;
        }
        [self.downloader fetch:item.music accept:nil validate:nil completion:^(NSURL *audio, DKMediaCandidate *c, NSString *u, NSString *audioError) {
            if (audioError) { DKMediaLibrarySaveVideo(file, ^(NSString *saveError) { done(saveError, [detail stringByAppendingString:@" 无音轨"]); }); return; }
            NSURL *output = [self.directory URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"mov"]];
            DKMediaComposeAudio(file, audio, output, ^(NSURL *merged, NSString *mergeError) {
                DKMediaLibrarySaveVideo(merged ?: file, ^(NSString *saveError) {
                    done(saveError, [detail stringByAppendingString:merged ? @" 已补音轨" : @" 补音轨失败"]);
                });
            });
        }];
    }];
}

- (void)saveLivePhoto:(DKMediaSaveItem *)item done:(void (^)(NSString *, NSString *))done {
    [self.downloader fetch:item.primary accept:DKImageAccept validate:^NSString *(NSURL *file) { return DKImageCheck(file); }
                completion:^(NSURL *image, DKMediaCandidate *imageCandidate, NSString *u1, NSString *imageError) {
        if (imageError) { done(imageError, nil); return; }
        [self.downloader fetch:item.paired accept:nil validate:^NSString *(NSURL *file) { return DKVideoCheck(file); }
                    completion:^(NSURL *video, DKMediaCandidate *videoCandidate, NSString *u2, NSString *videoError) {
            if (videoError) { done(videoError, nil); return; }
            NSString *detail = [NSString stringWithFormat:@"%@ + %@", imageCandidate.tag, videoCandidate.tag];
            DKMediaMakeLivePhoto(image, video, self.directory, ^(NSURL *photo, NSURL *movie, NSString *pairError) {
                if (pairError) { done(pairError, detail); return; }
                DKMediaLibrarySaveLivePhoto(photo, movie, ^(NSString *saveError) { done(saveError, detail); });
            });
        }];
    }];
}

- (void)shareAudio:(DKMediaSaveItem *)item done:(void (^)(NSString *, NSString *))done {
    [self.downloader fetch:item.primary accept:nil validate:nil completion:^(NSURL *file, DKMediaCandidate *candidate, NSString *url, NSString *error) {
        if (error) { done(error, nil); return; }
        NSString *ext = file.pathExtension.length ? file.pathExtension
            : ([url containsString:@"audio_mp4"] || [url containsString:@".m4a"] ? @"m4a" : @"mp3");
        NSURL *named = [self.directory URLByAppendingPathComponent:[@"music" stringByAppendingPathExtension:ext]];
        [NSFileManager.defaultManager moveItemAtURL:file toURL:named error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.timer invalidate];
            self.timer = nil;
            [self.hud showResult:DKMediaHUDStateSuccess title:@"音乐已下载" subtitle:nil];
            DKMediaShareFile(named, self.windowScene, ^{ done(nil, candidate.tag); });
        });
    }];
}

- (void)finish {
    [self.timer invalidate];
    self.timer = nil;
    [self.downloader cancel];
    [NSFileManager.defaultManager removeItemAtURL:self.directory error:nil];
    if (self.cancelled) {
        NSString *saved = self.saved ? [NSString stringWithFormat:@"已保存 %lu 项", (unsigned long)self.saved] : nil;
        [self.hud showResult:DKMediaHUDStateCancelled title:self.audioOnly ? @"已取消下载" : @"已取消保存" subtitle:saved];
    } else if (!self.failed) {
        // 音乐在弹出分享面板前已提示「音乐已下载」。
        if (!self.audioOnly) [self.hud showResult:DKMediaHUDStateSuccess title:[self successTitle] subtitle:nil];
        if (self.saved && DKPrefBool(DKKeyMediaSaveHaptic)) {
            UINotificationFeedbackGenerator *haptic = [UINotificationFeedbackGenerator new];
            [haptic notificationOccurred:UINotificationFeedbackTypeSuccess];
        }
    } else if (self.saved) {
        NSString *title = [NSString stringWithFormat:@"已保存 %lu 项，失败 %lu 项", (unsigned long)self.saved, (unsigned long)self.failed];
        [self.hud showResult:DKMediaHUDStateFailure title:title subtitle:self.lastError];
    } else {
        [self.hud showResult:DKMediaHUDStateFailure title:self.audioOnly ? @"下载失败" : @"保存失败" subtitle:self.lastError ?: @"未知原因"];
    }
    gDKActiveTask = nil;
}

@end

void DKMediaSaveRun(NSArray<DKMediaSaveItem *> *items, NSString *source, UIWindowScene *scene) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKMediaSaveRun(items, source, scene); });
        return;
    }
    if (gDKActiveTask) { [gDKActiveTask.hud nudge]; return; }
    if (!items.count) {
        DKMediaSaveNote([NSString stringWithFormat:@"[%@] 没有可保存的内容", source ?: @""]);
        DKMediaSaveHUD *hud = [[DKMediaSaveHUD alloc] initWithScene:DKMediaHUDSceneVideo windowScene:scene onCancel:nil];
        [hud showResult:DKMediaHUDStateFailure title:@"保存失败" subtitle:@"没有可保存的内容"];
        return;
    }
    DKMediaSaveTask *task = [DKMediaSaveTask new];
    task.items = items;
    task.source = source ?: @"";
    task.windowScene = scene ?: DKPromptSceneForResponder(nil);
    gDKActiveTask = task;
    [task start];
}
