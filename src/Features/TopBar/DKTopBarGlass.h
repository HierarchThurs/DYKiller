//
//  DKTopBarGlass.h
//  DYKiller
//
//  顶栏液态玻璃：左侧栏与搜索入口改为圆钮，频道条放进长胶囊。
//

#ifndef DKTopBarGlass_h
#define DKTopBarGlass_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 设置改变后立即刷新已见过的顶栏。
void DKTopBarGlassRefresh(void);

/// 玻璃开启时，触点是否落在槽位内圆钮之外（这部分空白不应触发入口）。
BOOL DKTopBarGlassSlotRejectsPoint(UIView *item, CGPoint point);

/// 评论区打开时的搜索图标副本：visible 时垫同样的玻璃圆钮，否则撤掉。
void DKTopBarGlassApplySearchCopy(UIView *copy, BOOL visible);

/// 顶栏玻璃的状态，一段多行文字，供探针输出。
NSString *DKTopBarGlassStatus(void);

#ifdef __cplusplus
}
#endif

#endif /* DKTopBarGlass_h */
