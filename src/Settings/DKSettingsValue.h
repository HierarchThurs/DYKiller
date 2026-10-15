//
//  DKSettingsValue.h
//  设置项落盘值的说明：种类、存储位置与取值约束，以及读当前值、规范化外来值、写入。
//  备份工具据此导出、校验与恢复。只依赖 Foundation、ImageIO 与 CommonCrypto。
//

#ifndef DKSettingsValue_h
#define DKSettingsValue_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 设置值的读写来源。正式环境为 NSUserDefaults.standardUserDefaults。
@protocol DKSettingsStore <NSObject>
- (nullable id)objectForKey:(NSString *)key;
- (void)setObject:(nullable id)value forKey:(NSString *)key;
- (void)removeObjectForKey:(NSString *)key;
/// 以 prefix 开头的全部键。
- (NSArray<NSString *> *)dk_keysWithPrefix:(NSString *)prefix;
@end

@interface NSUserDefaults (DKSettingsStore) <DKSettingsStore>
@end

/// 由规范值得到展示文案。values 与声明的 values 一一对应，「未设置」为 NSNull。
/// brief 为 YES 时返回行内短文案，NO 时返回完整文案；两者相同的项可忽略 brief。
typedef NSString *_Nonnull (^DKSettingsDescribe)(NSArray *values, BOOL brief);

typedef NS_ENUM(NSInteger, DKSettingsValueKind) {
    DKSettingsValueKindBool,      // NSUserDefaults BOOL
    DKSettingsValueKindInteger,   // NSUserDefaults 整数，限定范围
    DKSettingsValueKindIDSet,     // 「前缀 + ID」一族 BOOL 键（多选），值为选中的 ID
    DKSettingsValueKindImage,     // 沙盒内的图片文件，值为文件数据
};

@interface DKSettingsValue : NSObject

@property (nonatomic, readonly) DKSettingsValueKind kind;
/// 备份里的名字：Bool / Integer 为 NSUserDefaults 键，IDSet 为键前缀，Image 为图片名。
@property (nonatomic, copy, readonly) NSString *key;
@property (nonatomic, readonly) long long minimum;                           // Integer
@property (nonatomic, readonly) long long maximum;                           // Integer
@property (nonatomic, copy, readonly, nullable) NSString *path;              // Image：文件路径
@property (nonatomic, copy, readonly, nullable) NSArray<NSString *> *imageTypes;   // Image：允许的 UTType
@property (nonatomic, readonly) NSUInteger maxBytes;                         // Image
@property (nonatomic, readonly) NSUInteger minSide;                          // Image：像素
@property (nonatomic, readonly) NSUInteger maxSide;                          // Image：像素
@property (nonatomic, readonly) BOOL square;                                 // Image

+ (instancetype)boolWithKey:(NSString *)key;
+ (instancetype)integerWithKey:(NSString *)key minimum:(long long)minimum maximum:(long long)maximum;
+ (instancetype)idSetWithPrefix:(NSString *)prefix;
/// 图片文件。types 为允许的 UTType 标识（如 public.png）；GIF 允许多帧，其余类型只允许单帧。
+ (instancetype)imageWithName:(NSString *)name path:(NSString *)path types:(NSArray<NSString *> *)types
                     maxBytes:(NSUInteger)maxBytes minSide:(NSUInteger)minSide maxSide:(NSUInteger)maxSide
                       square:(BOOL)square;

- (instancetype)init NS_UNAVAILABLE;

/// 规范化：合法时返回规范值——Bool 为 @YES / @NO，Integer 为 NSNumber，IDSet 为排好序的 ID 数组
/// （nil / NSNull 视为空集），Image 为文件数据；「未设置」返回 NSNull。不合法返回 nil，reason 给出原因。
- (nullable id)normalize:(nullable id)raw reason:(NSString *_Nullable *_Nullable)reason;

/// 当前存值的规范值。存值不合法时按未设置；Image 只读文件，不做图片校验（超过 maxBytes 按未设置）。
- (id)currentValueInStore:(id<DKSettingsStore>)store;

/// 写入 Bool / Integer / IDSet 的规范值；NSNull 清除存值，IDSet 清掉不在新集合里的键。
/// Image 由 DKBackupStore 两段式提交，这里不处理。
- (void)writeValue:(id)value toStore:(id<DKSettingsStore>)store;

@end

NS_ASSUME_NONNULL_END

#endif /* DKSettingsValue_h */
