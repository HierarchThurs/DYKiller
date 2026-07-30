//
//  DKVideoFeedTable.h
//  DYKiller
//
//  「视频表被底栏压缩」这一类裁剪源头的对外接口：表查找（供页面修饰层排除这类结构）、
//  撑高原高（供调试探针判断表有没有被撑高），以及 HUD 钉位的命中统计。
//

#ifndef DKVideoFeedTable_h
#define DKVideoFeedTable_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 视频表的基类 `AWEFeedDataSafeTableView`；取不到返回 nil。
Class DKVideoFeedTableClass(void);

/// 该视图所在的视频表；不在表内返回 nil。
UIView *DKFeedTableForView(UIView *view);

/// 该表撑高前的高度；没被撑高过返回 nil。
NSNumber *DKVideoFeedTableOriginalHeight(UIView *table);

/// HUD 钉位命中统计的可读文本。
NSString *DKVideoFeedTableStats(void);

#ifdef __cplusplus
}
#endif

#endif /* DKVideoFeedTable_h */
