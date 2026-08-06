//
//  DKAudioLevels.mm
//  DYKiller
//

#import "DKAudioLevels.h"
#import "DKAudioSignal.h"
#import "DKAudioTap.h"

#import <Accelerate/Accelerate.h>

#include <algorithm>
#include <cmath>
#include <cstring>

namespace {

constexpr uint32_t kWindow = 1024;          // 与 DKAudioSignalDFTSetup1024 一致
constexpr uint32_t kBands = 32;

// 可视化的频率范围只取 60 Hz – 12 kHz，不是全频。两头都有实测理由：
//
// 低端：1024 点 @ 48 kHz 的 bin 宽是 46.875 Hz，40 Hz 以下压根分辨不出来。导出那份
//       40 Hz 起的 32 段映射里，band 0–3 全部落进 bin 1（beta3 实测四段值一模一样），
//       画出来就是最左四根条完全同步地一起动，一眼假。
// 高端：抖音是重压缩 AAC，beta3 那份素材 13 kHz 以上是零；留到 24 kHz 只会让最后
//       三根条永远不动，还各自白白平均掉 63/77/93 个 bin。
constexpr double kMinHz = 60.0;
constexpr double kMaxHz = 12000.0;

// 自适应增益：跟得上突强、退得慢，安静段落也能有满幅动作。
constexpr double kGainAttackTau = 0.10;
constexpr double kGainDecayTau = 2.00;
constexpr float kGainFloor = 0.01f;         // 下限，避免静音时把底噪放大成满幅

// 响应曲线。线性幅度直接画出来低电平几乎贴地，0.45 次方把中下段抬起来。
constexpr float kCurve = 0.45f;

float gPeakEnv = kGainFloor;

// 逐帧复用的 scratch，全部 static：分析在主线程跑，60 Hz 下不能有堆分配。
float gSamples[kWindow];
float gWindowFn[kWindow];
float gReal[kWindow], gImag[kWindow], gOutReal[kWindow], gOutImag[kWindow];
float gMagnitude[kWindow / 2];
bool gWindowReady = false;

void EnsureWindow(void) {
    if (gWindowReady) return;
    vDSP_hann_window(gWindowFn, kWindow, vDSP_HANN_NORM);
    gWindowReady = true;
}

float BandEdgeHz(uint32_t index) {
    return (float)(kMinHz * pow(kMaxHz / kMinHz, (double)index / kBands));
}

// 把幅度谱折成 kBands 段。
//
// 段宽不足一个 bin 时【在段中心频率上线性插值】而不是对整数 bin 区间求平均——后者会让
// 相邻若干段退化成同一个 bin 的同一个值。段宽够时取区间【最大值】而不是均值：
// 可视化要的是"这一段里最响的成分"，均值会把瞬态抹平。
void FoldBands(const float *magnitude, double sampleRate, float *bands) {
    const double binsPerHz = (double)kWindow / sampleRate;
    for (uint32_t k = 0; k < kBands; k++) {
        double lo = BandEdgeHz(k) * binsPerHz;
        double hi = BandEdgeHz(k + 1) * binsPerHz;
        uint32_t first = (uint32_t)ceil(lo);
        uint32_t last = (uint32_t)floor(hi);
        float value;
        if (last <= first || last >= kWindow / 2) {
            double center = std::min((lo + hi) * 0.5, (double)(kWindow / 2 - 2));
            uint32_t bin = (uint32_t)center;
            float frac = (float)(center - bin);
            value = magnitude[bin] * (1.0f - frac) + magnitude[bin + 1] * frac;
        } else {
            value = 0.0f;
            for (uint32_t bin = first; bin <= last && bin < kWindow / 2; bin++) {
                value = std::max(value, magnitude[bin]);
            }
        }
        bands[k] = value;
    }
}

} // namespace

uint32_t DKAudioLevelsBandCount(void) {
    return kBands;
}

void DKAudioLevelsReset(void) {
    gPeakEnv = kGainFloor;
}

BOOL DKAudioLevelsSampleBands(float *bands, double deltaSeconds) {
    if (!bands) return NO;
    memset(bands, 0, kBands * sizeof(float));

    double sampleRate = 48000.0;
    if (DKAudioTapCopyLatestSamples(gSamples, kWindow, &sampleRate) != kWindow) return NO;

    vDSP_DFT_Setup setup = (vDSP_DFT_Setup)DKAudioSignalDFTSetup1024();
    if (!setup) return NO;

    EnsureWindow();
    vDSP_vmul(gSamples, 1, gWindowFn, 1, gReal, 1, kWindow);
    memset(gImag, 0, sizeof(gImag));
    vDSP_DFT_Execute(setup, gReal, gImag, gOutReal, gOutImag);

    DSPSplitComplex split = { gOutReal, gOutImag };
    vDSP_zvabs(&split, 1, gMagnitude, 1, kWindow / 2);
    float scale = 1.0f / kWindow;
    vDSP_vsmul(gMagnitude, 1, &scale, gMagnitude, 1, kWindow / 2);

    FoldBands(gMagnitude, sampleRate, bands);

    float peak = 0.0f;
    vDSP_maxv(bands, 1, &peak, kBands);
    double tau = peak > gPeakEnv ? kGainAttackTau : kGainDecayTau;
    float target = std::max(peak, kGainFloor);
    gPeakEnv += (target - gPeakEnv) * (float)(1.0 - exp(-std::max(0.0, deltaSeconds) / tau));
    if (gPeakEnv < kGainFloor) gPeakEnv = kGainFloor;

    for (uint32_t k = 0; k < kBands; k++) {
        float normalized = std::min(1.0f, std::max(0.0f, bands[k] / gPeakEnv));
        bands[k] = powf(normalized, kCurve);
    }
    return YES;
}

void DKAudioLevelsResample(const float *bands, const float *u, float *out, uint32_t count) {
    if (!bands || !u || !out || count == 0) return;
    for (uint32_t k = 0; k < count; k++) {
        float position = std::min(1.0f, std::max(0.0f, u[k])) * (kBands - 1);
        uint32_t index = (uint32_t)position;
        float frac = position - index;
        uint32_t next = std::min(index + 1, kBands - 1);
        out[k] = bands[index] * (1.0f - frac) + bands[next] * frac;
    }
}

void DKAudioLevelsSpatialSmooth(float *values, uint32_t count) {
    if (!values || count < 3) return;
    float previous = values[0];
    for (uint32_t k = 1; k + 1 < count; k++) {
        float current = values[k];
        values[k] = 0.25f * previous + 0.5f * current + 0.25f * values[k + 1];
        previous = current;
    }
}

void DKAudioLevelsSmooth(float *levels, const float *targets, uint32_t count,
                         double deltaSeconds, double attackTau, double decayTau) {
    if (!levels || !targets || count == 0) return;
    double dt = std::max(0.0, deltaSeconds);
    float up = (float)(1.0 - exp(-dt / std::max(0.001, attackTau)));
    float down = (float)(1.0 - exp(-dt / std::max(0.001, decayTau)));
    for (uint32_t k = 0; k < count; k++) {
        float target = targets[k];
        levels[k] += (target - levels[k]) * (target > levels[k] ? up : down);
    }
}

// MARK: - 自检

NSDictionary *DKAudioLevelsSyntheticValidation(void) {
    NSMutableDictionary *checks = [NSMutableDictionary dictionary];
    const double sampleRate = 48000.0;
    float magnitude[kWindow / 2] = {};
    float bands[kBands] = {};

    // 1 kHz 单音：折出来的峰值必须落在包含 1 kHz 的那一段。
    uint32_t oneKHzBin = (uint32_t)round(1000.0 * kWindow / sampleRate);
    magnitude[oneKHzBin] = 1.0f;
    FoldBands(magnitude, sampleRate, bands);
    uint32_t strongest = 0;
    for (uint32_t k = 1; k < kBands; k++) if (bands[k] > bands[strongest]) strongest = k;
    checks[@"bandPeakAt1kHz"] = @(BandEdgeHz(strongest) <= 1000.0f &&
                                  BandEdgeHz(strongest + 1) >= 1000.0f);

    // 分段塌陷回归：给一条平坦谱，相邻段不得出现完全相同的值。
    // 40 Hz–24 kHz 的旧口径下，最低四段会同时落进 bin 1，值一模一样。
    for (uint32_t bin = 0; bin < kWindow / 2; bin++) magnitude[bin] = 1.0f / (1.0f + bin);
    FoldBands(magnitude, sampleRate, bands);
    BOOL distinct = YES;
    for (uint32_t k = 1; k < kBands; k++) if (bands[k] == bands[k - 1]) distinct = NO;
    checks[@"bandsDistinct"] = @(distinct);

    // 静音输入折出来必须全零。
    memset(magnitude, 0, sizeof(magnitude));
    FoldBands(magnitude, sampleRate, bands);
    BOOL silent = YES;
    for (uint32_t k = 0; k < kBands; k++) if (bands[k] != 0.0f) silent = NO;
    checks[@"bandsSilence"] = @(silent);

    // 跟随：上升快、下降慢，且都收敛到目标。
    float levels[4] = { 0, 0, 0, 0 };
    float targets[4] = { 1, 1, 1, 1 };
    for (int i = 0; i < 30; i++) DKAudioLevelsSmooth(levels, targets, 4, 1.0 / 60.0, 0.035, 0.240);
    BOOL rose = levels[0] > 0.99f;
    float afterAttack = levels[0];
    memset(targets, 0, sizeof(targets));
    DKAudioLevelsSmooth(levels, targets, 4, 1.0 / 60.0, 0.035, 0.240);
    BOOL slowFall = levels[0] < afterAttack && levels[0] > 0.9f;   // 一帧只掉一点
    for (int i = 0; i < 120; i++) DKAudioLevelsSmooth(levels, targets, 4, 1.0 / 60.0, 0.035, 0.240);
    checks[@"smoothConverges"] = @(rose && slowFall && levels[0] < 0.01f);

    // 重采样：u 单调时输出必须在段值之间，端点严格对齐首末段。
    for (uint32_t k = 0; k < kBands; k++) bands[k] = (float)k / (kBands - 1);
    float u[5] = { 0.0f, 0.25f, 0.5f, 0.75f, 1.0f }, out[5] = {};
    DKAudioLevelsResample(bands, u, out, 5);
    checks[@"resampleEndpoints"] = @(fabsf(out[0] - 0.0f) < 1e-5f && fabsf(out[4] - 1.0f) < 1e-5f &&
                                     out[1] > out[0] && out[2] > out[1] && out[3] > out[2]);

    BOOL passed = YES;
    for (NSNumber *value in checks.allValues) passed &= value.boolValue;
    return @{ @"passed": @(passed), @"checks": checks };
}
