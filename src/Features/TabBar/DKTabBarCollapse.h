//
//  DKTabBarCollapse.h
//  DYKiller
//
//  底栏动态收缩：上滑收成系统圆键，下滑或点圆键展开。胶囊、圆键与形变都由 UIKit 完成。
//

#ifndef DKTabBarCollapse_h
#define DKTabBarCollapse_h

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, DKTabBarCollapseSide) {
    DKTabBarCollapseSideOff = 0,
    DKTabBarCollapseSideLeft = 1,
    DKTabBarCollapseSideRight = 2,
};

#ifdef __cplusplus
extern "C" {
#endif

/// 当前档位。iPad 与低于 iOS 26 的系统恒为关闭。
DKTabBarCollapseSide DKTabBarCollapseCurrentSide(void);

/// 在抖音 Tab 控制器的 view 上接收上下滑；重复调用无副作用。
void DKTabBarCollapseAttach(UIView *view);
void DKTabBarCollapseDetach(void);

#ifdef __cplusplus
}
#endif

#endif /* DKTabBarCollapse_h */
