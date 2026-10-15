// 媒体保存入口共用的运行时工具：签名核对、按类名前缀找控制器。
#ifndef DKMediaSaveRuntime_h
#define DKMediaSaveRuntime_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

// types 为返回值及显式参数的类型首字符，如 v@ 表示 void(id)。
BOOL DKMediaMethod(Class cls, SEL selector, const char *types);
// 类名以 prefix 开头（含 _hmd_subfix_ 等运行时子类）。
BOOL DKMediaClassHasPrefix(id object, NSString *prefix);
// 沿响应链找第一个类名以 prefix 开头的控制器。
UIViewController *DKMediaControllerForResponder(UIResponder *responder, NSString *prefix);
// 从前台窗口根控制器沿 presented 链与子控制器查找类名以 prefix 开头的控制器。
UIViewController *DKMediaFindController(NSString *prefix);

#ifdef __cplusplus
}
#endif

#endif
