//
//  DKAudioHooks.xm
//  DYKiller
//
//  Apple 高层音频/播放器事件。所有方法保持原调用与返回值，
//  不安装 AVAudioNode tap，也不主动改变播放、会话或路由。
//
//  只保留四类观测点：会话状态（决定静音与中断语义）、AVAudioEngine 启停
//  （判断是否存在第二条音频链路）、AVPlayer 的播放与静音（回答「静音时 PCM
//  是否已归零」）、进程外播放器的身份（回答「图文 BGM 走的是哪条」）。
//  真正的取样在 DKAudioTap。
//
//  为什么需要第四类：0.5.2-beta4 实测图文类型 feed 的 BGM 在响，而两只 RemoteIO
//  输出单元照常回调、送出的却是数字静音（三秒 rms 全零）。进程内的 AudioUnit /
//  AudioQueue / AVAudioEngine 全部排除，那条音频只可能由 mediaserverd 代为渲染，
//  即 AVPlayer 或 AVAudioPlayer。这两族的入口在此登记，一次导出即可定位。
//

#import "DKAudioProbe.h"
#import "DKAudioHooks.h"
#import <AVFAudio/AVFAudio.h>
#import <AVFoundation/AVFoundation.h>
#import <dlfcn.h>
#import <math.h>
#import <objc/runtime.h>

static NSDictionary *DKAudioHookError(NSError **outError) {
    NSError *error = outError ? *outError : nil;
    return error ? @{ @"domain": error.domain ?: @"", @"code": @(error.code) } : @{};
}

static void DKRecordSessionChange(NSString *name,
                                  AVAudioSession *session,
                                  BOOL result,
                                  NSError **outError,
                                  NSDictionary *parameters) {
    if (!DKAudioProbeIsEnabled()) return;
    DKAudioProbeRecordObjectDetails(name, session, @{
        @"result": @(result),
        @"error": DKAudioHookError(outError),
        @"parameters": parameters ?: @{},
        @"sessionAfterCall": DKAudioProbeSessionSnapshot() ?: @{},
    });
}

static NSDictionary *DKPlayerState(AVPlayer *player) {
    if (!player) return @{};
    double seconds = CMTimeGetSeconds(player.currentTime);
    return @{
        @"rate": @(player.rate), @"volume": @(player.volume), @"muted": @(player.muted),
        @"timeControlStatus": @(player.timeControlStatus),
        @"currentTime": @(isfinite(seconds) ? seconds : -1),
        @"hasCurrentItem": @(player.currentItem != nil),
    };
}

// 只取资源的身份与音轨构成，不读正文、不读 URL 的查询串。
static NSDictionary *DKAssetDescription(AVPlayerItem *item) {
    AVAsset *asset = item.asset;
    if (!asset) return @{};
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[@"assetClass"] = NSStringFromClass(asset.class);
    if ([asset isKindOfClass:AVURLAsset.class]) {
        NSURL *url = ((AVURLAsset *)asset).URL;
        info[@"scheme"] = url.scheme ?: @"";
        info[@"pathExtension"] = url.pathExtension ?: @"";
        info[@"isFileURL"] = @(url.isFileURL);
    }
    info[@"audioTracks"] = @([asset tracksWithMediaType:AVMediaTypeAudio].count);
    info[@"videoTracks"] = @([asset tracksWithMediaType:AVMediaTypeVideo].count);
    info[@"hasAudioMix"] = @(item.audioMix != nil);
    return info;
}

static NSDictionary *DKAudioPlayerState(AVAudioPlayer *player) {
    if (!player) return @{};
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[@"playerClass"] = NSStringFromClass(player.class);
    info[@"playing"] = @(player.isPlaying);
    info[@"volume"] = @(player.volume);
    info[@"rate"] = @(player.rate);
    info[@"numberOfLoops"] = @(player.numberOfLoops);
    info[@"duration"] = @(player.duration);
    info[@"currentTime"] = @(player.currentTime);
    info[@"numberOfChannels"] = @(player.numberOfChannels);
    info[@"meteringEnabled"] = @(player.isMeteringEnabled);
    info[@"scheme"] = player.url.scheme ?: @"";
    info[@"pathExtension"] = player.url.pathExtension ?: @"";
    return info;
}

#pragma mark - 覆盖自检

// IMP 落在 DYKiller 自己的镜像里，就说明这个方法确实被我们接管了。
static BOOL DKHookImplementationIsOurs(IMP implementation) {
    if (!implementation) return NO;
    Dl_info info = {};
    if (dladdr((const void *)implementation, &info) == 0 || !info.dli_fname) return NO;
    return strstr(info.dli_fname, "DYKiller") != NULL;
}

NSArray<NSDictionary *> *DKAudioHooksCoverageJSON(void) {
    NSArray<NSArray *> *table = @[
        @[ @"AVAudioSession", @"setActive:error:", @"setActive:withOptions:error:",
           @"setCategory:mode:options:error:", @"setCategory:error:" ],
        @[ @"AVAudioEngine", @"init", @"startAndReturnError:", @"stop" ],
        @[ @"AVPlayer", @"init", @"initWithURL:", @"initWithPlayerItem:", @"play", @"pause",
           @"setVolume:", @"setMuted:", @"setRate:", @"replaceCurrentItemWithPlayerItem:" ],
        @[ @"AVQueuePlayer", @"initWithItems:" ],
        @[ @"AVPlayerItem", @"setAudioMix:" ],
        @[ @"AVAudioPlayer", @"initWithContentsOfURL:error:", @"initWithData:error:",
           @"play", @"playAtTime:", @"pause", @"stop", @"setVolume:" ],
    ];

    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (NSArray *row in table) {
        NSString *className = row.firstObject;
        Class cls = NSClassFromString(className);
        NSMutableArray<NSDictionary *> *methods = [NSMutableArray array];
        for (NSUInteger i = 1; i < row.count; i++) {
            NSString *name = row[i];
            SEL selector = NSSelectorFromString(name);
            Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
            [methods addObject:@{
                @"selector": name,
                @"exists": @(method != NULL),
                @"hooked": @(method && DKHookImplementationIsOurs(method_getImplementation(method))),
            }];
        }
        [result addObject:@{ @"class": className, @"classFound": @(cls != nil), @"methods": methods }];
    }
    return result;
}

#pragma mark - 会话

%hook AVAudioSession

- (BOOL)setActive:(BOOL)active error:(NSError **)outError {
    BOOL result = %orig;
    DKRecordSessionChange(@"AVAudioSession.setActive", self, result, outError, @{ @"active": @(active) });
    return result;
}

- (BOOL)setActive:(BOOL)active withOptions:(AVAudioSessionSetActiveOptions)options error:(NSError **)outError {
    BOOL result = %orig;
    DKRecordSessionChange(@"AVAudioSession.setActiveWithOptions", self, result, outError,
                          @{ @"active": @(active), @"options": @(options) });
    return result;
}

- (BOOL)setCategory:(AVAudioSessionCategory)category
               mode:(AVAudioSessionMode)mode
            options:(AVAudioSessionCategoryOptions)options
              error:(NSError **)outError {
    BOOL result = %orig;
    DKRecordSessionChange(@"AVAudioSession.setCategoryModeOptions", self, result, outError,
                          @{ @"category": category ?: @"", @"mode": mode ?: @"", @"options": @(options) });
    return result;
}

- (BOOL)setCategory:(AVAudioSessionCategory)category error:(NSError **)outError {
    BOOL result = %orig;
    DKRecordSessionChange(@"AVAudioSession.setCategory", self, result, outError,
                          @{ @"category": category ?: @"" });
    return result;
}

%end

%hook AVAudioEngine

// AVAudioEngine 的 RemoteIO 是 AVFAudio 在共享缓存内部创建的，那次
// AudioComponentInstanceNew 是缓存内直连调用，fishhook 的 GOT 重绑定拦不到——
// 于是「引擎在出声」和「进程内没有我们能看见的输出单元」可以同时成立。
// 登记构造，后续状态由媒体快照逐次读。
- (instancetype)init {
    id engine = %orig;
    if (engine && DKAudioProbeIsEnabled()) {
        DKAudioProbeRecordObjectDetails(@"AVAudioEngine.init", engine, @{});
    }
    return engine;
}

- (BOOL)startAndReturnError:(NSError **)outError {
    BOOL result = %orig;
    if (DKAudioProbeIsEnabled()) {
        DKAudioProbeRecordObjectDetails(@"AVAudioEngine.start", self, @{
            @"result": @(result), @"error": DKAudioHookError(outError), @"running": @(self.running),
        });
    }
    return result;
}

- (void)stop {
    %orig;
    if (DKAudioProbeIsEnabled()) {
        DKAudioProbeRecordObjectDetails(@"AVAudioEngine.stop", self, @{ @"running": @(self.running) });
    }
}

%end

%hook AVPlayer

// 登记构造而不只是登记播放：beta5 实测 play / pause / setRate: 全程 0 命中，
// 但播放完全可能由 AVFoundation 内部路径驱动（AVPlayerLooper 之类）。
// 对象总得先被创建——从构造入手就不依赖「它用哪个 setter」这个猜测。
- (instancetype)init {
    id player = %orig;
    if (player && DKAudioProbeIsEnabled()) DKAudioProbeRecordObjectDetails(@"AVPlayer.init", player, @{});
    return player;
}

- (instancetype)initWithURL:(NSURL *)url {
    id player = %orig;
    if (player && DKAudioProbeIsEnabled()) {
        DKAudioProbeRecordObjectDetails(@"AVPlayer.initWithURL", player, @{
            @"scheme": url.scheme ?: @"", @"pathExtension": url.pathExtension ?: @"",
        });
    }
    return player;
}

- (instancetype)initWithPlayerItem:(AVPlayerItem *)item {
    id player = %orig;
    if (player && DKAudioProbeIsEnabled()) {
        DKAudioProbeRecordObjectDetails(@"AVPlayer.initWithPlayerItem", player,
                                        @{ @"asset": DKAssetDescription(item) });
    }
    return player;
}

- (void)play {
    %orig;
    if (DKAudioProbeIsEnabled()) DKAudioProbeRecordObjectDetails(@"AVPlayer.play", self, DKPlayerState(self));
}

- (void)pause {
    %orig;
    if (DKAudioProbeIsEnabled()) DKAudioProbeRecordObjectDetails(@"AVPlayer.pause", self, DKPlayerState(self));
}

- (void)setVolume:(float)volume {
    %orig;
    if (DKAudioProbeIsEnabled()) {
        NSMutableDictionary *details = [DKPlayerState(self) mutableCopy];
        details[@"requestedVolume"] = @(volume);
        DKAudioProbeRecordObjectDetails(@"AVPlayer.setVolume", self, details);
    }
}

- (void)setMuted:(BOOL)muted {
    %orig;
    if (DKAudioProbeIsEnabled()) {
        NSMutableDictionary *details = [DKPlayerState(self) mutableCopy];
        details[@"requestedMuted"] = @(muted);
        DKAudioProbeRecordObjectDetails(@"AVPlayer.setMuted", self, details);
    }
}

// 抖音很可能直接写 rate 而不调 play——beta4 三份导出里 play/pause 一次都没命中。
- (void)setRate:(float)rate {
    %orig;
    if (DKAudioProbeIsEnabled()) {
        NSMutableDictionary *details = [DKPlayerState(self) mutableCopy];
        details[@"requestedRate"] = @(rate);
        details[@"asset"] = DKAssetDescription(self.currentItem);
        DKAudioProbeRecordObjectDetails(@"AVPlayer.setRate", self, details);
    }
}

- (void)replaceCurrentItemWithPlayerItem:(AVPlayerItem *)item {
    %orig;
    if (DKAudioProbeIsEnabled()) {
        NSMutableDictionary *details = [DKPlayerState(self) mutableCopy];
        details[@"asset"] = DKAssetDescription(item);
        DKAudioProbeRecordObjectDetails(@"AVPlayer.replaceCurrentItem", self, details);
    }
}

%end

// 谁给 item 装了 audioMix 直接决定我们能不能挂 MTAudioProcessingTap：
// 位置空着可以自己装，已经被占就必须串接而不是覆盖。
%hook AVPlayerItem

- (void)setAudioMix:(AVAudioMix *)audioMix {
    %orig;
    if (DKAudioProbeIsEnabled()) {
        DKAudioProbeRecordObjectDetails(@"AVPlayerItem.setAudioMix", self, @{
            @"asset": DKAssetDescription(self),
            @"inputParameterCount": @(audioMix.inputParameters.count),
            @"cleared": @(audioMix == nil),
        });
    }
}

%end

// AVAudioPlayer 也在 mediaserverd 里出声，进程内同样没有 PCM 可取；
// 但它自带 metering，若图文 BGM 走的是它，可视化就只能拿到电平而拿不到频谱。
%hook AVQueuePlayer

- (instancetype)initWithItems:(NSArray<AVPlayerItem *> *)items {
    id player = %orig;
    if (player && DKAudioProbeIsEnabled()) {
        DKAudioProbeRecordObjectDetails(@"AVQueuePlayer.initWithItems", player,
                                        @{ @"itemCount": @(items.count) });
    }
    return player;
}

%end

%hook AVAudioPlayer

- (instancetype)initWithContentsOfURL:(NSURL *)url error:(NSError **)outError {
    id player = %orig;
    if (player && DKAudioProbeIsEnabled()) {
        DKAudioProbeRecordObjectDetails(@"AVAudioPlayer.initWithContentsOfURL", player,
                                        DKAudioPlayerState(player));
    }
    return player;
}

- (instancetype)initWithData:(NSData *)data error:(NSError **)outError {
    id player = %orig;
    if (player && DKAudioProbeIsEnabled()) {
        NSMutableDictionary *details = [DKAudioPlayerState(player) mutableCopy];
        details[@"dataLength"] = @(data.length);
        DKAudioProbeRecordObjectDetails(@"AVAudioPlayer.initWithData", player, details);
    }
    return player;
}

- (BOOL)play {
    BOOL result = %orig;
    if (DKAudioProbeIsEnabled()) {
        NSMutableDictionary *details = [DKAudioPlayerState(self) mutableCopy];
        details[@"result"] = @(result);
        DKAudioProbeRecordObjectDetails(@"AVAudioPlayer.play", self, details);
    }
    return result;
}

- (BOOL)playAtTime:(NSTimeInterval)time {
    BOOL result = %orig;
    if (DKAudioProbeIsEnabled()) {
        NSMutableDictionary *details = [DKAudioPlayerState(self) mutableCopy];
        details[@"result"] = @(result);
        details[@"requestedTime"] = @(time);
        DKAudioProbeRecordObjectDetails(@"AVAudioPlayer.playAtTime", self, details);
    }
    return result;
}

- (void)pause {
    %orig;
    if (DKAudioProbeIsEnabled()) {
        DKAudioProbeRecordObjectDetails(@"AVAudioPlayer.pause", self, DKAudioPlayerState(self));
    }
}

- (void)stop {
    %orig;
    if (DKAudioProbeIsEnabled()) {
        DKAudioProbeRecordObjectDetails(@"AVAudioPlayer.stop", self, DKAudioPlayerState(self));
    }
}

- (void)setVolume:(float)volume {
    %orig;
    if (DKAudioProbeIsEnabled()) {
        NSMutableDictionary *details = [DKAudioPlayerState(self) mutableCopy];
        details[@"requestedVolume"] = @(volume);
        DKAudioProbeRecordObjectDetails(@"AVAudioPlayer.setVolume", self, details);
    }
}

%end
