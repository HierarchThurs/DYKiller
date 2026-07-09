//
//  DKUtils.h
//  跨功能复用的无状态工具：开关读取、页面作用域判定、目标高度计算。
//

#ifndef DKUtils_h
#define DKUtils_h

#import <UIKit/UIKit.h>

// .xm 文件按 ObjC++ 编译、本工具按 ObjC(.m) 编译，需 extern "C" 统一为 C 链接以正确链接。
#ifdef __cplusplus
extern "C" {
#endif

/// 读取某开关（NSUserDefaults BOOL）。
BOOL DKPrefBool(NSString *key);

/// 沿 parentViewController 链判断该 VC 是否位于私信「分享视频」详情页。
BOOL DKVCInIMDetail(UIViewController *vc);

/// 从任意视图经 responder 链找到最近的 VC，再判定是否在该详情页。
BOOL DKViewInIMDetail(UIView *view);

/// 视频要撑到的目标高度：向上找 UITableViewCellContentView 的满高；找不到返回 0。
CGFloat DKFullCellHeight(UIView *view);

#ifdef __cplusplus
}
#endif

#endif /* DKUtils_h */
