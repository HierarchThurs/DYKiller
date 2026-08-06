//
//  DKAudioLevels.h
//  DYKiller
//
//  主线程分析层：把 DKAudioTap 的实时样本变成 0…1 的分段电平，供音频可视化逐帧驱动。
//  逐帧零分配（scratch 全是 static），只在主线程调用。
//
//  与 DKAudioSignalFrequencyBands 的分工：那个是【导出的分析口径】，40 Hz–24 kHz 覆盖全频，
//  给离线看频谱用；这里是【可视化口径】，只保留素材真正有内容的那一段，见 .mm 里的说明。
//

#ifndef DKAudioLevels_h
#define DKAudioLevels_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 分段数。可视化的条数与它无关，由 DKAudioLevelsResample 插值得到。
uint32_t DKAudioLevelsBandCount(void);

/// 拉一次实时样本 → 加窗 → DFT → 分段 → 自适应增益 → 响应曲线，写入 bands[0…BandCount)。
/// bands[0] 是最低频。没有可用音频时把 bands 清零并返回 NO。
BOOL DKAudioLevelsSampleBands(float *bands, double deltaSeconds);

/// 把 BandCount 段插值成 count 个值。u[k] ∈ [0,1] 给出第 k 个输出取哪一段，
/// 由调用方按自己的几何在布局时算好（0 = 最低频）。
void DKAudioLevelsResample(const float *bands, const float *u, float *out, uint32_t count);

/// 3 抽空间平滑（0.25 / 0.5 / 0.25），让整条包络读起来是曲线而不是噪声。原地更新。
void DKAudioLevelsSpatialSmooth(float *values, uint32_t count);

/// 一阶跟随：上升用 attackTau、下降用 decayTau（秒）。levels 原地更新。
void DKAudioLevelsSmooth(float *levels, const float *targets, uint32_t count,
                         double deltaSeconds, double attackTau, double decayTau);

/// 复位自适应增益。功能重新开启时调用。
void DKAudioLevelsReset(void);

/// 分段映射、静音、1 kHz 定位与跟随收敛的合成自检。
NSDictionary *DKAudioLevelsSyntheticValidation(void);

#ifdef __cplusplus
}
#endif

#endif /* DKAudioLevels_h */
