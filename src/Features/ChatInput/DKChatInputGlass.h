//
//  DKChatInputGlass.h
//  DYKiller
//
//  聊天输入区的玻璃：输入行（胶囊 + 圆钮）、表情 / 加号面板卡片，以及原生背景模糊层与底色的接管。
//  几何由 DKChatInputSync 先写好，这里只按当前原生几何建玻璃。
//

#ifndef DKChatInputGlass_h
#define DKChatInputGlass_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 输入行与面板的玻璃：按当前原生几何建 / 更新槽位，撤掉不再需要的槽位并还原接管过的底色。
void DKChatInputGlassApply(id layout, BOOL clear, UIUserInterfaceStyle style);

/// 撤掉输入行与面板的全部玻璃并还原接管过的底色与 mask。
void DKChatInputGlassRestore(id layout);

#ifdef __cplusplus
}
#endif

#endif /* DKChatInputGlass_h */
