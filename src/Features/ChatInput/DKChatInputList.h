//
//  DKChatInputList.h
//  DYKiller
//
//  悬浮输入区下的消息列表：未弹出键盘时，列表容器与表格延伸到聊天页底部，
//  底部 inset 同步增加同样的量，最后一条消息仍停在原生位置，滑动时从输入区与面板下方经过。
//

#ifndef DKChatInputList_h
#define DKChatInputList_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 设置变化或输入页出现时，按当前状态撤掉或重新延伸已登记的消息列表。
void DKChatInputListRefresh(void);

#ifdef __cplusplus
}
#endif

#endif /* DKChatInputList_h */
