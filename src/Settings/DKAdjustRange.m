//
//  DKAdjustRange.m
//  DYKiller
//
//  缩放与位移类设置的登记表。新增这类设置时在 DKAdjustLoad 的登记段加一行，
//  设置项用 DKMakeAdjustSlider，功能取值用 DKAdjustValue；确认弹窗与探针按表自动列出。
//

#import "DKAdjustRange.h"
#import "DKKeys.h"

@interface DKAdjustSpec : NSObject
@property (nonatomic, readonly) DKAdjustKind kind;
@property (nonatomic, readonly) DKAdjustBounds normal;
@property (nonatomic, readonly) NSInteger defaultValue;
@end

@implementation DKAdjustSpec
- (instancetype)initWithKind:(DKAdjustKind)kind minimum:(NSInteger)minimum maximum:(NSInteger)maximum
                defaultValue:(NSInteger)defaultValue {
    if ((self = [super init])) {
        _kind = kind;
        _normal = (DKAdjustBounds){ minimum, maximum };
        _defaultValue = defaultValue;
    }
    return self;
}
@end

static void DKAdjustAdd(NSMutableArray<NSString *> *keys, NSMutableDictionary<NSString *, DKAdjustSpec *> *specs,
                        NSString *key, DKAdjustKind kind, NSInteger minimum, NSInteger maximum, NSInteger defaultValue) {
    [keys addObject:key];
    specs[key] = [[DKAdjustSpec alloc] initWithKind:kind minimum:minimum maximum:maximum defaultValue:defaultValue];
}

static void DKAdjustLoad(NSArray<NSString *> **outKeys, NSDictionary<NSString *, DKAdjustSpec *> **outSpecs) {
    static NSArray<NSString *> *keys;
    static NSDictionary<NSString *, DKAdjustSpec *> *specs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray<NSString *> *list = [NSMutableArray array];
        NSMutableDictionary<NSString *, DKAdjustSpec *> *map = [NSMutableDictionary dictionary];
        // 互动按钮
        DKAdjustAdd(list, map, DKKeyInteractionScale, DKAdjustKindScale, 50, 100, 100);
        DKAdjustAdd(list, map, DKKeyAvatarScale, DKAdjustKindScale, 50, 100, 100);
        DKAdjustAdd(list, map, DKKeyMusicScale, DKAdjustKindScale, 50, 100, 100);
        DKAdjustAdd(list, map, DKKeyInteractionOffset, DKAdjustKindOffset, 0, 100, 0);
        // 昵称文案
        DKAdjustAdd(list, map, DKKeyNicknameScale, DKAdjustKindScale, 25, 100, 100);
        DKAdjustAdd(list, map, DKKeyDescriptionScale, DKAdjustKindScale, 25, 100, 100);
        DKAdjustAdd(list, map, DKKeyInfoOffset, DKAdjustKindOffset, 0, 100, 0);
        // 进度条与图片指示器
        DKAdjustAdd(list, map, DKKeyProgressOffset, DKAdjustKindOffset, 0, 100, 0);
        DKAdjustAdd(list, map, DKKeyStoryIndicatorOffset, DKAdjustKindOffset, 0, 100, 0);
        // 悬浮玻璃底栏
        DKAdjustAdd(list, map, DKKeyGlassTabBarCapsuleHeight, DKAdjustKindScale, 60, 100, 100);
        DKAdjustAdd(list, map, DKKeyGlassTabBarCapsuleLength, DKAdjustKindScale, 80, 100, 100);
        DKAdjustAdd(list, map, DKKeyGlassTabBarPlusSize, DKAdjustKindScale, 60, 100, 100);
        keys = [list copy];
        specs = [map copy];
    });
    if (outKeys) *outKeys = keys;
    if (outSpecs) *outSpecs = specs;
}

static DKAdjustSpec *DKAdjustSpecForKey(NSString *key) {
    NSDictionary<NSString *, DKAdjustSpec *> *specs = nil;
    DKAdjustLoad(NULL, &specs);
    return key ? specs[key] : nil;
}

static NSInteger DKAdjustClamp(NSInteger value, DKAdjustBounds bounds) {
    return MIN(bounds.maximum, MAX(bounds.minimum, value));
}

#pragma mark - 功能取值

BOOL DKAdjustRangeExtended(void) {
    return [NSUserDefaults.standardUserDefaults boolForKey:DKKeyAdjustRangeExtended];
}

NSInteger DKAdjustValue(NSString *key) {
    DKAdjustSpec *spec = DKAdjustSpecForKey(key);
    if (!spec) return 0;
    id raw = [NSUserDefaults.standardUserDefaults objectForKey:key];
    NSInteger value = [raw respondsToSelector:@selector(integerValue)] ? [raw integerValue] : spec.defaultValue;
    return DKAdjustClamp(value, DKAdjustEffectiveBounds(key));
}

#pragma mark - 设置层

NSArray<NSString *> *DKAdjustKeys(void) {
    NSArray<NSString *> *keys = nil;
    DKAdjustLoad(&keys, NULL);
    return keys;
}

BOOL DKAdjustIsRegistered(NSString *key) {
    return DKAdjustSpecForKey(key) != nil;
}

DKAdjustKind DKAdjustKindForKey(NSString *key) {
    return DKAdjustSpecForKey(key).kind;
}

NSInteger DKAdjustDefaultValue(NSString *key) {
    return DKAdjustSpecForKey(key).defaultValue;
}

DKAdjustBounds DKAdjustNormalBounds(NSString *key) {
    DKAdjustSpec *spec = DKAdjustSpecForKey(key);
    return spec ? spec.normal : (DKAdjustBounds){ 0, 0 };
}

DKAdjustBounds DKAdjustExtendedBounds(NSString *key) {
    DKAdjustSpec *spec = DKAdjustSpecForKey(key);
    if (!spec) return (DKAdjustBounds){ 0, 0 };
    switch (spec.kind) {
        case DKAdjustKindScale: return (DKAdjustBounds){ 0, 200 };
        case DKAdjustKindOffset: return (DKAdjustBounds){ -100, 200 };
    }
    return spec.normal;
}

DKAdjustBounds DKAdjustEffectiveBounds(NSString *key) {
    return DKAdjustRangeExtended() ? DKAdjustExtendedBounds(key) : DKAdjustNormalBounds(key);
}

NSString *DKAdjustValueText(DKAdjustKind kind, NSInteger value) {
    return kind == DKAdjustKindOffset ? [NSString stringWithFormat:@"%ld pt", (long)value]
                                      : [NSString stringWithFormat:@"%ld%%", (long)value];
}

NSString *DKAdjustBoundsText(DKAdjustKind kind, DKAdjustBounds bounds) {
    return kind == DKAdjustKindOffset
        ? [NSString stringWithFormat:@"%ld–%ld pt", (long)bounds.minimum, (long)bounds.maximum]
        : [NSString stringWithFormat:@"%ld%%–%ld%%", (long)bounds.minimum, (long)bounds.maximum];
}

NSString *DKAdjustRangeStatus(void) {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"扩展所有缩放与位移=%@\n", DKAdjustRangeExtended() ? @"开" : @"关"];
    for (NSString *key in DKAdjustKeys()) {
        DKAdjustKind kind = DKAdjustKindForKey(key);
        id raw = [NSUserDefaults.standardUserDefaults objectForKey:key];
        [out appendFormat:@"  %@ 常规=%@ 生效=%@ 存值=%@ 生效值=%@\n", key,
            DKAdjustBoundsText(kind, DKAdjustNormalBounds(key)),
            DKAdjustBoundsText(kind, DKAdjustEffectiveBounds(key)),
            raw ?: @"(未设置)", DKAdjustValueText(kind, DKAdjustValue(key))];
    }
    return out;
}
