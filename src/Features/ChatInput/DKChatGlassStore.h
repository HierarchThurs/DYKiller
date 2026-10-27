//
//  DKChatGlassStore.h
//  DYKiller
//
//  聊天页玻璃的槽位仓库：每个宿主对象一份，
//  记下本模块建的玻璃、清掉的原生底色与阴影、挂上的 mask。每轮同步在 begin / end 之间声明“本轮需要什么”，
//  end 时撤掉没再声明的部分并还原原生值。
//

#ifndef DKChatGlassStore_h
#define DKChatGlassStore_h

#import <UIKit/UIKit.h>

/// 玻璃的四角形状。
typedef NS_ENUM(NSInteger, DKChatGlassShape) {
    DKChatGlassShapeRounded = 0,  // 四角同一固定半径
    DKChatGlassShapeCard = 1,     // 顶部固定半径，底部与屏幕圆角同心（不小于顶部半径）
};

API_AVAILABLE(ios(26.0))
@interface DKChatGlassStore : NSObject

/// 宿主上的仓库；create 为 NO 且尚未建立时返回 nil。
+ (instancetype)storeForOwner:(id)owner create:(BOOL)create;

/// 还原并移除宿主上的仓库。
+ (void)removeStoreForOwner:(id)owner;

/// 处于 begin / end 之间；本模块写视图引发的宿主回调据此跳过重入。
@property (nonatomic, readonly) BOOL syncing;

/// 开始一轮声明，材质两档与深浅色对本轮所有玻璃生效。
- (void)beginWithClear:(BOOL)clear style:(UIUserInterfaceStyle)style;

/// 结束本轮：撤掉没再声明的玻璃与 mask，还原没再声明的底色。
- (void)end;

/// 清掉视图底色；UIVisualEffectView 连同材质一起清。返回接管前的原生底色（宿主之后写的不透明色会刷新记录）。
/// 在 begin / end 之外调用时立即接管，下一轮声明里没再出现的照常还原。
- (UIColor *)clearBackingOfView:(UIView *)view;

/// 清掉独立形状图层的填充色；下一轮未声明或关闭时恢复原生色。
- (void)clearFillOfShapeLayer:(CAShapeLayer *)layer;

/// 清掉视图图层的阴影（不透明度置 0）；下一轮未声明或关闭时恢复原生不透明度。
- (void)clearShadowOfView:(UIView *)view;

/// 该视图的底色是否已由本仓库接管。
- (BOOL)tracksBackingOfView:(UIView *)view;

/// 声明一块玻璃：挂在 carrier 最底层，frame 为 carrier 坐标；tint 为 nil 时按材质默认染色。
/// source 是它代表的业务视图，既是槽位身份也是 interactive 玻璃的触摸源。
- (UIVisualEffectView *)placeGlassFor:(UIView *)source
                                   in:(UIView *)carrier
                                frame:(CGRect)frame
                                shape:(DKChatGlassShape)shape
                               radius:(CGFloat)radius
                          interactive:(BOOL)interactive
                                 tint:(UIColor *)tint;

/// 按玻璃当前的实际四角半径把 view 裁成玻璃的形状；view 已有宿主自己的 mask 时不覆盖。
/// mask 挂在 view 的可见区域上：滚动视图滚动后由 followBoundsOfMaskedView: 跟上。
- (void)maskView:(UIView *)view toGlass:(UIVisualEffectView *)glass;

/// 滚动视图滚动后让本仓库挂的 mask 跟住可见区域；没挂 mask 时什么也不做。
- (void)followBoundsOfMaskedView:(UIView *)view;

@end

#endif /* DKChatGlassStore_h */
