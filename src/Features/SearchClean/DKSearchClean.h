// 搜索页精简：中间页区块配置规则、Hook 安装与诊断。
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// 搜索中间页区块配置在 AB / 设置中的键，值为 {pageComponents:[{key, show}]}。
extern NSString *const DKSearchPageConfigKey;

BOOL DKSearchTemplateMatches(NSString *url, NSString *bundle);
BOOL DKSearchIsMiddlePageProps(NSDictionary *props);
id DKSearchCleanPageConfig(id config);
NSDictionary *DKSearchCleanGlobalProps(NSDictionary *props, NSString *url);
void DKSearchInstallNativeHooks(void);
void DKSearchInstallCameraHooks(void);
NSDictionary *DKSearchCleanStatus(void);

#ifdef __cplusplus
}
#endif
