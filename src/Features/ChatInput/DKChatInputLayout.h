//
//  DKChatInputLayout.h
//  DYKiller
//
//  聊天输入区的悬浮几何：行内槽位（左右圆钮 + 胶囊）的纯计算、按原生左右分组取按钮、
//  输入框文字区的 contentInset。同步入口 DKChatInputSync（声明在 DKChatInput.h）也在本模块实现。
//

#ifndef DKChatInputLayout_h
#define DKChatInputLayout_h

#import <UIKit/UIKit.h>

#define DKChatRowLeftLimit 2
#define DKChatRowRightLimit 4

/// 行内槽位（输入行元素容器坐标）：胶囊、左侧圆钮与右侧圆钮，左右各按原生数组顺序从左到右。
typedef struct {
    CGRect capsule;
    CGRect left[DKChatRowLeftLimit];
    NSUInteger leftCount;
    CGRect right[DKChatRowRightLimit];
    NSUInteger rightCount;
} DKChatRowFrames;

/// 元件之间的统一间距。
extern const CGFloat kDKChatRowGap;
/// 圆钮直径上限，等于单行输入行高度。
extern const CGFloat kDKChatButtonDiameter;
/// 文字距胶囊左右边缘的留白。
extern const CGFloat kDKChatCapsuleTextPadding;
/// 悬浮卡片（面板、最近照片条）左右与底部内缩。
extern const CGFloat kDKChatPanelInset;
/// 面板卡片的顶部圆角，底部与屏幕圆角同心且不小于它。
extern const CGFloat kDKChatPanelRadius;

#ifdef __cplusplus
extern "C" {
#endif

/// 由元素带与左右圆钮个数算行内槽位：圆钮直径 = MIN(band 高, kDKChatButtonDiameter)、底边对齐元素带；
/// 左组贴 band.minX、右组贴 band.maxX，按 kDKChatRowGap 排开，胶囊占中间。个数越界时返回全零。
DKChatRowFrames DKChatRowFramesMake(CGRect band, NSUInteger leftCount, NSUInteger rightCount);

/// 本轮参与布局的左右按钮：原生左右数组里仍在元素容器内、且没有被隐藏的按钮，保持原生顺序。
void DKChatInputRowButtons(id layout, NSArray<UIView *> **left, NSArray<UIView *> **right);

/// 当前行内槽位；没有输入背景槽或按钮超出上限时返回 NO。
BOOL DKChatInputRowFrames(id layout, DKChatRowFrames *frames);

/// 输入框 contentInset：左右让文字落在胶囊内并留 kDKChatCapsuleTextPadding，上下沿用原生值；
/// 功能不生效或 growing 不是该输入页的输入框时原样返回 native。
UIEdgeInsets DKChatInputTextInsets(id layout, UIView *growing, UIEdgeInsets native);

/// 当前系统外观（场景优先），玻璃的深浅色与 Clear 染色按它取。
UIUserInterfaceStyle DKChatInputStyle(UIViewController *input);

#ifdef __cplusplus
}
#endif

#endif /* DKChatInputLayout_h */
