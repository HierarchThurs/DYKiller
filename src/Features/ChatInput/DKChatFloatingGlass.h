//
//  DKChatFloatingGlass.h
//  DYKiller
//
//  聊天页浮动容器里的玻璃：表情提示条的每个芯片一块胶囊玻璃，最近照片条一块悬浮卡片。
//  浮动容器是输入页的兄弟层，芯片与照片条各自持有仓库，随宿主的布局、样式与进入窗口回调同步。
//

#ifndef DKChatFloatingGlass_h
#define DKChatFloatingGlass_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 设置变化或输入页出现时，把见过的芯片与照片条按当前设置重新同步（不生效时还原）。
void DKChatFloatingGlassRefresh(void);

#ifdef __cplusplus
}
#endif

#endif /* DKChatFloatingGlass_h */
