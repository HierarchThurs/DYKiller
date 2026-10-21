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

/// 在详情页的原生行高或分页计算之前准备子表尺寸；未入树时取已加载控制器的高度。
BOOL DKVideoFeedTablePrepareForController(UIViewController *controller, UITableView *table);

/// 详情页建行与分页前准备、三个行高入口的调用及修正统计。
NSString *DKVideoDetailTableStats(void);

/// iPad 首页建行前的表准备与整页行高修正统计。
NSString *DKVideoPadFeedTableStats(void);

/// HUD 钉位与视频表修正的会话累计统计；首页和详情控制器布局分别报告调用与补正次数。
NSString *DKVideoFeedTableStats(void);

#ifdef __cplusplus
}
#endif

#endif /* DKVideoFeedTable_h */
