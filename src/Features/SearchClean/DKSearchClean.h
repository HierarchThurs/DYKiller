// 搜索页精简：榜单目录、移除规则与搜索卡片配置。
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

NSArray<NSDictionary *> *DKSearchRankCatalog(void);
void DKSearchRecordRanks(NSArray<NSDictionary *> *entries);
NSString *DKSearchRankHideKey(NSString *rankID);
BOOL DKSearchRankHidden(NSString *rankID);
NSArray *DKSearchVisibleRanks(NSArray *tabs, NSString *(^identifier)(id));
BOOL DKSearchTemplateMatches(NSString *url, NSString *bundle);
NSDictionary *DKSearchCleanGlobalProps(NSDictionary *props, NSString *url);
void DKSearchInstallNativeHooks(void);
void DKSearchInstallCameraHooks(void);
NSDictionary *DKSearchCleanStatus(void);

#ifdef __cplusplus
}
#endif
