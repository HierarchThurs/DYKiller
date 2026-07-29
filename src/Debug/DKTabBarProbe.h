//
//  DKTabBarProbe.h
//  DYKiller
//
//  底栏探针：采集抖音底栏与系统 UITabBar 的运行时状态，供玻璃底栏方案验证使用。
//  验证结束后整文件删除。
//

#ifndef DKTabBarProbe_h
#define DKTabBarProbe_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 生成底栏探针报告文本（只读采集，不改变任何状态）。
NSString *DKTabBarProbeReport(void);

#ifdef __cplusplus
}
#endif

#endif /* DKTabBarProbe_h */
