//
//  DKListenGlass.h
//  听抖音页液态玻璃的模块间接口。
//

#ifndef DKListenGlass_h
#define DKListenGlass_h

#import "DKChatGlassStore.h"
#import "DKGlassGuard.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import <UIKit/UIKit.h>

static inline BOOL DKListenGlassOn(void) {
    return DKGlassOSAvailable() && DKPrefBool(DKKeyListenFeedGlass);
}

// 听抖音页的文字恒为白色，玻璃固定按深色配置。
API_AVAILABLE(ios(26.0))
static inline void DKListenGlassBegin(DKChatGlassStore *store) {
    [store beginWithClear:DKPrefBool(DKKeyListenFeedGlassClear) style:UIUserInterfaceStyleDark];
}

#ifdef __cplusplus
extern "C" {
#endif

/// 同步页面顶部的返回圆钮与标题胶囊；title 为 nil 时只处理返回键，titleExtra 是标题视图右侧多画的宽度。
void DKListenGlassSyncNav(UIView *host, UIButton *back, UIView *title, CGFloat titleExtra);

/// 打开或还原视图的裁剪，原值记在视图上。
void DKListenGlassSetUnclipped(UIView *view, BOOL unclipped);

/// 开关改值后刷新各模块。
void DKListenControlGlassRefresh(void);
void DKListenPlayerGlassRefresh(void);
void DKListenFilterListGlassRefresh(void);

#ifdef __cplusplus
}
#endif

#endif /* DKListenGlass_h */
