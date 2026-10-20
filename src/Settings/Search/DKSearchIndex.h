//
//  DKSearchIndex.h
//  设置搜索的条目与打分：布局表全量（静态可达）与当前页 live 项合并成一张索引。
//  只用 Foundation，可在没有 UI 的地方构建与查询。
//

#ifndef DKSearchIndex_h
#define DKSearchIndex_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class DKSettingsPage;

/// 一条搜索结果。子页入口（isPageEntry）与设置行共用同一结构。
@interface DKSearchEntry : NSObject
@property (nonatomic, copy, readonly) NSString *identifier;      // 设置键、子页 identifier 或动作行标题
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *icon;            // 抖音内置 svgIconImageName
@property (nonatomic, copy, readonly) NSString *pageTitle;       // 所在子页标题；一级页的项为空
@property (nonatomic, copy, readonly) NSString *sectionHeader;   // 所在分区标题
@property (nonatomic, copy, readonly) NSString *lockReason;      // 灰显原因；可用时为空
@property (nonatomic, copy, readonly) NSArray<DKSettingsPage *> *pagePath;   // 根 → 叶；一级页的项为空数组
@property (nonatomic, assign, readonly) BOOL isPageEntry;        // 子页入口
@property (nonatomic, assign, readonly) BOOL onCurrentPage;      // 命中项就在当前页
@end

@interface DKSearchIndex : NSObject

/// 按当前页建索引。pagePath 是页面的子页 identifier 序列（同 DKSearchPagePath）：
/// 空数组表示 DYKiller 一级页（此时不区分「本页」），nil 或布局表里找不到表示路径未知的运行时页面。
+ (instancetype)indexForPage:(UIViewController *)page pagePath:(NSArray<NSString *> *)pagePath;

/// 查询：当前页命中排在前，其后按匹配度；空查询返回空数组。
- (NSArray<DKSearchEntry *> *)resultsForQuery:(NSString *)query;

@end

#endif /* DKSearchIndex_h */
