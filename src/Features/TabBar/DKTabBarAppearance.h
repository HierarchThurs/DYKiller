//
//  DKTabBarAppearance.h
//  DYKiller
//
//  外观定制：底栏样式（默认 / 单图标 / 图标+文字）、拍摄按钮（默认 / 新图标 / 新双色图标 / 自定义图片）
//  与底栏文字。悬浮玻璃底栏与抖音原生底栏共用这里的取值。
//

#ifndef DKTabBarAppearance_h
#define DKTabBarAppearance_h

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, DKTabBarStyle) {
    DKTabBarStyleDefault = 0,
    DKTabBarStyleIcon = 1,
    DKTabBarStyleIconText = 2,
};

typedef NS_ENUM(NSInteger, DKPlusStyle) {
    DKPlusStyleDefault = 0,
    DKPlusStyleCamera = 1,
    DKPlusStyleBrand = 2,
    DKPlusStyleCustom = 3,
};

#ifdef __cplusplus
extern "C" {
#endif

/// 底栏样式；越界按默认。
DKTabBarStyle DKTabBarCurrentStyle(void);

/// 拍摄按钮实际生效的样式：选了「自定义图片」但还没有图片时按默认。只在主线程调用。
DKPlusStyle DKPlusCurrentStyle(void);

/// 该 tab 的自定义文字；未设置返回 nil。
NSString *DKTabBarCustomTitle(NSString *tabID);

/// 立即按当前设置重排底栏文字、图标与拍摄按钮（两种底栏都会跟上）。
void DKTabBarAppearanceRefresh(void);

/// 当前外观状态，一段多行文字，供探针输出。
NSString *DKTabBarAppearanceStatus(void);

#ifdef __cplusplus
}
#endif

#endif /* DKTabBarAppearance_h */
