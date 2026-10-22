//
//  DKChatEmojiTabGlass.h
//  DYKiller
//
//  表情面板顶部页签的玻璃：搜索入口一枚圆钮，每个页签一块胶囊，选中页签用着色玻璃并撤掉原生白底。
//  页签格子与面板各自持有仓库，随原生的选中刷新、布局与进入窗口回调同步；评论区等复用场景不接管。
//

#ifndef DKChatEmojiTabGlass_h
#define DKChatEmojiTabGlass_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 设置或外观变化时，把见过的页签与搜索入口按当前设置重新同步（不生效时还原）。
void DKChatEmojiTabGlassRefresh(void);

#ifdef __cplusplus
}
#endif

#endif /* DKChatEmojiTabGlass_h */
