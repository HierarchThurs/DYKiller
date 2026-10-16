//
//  DKAdjustRange.h
//  DYKiller
//
//  缩放与位移类设置的取值范围登记表。常规范围按抖音界面的最佳显示效果设定；
//  「扩展所有缩放与位移」开启后，各项按种类放宽到扩展范围。功能取值与设置滑条共用这一张表。
//

#ifndef DKAdjustRange_h
#define DKAdjustRange_h

#import <Foundation/Foundation.h>

/// 可扩展调整项的种类，决定扩展范围与单位。
typedef NS_ENUM(NSInteger, DKAdjustKind) {
    DKAdjustKindScale = 0,   // 百分比，扩展范围 0–200
    DKAdjustKindOffset = 1,  // pt，正值上移；扩展范围 -100–200
};

typedef struct {
    NSInteger minimum;
    NSInteger maximum;
} DKAdjustBounds;

#ifdef __cplusplus
extern "C" {
#endif

#pragma mark - 功能取值

/// 「扩展所有缩放与位移」是否开启。
BOOL DKAdjustRangeExtended(void);

/// 该项当前生效的值：存值（未设置取默认值）钳到当前生效范围。未登记的键返回 0。
NSInteger DKAdjustValue(NSString *key);

#pragma mark - 设置层

/// 已登记的键，按登记顺序。
NSArray<NSString *> *DKAdjustKeys(void);

BOOL DKAdjustIsRegistered(NSString *key);
DKAdjustKind DKAdjustKindForKey(NSString *key);
NSInteger DKAdjustDefaultValue(NSString *key);

DKAdjustBounds DKAdjustNormalBounds(NSString *key);
DKAdjustBounds DKAdjustExtendedBounds(NSString *key);
/// 扩展开启时为扩展范围，否则为常规范围。
DKAdjustBounds DKAdjustEffectiveBounds(NSString *key);

/// 数值读数，如「85%」「-20 pt」。
NSString *DKAdjustValueText(DKAdjustKind kind, NSInteger value);
/// 范围读数，如「50%–100%」「-100–200 pt」。
NSString *DKAdjustBoundsText(DKAdjustKind kind, DKAdjustBounds bounds);

/// 开关与各项的常规 / 生效范围及当前值，一段多行文字，供探针输出。
NSString *DKAdjustRangeStatus(void);

#ifdef __cplusplus
}
#endif

#endif /* DKAdjustRange_h */
