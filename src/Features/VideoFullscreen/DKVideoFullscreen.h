//
//  DKVideoFullscreen.h
//  DYKiller
//
//  视频全屏与评论态冻结的共享契约。
//
//  对 UIView 的 frame 写入只留一个拦截点，统一在 DKVideoGeometry.xm，按写入方的归属控制器分派。
//  理由不是钩子会互相覆盖（多层 %hook 会正常串联，本项目就有三对同名方法分挂在两个文件里、
//  六个功能同时正常），而是：setFrame: 是 UIKit 最热的方法，第二个全局钩子会让全 App 每一次
//  frame 写入都多付一次代价；且两个各自改值的拦截器会争夺同一个返回值，谁最后写谁赢。
//    · AWEDPlayerViewController_Merge  → 视频容器，规则统一，不分页；
//    · AWEPlayInteractionViewController → HUD，只有撑高过的表需要钉位，其余一律放行。
//

#ifndef DKVideoFullscreen_h
#define DKVideoFullscreen_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 视频全屏总开关。首页、朋友页、好友聊天页、搜索页、其他用户作品页共用。
BOOL DKVideoFullscreenOn(void);

/// 评论区几何冻结是否生效：评论区液态玻璃开着时，视频与图文一律不许被缩放平移。
BOOL DKCommentFreezeOn(void);

/// 视频容器（Merge 根视图）此刻应有的 frame；两个开关都关着或算不出来时返回 CGRectNull。
/// 写入拦截、两处重钉与调试探针共用这一个判据。
CGRect DKVideoContainerTargetFrame(UIView *view);

/// 两个矩形是否已经一致（容差覆盖 @3x 亚像素漂移）。判「要不要改写」与「达没达标」同一把尺子。
BOOL DKRectsClose(CGRect lhs, CGRect rhs);

/// 视频容器两处重钉的命中数：willDisplay（model 绑定后重算）与布局后兜底。供探针核对。
NSString *DKVideoContainerPinStats(void);

/// 拦下的「把视频挪走」写入数（来意 origin 不在原点，评论区缩放是唯一来源）。供探针核对。
/// 评论面板开合、拖拽、缩放进出全屏时视频不动，靠的就是这一条。
NSString *DKVideoContainerMoveStats(void);

/// 内嵌画中画闸门被关掉的次数。实现在 Comment/DKCommentFullBackdrop.xm。
/// 恒为 0 说明这个钩子没被调用（签名对不上），窗口作用域守卫仍在兜着。
NSString *DKCommentPiPGateStats(void);

/// 全屏评论容器此刻在不在屏。实现在 Comment/DKCommentFullBackdrop.xm。
BOOL DKCommentFullPanelOnScreen(void);

/// 全屏评论区里主播放器播完后的补播情况：命中数、期间的 pause 次数、最近一次的闸门读数。
/// 实现在 Comment/DKCommentFullBackdrop.xm。
NSString *DKCommentLoopResumeStats(void);

/// 把弹幕切回当前状态该有的可见性；全屏评论区进出时调用。
/// 实现在 Comment/DKCommentDanmaku.xm，只动接管过的那一层，不做树遍历。
void DKCommentDanmakuSyncForFullPanel(void);

/// 弹幕接管的命中数与当前可见性。供探针核对。
NSString *DKCommentDanmakuStats(void);

/// 图文要延伸到底栏的底色（整页背景渐变的末色）；取不到返回 nil。实现与调试探针共用。
/// 参数是 RichContentContainerViewController，此处按 UIViewController 收以免头文件互相依赖。
UIColor *DKRichBackdropColor(UIViewController *container);

/// 图文可见 Cell 的贴底压暗层状态：transform 后底边、Cell 满高与剩余裁剪数。供探针核对。
NSString *DKRichBottomGradientStats(UIView *collectionView);

/// 首页/朋友页 HUD 钉位：撑高 feed 表后把 HUD 高度按回撑高前的值。
/// 不在已撑高的 feed 内（含全部详情页）返回 CGRectNull 放行。
CGRect DKFeedHUDAdjustFrame(UIView *view, CGRect frame);

/// 同步评论态 HUD 顶部黑遮罩的显隐，每轮布局后调一次。
void DKHUDStatusBarCoverSync(UIViewController *interaction);

/// 该遮罩应有的高度（窗口安全区高）。实现与调试探针共用同一把尺子。
CGFloat DKHUDStatusBarCoverHeight(UIView *hudView);

/// 注册一个「开关关闭时立刻还原」的回调。各分支在 %ctor 里登记，由统一的开关项触发。
void DKVideoFullscreenRegisterRestore(void (*restore)(void));

#ifdef __cplusplus
}
#endif

#endif /* DKVideoFullscreen_h */
