//
//  DKChatFloatingGlass.h
//  DYKiller
//
//  聊天页浮动层的玻璃：表情提示条的每个芯片一块胶囊玻璃，最近照片条一块悬浮卡片，
//  消息列表底部的回到最新 / 新消息提示一块同形玻璃。
//  三者都是输入页之外的兄弟层，各自持有仓库，随宿主的布局、样式与进入窗口回调同步。
//

#ifndef DKChatFloatingGlass_h
#define DKChatFloatingGlass_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 设置变化或输入页出现时，把见过的芯片、照片条与底部提示按当前设置重新同步（不生效时还原）。
void DKChatFloatingGlassRefresh(void);

#ifdef __cplusplus
}
#endif

#endif /* DKChatFloatingGlass_h */
