#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 按当前 iPad 评论布局同步原生背景遮罩，仅由评论区液态玻璃控制。
void DKCommentPadBackdropSync(UIViewController *controller);

/// 设置改动后同步已接管的评论容器。
void DKCommentPadBackdropRefresh(void);

#ifdef __cplusplus
}
#endif
