//
//  DKChatInputPendant.h
//  DYKiller
//
//  聊天页小火人挂件：吸附在输入区时（键盘、表情面板、加号面板）水平居中到输入行中线，
//  趴在输入胶囊上；纵向位置与其它状态保持原生。
//

#ifndef DKChatInputPendant_h
#define DKChatInputPendant_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 设置变化时按当前设置重新定位见过的挂件（不生效时回到原生横向位置）。
void DKChatInputPendantRefresh(void);

#ifdef __cplusplus
}
#endif

#endif /* DKChatInputPendant_h */
