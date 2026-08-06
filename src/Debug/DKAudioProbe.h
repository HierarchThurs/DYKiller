//
//  DKAudioProbe.h
//  DYKiller
//
//  音频专项探针的编排层：管采样窗口、AVFoundation 侧的高层事件，
//  并在采样结束后把 DKAudioTap 的实时记录转成可导出的不可变数据。
//  实时取样本身在 DKAudioTap。
//

#ifndef DKAudioProbe_h
#define DKAudioProbe_h

#import <Foundation/Foundation.h>

/// 采样窗口固定为「1 秒稳定 + 3 秒 PCM + 1 秒收尾」。
extern const double DKAudioProbeWarmupSeconds;
extern const double DKAudioProbeRecordSeconds;
extern const double DKAudioProbeTotalSeconds;

@interface DKAudioProbeCapture : NSObject
@property (nonatomic, copy) NSString *declaredState;
@property (nonatomic, copy) NSString *actualState;
/// 采样前后各一次 AVAudioSession 快照。
@property (nonatomic, strong) NSDictionary *sessionJSON;
@property (nonatomic, strong) NSArray *backendsJSON;
@property (nonatomic, copy) NSString *timelineJSONL;
/// 30 Hz 的 RMS / 峰值 / 频谱带时间序列，可直接离线绘制与调参。
@property (nonatomic, copy) NSString *signalJSONL;
@property (nonatomic, strong) NSArray *mediaSnapshotsJSON;
@property (nonatomic, strong) NSDictionary *glassTargetJSON;
@property (nonatomic, strong) NSDictionary *diagnosticsJSON;
@property (nonatomic, copy) NSString *summaryText;
/// 每项包含 fileName、data、metadata；data 为单声道 Float32 WAV。
@property (nonatomic, strong) NSArray<NSDictionary *> *pcmFiles;
@end

#ifdef __cplusplus
extern "C" {
#endif

/// 在调试开关已持久化开启时尽早安装底层符号包装。
void DKAudioProbeInstallIfEnabled(BOOL launchPhase);

/// 设置开关变化后同步状态；关闭时已安装包装器只透明转发。
void DKAudioProbePreferenceDidChange(void);

/// 当前进程是否从启动阶段就完成了后端包装。
BOOL DKAudioProbeHasLaunchCoverage(void);
BOOL DKAudioProbeIsEnabled(void);
BOOL DKAudioProbeIsCaptureActive(void);

/// 相对本次采样起点的秒数；未开始采样时返回 -1。
double DKAudioProbeCurrentCaptureSecond(void);

/// declaredState 取 playing / paused / muted-playing。
/// 调用方负责在 DKAudioProbeTotalSeconds 后 Stop，再在后台 Build。
BOOL DKAudioProbeStartCapture(NSString *declaredState);
void DKAudioProbeStopCapture(void);

/// 在后台生成派生指标、WAV、后端与时间线文件所需的不可变数据。
DKAudioProbeCapture *DKAudioProbeBuildCapture(NSArray *mediaSnapshots, NSDictionary *glassTarget);

/// 当前 AVAudioSession 的只读快照。
NSDictionary *DKAudioProbeSessionSnapshot(void);

/// AVFoundation / AVFAudio 侧 hook 的非实时事件入口。
void DKAudioProbeRecordObjectDetails(NSString *name, id object, NSDictionary *details);

/// 高层 hook 见过且仍存活的播放器/引擎对象；只返回弱引用快照，
/// 供媒体快照把它们的播放状态一并纳入判定。
NSArray *DKAudioProbeObservedObjects(void);

#ifdef __cplusplus
}
#endif

#endif /* DKAudioProbe_h */
