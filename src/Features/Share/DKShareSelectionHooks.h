// 分享评论选人状态与发送按钮布局的同步接口。
#ifndef DKShareSelectionHooks_h
#define DKShareSelectionHooks_h

#import <UIKit/UIKit.h>

// 选人回调结束后同步输入区；overlay 可在状态回调中为空。
BOOL DKShareCommentSelectionChanged(id section, UIView *overlay);
// 发送按钮完成自身布局后挂载玻璃；返回是否首次挂载。
BOOL DKShareSendButtonDidLayout(UIView *button);
// Hook 安装与回调计数。
NSString *DKShareSelectionHooksStatus(void);
NSString *DKShareSelectionDiagnostics(void);

#endif
