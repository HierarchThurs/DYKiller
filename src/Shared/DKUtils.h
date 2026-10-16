//
//  DKUtils.h
//  跨功能复用的无状态工具：开关读取、子控制器查找、Cell 满高计算。
//

#ifndef DKUtils_h
#define DKUtils_h

#import <UIKit/UIKit.h>

/// 「显示 / 隐藏 / 移除」三档单选的取值。
typedef NS_ENUM(NSInteger, DKDisplayMode) {
    DKDisplayModeShow = 0,    // 抖音原样
    DKDisplayModeHide = 1,    // 不显示，位置与点击保留
    DKDisplayModeRemove = 2,  // 不显示、不可点击，按抖音原生排布收拢
};

// .xm 文件按 ObjC++ 编译、本工具按 ObjC(.m) 编译，需 extern "C" 统一为 C 链接以正确链接。
#ifdef __cplusplus
extern "C" {
#endif

/// 读取某开关（NSUserDefaults BOOL）。
BOOL DKPrefBool(NSString *key);

/// 读取某单选项（NSUserDefaults NSInteger）。未设置时为 0。
NSInteger DKPrefInteger(NSString *key);

/// 读取「显示 / 隐藏 / 移除」三档单选；未设置或越界按显示。
DKDisplayMode DKPrefDisplayMode(NSString *key);

/// 读取 0–100 的百分比设置并换算为 0–1；未设置时取 defaultPercent，越界按边界。
CGFloat DKPrefFraction(NSString *key, NSInteger defaultPercent);

/// 音频取样包装该不该开：「调试工具」或「音频可视化」任一开着。安装与开关都按这一条判定。
BOOL DKAudioSamplingWanted(void);

/// 从 view 起沿响应链找所属的播放交互层控制器（AWEPlayInteractionViewController）；不在交互层内返回 nil。
UIViewController *DKPlayInteractionControllerForView(UIView *view);

/// 沿 childViewControllers 递归找指定类名的子控制器。
/// 抖音的面板类多是 Swift 类，类名带点，Logos 的 %hook 用不了，只能按名字取。
UIViewController *DKChildControllerNamed(UIViewController *controller, NSString *className);

/// 该颜色是否为不透明纯黑（识别抖音铺的黑色垫层用）。
BOOL DKColorIsOpaqueBlack(UIColor *color);

/// Clear 液态玻璃在该外观下应有的染色：浅色档不染色，深色档黑 30%。
/// Clear 对 overrideUserInterfaceStyle 不敏感，深色只能靠染色。悬浮底栏与评论面板共用此口径。
UIColor *DKGlassTintForStyle(UIUserInterfaceStyle style);

/// 该颜色是否为黑系文字色。抖音主文字色 #161823 是偏蓝的近黑（饱和度 0.37），
/// 只看饱和度会误判成彩色，故按明度与饱和度双阈值判定。
BOOL DKGlassColorIsInk(UIColor *color);

/// 玻璃上的目标文字色：彩色与浅色原样返回；黑系在 Clear 下转白、Regular 下只有深色档转白。
/// 转白保留原色 alpha，保住主次文字的层级。
UIColor *DKGlassInkTextColor(UIColor *original, BOOL clear, UIUserInterfaceStyle style);

/// 把 root 子树里的黑系文字改成 DKGlassInkTextColor 的结果，原色记在关联对象上。
/// 不下探 UIControl：按钮标题由 UIButtonConfiguration 管，直接写 textColor 会被它覆盖。
void DKGlassApplyInkText(UIView *root, BOOL clear, UIUserInterfaceStyle style);

/// 还原 DKGlassApplyInkText 改过的文字色。
void DKGlassRestoreInkText(UIView *root);

/// 从 view 自身起向上找所在 Cell 的 contentView；不在 Cell 内返回 nil。
UIView *DKCellContentView(UIView *view);

/// 视频要撑到的目标高度：所在 Cell contentView 的满高；找不到返回 0。
CGFloat DKFullCellHeight(UIView *view);

#ifdef __cplusplus
}
#endif

#endif /* DKUtils_h */
