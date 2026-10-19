//
//  DKPublishRegion.h
//  发布地区：作品的城市代码（JSON city）与国家地区码（region）→ 显示地名。只用 Foundation。
//  国内按内置区划表显示到地级；国外用城市代码作 GeoNames 地名 ID 查询，未查到时显示国家名，
//  都没有时退到抖音原生属地文字（ip_attribution）。不读作者自选的作品地点。
//

#ifndef DKPublishRegion_h
#define DKPublishRegion_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 区划表（DKPublishRegionTable.m）：省级 2 位、地级 4 位、省直辖县级 6 位代码 → 简称。
NSDictionary<NSString *, NSString *> *DKPublishRegionProvinces(void);
NSDictionary<NSString *, NSString *> *DKPublishRegionPrefectures(void);
NSDictionary<NSString *, NSString *> *DKPublishRegionCounties(void);

/// 国内 6 位区划代码 → 「省 市」；地级查不到时退到省级。不是已知省级前缀的 6 位数字返回 nil。
NSString *DKPublishRegionChinaName(NSString *code);

/// ISO 3166-1 alpha-2 国家地区码 → 中文名；港澳台为「中国香港」「中国澳门」「中国台湾」。未知返回 nil。
NSString *DKPublishRegionCountryName(NSString *region);

/// 作品的显示地区，主线程调用。国外地名 ID 未缓存且填了用户名时发起查询（同一 ID 同时只发一次，
/// 失败的 ID 隔 10 分钟或换用户名后再试），查到后在主线程调 resolved(地名 ID)；当前先返回可得的兜底地名。
NSString *DKPublishRegionName(NSString *cityCode, NSString *region, NSString *ipAttribution, NSString *username,
                              void (^resolved)(NSString *geonameId));

/// 诊断：进行中与失败的地名查询数量。
NSString *DKPublishRegionStatus(void);

#ifdef __cplusplus
}
#endif

#endif /* DKPublishRegion_h */
