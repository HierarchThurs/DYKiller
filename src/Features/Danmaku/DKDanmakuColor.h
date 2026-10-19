// 弹幕正文与点赞信息的可复位着色，复用同一条目的配色。
#ifndef DKDanmakuColor_h
#define DKDanmakuColor_h
#import "DouyinHeaders.h"
#ifdef __cplusplus
extern "C" {
#endif
/// 只读原生竖屏弹幕不透明度，设置页使用；不可读取时返回 1。
double DKDanmakuNativeAlpha(void);
void DKDanmakuColorRefresh(void);
/// Hook 介入的条件：功能开着，或条目 / Label 上还留有本功能的状态（关闭后等复用时清理）。
BOOL DKDanmakuViewEngaged(AWEDanmakuItemCommonView *view);
BOOL DKDanmakuLabelEngaged(UILabel *label);
void DKDanmakuBeginEntry(AWEDanmakuItemCommonView *view, id descriptor);
void DKDanmakuBeginUpdate(AWEDanmakuItemCommonView *view, BOOL newEntry);
void DKDanmakuEndUpdate(AWEDanmakuItemCommonView *view);
void DKDanmakuResetView(AWEDanmakuItemCommonView *view);
void DKDanmakuTrackView(AWEDanmakuItemCommonView *view);
/// 仅认条目 diggNumView 指向的直接子视图。
AWEDanmakuItemCommonView *DKDanmakuDiggOwner(AWEDanmakuDiggNumView *view);
void DKDanmakuLayoutDigg(AWEDanmakuDiggNumView *view);
BOOL DKDanmakuOwnWrite(UILabel *label);
void DKDanmakuNativeWriteBegin(AWEDanmakuContentLabel *label);
void DKDanmakuNativeWriteFinished(AWEDanmakuContentLabel *label);
void DKDanmakuBeginDraw(UILabel *label);
void DKDanmakuEndDraw(UILabel *label);
/// 诊断：设置值与已登记条目的接管状态。
NSString *DKDanmakuColorStatus(void);
#ifdef __cplusplus
}
#endif
#endif
