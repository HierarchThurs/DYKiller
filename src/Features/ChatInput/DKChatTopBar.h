// 聊天页顶栏：材质同步与设置变化后的原生重排。
#ifndef DKChatTopBar_h
#define DKChatTopBar_h
#import <UIKit/UIKit.h>
#ifdef __cplusplus
extern "C" {
#endif
void DKChatTopBarRefresh(void);
void DKChatTopBarSync(UIView *bar);
/// 原生页面布局期间撤销顶部位移，写入完成后同步最终几何。
void DKChatTopBarNativeLayout(UIViewController *host, dispatch_block_t nativeLayout);
void DKChatTopCleanRefresh(void);
/// 居中布局是否已把该在线圆点移出头像（挪到在线文字左侧或淡出）。
BOOL DKChatTopOnlineDotAway(UIView *dot);
/// 按圆点当前是否留在头像上，重设所属头像的原生缺口遮罩。
void DKChatTopAvatarNotchSync(UIView *dot);
/// 居中头像时顶部区域比原生导航高出的量；未居中或未开启玻璃时为 0。
CGFloat DKChatTopHeaderExtra(UIViewController *host);
#ifdef __cplusplus
}
#endif
#endif
