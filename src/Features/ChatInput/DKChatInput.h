//
//  DKChatInput.h
//  DYKiller
//
//  聊天输入区：普通私聊/群聊宿主判定、组件查找、布局登记，以及悬浮玻璃的单一同步入口。
//  抖音私有类声明集中在 DouyinHeaders.h 的「聊天输入功能组用到的类」分区。
//

#ifndef DKChatInput_h
#define DKChatInput_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 对象是否属于某个抖音类（类不存在或对象为 nil 时为假）。
BOOL DKChatInputIsKind(id object, NSString *className);

/// 读取对象上某个对象类型 ivar（对象为 nil、ivar 不存在或非对象类型时返回 nil）。
id DKChatInputObjectIvar(id object, const char *name);

/// 组件所属的普通聊天输入控制器；公司会话、POI 会话、作品详情、图文详情内返回 nil。
UIViewController *DKChatInputController(id component);

/// 聊天页内任意视图（浮动容器、消息列表等输入页之外的兄弟层）所属的普通聊天输入控制器，规则同上。
UIViewController *DKChatInputControllerForPageView(UIView *view);

/// 悬浮玻璃对该输入页是否生效：系统支持、开关打开、输入页已加载，可在进入窗口前准备。
BOOL DKChatInputGlassWanted(UIViewController *input);

/// 同一组件管理器内的语义组件（按类名），找不到返回 nil。
id DKChatInputComponent(id component, NSString *className);

/// 输入行布局对象：布局回调里登记、按输入页内视图或输入控制器反查、取全部在场对象。
void DKChatInputRegisterLayout(id layout);
id DKChatInputLayoutForView(UIView *view);
id DKChatInputLayoutForController(UIViewController *input);
NSArray *DKChatInputLayouts(void);

/// 设置变化后的立即刷新（主线程）：输入行重排，消息列表、浮动层、表情页签与小火人重新同步。
void DKChatInputRefresh(void);

/// 表情提示条的即时刷新（设置变化时调用）。
void DKChatInputCleanRefresh(void);

/// 单一同步入口：输入行几何 → 原生背景模糊层 → 输入行与面板玻璃。
void DKChatInputSync(id layout);

/// 关闭功能或离场时还原：玻璃、原生 effect 与接管过的底色。
/// 行内 frame 与文字区 inset 不存原值——原生下一次布局会自己算回去。
void DKChatInputRestore(id layout);

#ifdef __cplusplus
}
#endif

#endif /* DKChatInput_h */
