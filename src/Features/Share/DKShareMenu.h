// 分享面板的动态功能目录与数据过滤。
#ifndef DKShareMenu_h
#define DKShareMenu_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

NSArray<NSDictionary *> *DKShareMenuCatalog(void);
NSString *DKShareMenuHideKey(NSString *itemID);
/// 收录原始功能行，再按移除开关过滤；空行一并移除，未调整时返回原数组。
NSArray *DKShareMenuFilter(NSArray *lines);
NSString *DKShareMenuStatus(void);

#ifdef __cplusplus
}
#endif
#endif
