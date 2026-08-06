//
//  DKAudioTap.h
//  DYKiller
//
//  进程音频输出的只读旁路。用 fishhook 重绑定 AudioToolbox 的少数入口拿到
//  输出单元/队列句柄，再用公开的 AudioUnitAddRenderNotify 旁听已渲染的样本；
//  不替换抖音自己的 AURenderCallback，因此不进它出声的主链路。
//
//  这一层是后续音频可视化功能要复用的部分：取样机制与功能将要使用的完全一致。
//

#ifndef DKAudioTap_h
#define DKAudioTap_h

#import <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>

typedef NS_ENUM(uint32_t, DKAudioTapSourceKind) {
    DKAudioTapSourceKindAudioUnit = 1,
    DKAudioTapSourceKindAudioQueue = 2,
    DKAudioTapSourceKindMediaTap = 3,
};

/// 一路已录到的单声道 Float32 样本。samples 由 tap 持有，读取方不得释放。
typedef struct {
    uint32_t sourceID;
    uint32_t kind;
    const float *samples;
    uint64_t frameCount;
    double sampleRate;
    AudioStreamBasicDescription sourceFormat;
} DKAudioTapSlot;

#ifdef __cplusplus
extern "C" {
#endif

/// 安装符号包装。幂等；只有第一次真正执行 rebind。
void DKAudioTapInstall(void);

/// 关闭后所有包装器只透明转发，不再登记、不再取样。
void DKAudioTapSetEnabled(BOOL enabled);
BOOL DKAudioTapIsInstalled(void);

/// 开启采样窗口：先静置 warmupSeconds，再录 recordSeconds 的 PCM。
/// 失败返回 NO（未安装、已在采样、PCM 缓冲分配失败）。
BOOL DKAudioTapBeginCapture(double warmupSeconds, double recordSeconds);
void DKAudioTapEndCapture(void);
BOOL DKAudioTapIsCapturing(void);

/// 等待实时写入方全部离开缓冲区，之后读槽位才是安全的。
void DKAudioTapWaitForWriters(void);

uint64_t DKAudioTapCaptureStartTicks(void);
uint64_t DKAudioTapCaptureStopTicks(void);
double DKAudioTapSecondsFromTicks(uint64_t ticks);
double DKAudioTapSecondsRelativeTo(uint64_t ticks, uint64_t origin);
/// 相对本次采样起点的秒数；未开始采样时返回 -1。
double DKAudioTapCurrentCaptureSecond(void);

/// 采样结束后读取录到的各路 PCM。index < DKAudioTapSlotCount()。
uint32_t DKAudioTapSlotCount(void);
BOOL DKAudioTapReadSlot(uint32_t index, DKAudioTapSlot *out);

#pragma mark - 实时电平旁路

// 与上面那套五秒采集彼此独立：采集是"开一个窗口、录完就停"，这里是常开的滚动环，
// 供音频可视化逐帧取最近一段样本。两者共用同一次下混，互不影响对方的计数。

/// 常开电平旁路的开关。关闭时实时侧完全不碰环形缓冲。
void DKAudioTapSetLiveMeteringEnabled(BOOL enabled);
BOOL DKAudioTapIsLiveMeteringEnabled(void);

/// 拷出当前"最响的那一路"最近的 count 个单声道 Float32 样本（out[count-1] 为最新）。
/// 返回实际拷出的帧数；无活跃音源、或拷贝期间被实时侧覆盖时返回 0。
/// sampleRateOut 可为 NULL。只在主线程调用。
uint32_t DKAudioTapCopyLatestSamples(float *out, uint32_t count, double *sampleRateOut);

/// withinSeconds 内是否还有音源在送 buffer。用于决定可视化的显隐与帧率档位。
BOOL DKAudioTapHasRecentAudio(double withinSeconds);

/// 后端登记表：每个 unit / queue / tap 的身份、格式、启停与统计。
NSArray<NSDictionary *> *DKAudioTapBackendsJSON(void);
/// 每个被重绑定符号的覆盖情况与命中调用者。
NSArray<NSDictionary *> *DKAudioTapSymbolCoverageJSON(void);
/// 实时层事件行（含 ticks 键），供上层与 ObjC 事件合并后按时间排序。
NSArray<NSDictionary *> *DKAudioTapEventRows(void);
/// 溢出、丢帧、争用等计数器汇总。
NSDictionary *DKAudioTapCountersJSON(void);

NSArray<NSString *> *DKAudioTapCallerImageNames(void);
/// 指针命中已登记后端时返回 source-NN，否则 nil。
NSString *DKAudioTapSourceIDForPointer(uintptr_t pointer);

#ifdef __cplusplus
}
#endif

#endif /* DKAudioTap_h */
