//
//  DKUtils.h
//  跨功能复用的无状态工具：开关读取、子控制器查找、Cell 满高计算。
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

/// 沿 childViewControllers 递归找指定类名的子控制器。
/// 抖音的面板类多是 Swift 类，类名带点，Logos 的 %hook 用不了，只能按名字取。
UIViewController *DKChildControllerNamed(UIViewController *controller, NSString *className);

/// 该颜色是否为不透明纯黑（识别抖音铺的黑色垫层用）。
BOOL DKColorIsOpaqueBlack(UIColor *color);

/// 从 view 自身起向上找所在 Cell 的 contentView；不在 Cell 内返回 nil。
UIView *DKCellContentView(UIView *view);

/// 视频要撑到的目标高度：所在 Cell contentView 的满高；找不到返回 0。
CGFloat DKFullCellHeight(UIView *view);

#ifdef __cplusplus
}
#endif

#endif /* DKUtils_h */
