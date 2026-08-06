//
//  DKAudioProbe.mm
//  DYKiller
//
//  采样窗口编排与结果组装。全部工作都在主线程或后台线程完成，
//  实时路径见 DKAudioTap。
//

#import "DKAudioProbe.h"
#import "DKAudioHooks.h"
#import "DKAudioSignal.h"
#import "DKAudioTap.h"
#import "DKKeys.h"
#import "DKUtils.h"

#import <AVFAudio/AVFAudio.h>
#import <mach/mach_time.h>
#import <os/lock.h>

#include <algorithm>
#include <atomic>
#include <cmath>

const double DKAudioProbeWarmupSeconds = 1.0;
const double DKAudioProbeRecordSeconds = 3.0;
const double DKAudioProbeTotalSeconds = 5.0;

// 导出的 WAV 路数上限；超出的按 RMS 排名截断。
static const NSUInteger kDKExportPCMCount = 4;
// 派生时间序列的采样率，与可视化的刷新量级对齐。
static const double kDKSignalRateHz = 30.0;
static const NSUInteger kDKObjectEventLimit = 1024;

@implementation DKAudioProbeCapture
@end

static std::atomic<bool> DKProbeEnabled { false };
static std::atomic<bool> DKLaunchCoverage { false };
static std::atomic<bool> DKNotificationsInstalled { false };
static std::atomic<uint64_t> DKObjectEventDrops { 0 };
static NSString *DKDeclaredState;
static NSDictionary *DKSessionBefore;
static NSMutableArray<NSDictionary *> *DKObjectEvents;
static NSHashTable *DKObservedObjects;
static os_unfair_lock DKObjectEventLock = OS_UNFAIR_LOCK_INIT;

#pragma mark - 小工具

static NSString *DKCompactJSONLine(NSDictionary *dictionary) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:&error];
    if (!data || error) return @"";
    NSString *line = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return line.length ? [line stringByAppendingString:@"\n"] : @"";
}

static NSDictionary *DKRouteJSON(AVAudioSessionRouteDescription *route) {
    if (!route) return @{};
    NSMutableArray *inputs = [NSMutableArray array];
    for (AVAudioSessionPortDescription *port in route.inputs) {
        [inputs addObject:@{ @"portType": port.portType ?: @"", @"channelCount": @(port.channels.count) }];
    }
    NSMutableArray *outputs = [NSMutableArray array];
    for (AVAudioSessionPortDescription *port in route.outputs) {
        [outputs addObject:@{ @"portType": port.portType ?: @"", @"channelCount": @(port.channels.count) }];
    }
    return @{ @"inputs": inputs, @"outputs": outputs };
}

static NSDictionary *DKNotificationDetails(NSNotification *notification) {
    NSDictionary *userInfo = notification.userInfo ?: @{};
    NSMutableDictionary *safe = [NSMutableDictionary dictionary];
    // 不收 AVAudioSessionInterruptionReasonKey：它是 iOS 14.5 才有的弱链接符号，
    // 部署目标 14.0 下取到 NULL 会让字面量数组直接崩，而 Type/Option 两个键已经够用。
    for (NSString *key in @[ AVAudioSessionInterruptionTypeKey,
                             AVAudioSessionInterruptionOptionKey,
                             AVAudioSessionRouteChangeReasonKey,
                             AVAudioSessionSilenceSecondaryAudioHintTypeKey ]) {
        id value = userInfo[key];
        if ([value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class]) safe[key] = value;
    }
    AVAudioSessionRouteDescription *previous = userInfo[AVAudioSessionRouteChangePreviousRouteKey];
    if ([previous isKindOfClass:AVAudioSessionRouteDescription.class]) {
        safe[@"previousRoute"] = DKRouteJSON(previous);
    }
    return @{ @"notification": notification.name ?: @"", @"userInfo": safe };
}

#pragma mark - 生命周期

void DKAudioProbeInstallIfEnabled(BOOL launchPhase) {
    BOOL enabled = DKPrefBool(DKKeyDebugInspectorEnabled);
    DKProbeEnabled.store(enabled, std::memory_order_release);

    // 符号包装是探针与音频可视化共用的，任一开着就装；导出通路仍然只看调试开关。
    // 包装只能在启动期装上，故这两个开关都是"打开后需重启抖音才生效"。
    if (!enabled && DKPrefInteger(DKKeyAudioVizPosition) == 0) return;
    DKAudioTapInstall();
    DKAudioTapSetEnabled(YES);
    if (!enabled) return;

    bool expected = false;
    if (DKNotificationsInstalled.compare_exchange_strong(expected, true, std::memory_order_acq_rel)) {
        DKObjectEvents = [NSMutableArray array];
        DKObservedObjects = [NSHashTable weakObjectsHashTable];
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        for (NSNotificationName name in @[ AVAudioSessionRouteChangeNotification,
                                           AVAudioSessionInterruptionNotification,
                                           AVAudioSessionMediaServicesWereLostNotification,
                                           AVAudioSessionMediaServicesWereResetNotification,
                                           AVAudioSessionSilenceSecondaryAudioHintNotification ]) {
            [center addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
                DKAudioProbeRecordObjectDetails(note.name, note.object, DKNotificationDetails(note));
            }];
        }
    }
    if (launchPhase) DKLaunchCoverage.store(true, std::memory_order_release);
}

void DKAudioProbePreferenceDidChange(void) {
    BOOL enabled = DKPrefBool(DKKeyDebugInspectorEnabled);
    DKProbeEnabled.store(enabled, std::memory_order_release);
    if (enabled && !DKAudioTapIsInstalled()) {
        DKAudioProbeInstallIfEnabled(NO);
        return;
    }
    // 关掉调试开关不能顺手把包装器也关了——音频可视化可能正靠它取样。
    DKAudioTapSetEnabled(enabled || DKPrefInteger(DKKeyAudioVizPosition) != 0);
    if (!enabled) DKLaunchCoverage.store(false, std::memory_order_release);
}

BOOL DKAudioProbeHasLaunchCoverage(void) {
    return DKAudioTapIsInstalled() && DKLaunchCoverage.load(std::memory_order_acquire);
}

BOOL DKAudioProbeIsEnabled(void) {
    return DKProbeEnabled.load(std::memory_order_acquire);
}

BOOL DKAudioProbeIsCaptureActive(void) {
    return DKAudioTapIsCapturing();
}

double DKAudioProbeCurrentCaptureSecond(void) {
    return DKAudioTapCurrentCaptureSecond();
}

BOOL DKAudioProbeStartCapture(NSString *declaredState) {
    if (!DKProbeEnabled.load(std::memory_order_acquire) || !DKAudioProbeHasLaunchCoverage()) return NO;
    if (![@[ @"playing", @"paused", @"muted-playing" ] containsObject:declaredState ?: @""]) return NO;

    DKSessionBefore = DKAudioProbeSessionSnapshot();
    if (!DKAudioTapBeginCapture(DKAudioProbeWarmupSeconds, DKAudioProbeRecordSeconds)) return NO;
    DKDeclaredState = [declaredState copy];
    return YES;
}

void DKAudioProbeStopCapture(void) {
    DKAudioTapEndCapture();
}

#pragma mark - 会话快照

NSDictionary *DKAudioProbeSessionSnapshot(void) {
    AVAudioSession *session = AVAudioSession.sharedInstance;
    return @{
        @"category": session.category ?: @"",
        @"mode": session.mode ?: @"",
        @"categoryOptions": @(session.categoryOptions),
        @"sampleRate": @(session.sampleRate),
        @"ioBufferDuration": @(session.IOBufferDuration),
        @"outputLatency": @(session.outputLatency),
        @"outputNumberOfChannels": @(session.outputNumberOfChannels),
        // 抖音的「静音播放」如果压的是系统输出音量，这里就能看出来。
        @"outputVolume": @(session.outputVolume),
        @"otherAudioPlaying": @(session.otherAudioPlaying),
        @"secondaryAudioShouldBeSilencedHint": @(session.secondaryAudioShouldBeSilencedHint),
        @"route": DKRouteJSON(session.currentRoute),
    };
}

#pragma mark - 高层事件

void DKAudioProbeRecordObjectDetails(NSString *name, id object, NSDictionary *details) {
    if (!DKProbeEnabled.load(std::memory_order_relaxed) || name.length == 0) return;
    NSMutableDictionary *event = [@{
        @"ticks": @(mach_continuous_time()),
        @"event": name,
        @"objectClass": object ? NSStringFromClass([object class]) : @"",
    } mutableCopy];
    if (details.count) event[@"details"] = details;
    os_unfair_lock_lock(&DKObjectEventLock);
    if (object) [DKObservedObjects addObject:object];
    if (DKObjectEvents.count < kDKObjectEventLimit) [DKObjectEvents addObject:event];
    else DKObjectEventDrops.fetch_add(1, std::memory_order_relaxed);
    os_unfair_lock_unlock(&DKObjectEventLock);
}

NSArray *DKAudioProbeObservedObjects(void) {
    os_unfair_lock_lock(&DKObjectEventLock);
    NSArray *objects = DKObservedObjects.allObjects ?: @[];
    os_unfair_lock_unlock(&DKObjectEventLock);
    return objects;
}

#pragma mark - 结果组装

static NSString *DKTimelineJSONL(void) {
    uint64_t captureStart = DKAudioTapCaptureStartTicks();
    uint64_t captureStop = DKAudioTapCaptureStopTicks();
    NSMutableArray<NSDictionary *> *timeline = [DKAudioTapEventRows() mutableCopy] ?: [NSMutableArray array];

    os_unfair_lock_lock(&DKObjectEventLock);
    NSArray<NSDictionary *> *objectEvents = [DKObjectEvents copy] ?: @[];
    os_unfair_lock_unlock(&DKObjectEventLock);
    for (NSDictionary *event in objectEvents) {
        NSMutableDictionary *row = [event mutableCopy];
        uint64_t ticks = [row[@"ticks"] unsignedLongLongValue];
        row[@"secondsSinceCaptureStart"] = @(DKAudioTapSecondsRelativeTo(ticks, captureStart));
        row[@"withinCapture"] = @(captureStart > 0 && ticks >= captureStart &&
                                  (captureStop == 0 || ticks <= captureStop));
        [timeline addObject:row];
    }
    [timeline sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [left[@"ticks"] compare:right[@"ticks"]];
    }];

    NSMutableString *out = [NSMutableString string];
    for (NSDictionary *event in timeline) [out appendString:DKCompactJSONLine(event)];
    return out;
}

static NSArray<NSString *> *DKSnapshotStates(NSArray *snapshots) {
    NSMutableArray<NSString *> *states = [NSMutableArray array];
    for (NSDictionary *snapshot in snapshots) {
        NSString *state = [snapshot[@"derivedState"] isKindOfClass:NSString.class]
            ? snapshot[@"derivedState"] : @"unknown";
        [states addObject:state];
    }
    return states;
}

DKAudioProbeCapture *DKAudioProbeBuildCapture(NSArray *mediaSnapshots, NSDictionary *glassTarget) {
    DKAudioTapWaitForWriters();

    // 先把所有录到内容的槽位按 RMS 排名，再决定导出哪几路。
    NSMutableArray<NSDictionary *> *ranked = [NSMutableArray array];
    uint32_t slotCount = DKAudioTapSlotCount();
    for (uint32_t i = 0; i < slotCount; i++) {
        DKAudioTapSlot slot = {};
        if (!DKAudioTapReadSlot(i, &slot)) continue;
        NSDictionary *metrics = DKAudioSignalMetrics(slot.samples, slot.frameCount);
        [ranked addObject:@{ @"slot": @(i), @"metrics": metrics,
                             @"frames": @(slot.frameCount), @"rms": metrics[@"rms"] ?: @0 }];
    }
    [ranked sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        double leftRMS = [left[@"rms"] doubleValue];
        double rightRMS = [right[@"rms"] doubleValue];
        if (fabs(leftRMS - rightRMS) > 1e-7) return leftRMS > rightRMS ? NSOrderedAscending : NSOrderedDescending;
        return [right[@"frames"] compare:left[@"frames"]];
    }];

    NSMutableArray<NSDictionary *> *pcmFiles = [NSMutableArray array];
    NSMutableString *signal = [NSMutableString string];
    double strongestRMS = 0;
    double strongestPeak = 0;
    NSUInteger exportCount = std::min<NSUInteger>(ranked.count, kDKExportPCMCount);
    for (NSUInteger rank = 0; rank < exportCount; rank++) {
        DKAudioTapSlot slot = {};
        if (!DKAudioTapReadSlot([ranked[rank][@"slot"] unsignedIntValue], &slot)) continue;
        NSDictionary *metrics = ranked[rank][@"metrics"];
        strongestRMS = std::max(strongestRMS, [metrics[@"rms"] doubleValue]);
        strongestPeak = std::max(strongestPeak, [metrics[@"peak"] doubleValue]);

        NSString *baseName = [NSString stringWithFormat:@"source-%02u", slot.sourceID];
        NSData *wav = DKAudioSignalFloatWAV(slot.samples, slot.frameCount, slot.sampleRate);
        if (wav.length) {
            [pcmFiles addObject:@{
                @"fileName": [baseName stringByAppendingString:@".wav"],
                @"data": wav,
                @"metadata": @{
                    @"sourceID": baseName,
                    @"captureRank": @(rank + 1),
                    @"frames": @(slot.frameCount),
                    @"sampleRate": @(slot.sampleRate),
                    @"duration": @(slot.sampleRate > 0 ? slot.frameCount / slot.sampleRate : 0),
                    @"processing": @"mono downmix, Float32, no loudness normalization",
                    @"metrics": metrics,
                },
            }];
        }

        // 30 Hz 的滑窗指标：可视化的分频与 attack/decay 参数可以直接拿它离线迭代。
        uint64_t step = (uint64_t)std::max(1.0, slot.sampleRate / kDKSignalRateHz);
        for (uint64_t offset = 0; offset < slot.frameCount; offset += step) {
            uint64_t windowCount = std::min<uint64_t>(1024, slot.frameCount - offset);
            NSDictionary *windowMetrics = DKAudioSignalMetrics(slot.samples + offset, windowCount);
            [signal appendString:DKCompactJSONLine(@{
                @"sourceID": baseName,
                @"time": @(slot.sampleRate > 0 ? offset / slot.sampleRate : 0),
                @"frames": @(windowCount),
                @"rms": windowMetrics[@"rms"] ?: @0,
                @"peak": windowMetrics[@"peak"] ?: @0,
                @"dc": windowMetrics[@"dc"] ?: @0,
                @"zeroCrossingRate": windowMetrics[@"zeroCrossingRate"] ?: @0,
                @"bands": DKAudioSignalFrequencyBands(slot.samples + offset, windowCount, slot.sampleRate) ?: @[],
            })];
        }
    }

    BOOL hasSignal = strongestPeak > 1e-7;
    NSDictionary *counters = DKAudioTapCountersJSON();
    NSArray<NSString *> *snapshotStates = DKSnapshotStates(mediaSnapshots ?: @[]);
    BOOL sawPlaying = [snapshotStates containsObject:@"playing"];
    BOOL sawPaused = [snapshotStates containsObject:@"paused"];
    uint64_t callbackSources = [counters[@"callbackSourcesDuringCapture"] unsignedLongLongValue];

    NSString *actualState = @"unknown";
    if (sawPlaying && sawPaused) actualState = @"state-changed-during-capture";
    else if (hasSignal) actualState = sawPaused ? @"paused-with-signal" : (sawPlaying ? @"playing" : @"signal-active");
    else if (ranked.count > 0) actualState = sawPlaying ? @"playing-with-silent-output" : (sawPaused ? @"paused" : @"silent-callbacks");
    else if (callbackSources > 0) actualState = @"callbacks-without-pcm";
    else actualState = @"no-active-backend";

    // 不可读帧优先于其余判定：有不可读帧就说明 buffer 排布没被读对，此时哪怕录到了"信号"
    // 也是拼错的波形。beta2 就是在 unreadableFrames == 采样总帧数的情况下照样报
    // linear-pcm-signal-recorded，把一份错数据当成好数据交了出去。
    uint64_t unreadableFrames = [counters[@"unreadableFrames"] unsignedLongLongValue];
    NSString *pcmDisposition = @"no-linear-pcm-output-observed";
    if (unreadableFrames > 0) pcmDisposition = @"layout-mismatch-frames-dropped";
    else if (ranked.count > 0 && hasSignal) pcmDisposition = @"linear-pcm-signal-recorded";
    else if (ranked.count > 0) pcmDisposition = @"real-silent-buffers-preserved";
    else if (callbackSources == 0) pcmDisposition = @"no-callbacks-during-window";
    else if ([counters[@"unsupportedBuffers"] unsignedLongLongValue] > 0) pcmDisposition = @"callbacks-active-unsupported-format";
    else if ([counters[@"formatMismatchBuffers"] unsignedLongLongValue] > 0) pcmDisposition = @"callbacks-active-format-changed";
    else if ([counters[@"captureSlotMisses"] unsignedLongLongValue] > 0) pcmDisposition = @"callbacks-active-no-pcm-slot";

    NSDictionary *syntheticValidation = DKAudioSignalSyntheticValidation();
    NSArray<NSDictionary *> *objcHooks = DKAudioHooksCoverageJSON();
    NSMutableArray<NSString *> *warnings = [NSMutableArray array];
    if (!DKLaunchCoverage.load(std::memory_order_relaxed)) [warnings addObject:@"探针不是从进程启动就生效"];
    // 没装上的 hook 必须喊出来：否则「命中 0 次」会被当成「抖音没调用」，结论就反了。
    for (NSDictionary *group in objcHooks) {
        if (![group[@"classFound"] boolValue]) {
            [warnings addObject:[NSString stringWithFormat:@"类 %@ 不存在，该组观测点全部落空", group[@"class"]]];
            continue;
        }
        for (NSDictionary *method in group[@"methods"]) {
            if ([method[@"exists"] boolValue] && ![method[@"hooked"] boolValue]) {
                [warnings addObject:[NSString stringWithFormat:@"%@ 的 %@ 没有被接管，它的 0 命中不能当作证据",
                                     group[@"class"], method[@"selector"]]];
            }
        }
    }
    if ([counters[@"renderNotifySources"] unsignedLongLongValue] == 0) [warnings addObject:@"没有任何输出单元挂上 AudioUnitAddRenderNotify"];
    if ([counters[@"eventOverflow"] unsignedLongLongValue] > 0) [warnings addObject:@"事件环溢出"];
    if ([counters[@"sourceOverflow"] unsignedLongLongValue] > 0) [warnings addObject:@"后端登记表溢出"];
    if ([counters[@"contentionDrops"] unsignedLongLongValue] > 0) [warnings addObject:@"实时争用丢弃了 PCM 块"];
    if ([counters[@"estimatedDroppedFrames"] unsignedLongLongValue] > 0) [warnings addObject:@"回调间隔存在估算缺口"];
    if ([counters[@"pcmCapacityDroppedFrames"] unsignedLongLongValue] > 0) [warnings addObject:@"PCM 容量不足丢帧"];
    if (unreadableFrames > 0) {
        [warnings addObject:[NSString stringWithFormat:
            @"有 %llu 帧按当前布局推导读不出任何声道，PCM 与频谱不可信——核对 backends.json 的 bufferLayout",
            (unsigned long long)unreadableFrames]];
    }
    if ([counters[@"unsupportedBuffers"] unsignedLongLongValue] > 0) [warnings addObject:@"回调使用了不支持的 PCM 格式"];
    if ([counters[@"formatMismatchBuffers"] unsignedLongLongValue] > 0) [warnings addObject:@"采样期间格式发生变化，不匹配的缓冲被跳过"];
    if ([counters[@"pcmAllocationFailures"] unsignedLongLongValue] > 0) [warnings addObject:@"PCM 缓冲分配失败"];
    if ([counters[@"probeMaxMicroseconds"] doubleValue] > 500.0) [warnings addObject:@"单次实时旁路耗时超过 0.5 ms"];
    if (ranked.count > kDKExportPCMCount) [warnings addObject:@"录到的 PCM 路数超过四路，WAV 已按 RMS 排名截断"];
    if (![syntheticValidation[@"passed"] boolValue]) [warnings addObject:@"DKAudioSignal 合成自检未通过"];

    uint64_t captureStart = DKAudioTapCaptureStartTicks();
    uint64_t captureStop = DKAudioTapCaptureStopTicks();
    NSMutableDictionary *diagnostics = [counters mutableCopy];
    diagnostics[@"launchCoverage"] = @(DKLaunchCoverage.load(std::memory_order_relaxed));
    diagnostics[@"captureDuration"] = @(DKAudioTapSecondsRelativeTo(captureStop, captureStart));
    diagnostics[@"pcmWindow"] = @{ @"warmupSeconds": @(DKAudioProbeWarmupSeconds),
                                   @"recordSeconds": @(DKAudioProbeRecordSeconds),
                                   @"signalRateHz": @(kDKSignalRateHz) };
    diagnostics[@"objectEventDrops"] = @(DKObjectEventDrops.load(std::memory_order_relaxed));
    diagnostics[@"pcmSourcesCaptured"] = @(ranked.count);
    diagnostics[@"pcmSourcesExported"] = @(pcmFiles.count);
    diagnostics[@"pcmDisposition"] = pcmDisposition;
    diagnostics[@"mediaSnapshotStates"] = snapshotStates;
    diagnostics[@"strongestRMS"] = @(strongestRMS);
    diagnostics[@"strongestPeak"] = @(strongestPeak);
    diagnostics[@"symbols"] = DKAudioTapSymbolCoverageJSON();
    // ObjC 侧的同类读数。没有它，「某个 hook 命中 0 次」分不出「抖音没调」和「没装上」。
    diagnostics[@"objcHooks"] = objcHooks;
    diagnostics[@"callerImages"] = DKAudioTapCallerImageNames();
    diagnostics[@"syntheticValidation"] = syntheticValidation;
    diagnostics[@"warnings"] = warnings;

    DKAudioProbeCapture *capture = [DKAudioProbeCapture new];
    capture.declaredState = DKDeclaredState ?: @"unknown";
    capture.actualState = actualState;
    capture.sessionJSON = @{ @"beforeCapture": DKSessionBefore ?: @{},
                             @"afterCapture": DKAudioProbeSessionSnapshot() ?: @{} };
    capture.backendsJSON = DKAudioTapBackendsJSON();
    capture.timelineJSONL = DKTimelineJSONL();
    capture.signalJSONL = signal;
    capture.mediaSnapshotsJSON = mediaSnapshots ?: @[];
    capture.glassTargetJSON = glassTarget ?: @{};
    capture.diagnosticsJSON = diagnostics;
    capture.pcmFiles = pcmFiles;
    capture.summaryText = [NSString stringWithFormat:
        @"DYKiller 音频专项探针\n"
        @"声明状态: %@\n推断状态: %@\nPCM 结论: %@\n"
        @"后端源: %@，挂上只读旁路: %@\n"
        @"录到 PCM: %lu 路，导出 WAV: %lu 个\n"
        @"最强 RMS: %.8f，峰值: %.8f\n"
        @"单次实时旁路最大耗时: %.3f us\n"
        @"警告: %@\n",
        capture.declaredState, actualState, pcmDisposition,
        counters[@"registeredSources"], counters[@"renderNotifySources"],
        (unsigned long)ranked.count, (unsigned long)pcmFiles.count,
        strongestRMS, strongestPeak, [counters[@"probeMaxMicroseconds"] doubleValue],
        warnings.count ? [warnings componentsJoinedByString:@"; "] : @"无"];
    return capture;
}
