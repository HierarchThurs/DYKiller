#ifndef DKInteractionIconPicker_h
#define DKInteractionIconPicker_h
#import <UIKit/UIKit.h>
#import "DKInteractionIconRules.h"
#ifdef __cplusplus
extern "C" {
#endif
/// 成功更换或清除后调用 didChange；取消和失败不提交。
void DKInteractionIconShowPicker(DKInteractionIconSlot slot, UIViewController *presenter, void (^didChange)(BOOL hasImage));
#ifdef __cplusplus
}
#endif
#endif
