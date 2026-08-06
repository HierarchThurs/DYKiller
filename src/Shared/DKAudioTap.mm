//
//  DKAudioTap.mm
//  DYKiller
//
//  实时层。这个文件里凡是会被音频渲染线程执行到的代码（DKRenderNotify、
//  DKCaptureBuffer 及其调用链）必须遵守：不分配内存、不加锁、不发 ObjC 消息、
//  不做任何可能阻塞的系统调用。缓冲区在采样开始前于主线程一次性分配。
//
//  取样口是公开只读的 AudioUnitAddRenderNotify：抖音全二进制 0 引用该 API，
//  我们独占；回调里只读 ioData 并原样返回 noErr，不影响它的输出。
//

#import "DKAudioTap.h"
#import "DKAudioSignal.h"
#import "fishhook.h"

#import <CoreMedia/CoreMedia.h>
#import <MediaToolbox/MediaToolbox.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <os/lock.h>
#import <unistd.h>
#if __has_feature(ptrauth_calls)
#import <ptrauth.h>
#endif

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>

namespace {

constexpr uint32_t kDKMaxSources = 32;
constexpr uint32_t kDKMaxEvents = 4096;
constexpr uint32_t kDKCaptureSlots = 8;
constexpr uint32_t kDKMaxFormatRecords = 8;
constexpr double kDKMaxSampleRate = 192000.0;
constexpr double kDKMaxPCMSeconds = 4.0;
constexpr uint64_t kDKMaxPCMFrames = (uint64_t)(kDKMaxSampleRate * kDKMaxPCMSeconds);

// 实时电平旁路的容量。全部是 BSS 里的定长数组：实时侧永远不分配，也没有生命周期问题。
// 4 路 × 4096 帧 × 4 字节 = 64 KB；4096 帧在 48 kHz 下是 85 ms，够 1024 点分析窗用还有余量。
constexpr uint32_t kDKLiveRings = 4;
constexpr uint32_t kDKLiveRingFrames = 4096;
constexpr uint32_t kDKLiveRingMask = kDKLiveRingFrames - 1;
static_assert((kDKLiveRingFrames & kDKLiveRingMask) == 0, "环长必须是 2 的幂");
// 单次回调最多下混这么多帧进环。抖音实测 1024，留一倍余量；栈上 8 KB。
constexpr uint32_t kDKLiveBlockFrames = 2048;

// MARK: - 事件

enum DKEventKind : uint32_t {
    DKEventComponentNew = 1,
    DKEventComponentDispose,
    DKEventUnitInitialize,
    DKEventOutputStart,
    DKEventOutputStop,
    DKEventRenderNotifyInstall,
    DKEventQueueNew,
    DKEventQueueStart,
    DKEventQueueStop,
    DKEventQueueDispose,
    DKEventQueueEnqueue,
    DKEventMediaTapCreate,
};

static const char *DKEventName(uint32_t kind) {
    switch (kind) {
        case DKEventComponentNew: return "AudioComponentInstanceNew";
        case DKEventComponentDispose: return "AudioComponentInstanceDispose";
        case DKEventUnitInitialize: return "AudioUnitInitialize";
        case DKEventOutputStart: return "AudioOutputUnitStart";
        case DKEventOutputStop: return "AudioOutputUnitStop";
        case DKEventRenderNotifyInstall: return "AudioUnitAddRenderNotify";
        case DKEventQueueNew: return "AudioQueueNewOutput";
        case DKEventQueueStart: return "AudioQueueStart";
        case DKEventQueueStop: return "AudioQueueStop";
        case DKEventQueueDispose: return "AudioQueueDispose";
        case DKEventQueueEnqueue: return "AudioQueueEnqueueBuffer";
        case DKEventMediaTapCreate: return "MTAudioProcessingTapCreate";
    }
    return "Unknown";
}

struct DKEvent {
    std::atomic<uint32_t> ready;
    uint32_t kind;
    uint32_t sourceID;
    int32_t status;
    uint64_t ticks;
    uintptr_t caller;
    uint64_t value1;
    uint64_t value2;
};

// MARK: - 符号

enum DKSymbolIndex : uint32_t {
    DKSymbolComponentNew = 0,
    DKSymbolComponentDispose,
    DKSymbolUnitInitialize,
    DKSymbolOutputStart,
    DKSymbolOutputStop,
    DKSymbolQueueNewOutput,
    DKSymbolQueueNewOutputDispatch,
    DKSymbolQueueStart,
    DKSymbolQueueStop,
    DKSymbolQueueDispose,
    DKSymbolQueueEnqueue,
    DKSymbolTapCreate,
    DKSymbolCount,
};

static const char *const DKSymbolNames[DKSymbolCount] = {
    "AudioComponentInstanceNew",
    "AudioComponentInstanceDispose",
    "AudioUnitInitialize",
    "AudioOutputUnitStart",
    "AudioOutputUnitStop",
    "AudioQueueNewOutput",
    "AudioQueueNewOutputWithDispatchQueue",
    "AudioQueueStart",
    "AudioQueueStop",
    "AudioQueueDispose",
    "AudioQueueEnqueueBuffer",
    "MTAudioProcessingTapCreate",
};

struct DKSymbolCoverage {
    void *original;
    int rebindResult;
    std::atomic<uint64_t> hits;
    std::atomic<uint64_t> firstTicks;
    std::atomic<uint64_t> lastTicks;
    std::atomic<uintptr_t> firstCaller;
    std::atomic<uintptr_t> lastCaller;
    std::atomic<int32_t> lastStatus;
};

// MARK: - 源

struct DKFormatRecord {
    std::atomic<uint32_t> version;
    uint32_t scope;
    uint64_t ticks;
    AudioStreamBasicDescription format;
};

struct DKSource {
    std::atomic<uintptr_t> handle;
    uint32_t sourceID;
    uint32_t kind;
    OSType componentType;
    OSType componentSubType;
    OSType componentManufacturer;
    // seqlock：实时侧只读，写在非实时侧。
    std::atomic<uint32_t> formatVersion;
    AudioStreamBasicDescription format;
    std::atomic<uint32_t> formatRecordCount;
    DKFormatRecord formatRecords[kDKMaxFormatRecords];
    std::atomic<int> active;
    std::atomic<int> disposed;
    std::atomic<int> notifyInstalled;
    std::atomic<int32_t> notifyStatus;
    std::atomic<uint64_t> hits;
    std::atomic<uint64_t> frames;
    std::atomic<uint64_t> firstCallbackTicks;
    std::atomic<uint64_t> previousCallbackTicks;
    std::atomic<uint64_t> callbackIntervalCount;
    std::atomic<uint64_t> callbackIntervalTicks;
    std::atomic<uint64_t> minCallbackIntervalTicks;
    std::atomic<uint64_t> maxCallbackIntervalTicks;
    std::atomic<uint64_t> estimatedDroppedFrames;
    std::atomic<uint64_t> lastTicks;
    std::atomic<int32_t> lastStatus;
    std::atomic<uint64_t> contentionDrops;
    std::atomic<uint64_t> unsupportedBuffers;
    std::atomic<uint64_t> unreadableFrames;
    std::atomic<uint64_t> captureSlotMisses;
    std::atomic<uint64_t> formatMismatchBuffers;
    std::atomic<uint64_t> pcmCapacityDroppedFrames;
    std::atomic<uint64_t> configurationOverflow;
    std::atomic<uint64_t> probeTicks;
    std::atomic<uint64_t> probeBlocks;
    std::atomic<uint64_t> maxProbeTicks;
    std::atomic<int> captureSlot;
    // ioData 的实测排布。缓存的 ASBD 描述的是客户端推进去的格式，与 PostRender 拿到的
    // buffer 排布允许不同（beta2 就在这里读错了），故把真实几何原样记下来。
    std::atomic<uint32_t> layoutNumberBuffers;
    std::atomic<uint32_t> layoutChannelsPerBuffer;
    std::atomic<uint32_t> layoutDataByteSize;
    std::atomic<uint32_t> layoutRenderFrames;
    // 实时电平旁路。liveRing 一旦认领就不再归还——源本身是只增不减的。
    std::atomic<int> liveRing;
    std::atomic<uint64_t> liveWrite;
    std::atomic<uint64_t> liveTicks;
    std::atomic<double> liveSampleRate;
    // 块 RMS 的指数滑动平均，选源用。float 的 atomic 在 arm64 上是无锁的。
    std::atomic<float> liveEnergy;
    std::atomic_flag captureGuard = ATOMIC_FLAG_INIT;
};

struct DKPCMSlot {
    float *samples;
    std::atomic<int> sourceID;
    std::atomic<uint64_t> frameCount;
    AudioStreamBasicDescription format;
};

// MARK: - 全局状态

static DKSource DKSources[kDKMaxSources];
static std::atomic<uint32_t> DKSourceCount { 0 };
static std::atomic<uint64_t> DKSourceOverflow { 0 };
static os_unfair_lock DKSourceLock = OS_UNFAIR_LOCK_INIT;

static DKEvent DKEvents[kDKMaxEvents];
static std::atomic<uint32_t> DKEventCount { 0 };
static std::atomic<uint64_t> DKEventOverflow { 0 };
static DKSymbolCoverage DKCoverage[DKSymbolCount];

static DKPCMSlot DKPCMSlots[kDKCaptureSlots];
static std::atomic<uint64_t> DKPCMAllocationFailures { 0 };
static std::atomic<int> DKActiveWriters { 0 };

// 实时电平旁路：每路一个滚动环，单写者（该源自己的渲染线程）+ 单读者（主线程）。
static float DKLiveRing[kDKLiveRings][kDKLiveRingFrames];
static std::atomic<uint32_t> DKLiveRingsClaimed { 0 };
static std::atomic<bool> DKLiveEnabled { false };

static std::atomic<bool> DKTapEnabled { false };
static std::atomic<bool> DKTapInstalled { false };
static std::atomic<bool> DKCaptureActive { false };
static os_unfair_lock DKCaptureControlLock = OS_UNFAIR_LOCK_INIT;
static std::atomic<uint64_t> DKCaptureStartTicks { 0 };
static std::atomic<uint64_t> DKCaptureStopTicks { 0 };
static std::atomic<uint64_t> DKPCMStartTicks { 0 };
static std::atomic<uint64_t> DKPCMStopTicks { 0 };
static mach_timebase_info_data_t DKTimebase;

static __attribute__((always_inline)) inline uintptr_t DKStripCaller(void *address) {
#if __has_feature(ptrauth_calls)
    return (uintptr_t)ptrauth_strip(address, ptrauth_key_return_address);
#else
    return (uintptr_t)address;
#endif
}

#define DK_CALLER() DKStripCaller(__builtin_return_address(0))

static uint64_t DKNanosecondsToTicks(uint64_t ns) {
    if (DKTimebase.numer == 0) mach_timebase_info(&DKTimebase);
    return (uint64_t)((long double)ns * DKTimebase.denom / DKTimebase.numer);
}

static double DKTicksToSeconds(uint64_t ticks) {
    if (DKTimebase.numer == 0) mach_timebase_info(&DKTimebase);
    return (double)((long double)ticks * DKTimebase.numer / DKTimebase.denom / 1000000000.0L);
}

static double DKRelativeSeconds(uint64_t ticks, uint64_t origin) {
    if (ticks == 0 || origin == 0) return -1.0;
    return ticks >= origin ? DKTicksToSeconds(ticks - origin) : -DKTicksToSeconds(origin - ticks);
}

static NSString *DKPointerString(uintptr_t pointer) {
    return [NSString stringWithFormat:@"0x%llx", (unsigned long long)pointer];
}

static NSString *DKFourCC(OSType value) {
    char chars[5] = {
        (char)((value >> 24) & 0xff), (char)((value >> 16) & 0xff),
        (char)((value >> 8) & 0xff), (char)(value & 0xff), 0
    };
    for (int i = 0; i < 4; i++) {
        if (chars[i] < 32 || chars[i] > 126) return [NSString stringWithFormat:@"0x%08x", value];
    }
    return [NSString stringWithUTF8String:chars] ?: @"";
}

static NSString *DKImageForAddress(uintptr_t address) {
    if (!address) return @"";
    Dl_info info = {};
    if (dladdr((const void *)address, &info) == 0 || !info.dli_fname) return @"";
    NSString *path = [NSString stringWithUTF8String:info.dli_fname] ?: @"";
    return path.lastPathComponent ?: @"";
}

static NSString *DKSymbolForAddress(uintptr_t address) {
    if (!address) return @"";
    Dl_info info = {};
    if (dladdr((const void *)address, &info) == 0 || !info.dli_sname) return @"";
    return [NSString stringWithUTF8String:info.dli_sname] ?: @"";
}

static NSString *DKSourceKindName(uint32_t kind) {
    switch (kind) {
        case DKAudioTapSourceKindAudioUnit: return @"AudioUnit";
        case DKAudioTapSourceKindAudioQueue: return @"AudioQueue";
        case DKAudioTapSourceKindMediaTap: return @"MediaProcessingTap";
    }
    return @"Unknown";
}

static NSDictionary *DKASBDJSON(const AudioStreamBasicDescription &format) {
    return @{
        @"sampleRate": @(format.mSampleRate),
        @"formatID": DKFourCC(format.mFormatID),
        @"formatFlags": @(format.mFormatFlags),
        @"bytesPerPacket": @(format.mBytesPerPacket),
        @"framesPerPacket": @(format.mFramesPerPacket),
        @"bytesPerFrame": @(format.mBytesPerFrame),
        @"channelsPerFrame": @(format.mChannelsPerFrame),
        @"bitsPerChannel": @(format.mBitsPerChannel),
        @"nonInterleaved": @((format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0),
        @"float": @((format.mFormatFlags & kAudioFormatFlagIsFloat) != 0),
        @"signedInteger": @((format.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0),
    };
}

// MARK: - 格式读写（seqlock）

static void DKWriteSourceFormat(DKSource *source, const AudioStreamBasicDescription *format) {
    if (!source || !format) return;
    for (int attempt = 0; attempt < 4; attempt++) {
        uint32_t version = source->formatVersion.load(std::memory_order_acquire);
        if (version & 1) continue;
        if (!source->formatVersion.compare_exchange_weak(version, version + 1,
                                                         std::memory_order_acq_rel,
                                                         std::memory_order_relaxed)) continue;
        source->format = *format;
        source->formatVersion.store(version + 2, std::memory_order_release);
        return;
    }
    source->configurationOverflow.fetch_add(1, std::memory_order_relaxed);
}

static bool DKReadSourceFormat(DKSource *source, AudioStreamBasicDescription *format) {
    if (!source || !format) return false;
    for (int attempt = 0; attempt < 4; attempt++) {
        uint32_t before = source->formatVersion.load(std::memory_order_acquire);
        if (before == 0 || (before & 1)) continue;
        AudioStreamBasicDescription copy = source->format;
        uint32_t after = source->formatVersion.load(std::memory_order_acquire);
        if (before == after && !(after & 1)) {
            *format = copy;
            return copy.mSampleRate > 0 && copy.mChannelsPerFrame > 0;
        }
    }
    return false;
}

static void DKAppendFormatRecord(DKSource *source, uint32_t scope,
                                 const AudioStreamBasicDescription *format) {
    if (!source || !format) return;
    uint32_t index = source->formatRecordCount.fetch_add(1, std::memory_order_relaxed);
    if (index >= kDKMaxFormatRecords) {
        source->configurationOverflow.fetch_add(1, std::memory_order_relaxed);
        return;
    }
    DKFormatRecord &record = source->formatRecords[index];
    record.version.store(1, std::memory_order_release);
    record.scope = scope;
    record.ticks = mach_continuous_time();
    record.format = *format;
    record.version.store(2, std::memory_order_release);
}

// MARK: - 源登记

static DKSource *DKFindSource(uintptr_t handle, uint32_t kind) {
    uint32_t count = DKSourceCount.load(std::memory_order_acquire);
    for (uint32_t offset = 0; offset < count; offset++) {
        uint32_t i = count - offset - 1;
        if (DKSources[i].kind == kind &&
            DKSources[i].disposed.load(std::memory_order_relaxed) == 0 &&
            DKSources[i].handle.load(std::memory_order_acquire) == handle) return &DKSources[i];
    }
    return nullptr;
}

static DKSource *DKCreateSource(uintptr_t handle, uint32_t kind,
                                const AudioStreamBasicDescription *format) {
    if (!handle) return nullptr;
    DKSource *existing = DKFindSource(handle, kind);
    if (existing) {
        if (format) {
            DKWriteSourceFormat(existing, format);
            DKAppendFormatRecord(existing, UINT32_MAX, format);
        }
        return existing;
    }

    os_unfair_lock_lock(&DKSourceLock);
    existing = DKFindSource(handle, kind);
    if (existing) {
        os_unfair_lock_unlock(&DKSourceLock);
        if (format) {
            DKWriteSourceFormat(existing, format);
            DKAppendFormatRecord(existing, UINT32_MAX, format);
        }
        return existing;
    }

    uint32_t index = DKSourceCount.load(std::memory_order_relaxed);
    if (index >= kDKMaxSources) {
        DKSourceOverflow.fetch_add(1, std::memory_order_relaxed);
        os_unfair_lock_unlock(&DKSourceLock);
        return nullptr;
    }

    DKSource *source = &DKSources[index];
    source->sourceID = index + 1;
    source->kind = kind;
    source->componentType = 0;
    source->componentSubType = 0;
    source->componentManufacturer = 0;
    source->formatVersion.store(0, std::memory_order_relaxed);
    source->formatRecordCount.store(0, std::memory_order_relaxed);
    for (uint32_t i = 0; i < kDKMaxFormatRecords; i++) {
        source->formatRecords[i].version.store(0, std::memory_order_relaxed);
    }
    source->active.store(0, std::memory_order_relaxed);
    source->disposed.store(0, std::memory_order_relaxed);
    source->notifyInstalled.store(0, std::memory_order_relaxed);
    source->notifyStatus.store(0, std::memory_order_relaxed);
    source->hits.store(0, std::memory_order_relaxed);
    source->frames.store(0, std::memory_order_relaxed);
    source->firstCallbackTicks.store(0, std::memory_order_relaxed);
    source->previousCallbackTicks.store(0, std::memory_order_relaxed);
    source->callbackIntervalCount.store(0, std::memory_order_relaxed);
    source->callbackIntervalTicks.store(0, std::memory_order_relaxed);
    source->minCallbackIntervalTicks.store(0, std::memory_order_relaxed);
    source->maxCallbackIntervalTicks.store(0, std::memory_order_relaxed);
    source->estimatedDroppedFrames.store(0, std::memory_order_relaxed);
    source->lastTicks.store(0, std::memory_order_relaxed);
    source->lastStatus.store(0, std::memory_order_relaxed);
    source->contentionDrops.store(0, std::memory_order_relaxed);
    source->unsupportedBuffers.store(0, std::memory_order_relaxed);
    source->unreadableFrames.store(0, std::memory_order_relaxed);
    source->captureSlotMisses.store(0, std::memory_order_relaxed);
    source->formatMismatchBuffers.store(0, std::memory_order_relaxed);
    source->pcmCapacityDroppedFrames.store(0, std::memory_order_relaxed);
    source->configurationOverflow.store(0, std::memory_order_relaxed);
    source->probeTicks.store(0, std::memory_order_relaxed);
    source->probeBlocks.store(0, std::memory_order_relaxed);
    source->maxProbeTicks.store(0, std::memory_order_relaxed);
    source->captureSlot.store(-1, std::memory_order_relaxed);
    source->layoutNumberBuffers.store(0, std::memory_order_relaxed);
    source->layoutChannelsPerBuffer.store(0, std::memory_order_relaxed);
    source->layoutDataByteSize.store(0, std::memory_order_relaxed);
    source->layoutRenderFrames.store(0, std::memory_order_relaxed);
    source->liveRing.store(-1, std::memory_order_relaxed);
    source->liveWrite.store(0, std::memory_order_relaxed);
    source->liveTicks.store(0, std::memory_order_relaxed);
    source->liveSampleRate.store(0, std::memory_order_relaxed);
    source->liveEnergy.store(0, std::memory_order_relaxed);
    source->captureGuard.clear(std::memory_order_relaxed);
    if (format) {
        DKWriteSourceFormat(source, format);
        DKAppendFormatRecord(source, UINT32_MAX, format);
    }
    source->handle.store(handle, std::memory_order_release);
    DKSourceCount.store(index + 1, std::memory_order_release);
    os_unfair_lock_unlock(&DKSourceLock);
    return source;
}

// MARK: - 统计

static void DKUpdateMax(std::atomic<uint64_t> &value, uint64_t candidate) {
    uint64_t current = value.load(std::memory_order_relaxed);
    while (candidate > current &&
           !value.compare_exchange_weak(current, candidate, std::memory_order_relaxed)) {}
}

static void DKUpdateMinNonZero(std::atomic<uint64_t> &value, uint64_t candidate) {
    uint64_t current = value.load(std::memory_order_relaxed);
    while ((current == 0 || candidate < current) &&
           !value.compare_exchange_weak(current, candidate, std::memory_order_relaxed)) {}
}

static void DKRecordProbeElapsed(DKSource *source, uint64_t begin) {
    if (!source || begin == 0) return;
    uint64_t elapsed = mach_continuous_time() - begin;
    source->probeTicks.fetch_add(elapsed, std::memory_order_relaxed);
    source->probeBlocks.fetch_add(1, std::memory_order_relaxed);
    DKUpdateMax(source->maxProbeTicks, elapsed);
}

static void DKRecordCallbackActivity(DKSource *source, uint32_t frames, OSStatus status) {
    if (!source || !DKTapEnabled.load(std::memory_order_relaxed)) return;
    uint64_t now = mach_continuous_time();
    source->hits.fetch_add(1, std::memory_order_relaxed);
    source->frames.fetch_add(frames, std::memory_order_relaxed);
    source->lastTicks.store(now, std::memory_order_relaxed);
    source->lastStatus.store(status, std::memory_order_relaxed);
    if (!DKCaptureActive.load(std::memory_order_relaxed)) return;

    uint64_t zero = 0;
    source->firstCallbackTicks.compare_exchange_strong(zero, now, std::memory_order_relaxed);
    uint64_t previous = source->previousCallbackTicks.exchange(now, std::memory_order_relaxed);
    if (previous == 0 || now <= previous) return;
    uint64_t interval = now - previous;
    source->callbackIntervalCount.fetch_add(1, std::memory_order_relaxed);
    source->callbackIntervalTicks.fetch_add(interval, std::memory_order_relaxed);
    DKUpdateMinNonZero(source->minCallbackIntervalTicks, interval);
    DKUpdateMax(source->maxCallbackIntervalTicks, interval);

    AudioStreamBasicDescription format = {};
    if (!DKReadSourceFormat(source, &format) || format.mSampleRate <= 0 || frames == 0) return;
    uint64_t expected = DKNanosecondsToTicks((uint64_t)llround((double)frames / format.mSampleRate * 1.0e9));
    if (expected == 0 || interval <= expected + expected / 2) return;
    uint64_t periods = interval / expected;
    if (periods > 1) {
        source->estimatedDroppedFrames.fetch_add((periods - 1) * frames, std::memory_order_relaxed);
    }
}

static void DKRecordEvent(uint32_t kind, DKSource *source, OSStatus status,
                          uintptr_t caller, uint64_t value1, uint64_t value2 = 0) {
    if (!DKTapEnabled.load(std::memory_order_relaxed)) return;
    uint32_t index = DKEventCount.fetch_add(1, std::memory_order_relaxed);
    if (index >= kDKMaxEvents) {
        DKEventOverflow.fetch_add(1, std::memory_order_relaxed);
        return;
    }
    DKEvent *event = &DKEvents[index];
    event->kind = kind;
    event->sourceID = source ? source->sourceID : 0;
    event->status = status;
    event->ticks = mach_continuous_time();
    event->caller = caller;
    event->value1 = value1;
    event->value2 = value2;
    event->ready.store(1, std::memory_order_release);
}

static void DKHitSymbol(DKSymbolIndex index, OSStatus status, uintptr_t caller) {
    if (!DKTapEnabled.load(std::memory_order_relaxed)) return;
    DKSymbolCoverage &coverage = DKCoverage[index];
    uint64_t now = mach_continuous_time();
    if (coverage.hits.fetch_add(1, std::memory_order_relaxed) == 0) {
        coverage.firstTicks.store(now, std::memory_order_relaxed);
        coverage.firstCaller.store(caller, std::memory_order_relaxed);
    }
    coverage.lastTicks.store(now, std::memory_order_relaxed);
    coverage.lastCaller.store(caller, std::memory_order_relaxed);
    coverage.lastStatus.store(status, std::memory_order_relaxed);
}

// MARK: - PCM 写入（实时路径）

static int DKClaimCaptureSlot(DKSource *source, const AudioStreamBasicDescription &format) {
    int existing = source->captureSlot.load(std::memory_order_acquire);
    if (existing >= 0) return existing;
    for (uint32_t i = 0; i < kDKCaptureSlots; i++) {
        int expected = 0;
        int reservation = -(int)source->sourceID;
        if (DKPCMSlots[i].sourceID.compare_exchange_strong(expected, reservation,
                                                           std::memory_order_acq_rel)) {
            DKPCMSlots[i].format = format;
            DKPCMSlots[i].sourceID.store((int)source->sourceID, std::memory_order_release);
            source->captureSlot.store((int)i, std::memory_order_release);
            return (int)i;
        }
        if (expected == (int)source->sourceID) {
            source->captureSlot.store((int)i, std::memory_order_release);
            return (int)i;
        }
    }
    return -1;
}

static bool DKFormatCanConvert(const AudioStreamBasicDescription &format) {
    if (format.mFormatID != kAudioFormatLinearPCM || format.mChannelsPerFrame == 0 ||
        format.mSampleRate <= 0 || format.mSampleRate > kDKMaxSampleRate ||
        (format.mFormatFlags & kAudioFormatFlagIsBigEndian) ||
        !(format.mFormatFlags & kAudioFormatFlagIsPacked)) return false;
    if ((format.mFormatFlags & kAudioFormatFlagIsFloat) &&
        (format.mBitsPerChannel == 32 || format.mBitsPerChannel == 64)) return true;
    if ((format.mFormatFlags & kAudioFormatFlagIsSignedInteger) &&
        (format.mBitsPerChannel == 16 || format.mBitsPerChannel == 32)) return true;
    return false;
}

static bool DKFormatsMatch(const AudioStreamBasicDescription &l,
                           const AudioStreamBasicDescription &r) {
    return fabs(l.mSampleRate - r.mSampleRate) < 0.001 && l.mFormatID == r.mFormatID &&
           l.mFormatFlags == r.mFormatFlags && l.mBytesPerFrame == r.mBytesPerFrame &&
           l.mChannelsPerFrame == r.mChannelsPerFrame && l.mBitsPerChannel == r.mBitsPerChannel;
}

static uint32_t DKCaptureBuffer(DKSource *source, const AudioBufferList *bufferList,
                                uint32_t frameCount) {
    if (!source || !bufferList || frameCount == 0 ||
        !DKCaptureActive.load(std::memory_order_relaxed)) return 0;

    uint64_t now = mach_continuous_time();
    if (now < DKPCMStartTicks.load(std::memory_order_relaxed) ||
        now >= DKPCMStopTicks.load(std::memory_order_relaxed)) return 0;
    uint64_t begin = now;

    AudioStreamBasicDescription format = {};
    if (!DKReadSourceFormat(source, &format) || !DKFormatCanConvert(format)) {
        source->unsupportedBuffers.fetch_add(1, std::memory_order_relaxed);
        DKRecordProbeElapsed(source, begin);
        return 0;
    }

    int slotIndex = DKClaimCaptureSlot(source, format);
    if (slotIndex < 0 || !DKPCMSlots[slotIndex].samples) {
        source->captureSlotMisses.fetch_add(1, std::memory_order_relaxed);
        DKRecordProbeElapsed(source, begin);
        return 0;
    }
    if (!DKFormatsMatch(DKPCMSlots[slotIndex].format, format)) {
        source->formatMismatchBuffers.fetch_add(1, std::memory_order_relaxed);
        DKRecordProbeElapsed(source, begin);
        return 0;
    }

    if (source->captureGuard.test_and_set(std::memory_order_acquire)) {
        source->contentionDrops.fetch_add(1, std::memory_order_relaxed);
        DKRecordProbeElapsed(source, begin);
        return 0;
    }
    DKActiveWriters.fetch_add(1, std::memory_order_relaxed);

    DKPCMSlot &slot = DKPCMSlots[slotIndex];
    uint64_t written = slot.frameCount.load(std::memory_order_relaxed);
    uint64_t available = written < kDKMaxPCMFrames ? kDKMaxPCMFrames - written : 0;
    uint32_t capacity = (uint32_t)std::min<uint64_t>(available, UINT32_MAX);
    if (capacity < frameCount) {
        source->pcmCapacityDroppedFrames.fetch_add(frameCount - capacity, std::memory_order_relaxed);
    }
    uint64_t unreadable = 0;
    uint32_t count = DKAudioSignalDownmix(bufferList, &format, frameCount,
                                          slot.samples + written, capacity, &unreadable);
    if (unreadable) source->unreadableFrames.fetch_add(unreadable, std::memory_order_relaxed);
    slot.frameCount.store(written + count, std::memory_order_release);

    DKRecordProbeElapsed(source, begin);
    DKActiveWriters.fetch_sub(1, std::memory_order_relaxed);
    source->captureGuard.clear(std::memory_order_release);
    return count;
}

// MARK: - 实时电平旁路

// 音频渲染线程执行。认领一个环槽位；抢不到（已满 4 路）就永久放弃，返回 -1。
static int DKClaimLiveRing(DKSource *source) {
    int ring = source->liveRing.load(std::memory_order_acquire);
    if (ring >= 0) return ring;
    if (ring < -1) return -1;                    // -2 表示试过且抢不到

    uint32_t claimed = DKLiveRingsClaimed.load(std::memory_order_relaxed);
    while (claimed < kDKLiveRings) {
        if (DKLiveRingsClaimed.compare_exchange_weak(claimed, claimed + 1,
                                                     std::memory_order_acq_rel,
                                                     std::memory_order_relaxed)) {
            source->liveWrite.store(0, std::memory_order_relaxed);
            source->liveRing.store((int)claimed, std::memory_order_release);
            return (int)claimed;
        }
    }
    source->liveRing.store(-2, std::memory_order_release);
    return -1;
}

// 音频渲染线程执行。下混一块进栈上缓冲，再拷进滚动环，顺手更新能量与时刻。
// 与 DKCaptureBuffer 各走各的：采集窗口开没开都不影响这里。
static void DKPublishLive(DKSource *source, const AudioBufferList *bufferList, uint32_t frameCount) {
    if (!source || !bufferList || frameCount == 0) return;
    if (!DKLiveEnabled.load(std::memory_order_relaxed)) return;

    AudioStreamBasicDescription format = {};
    if (!DKReadSourceFormat(source, &format) || !DKFormatCanConvert(format)) return;

    int ring = DKClaimLiveRing(source);
    if (ring < 0) return;

    float block[kDKLiveBlockFrames];
    uint32_t want = std::min(frameCount, kDKLiveBlockFrames);
    uint64_t unreadable = 0;
    uint32_t count = DKAudioSignalDownmix(bufferList, &format, want, block,
                                          kDKLiveBlockFrames, &unreadable);
    if (count == 0) return;

    uint64_t write = source->liveWrite.load(std::memory_order_relaxed);
    uint32_t head = (uint32_t)(write & kDKLiveRingMask);
    uint32_t first = std::min(count, kDKLiveRingFrames - head);
    memcpy(DKLiveRing[ring] + head, block, first * sizeof(float));
    if (count > first) memcpy(DKLiveRing[ring], block + first, (count - first) * sizeof(float));
    source->liveWrite.store(write + count, std::memory_order_release);

    double sum = 0.0;
    for (uint32_t i = 0; i < count; i++) sum += (double)block[i] * block[i];
    float rms = (float)sqrt(sum / count);
    // 选源用的能量：上升立刻跟上，下降留一点惯性，避免在块间抖动时来回换源。
    float previous = source->liveEnergy.load(std::memory_order_relaxed);
    source->liveEnergy.store(rms > previous ? rms : previous + (rms - previous) * 0.25f,
                             std::memory_order_relaxed);
    source->liveSampleRate.store(format.mSampleRate, std::memory_order_relaxed);
    source->liveTicks.store(mach_continuous_time(), std::memory_order_release);
}

// MARK: - 只读旁路

// 音频渲染线程执行。四条 relaxed store，记最近一次 ioData 的真实排布。
static void DKRecordBufferLayout(DKSource *source, const AudioBufferList *data, uint32_t frames) {
    if (!source || !data || data->mNumberBuffers == 0) return;
    const AudioBuffer &first = data->mBuffers[0];
    source->layoutNumberBuffers.store(data->mNumberBuffers, std::memory_order_relaxed);
    source->layoutChannelsPerBuffer.store(first.mNumberChannels, std::memory_order_relaxed);
    source->layoutDataByteSize.store(first.mDataByteSize, std::memory_order_relaxed);
    source->layoutRenderFrames.store(frames, std::memory_order_relaxed);
}

// 音频渲染线程执行。只在 PostRender 且无错误时读一次 ioData，然后原样返回。
static OSStatus DKRenderNotify(void *refCon,
                               AudioUnitRenderActionFlags *flags,
                               const AudioTimeStamp *timestamp,
                               UInt32 bus,
                               UInt32 frames,
                               AudioBufferList *data) {
    (void)timestamp;
    if (!flags || !(*flags & kAudioUnitRenderAction_PostRender)) return noErr;
    if (*flags & kAudioUnitRenderAction_PostRenderError) return noErr;
    if (bus != 0) return noErr;   // 输出单元的输出 element 固定为 0
    DKSource *source = (DKSource *)refCon;
    if (!source || !DKTapEnabled.load(std::memory_order_relaxed)) return noErr;
    DKRecordCallbackActivity(source, frames, noErr);
    if (data) {
        DKRecordBufferLayout(source, data, frames);
        DKPublishLive(source, data, frames);
        DKCaptureBuffer(source, data, frames);
    }
    return noErr;
}

// 输出单元送进 RemoteIO 的客户端格式在 Input scope element 0。必须在非实时线程读好。
static void DKCacheOutputUnitFormat(AudioUnit unit, DKSource *source) {
    if (!unit || !source) return;
    AudioStreamBasicDescription format = {};
    UInt32 size = sizeof(format);
    if (AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Input, 0, &format, &size) != noErr) return;
    if (format.mSampleRate <= 0 || format.mChannelsPerFrame == 0) return;
    AudioStreamBasicDescription current = {};
    if (DKReadSourceFormat(source, &current) && DKFormatsMatch(current, format)) return;
    DKWriteSourceFormat(source, &format);
    DKAppendFormatRecord(source, kAudioUnitScope_Input, &format);
}

static void DKInstallRenderNotify(AudioUnit unit, DKSource *source, uintptr_t caller) {
    if (!unit || !source) return;
    int expected = 0;
    if (!source->notifyInstalled.compare_exchange_strong(expected, 1, std::memory_order_acq_rel)) return;
    OSStatus status = AudioUnitAddRenderNotify(unit, DKRenderNotify, source);
    source->notifyStatus.store(status, std::memory_order_relaxed);
    if (status != noErr) source->notifyInstalled.store(0, std::memory_order_release);
    DKRecordEvent(DKEventRenderNotifyInstall, source, status, caller, (uintptr_t)unit);
}

static void DKRemoveRenderNotify(AudioUnit unit, DKSource *source) {
    if (!unit || !source) return;
    if (source->notifyInstalled.exchange(0, std::memory_order_acq_rel) == 0) return;
    AudioUnitRemoveRenderNotify(unit, DKRenderNotify, source);
}

// MARK: - 原始函数

static OSStatus (*DKOrigComponentNew)(AudioComponent, AudioComponentInstance *);
static OSStatus (*DKOrigComponentDispose)(AudioComponentInstance);
static OSStatus (*DKOrigUnitInitialize)(AudioUnit);
static OSStatus (*DKOrigOutputStart)(AudioUnit);
static OSStatus (*DKOrigOutputStop)(AudioUnit);
static OSStatus (*DKOrigQueueNewOutput)(const AudioStreamBasicDescription *, AudioQueueOutputCallback, void *, CFRunLoopRef, CFStringRef, UInt32, AudioQueueRef *);
static OSStatus (*DKOrigQueueNewOutputDispatch)(AudioQueueRef *, const AudioStreamBasicDescription *, UInt32, dispatch_queue_t, AudioQueueOutputCallbackBlock);
static OSStatus (*DKOrigQueueStart)(AudioQueueRef, const AudioTimeStamp *);
static OSStatus (*DKOrigQueueStop)(AudioQueueRef, Boolean);
static OSStatus (*DKOrigQueueDispose)(AudioQueueRef, Boolean);
static OSStatus (*DKOrigQueueEnqueue)(AudioQueueRef, AudioQueueBufferRef, UInt32, const AudioStreamPacketDescription *);
static OSStatus (*DKOrigTapCreate)(CFAllocatorRef, const MTAudioProcessingTapCallbacks *, MTAudioProcessingTapCreationFlags, MTAudioProcessingTapRef *);

// MARK: - 包装

static OSStatus DKHookComponentNew(AudioComponent component, AudioComponentInstance *instanceOut) {
    uintptr_t caller = DK_CALLER();
    OSStatus status = DKOrigComponentNew ? DKOrigComponentNew(component, instanceOut) : kAudio_ParamError;
    if (!DKTapEnabled.load(std::memory_order_relaxed)) return status;
    DKHitSymbol(DKSymbolComponentNew, status, caller);
    DKSource *source = nullptr;
    if (status == noErr && instanceOut && *instanceOut) {
        source = DKCreateSource((uintptr_t)*instanceOut, DKAudioTapSourceKindAudioUnit, nullptr);
        AudioComponentDescription description = {};
        if (source && component && AudioComponentGetDescription(component, &description) == noErr) {
            source->componentType = description.componentType;
            source->componentSubType = description.componentSubType;
            source->componentManufacturer = description.componentManufacturer;
        }
    }
    DKRecordEvent(DKEventComponentNew, source, status, caller,
                  instanceOut ? (uintptr_t)*instanceOut : 0);
    return status;
}

static OSStatus DKHookComponentDispose(AudioComponentInstance instance) {
    uintptr_t caller = DK_CALLER();
    DKSource *source = DKTapEnabled.load(std::memory_order_relaxed)
        ? DKFindSource((uintptr_t)instance, DKAudioTapSourceKindAudioUnit) : nullptr;
    // 必须在实例失效之前摘掉 notify，否则回调指针悬空。
    if (source) DKRemoveRenderNotify(instance, source);
    OSStatus status = DKOrigComponentDispose ? DKOrigComponentDispose(instance) : kAudio_ParamError;
    if (!DKTapEnabled.load(std::memory_order_relaxed)) return status;
    DKHitSymbol(DKSymbolComponentDispose, status, caller);
    if (source && status == noErr) {
        source->active.store(0, std::memory_order_relaxed);
        source->disposed.store(1, std::memory_order_relaxed);
    }
    DKRecordEvent(DKEventComponentDispose, source, status, caller, (uintptr_t)instance);
    return status;
}

static OSStatus DKHookUnitInitialize(AudioUnit unit) {
    OSStatus status = DKOrigUnitInitialize ? DKOrigUnitInitialize(unit) : kAudio_ParamError;
    if (!DKTapEnabled.load(std::memory_order_relaxed)) return status;
    uintptr_t caller = DK_CALLER();
    DKHitSymbol(DKSymbolUnitInitialize, status, caller);
    DKSource *source = DKFindSource((uintptr_t)unit, DKAudioTapSourceKindAudioUnit);
    if (source && status == noErr) DKCacheOutputUnitFormat(unit, source);
    DKRecordEvent(DKEventUnitInitialize, source, status, caller, (uintptr_t)unit);
    return status;
}

static OSStatus DKHookOutputStart(AudioUnit unit) {
    OSStatus status = DKOrigOutputStart ? DKOrigOutputStart(unit) : kAudio_ParamError;
    if (!DKTapEnabled.load(std::memory_order_relaxed)) return status;
    uintptr_t caller = DK_CALLER();
    DKHitSymbol(DKSymbolOutputStart, status, caller);
    // 只有被 AudioOutputUnitStart 启动过的实例才是输出单元，也只有它值得挂旁路。
    DKSource *source = DKCreateSource((uintptr_t)unit, DKAudioTapSourceKindAudioUnit, nullptr);
    if (source && status == noErr) {
        source->active.store(1, std::memory_order_relaxed);
        DKCacheOutputUnitFormat(unit, source);
        DKInstallRenderNotify(unit, source, caller);
    }
    if (source) source->lastStatus.store(status, std::memory_order_relaxed);
    DKRecordEvent(DKEventOutputStart, source, status, caller, (uintptr_t)unit);
    return status;
}

static OSStatus DKHookOutputStop(AudioUnit unit) {
    OSStatus status = DKOrigOutputStop ? DKOrigOutputStop(unit) : kAudio_ParamError;
    if (!DKTapEnabled.load(std::memory_order_relaxed)) return status;
    uintptr_t caller = DK_CALLER();
    DKHitSymbol(DKSymbolOutputStop, status, caller);
    DKSource *source = DKFindSource((uintptr_t)unit, DKAudioTapSourceKindAudioUnit);
    // notify 留着：同一只 unit 常被反复启停，重复装卸没有收益。
    if (source && status == noErr) source->active.store(0, std::memory_order_relaxed);
    DKRecordEvent(DKEventOutputStop, source, status, caller, (uintptr_t)unit);
    return status;
}

static OSStatus DKHookQueueNewOutput(const AudioStreamBasicDescription *format,
                                     AudioQueueOutputCallback callback,
                                     void *userData,
                                     CFRunLoopRef runLoop,
                                     CFStringRef mode,
                                     UInt32 flags,
                                     AudioQueueRef *queueOut) {
    uintptr_t caller = DK_CALLER();
    OSStatus status = DKOrigQueueNewOutput
        ? DKOrigQueueNewOutput(format, callback, userData, runLoop, mode, flags, queueOut)
        : kAudio_ParamError;
    if (!DKTapEnabled.load(std::memory_order_relaxed)) return status;
    DKHitSymbol(DKSymbolQueueNewOutput, status, caller);
    DKSource *source = status == noErr && queueOut && *queueOut
        ? DKCreateSource((uintptr_t)*queueOut, DKAudioTapSourceKindAudioQueue, format) : nullptr;
    DKRecordEvent(DKEventQueueNew, source, status, caller, queueOut ? (uintptr_t)*queueOut : 0, flags);
    return status;
}

static OSStatus DKHookQueueNewOutputDispatch(AudioQueueRef *queueOut,
                                             const AudioStreamBasicDescription *format,
                                             UInt32 flags,
                                             dispatch_queue_t queue,
                                             AudioQueueOutputCallbackBlock block) {
    uintptr_t caller = DK_CALLER();
    OSStatus status = DKOrigQueueNewOutputDispatch
        ? DKOrigQueueNewOutputDispatch(queueOut, format, flags, queue, block) : kAudio_ParamError;
    if (!DKTapEnabled.load(std::memory_order_relaxed)) return status;
    DKHitSymbol(DKSymbolQueueNewOutputDispatch, status, caller);
    DKSource *source = status == noErr && queueOut && *queueOut
        ? DKCreateSource((uintptr_t)*queueOut, DKAudioTapSourceKindAudioQueue, format) : nullptr;
    DKRecordEvent(DKEventQueueNew, source, status, caller, queueOut ? (uintptr_t)*queueOut : 0, flags);
    return status;
}

static OSStatus DKHookQueueStart(AudioQueueRef queue, const AudioTimeStamp *time) {
    OSStatus status = DKOrigQueueStart ? DKOrigQueueStart(queue, time) : kAudio_ParamError;
    if (!DKTapEnabled.load(std::memory_order_relaxed)) return status;
    uintptr_t caller = DK_CALLER();
    DKHitSymbol(DKSymbolQueueStart, status, caller);
    DKSource *source = DKFindSource((uintptr_t)queue, DKAudioTapSourceKindAudioQueue);
    if (source && status == noErr) source->active.store(1, std::memory_order_relaxed);
    DKRecordEvent(DKEventQueueStart, source, status, caller, (uintptr_t)queue);
    return status;
}

static OSStatus DKHookQueueStop(AudioQueueRef queue, Boolean immediate) {
    OSStatus status = DKOrigQueueStop ? DKOrigQueueStop(queue, immediate) : kAudio_ParamError;
    if (!DKTapEnabled.load(std::memory_order_relaxed)) return status;
    uintptr_t caller = DK_CALLER();
    DKHitSymbol(DKSymbolQueueStop, status, caller);
    DKSource *source = DKFindSource((uintptr_t)queue, DKAudioTapSourceKindAudioQueue);
    if (source && status == noErr) source->active.store(0, std::memory_order_relaxed);
    DKRecordEvent(DKEventQueueStop, source, status, caller, (uintptr_t)queue, immediate);
    return status;
}

static OSStatus DKHookQueueDispose(AudioQueueRef queue, Boolean immediate) {
    OSStatus status = DKOrigQueueDispose ? DKOrigQueueDispose(queue, immediate) : kAudio_ParamError;
    if (!DKTapEnabled.load(std::memory_order_relaxed)) return status;
    uintptr_t caller = DK_CALLER();
    DKHitSymbol(DKSymbolQueueDispose, status, caller);
    DKSource *source = DKFindSource((uintptr_t)queue, DKAudioTapSourceKindAudioQueue);
    if (source && status == noErr) {
        source->active.store(0, std::memory_order_relaxed);
        source->disposed.store(1, std::memory_order_relaxed);
    }
    DKRecordEvent(DKEventQueueDispose, source, status, caller, (uintptr_t)queue, immediate);
    return status;
}

// AudioQueue 走的是「入队即将播放的缓冲」，比 AudioUnit 旁路多一个缓冲的延迟，
// 但同样不改数据。这条是 AudioUnit 路径不成立时的兜底取样口。
static OSStatus DKHookQueueEnqueue(AudioQueueRef queue,
                                   AudioQueueBufferRef buffer,
                                   UInt32 packetCount,
                                   const AudioStreamPacketDescription *packets) {
    if (!DKTapEnabled.load(std::memory_order_relaxed)) {
        return DKOrigQueueEnqueue ? DKOrigQueueEnqueue(queue, buffer, packetCount, packets)
                                  : kAudio_ParamError;
    }
    uintptr_t caller = DK_CALLER();
    DKSource *source = DKFindSource((uintptr_t)queue, DKAudioTapSourceKindAudioQueue);
    uint32_t frames = 0;
    if (source && buffer && buffer->mAudioData && buffer->mAudioDataByteSize > 0) {
        AudioStreamBasicDescription format = {};
        if (DKReadSourceFormat(source, &format) && format.mBytesPerFrame > 0) {
            frames = buffer->mAudioDataByteSize / format.mBytesPerFrame;
            struct {
                UInt32 count;
                AudioBuffer buffer;
            } list = { 1, { format.mChannelsPerFrame, buffer->mAudioDataByteSize, buffer->mAudioData } };
            DKCaptureBuffer(source, (const AudioBufferList *)&list, frames);
        }
    }
    OSStatus status = DKOrigQueueEnqueue
        ? DKOrigQueueEnqueue(queue, buffer, packetCount, packets) : kAudio_ParamError;
    DKHitSymbol(DKSymbolQueueEnqueue, status, caller);
    if (source) DKRecordCallbackActivity(source, frames, status);
    if (DKCaptureActive.load(std::memory_order_relaxed)) {
        DKRecordEvent(DKEventQueueEnqueue, source, status, caller,
                      buffer ? buffer->mAudioDataByteSize : 0, packetCount);
    }
    return status;
}

// 只登记「有没有人用 AVPlayer 的音频 tap」，不接管它的 process 回调。
static OSStatus DKHookTapCreate(CFAllocatorRef allocator,
                                const MTAudioProcessingTapCallbacks *callbacks,
                                MTAudioProcessingTapCreationFlags flags,
                                MTAudioProcessingTapRef *tapOut) {
    uintptr_t caller = DK_CALLER();
    OSStatus status = DKOrigTapCreate ? DKOrigTapCreate(allocator, callbacks, flags, tapOut)
                                      : kAudio_ParamError;
    if (!DKTapEnabled.load(std::memory_order_relaxed)) return status;
    DKHitSymbol(DKSymbolTapCreate, status, caller);
    DKSource *source = status == noErr && tapOut && *tapOut
        ? DKCreateSource((uintptr_t)*tapOut, DKAudioTapSourceKindMediaTap, nullptr) : nullptr;
    DKRecordEvent(DKEventMediaTapCreate, source, status, caller,
                  tapOut ? (uintptr_t)*tapOut : 0, flags);
    return status;
}

static void DKInstallRebindings(void) {
    for (uint32_t i = 0; i < DKSymbolCount; i++) {
        DKCoverage[i].original = dlsym(RTLD_DEFAULT, DKSymbolNames[i]);
        DKCoverage[i].rebindResult = -1;
    }
#define DK_RESOLVE(VAR, INDEX) VAR = reinterpret_cast<decltype(VAR)>(DKCoverage[INDEX].original)
    DK_RESOLVE(DKOrigComponentNew, DKSymbolComponentNew);
    DK_RESOLVE(DKOrigComponentDispose, DKSymbolComponentDispose);
    DK_RESOLVE(DKOrigUnitInitialize, DKSymbolUnitInitialize);
    DK_RESOLVE(DKOrigOutputStart, DKSymbolOutputStart);
    DK_RESOLVE(DKOrigOutputStop, DKSymbolOutputStop);
    DK_RESOLVE(DKOrigQueueNewOutput, DKSymbolQueueNewOutput);
    DK_RESOLVE(DKOrigQueueNewOutputDispatch, DKSymbolQueueNewOutputDispatch);
    DK_RESOLVE(DKOrigQueueStart, DKSymbolQueueStart);
    DK_RESOLVE(DKOrigQueueStop, DKSymbolQueueStop);
    DK_RESOLVE(DKOrigQueueDispose, DKSymbolQueueDispose);
    DK_RESOLVE(DKOrigQueueEnqueue, DKSymbolQueueEnqueue);
    DK_RESOLVE(DKOrigTapCreate, DKSymbolTapCreate);
#undef DK_RESOLVE

    struct dk_rebinding bindings[DKSymbolCount] = {
        { DKSymbolNames[DKSymbolComponentNew], (void *)DKHookComponentNew, nullptr },
        { DKSymbolNames[DKSymbolComponentDispose], (void *)DKHookComponentDispose, nullptr },
        { DKSymbolNames[DKSymbolUnitInitialize], (void *)DKHookUnitInitialize, nullptr },
        { DKSymbolNames[DKSymbolOutputStart], (void *)DKHookOutputStart, nullptr },
        { DKSymbolNames[DKSymbolOutputStop], (void *)DKHookOutputStop, nullptr },
        { DKSymbolNames[DKSymbolQueueNewOutput], (void *)DKHookQueueNewOutput, nullptr },
        { DKSymbolNames[DKSymbolQueueNewOutputDispatch], (void *)DKHookQueueNewOutputDispatch, nullptr },
        { DKSymbolNames[DKSymbolQueueStart], (void *)DKHookQueueStart, nullptr },
        { DKSymbolNames[DKSymbolQueueStop], (void *)DKHookQueueStop, nullptr },
        { DKSymbolNames[DKSymbolQueueDispose], (void *)DKHookQueueDispose, nullptr },
        { DKSymbolNames[DKSymbolQueueEnqueue], (void *)DKHookQueueEnqueue, nullptr },
        { DKSymbolNames[DKSymbolTapCreate], (void *)DKHookTapCreate, nullptr },
    };
    int result = dk_rebind_symbols(bindings, DKSymbolCount);
    for (uint32_t i = 0; i < DKSymbolCount; i++) DKCoverage[i].rebindResult = result;
}

} // namespace

// MARK: - 对外接口

void DKAudioTapInstall(void) {
    bool expected = false;
    if (!DKTapInstalled.compare_exchange_strong(expected, true, std::memory_order_acq_rel)) return;
    mach_timebase_info(&DKTimebase);
    DKInstallRebindings();
}

void DKAudioTapSetEnabled(BOOL enabled) {
    DKTapEnabled.store(enabled, std::memory_order_release);
    if (!enabled) DKCaptureActive.store(false, std::memory_order_release);
}

// MARK: - 实时电平旁路（读侧，主线程）

void DKAudioTapSetLiveMeteringEnabled(BOOL enabled) {
    DKLiveEnabled.store(enabled, std::memory_order_release);
}

BOOL DKAudioTapIsLiveMeteringEnabled(void) {
    return DKLiveEnabled.load(std::memory_order_acquire);
}

// 挑当前最响、且还在活动的那一路。
//
// beta2 实测抖音同时跑两只 RemoteIO，其中一只全程恒零——取"第一路"会永远画不出东西，
// 必须按能量选。staleSeconds 之外的源不参选，否则一首歌停了还会锁在旧源上。
static DKSource *DKLoudestLiveSource(double staleSeconds, uint64_t now) {
    uint32_t count = DKSourceCount.load(std::memory_order_acquire);
    DKSource *best = nullptr;
    float bestEnergy = -1.0f;
    for (uint32_t i = 0; i < count; i++) {
        DKSource *source = &DKSources[i];
        if (source->liveRing.load(std::memory_order_acquire) < 0) continue;
        uint64_t ticks = source->liveTicks.load(std::memory_order_acquire);
        if (ticks == 0 || now < ticks) continue;
        if (DKTicksToSeconds(now - ticks) > staleSeconds) continue;
        float energy = source->liveEnergy.load(std::memory_order_relaxed);
        if (energy > bestEnergy) { bestEnergy = energy; best = source; }
    }
    return best;
}

uint32_t DKAudioTapCopyLatestSamples(float *out, uint32_t count, double *sampleRateOut) {
    if (!out || count == 0 || count > kDKLiveRingFrames) return 0;
    if (!DKLiveEnabled.load(std::memory_order_acquire)) return 0;

    DKSource *source = DKLoudestLiveSource(0.25, mach_continuous_time());
    if (!source) return 0;
    int ring = source->liveRing.load(std::memory_order_acquire);
    if (ring < 0 || ring >= (int)kDKLiveRings) return 0;

    uint64_t before = source->liveWrite.load(std::memory_order_acquire);
    if (before < count) return 0;                 // 环还没填满一个分析窗

    uint32_t start = (uint32_t)((before - count) & kDKLiveRingMask);
    uint32_t first = std::min(count, kDKLiveRingFrames - start);
    memcpy(out, DKLiveRing[ring] + start, first * sizeof(float));
    if (count > first) memcpy(out + first, DKLiveRing[ring], (count - first) * sizeof(float));

    // 拷贝期间实时侧可能已经绕回来盖掉了我们正在读的那一段。复读游标判定：
    // 写入前进超过"环长 − 窗长"就说明被追上了，这一帧直接丢（60 Hz 下看不出来）。
    uint64_t after = source->liveWrite.load(std::memory_order_acquire);
    if (after - before > kDKLiveRingFrames - count) return 0;

    if (sampleRateOut) {
        double rate = source->liveSampleRate.load(std::memory_order_relaxed);
        *sampleRateOut = rate > 0 ? rate : 48000.0;
    }
    return count;
}

BOOL DKAudioTapHasRecentAudio(double withinSeconds) {
    if (!DKLiveEnabled.load(std::memory_order_acquire)) return NO;
    return DKLoudestLiveSource(withinSeconds, mach_continuous_time()) != nullptr;
}

BOOL DKAudioTapIsInstalled(void) {
    return DKTapInstalled.load(std::memory_order_acquire);
}

BOOL DKAudioTapIsCapturing(void) {
    return DKCaptureActive.load(std::memory_order_acquire);
}

uint64_t DKAudioTapCaptureStartTicks(void) {
    return DKCaptureStartTicks.load(std::memory_order_acquire);
}

uint64_t DKAudioTapCaptureStopTicks(void) {
    return DKCaptureStopTicks.load(std::memory_order_acquire);
}

double DKAudioTapSecondsFromTicks(uint64_t ticks) {
    return DKTicksToSeconds(ticks);
}

double DKAudioTapSecondsRelativeTo(uint64_t ticks, uint64_t origin) {
    return DKRelativeSeconds(ticks, origin);
}

double DKAudioTapCurrentCaptureSecond(void) {
    uint64_t start = DKCaptureStartTicks.load(std::memory_order_acquire);
    return start ? DKRelativeSeconds(mach_continuous_time(), start) : -1.0;
}

BOOL DKAudioTapBeginCapture(double warmupSeconds, double recordSeconds) {
    if (!DKTapInstalled.load(std::memory_order_acquire) ||
        !DKTapEnabled.load(std::memory_order_acquire) ||
        warmupSeconds < 0 || recordSeconds <= 0 || recordSeconds > kDKMaxPCMSeconds) return NO;

    os_unfair_lock_lock(&DKCaptureControlLock);
    if (DKCaptureActive.load(std::memory_order_acquire)) {
        os_unfair_lock_unlock(&DKCaptureControlLock);
        return NO;
    }

    DKCaptureStartTicks.store(0, std::memory_order_release);
    DKCaptureStopTicks.store(0, std::memory_order_release);
    DKPCMAllocationFailures.store(0, std::memory_order_relaxed);
    BOOL anySlot = NO;
    for (uint32_t i = 0; i < kDKCaptureSlots; i++) {
        if (!DKPCMSlots[i].samples) DKPCMSlots[i].samples = (float *)calloc(kDKMaxPCMFrames, sizeof(float));
        if (DKPCMSlots[i].samples) anySlot = YES;
        else DKPCMAllocationFailures.fetch_add(1, std::memory_order_relaxed);
        DKPCMSlots[i].sourceID.store(0, std::memory_order_relaxed);
        DKPCMSlots[i].frameCount.store(0, std::memory_order_relaxed);
        DKPCMSlots[i].format = {};
    }
    if (!anySlot) {
        os_unfair_lock_unlock(&DKCaptureControlLock);
        return NO;
    }

    uint32_t sourceCount = DKSourceCount.load(std::memory_order_acquire);
    for (uint32_t i = 0; i < sourceCount; i++) {
        DKSource &source = DKSources[i];
        source.captureSlot.store(-1, std::memory_order_relaxed);
        source.firstCallbackTicks.store(0, std::memory_order_relaxed);
        source.previousCallbackTicks.store(0, std::memory_order_relaxed);
        source.callbackIntervalCount.store(0, std::memory_order_relaxed);
        source.callbackIntervalTicks.store(0, std::memory_order_relaxed);
        source.minCallbackIntervalTicks.store(0, std::memory_order_relaxed);
        source.maxCallbackIntervalTicks.store(0, std::memory_order_relaxed);
        source.estimatedDroppedFrames.store(0, std::memory_order_relaxed);
        source.contentionDrops.store(0, std::memory_order_relaxed);
        source.unsupportedBuffers.store(0, std::memory_order_relaxed);
        source.unreadableFrames.store(0, std::memory_order_relaxed);
        source.captureSlotMisses.store(0, std::memory_order_relaxed);
        source.formatMismatchBuffers.store(0, std::memory_order_relaxed);
        source.pcmCapacityDroppedFrames.store(0, std::memory_order_relaxed);
        source.probeTicks.store(0, std::memory_order_relaxed);
        source.probeBlocks.store(0, std::memory_order_relaxed);
        source.maxProbeTicks.store(0, std::memory_order_relaxed);
    }

    uint64_t start = mach_continuous_time();
    uint64_t pcmStart = start + DKNanosecondsToTicks((uint64_t)(warmupSeconds * 1.0e9));
    DKCaptureStartTicks.store(start, std::memory_order_release);
    DKPCMStartTicks.store(pcmStart, std::memory_order_release);
    DKPCMStopTicks.store(pcmStart + DKNanosecondsToTicks((uint64_t)(recordSeconds * 1.0e9)),
                         std::memory_order_release);
    DKCaptureActive.store(true, std::memory_order_release);
    os_unfair_lock_unlock(&DKCaptureControlLock);
    return YES;
}

void DKAudioTapEndCapture(void) {
    DKCaptureActive.store(false, std::memory_order_release);
    uint64_t zero = 0;
    DKCaptureStopTicks.compare_exchange_strong(zero, mach_continuous_time(),
                                               std::memory_order_release,
                                               std::memory_order_relaxed);
}

void DKAudioTapWaitForWriters(void) {
    for (int attempt = 0; attempt < 100 && DKActiveWriters.load(std::memory_order_acquire) > 0; attempt++) {
        usleep(1000);
    }
}

uint32_t DKAudioTapSlotCount(void) {
    return kDKCaptureSlots;
}

BOOL DKAudioTapReadSlot(uint32_t index, DKAudioTapSlot *out) {
    if (index >= kDKCaptureSlots || !out) return NO;
    int sourceID = DKPCMSlots[index].sourceID.load(std::memory_order_acquire);
    uint64_t frames = DKPCMSlots[index].frameCount.load(std::memory_order_acquire);
    if (sourceID <= 0 || frames == 0 || !DKPCMSlots[index].samples) return NO;
    out->sourceID = (uint32_t)sourceID;
    out->kind = (uint32_t)sourceID <= kDKMaxSources ? DKSources[sourceID - 1].kind : 0;
    out->samples = DKPCMSlots[index].samples;
    out->frameCount = frames;
    out->sampleRate = DKPCMSlots[index].format.mSampleRate;
    out->sourceFormat = DKPCMSlots[index].format;
    return YES;
}

// ioData 的实测排布，以及它与缓存 ASBD 的说法是否一致。
//
// 两者本来就允许不一致：ASBD 来自 kAudioUnitScope_Input，描述的是抖音推进去的格式；
// ioData 是 unit 填完之后交给硬件的那份。0.5.2-beta2 在设备上就是「ASBD 说交错、
// ioData 是 2 buffer × 1 声道」，按 ASBD 读会读错——下混因此改为只信这里的数字。
static NSDictionary *DKBufferLayoutJSON(DKSource *source) {
    uint32_t buffers = source->layoutNumberBuffers.load(std::memory_order_relaxed);
    if (buffers == 0) return @{};   // 窗口内没有回调，没量到

    uint32_t channels = source->layoutChannelsPerBuffer.load(std::memory_order_relaxed);
    uint32_t byteSize = source->layoutDataByteSize.load(std::memory_order_relaxed);
    uint32_t renderFrames = source->layoutRenderFrames.load(std::memory_order_relaxed);

    AudioStreamBasicDescription format = {};
    BOOL hasFormat = DKReadSourceFormat(source, &format);
    uint32_t bytesPerSample = hasFormat ? format.mBitsPerChannel / 8 : 0;
    uint32_t stride = channels * bytesPerSample;
    uint32_t framesPerBuffer = stride ? byteSize / stride : 0;

    // ASBD 声称非交错就该是「每 buffer 一个声道」，声称交错就该是「单 buffer 承载全部声道」。
    BOOL declaredNonInterleaved = hasFormat &&
        (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    BOOL actualNonInterleaved = buffers > 1 || (channels == 1 && format.mChannelsPerFrame > 1);

    return @{
        @"numberBuffers": @(buffers),
        @"channelsPerBuffer": @(channels),
        @"dataByteSizePerBuffer": @(byteSize),
        @"framesPerBuffer": @(framesPerBuffer),
        @"renderFrames": @(renderFrames),
        @"coversRenderFrames": @(framesPerBuffer >= renderFrames),
        @"declaredNonInterleaved": @(declaredNonInterleaved),
        @"actualNonInterleaved": @(actualNonInterleaved),
        @"matchesDeclaredFormat": @(declaredNonInterleaved == actualNonInterleaved),
    };
}

NSArray<NSDictionary *> *DKAudioTapBackendsJSON(void) {
    uint64_t captureStart = DKCaptureStartTicks.load(std::memory_order_relaxed);
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    uint32_t count = DKSourceCount.load(std::memory_order_acquire);
    for (uint32_t i = 0; i < count; i++) {
        DKSource *source = &DKSources[i];
        AudioStreamBasicDescription format = {};
        BOOL hasFormat = DKReadSourceFormat(source, &format);

        NSMutableArray *history = [NSMutableArray array];
        uint32_t records = std::min<uint32_t>(source->formatRecordCount.load(std::memory_order_acquire),
                                              kDKMaxFormatRecords);
        for (uint32_t r = 0; r < records; r++) {
            DKFormatRecord &record = source->formatRecords[r];
            uint32_t before = record.version.load(std::memory_order_acquire);
            if (before == 0 || (before & 1)) continue;
            uint32_t scope = record.scope;
            uint64_t ticks = record.ticks;
            AudioStreamBasicDescription recorded = record.format;
            if (record.version.load(std::memory_order_acquire) != before) continue;
            [history addObject:@{
                @"scope": @(scope),
                @"ticks": @(ticks),
                @"second": @(DKRelativeSeconds(ticks, captureStart)),
                @"asbd": DKASBDJSON(recorded),
            }];
        }

        uint64_t intervalCount = source->callbackIntervalCount.load(std::memory_order_relaxed);
        uint64_t intervalTicks = source->callbackIntervalTicks.load(std::memory_order_relaxed);
        uint64_t probeBlocks = source->probeBlocks.load(std::memory_order_relaxed);
        uint64_t probeTicks = source->probeTicks.load(std::memory_order_relaxed);
        [result addObject:@{
            @"sourceID": [NSString stringWithFormat:@"source-%02u", source->sourceID],
            @"kind": DKSourceKindName(source->kind),
            @"handle": DKPointerString(source->handle.load(std::memory_order_relaxed)),
            @"active": @(source->active.load(std::memory_order_relaxed) != 0),
            @"disposed": @(source->disposed.load(std::memory_order_relaxed) != 0),
            @"renderNotifyInstalled": @(source->notifyInstalled.load(std::memory_order_relaxed) != 0),
            @"renderNotifyStatus": @(source->notifyStatus.load(std::memory_order_relaxed)),
            @"componentType": DKFourCC(source->componentType),
            @"componentSubType": DKFourCC(source->componentSubType),
            @"componentManufacturer": DKFourCC(source->componentManufacturer),
            @"format": hasFormat ? DKASBDJSON(format) : @{},
            @"formatHistory": history,
            @"bufferLayout": DKBufferLayoutJSON(source),
            @"hits": @(source->hits.load(std::memory_order_relaxed)),
            @"frames": @(source->frames.load(std::memory_order_relaxed)),
            @"lastStatus": @(source->lastStatus.load(std::memory_order_relaxed)),
            @"lastActivitySecond": @(DKRelativeSeconds(source->lastTicks.load(std::memory_order_relaxed), captureStart)),
            @"firstCaptureCallbackSecond": @(DKRelativeSeconds(source->firstCallbackTicks.load(std::memory_order_relaxed), captureStart)),
            @"captureSlot": @(source->captureSlot.load(std::memory_order_relaxed)),
            @"callbackTiming": @{
                @"intervalCount": @(intervalCount),
                @"meanMilliseconds": @(intervalCount ? DKTicksToSeconds(intervalTicks / intervalCount) * 1000.0 : 0),
                @"minMilliseconds": @(DKTicksToSeconds(source->minCallbackIntervalTicks.load(std::memory_order_relaxed)) * 1000.0),
                @"maxMilliseconds": @(DKTicksToSeconds(source->maxCallbackIntervalTicks.load(std::memory_order_relaxed)) * 1000.0),
                @"estimatedDroppedFrames": @(source->estimatedDroppedFrames.load(std::memory_order_relaxed)),
            },
            @"contentionDrops": @(source->contentionDrops.load(std::memory_order_relaxed)),
            @"unsupportedBuffers": @(source->unsupportedBuffers.load(std::memory_order_relaxed)),
            @"unreadableFrames": @(source->unreadableFrames.load(std::memory_order_relaxed)),
            @"captureSlotMisses": @(source->captureSlotMisses.load(std::memory_order_relaxed)),
            @"formatMismatchBuffers": @(source->formatMismatchBuffers.load(std::memory_order_relaxed)),
            @"pcmCapacityDroppedFrames": @(source->pcmCapacityDroppedFrames.load(std::memory_order_relaxed)),
            @"configurationOverflow": @(source->configurationOverflow.load(std::memory_order_relaxed)),
            @"probeBlocks": @(probeBlocks),
            @"probeAverageMicroseconds": @(probeBlocks ? DKTicksToSeconds(probeTicks / probeBlocks) * 1000000.0 : 0),
            @"probeMaxMicroseconds": @(DKTicksToSeconds(source->maxProbeTicks.load(std::memory_order_relaxed)) * 1000000.0),
        }];
    }
    return result;
}

NSArray<NSDictionary *> *DKAudioTapSymbolCoverageJSON(void) {
    uint64_t captureStart = DKCaptureStartTicks.load(std::memory_order_relaxed);
    NSMutableArray<NSDictionary *> *result = [NSMutableArray arrayWithCapacity:DKSymbolCount];
    for (uint32_t i = 0; i < DKSymbolCount; i++) {
        DKSymbolCoverage &coverage = DKCoverage[i];
        struct dk_rebinding_status rebinding = {};
        BOOL hasStatus = dk_rebinding_status_for_name(DKSymbolNames[i], &rebinding) == 0;
        uintptr_t firstCaller = coverage.firstCaller.load(std::memory_order_relaxed);
        uintptr_t lastCaller = coverage.lastCaller.load(std::memory_order_relaxed);
        [result addObject:@{
            @"symbol": [NSString stringWithUTF8String:DKSymbolNames[i]] ?: @"",
            @"originalAvailable": @(coverage.original != nullptr),
            @"rebindResult": @(coverage.rebindResult),
            @"symbolPointerMatches": @(hasStatus ? rebinding.symbol_matches : 0),
            @"successfulRebindings": @(hasStatus ? rebinding.successful_writes : 0),
            @"protectionFailures": @(hasStatus ? rebinding.protection_failures : 0),
            @"rebound": @(hasStatus && rebinding.successful_writes > 0),
            @"hitCount": @(coverage.hits.load(std::memory_order_relaxed)),
            @"firstSecond": @(DKRelativeSeconds(coverage.firstTicks.load(std::memory_order_relaxed), captureStart)),
            @"lastSecond": @(DKRelativeSeconds(coverage.lastTicks.load(std::memory_order_relaxed), captureStart)),
            @"firstCallerImage": DKImageForAddress(firstCaller),
            @"lastCallerImage": DKImageForAddress(lastCaller),
            @"firstCallerSymbol": DKSymbolForAddress(firstCaller),
            @"lastCallerSymbol": DKSymbolForAddress(lastCaller),
            @"lastStatus": @(coverage.lastStatus.load(std::memory_order_relaxed)),
        }];
    }
    return result;
}

NSArray<NSDictionary *> *DKAudioTapEventRows(void) {
    uint64_t captureStart = DKCaptureStartTicks.load(std::memory_order_relaxed);
    uint64_t captureStop = DKCaptureStopTicks.load(std::memory_order_relaxed);
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    uint32_t count = std::min<uint32_t>(DKEventCount.load(std::memory_order_acquire), kDKMaxEvents);
    for (uint32_t i = 0; i < count; i++) {
        DKEvent *event = &DKEvents[i];
        if (!event->ready.load(std::memory_order_acquire)) continue;
        [rows addObject:@{
            @"ticks": @(event->ticks),
            @"secondsSinceCaptureStart": @(DKRelativeSeconds(event->ticks, captureStart)),
            @"withinCapture": @(captureStart > 0 && event->ticks >= captureStart &&
                                (captureStop == 0 || event->ticks <= captureStop)),
            @"event": [NSString stringWithUTF8String:DKEventName(event->kind)] ?: @"",
            @"sourceID": event->sourceID ? [NSString stringWithFormat:@"source-%02u", event->sourceID] : @"",
            @"status": @(event->status),
            @"callerImage": DKImageForAddress(event->caller),
            @"callerSymbol": DKSymbolForAddress(event->caller),
            @"value1": @(event->value1),
            @"value2": @(event->value2),
        }];
    }
    return rows;
}

NSDictionary *DKAudioTapCountersJSON(void) {
    uint64_t contentionDrops = 0, estimatedDroppedFrames = 0, capacityDroppedFrames = 0;
    uint64_t captureSlotMisses = 0, unsupportedBuffers = 0, unreadableFrames = 0;
    uint64_t configurationOverflow = 0, formatMismatchBuffers = 0;
    uint32_t callbackSources = 0, notifySources = 0;
    double maxProbeMicroseconds = 0;
    uint32_t count = DKSourceCount.load(std::memory_order_acquire);
    for (uint32_t i = 0; i < count; i++) {
        DKSource &source = DKSources[i];
        maxProbeMicroseconds = std::max(maxProbeMicroseconds,
            DKTicksToSeconds(source.maxProbeTicks.load(std::memory_order_relaxed)) * 1000000.0);
        contentionDrops += source.contentionDrops.load(std::memory_order_relaxed);
        estimatedDroppedFrames += source.estimatedDroppedFrames.load(std::memory_order_relaxed);
        capacityDroppedFrames += source.pcmCapacityDroppedFrames.load(std::memory_order_relaxed);
        captureSlotMisses += source.captureSlotMisses.load(std::memory_order_relaxed);
        unsupportedBuffers += source.unsupportedBuffers.load(std::memory_order_relaxed);
        unreadableFrames += source.unreadableFrames.load(std::memory_order_relaxed);
        configurationOverflow += source.configurationOverflow.load(std::memory_order_relaxed);
        formatMismatchBuffers += source.formatMismatchBuffers.load(std::memory_order_relaxed);
        if (source.firstCallbackTicks.load(std::memory_order_relaxed) != 0) callbackSources++;
        if (source.notifyInstalled.load(std::memory_order_relaxed) != 0) notifySources++;
    }
    return @{
        @"registeredSources": @(count),
        @"sourceOverflow": @(DKSourceOverflow.load(std::memory_order_relaxed)),
        @"renderNotifySources": @(notifySources),
        @"callbackSourcesDuringCapture": @(callbackSources),
        @"eventCount": @(std::min<uint32_t>(DKEventCount.load(std::memory_order_relaxed), kDKMaxEvents)),
        @"eventOverflow": @(DKEventOverflow.load(std::memory_order_relaxed)),
        @"activeWritersAfterStop": @(DKActiveWriters.load(std::memory_order_relaxed)),
        @"pcmAllocationFailures": @(DKPCMAllocationFailures.load(std::memory_order_relaxed)),
        @"contentionDrops": @(contentionDrops),
        @"estimatedDroppedFrames": @(estimatedDroppedFrames),
        @"pcmCapacityDroppedFrames": @(capacityDroppedFrames),
        @"captureSlotMisses": @(captureSlotMisses),
        @"unsupportedBuffers": @(unsupportedBuffers),
        @"unreadableFrames": @(unreadableFrames),
        @"configurationOverflow": @(configurationOverflow),
        @"formatMismatchBuffers": @(formatMismatchBuffers),
        @"probeMaxMicroseconds": @(maxProbeMicroseconds),
    };
}

NSArray<NSString *> *DKAudioTapCallerImageNames(void) {
    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];
    for (uint32_t i = 0; i < DKSymbolCount; i++) {
        NSString *first = DKImageForAddress(DKCoverage[i].firstCaller.load(std::memory_order_relaxed));
        NSString *last = DKImageForAddress(DKCoverage[i].lastCaller.load(std::memory_order_relaxed));
        if (first.length) [names addObject:first];
        if (last.length) [names addObject:last];
    }
    return names.array;
}

NSString *DKAudioTapSourceIDForPointer(uintptr_t pointer) {
    if (!pointer) return nil;
    uint32_t count = DKSourceCount.load(std::memory_order_acquire);
    for (uint32_t offset = 0; offset < count; offset++) {
        uint32_t i = count - offset - 1;
        if (DKSources[i].handle.load(std::memory_order_relaxed) != pointer) continue;
        if (DKSources[i].disposed.load(std::memory_order_relaxed) != 0) continue;
        return [NSString stringWithFormat:@"source-%02u", DKSources[i].sourceID];
    }
    return nil;
}
