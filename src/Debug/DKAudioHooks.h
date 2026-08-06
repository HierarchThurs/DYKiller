//
//  DKAudioHooks.h
//  DYKiller
//
//  高层 hook 的覆盖自检。
//
//  底层 C 符号有 rebound / symbolPointerMatches 可查，ObjC 这边一直没有：
//  「命中 0 次」既可能是抖音真没调，也可能是 hook 压根没装上，两种情况在导出里长得一样。
//  0.5.2-beta5 判定「图文 BGM 不走 AVPlayer/AVAudioPlayer」时就卡在这个歧义上。
//

#ifndef DKAudioHooks_h
#define DKAudioHooks_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 每个被 hook 的类与方法：类在不在、方法在不在、当前实现是不是我们的。
/// 用 dladdr 反查 IMP 所属镜像判定，不依赖 Logos 内部结构。
NSArray<NSDictionary *> *DKAudioHooksCoverageJSON(void);

#ifdef __cplusplus
}
#endif

#endif /* DKAudioHooks_h */
