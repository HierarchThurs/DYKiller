//
//  DKSideBarSwipe.xm
//  功能：顶栏入口 —— 屏蔽在最左侧频道右滑展开左侧栏。
//
//  实现：
//   - 左侧栏滑动手势的开始判定与频道分页的让位判定都询问
//     -[AWELeftSideBarManager canShowLeftSideBarWithPanGesture:]。
//   - 开关开启时返回 NO：手势不开始，频道分页照常处理右滑。点击入口与滑动关闭不经过此方法。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKUtils.h"

%hook AWELeftSideBarManager

- (BOOL)canShowLeftSideBarWithPanGesture:(id)identification {
    if (DKPrefBool(DKKeyBlockSideBarSwipe)) return NO;
    return %orig;
}

%end
