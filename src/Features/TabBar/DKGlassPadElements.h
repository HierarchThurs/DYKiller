//
//  DKGlassPadElements.h
//  iPad 玻璃底栏的位置（默认 / 左端 / 右端）与两侧元素按钮（连播 / 弹幕 / 倍速等）的液态玻璃。
//  非 iPad 时两个入口都原样返回，不读写任何视图。
//

#ifndef DKGlassPadElements_h
#define DKGlassPadElements_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 玻璃组（胶囊 + 拍摄圆键）在抖音底栏内的左缘。groupFrame 为居中时的几何；
/// 未选靠边、非 iPad，或靠边后与元素按钮放不下时返回居中值。
CGFloat DKGlassPadGroupLeft(UIView *douyinBar, CGRect groupFrame);

/// 按当前位置重排两侧元素按钮并同步其玻璃。groupFrame 传 CGRectNull 表示玻璃底栏已关闭，全部还原。
void DKGlassPadElementsLayout(UIView *douyinBar, CGRect groupFrame);

/// 元素按钮玻璃的当前读数，一句话自述，供调试导出。
NSString *DKGlassPadElementsStatus(void);

#ifdef __cplusplus
}
#endif

#endif /* DKGlassPadElements_h */
