//
//  DKAudioSignal.h
//  DYKiller
//
//  纯音频数据转换与离线信号分析；实时入口不分配内存。
//

#ifndef DKAudioSignal_h
#define DKAudioSignal_h

#import <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 把线性 PCM 下混为单声道 Float32，返回实际写入帧数。
uint32_t DKAudioSignalDownmix(const AudioBufferList *bufferList,
                              const AudioStreamBasicDescription *format,
                              uint32_t frameCount,
                              float *output,
                              uint32_t outputCapacity,
                              uint64_t *unreadableFrames);

NSData *DKAudioSignalFloatWAV(const float *samples, uint64_t frameCount, double sampleRate);
NSDictionary *DKAudioSignalMetrics(const float *samples, uint64_t count);
NSArray<NSNumber *> *DKAudioSignalFrequencyBands(const float *samples,
                                                 uint64_t available,
                                                 double sampleRate);

/// Float32/Int16、交错/非交错、静音、频谱、WAV 与容量边界自检。
NSDictionary *DKAudioSignalSyntheticValidation(void);

/// 共用的 1024 点 DFT setup（进程内只建一次）。供 DKAudioLevels 逐帧复用，
/// 避免每帧新建/销毁。失败返回 NULL。
void *DKAudioSignalDFTSetup1024(void);

#ifdef __cplusplus
}
#endif

#endif /* DKAudioSignal_h */
