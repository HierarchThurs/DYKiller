//
//  DKChatTopCenter.h
//  DYKiller
//
//  聊天顶栏居中头像的纯几何：头像居中，名称胶囊在头像下方，火花与在线信息按设置放进名称胶囊或两侧胶囊。
//  所有坐标都在顶栏内容行（carrier）坐标系内。
//

#ifndef DKChatTopCenter_h
#define DKChatTopCenter_h

#import <UIKit/UIKit.h>

/// 火花 / 在线信息的位置，与设置存值一致。
typedef NS_ENUM(NSInteger, DKChatTopPlace) {
    DKChatTopPlaceCenter = 0,
    DKChatTopPlaceLeft = 1,
    DKChatTopPlaceRight = 2,
};

/// 一项附加信息：输入原生尺寸与位置，输出目标中心与缩放。尺寸为空表示没有这一项。
typedef struct {
    CGSize size;
    DKChatTopPlace place;
    CGPoint center;
    CGFloat scale;
} DKChatTopPiece;

typedef struct {
    CGRect row;           // 顶栏行，玻璃与它同高
    CGFloat leftEdge;     // 左侧胶囊的起点（返回胶囊右侧留出间距后）
    CGFloat rightEdge;    // 右侧胶囊的终点（通话 / 菜单左侧留出间距后）
    CGFloat avatarSide;   // 居中头像边长
    CGSize name;          // 名称行（名称 + 人数）
    DKChatTopPiece streak;
    DKChatTopPiece online;
} DKChatTopCenterSpec;

typedef struct {
    CGRect avatar;
    CGRect capsule;       // 名称胶囊
    CGFloat capsuleRadius;
    CGPoint nameCenter;
    CGRect left;          // 左侧胶囊，没有时为 CGRectNull
    CGRect right;         // 右侧胶囊，没有时为 CGRectNull
    DKChatTopPiece streak;
    DKChatTopPiece online;
} DKChatTopCenterFrames;

/// 居中头像边长。
extern const CGFloat kDKChatTopAvatarSide;

#ifdef __cplusplus
extern "C" {
#endif

/// 居中布局：头像水平居中，边长大于行高时顶边比行顶高 2pt；名称胶囊压住头像底边 2pt，居中项依次（火花、在线）并入胶囊。
/// 同侧两项合并成一个胶囊（火花在上），放不下时整体等比缩小，空间足够时保持原尺寸、不放大。
DKChatTopCenterFrames DKChatTopCenterFramesMake(DKChatTopCenterSpec spec);

#ifdef __cplusplus
}
#endif

#endif /* DKChatTopCenter_h */
