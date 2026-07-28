//
//  DKUtils.h
//  跨功能复用的无状态工具：开关读取、详情页作用域判定、Cell 满高计算。
//

#ifndef DKUtils_h
#define DKUtils_h

#import <UIKit/UIKit.h>

/// 视频详情页的页面归属。首页及其余详情页均为 None，功能天然不生效。
typedef NS_ENUM(NSUInteger, DKDetailPage) {
    DKDetailPageNone = 0,
    DKDetailPageChat,     // 私信「分享视频」详情页
    DKDetailPageSearch,   // 搜索结果详情页
};

// .xm 文件按 ObjC++ 编译、本工具按 ObjC(.m) 编译，需 extern "C" 统一为 C 链接以正确链接。
#ifdef __cplusplus
extern "C" {
#endif

/// 读取某开关（NSUserDefaults BOOL）。
BOOL DKPrefBool(NSString *key);

/// 沿 responder 链找到最近的详情页控制器并判定其页面归属；视图与控制器均可传入。
DKDetailPage DKDetailPageForResponder(UIResponder *responder);

/// 该页面的全屏开关是否开启。
BOOL DKDetailPageFullscreenOn(DKDetailPage page);

/// 从 view 自身起向上找所在 Cell 的 contentView；不在 Cell 内返回 nil。
UIView *DKCellContentView(UIView *view);

/// 视频要撑到的目标高度：所在 Cell contentView 的满高；找不到返回 0。
CGFloat DKFullCellHeight(UIView *view);

#ifdef __cplusplus
}
#endif

#endif /* DKUtils_h */
