//
//  DKChatTopBlur.h
//  DYKiller
//
//  聊天页顶部渐变模糊：独立系统模糊视图放在导航下方，从顶栏内容底边向屏幕顶部加深。
//

#ifndef DKChatTopBlur_h
#define DKChatTopBlur_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// bottom 为 bar 坐标中的内容底边；启用时暂时关闭表格顶部边缘效果，撤销时恢复。
void DKChatTopBlurSync(UIView *bar, UIScrollView *table, CGFloat bottom,
                       UIUserInterfaceStyle style, BOOL wanted) API_AVAILABLE(ios(26.0));

#ifdef __cplusplus
}
#endif

#endif /* DKChatTopBlur_h */
