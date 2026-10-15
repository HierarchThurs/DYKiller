//
//  DKSettingsValue.m
//

#import "DKSettingsValue.h"
#import <ImageIO/ImageIO.h>
#import <math.h>

// 多选一族键的条数上限与单个 ID 的长度上限。
static const NSUInteger kDKMaxSetCount = 512;
static const NSUInteger kDKMaxIDLength = 128;

@implementation NSUserDefaults (DKSettingsStore)

- (NSArray<NSString *> *)dk_keysWithPrefix:(NSString *)prefix {
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (NSString *key in self.dictionaryRepresentation) {
        if ([key isKindOfClass:NSString.class] && [key hasPrefix:prefix]) [keys addObject:key];
    }
    return keys;
}

@end

static void DKSetReason(NSString **reason, NSString *text) {
    if (reason) *reason = text;
}

static BOOL DKIsBoolNumber(id raw) {
    return [raw isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)raw) == CFBooleanGetTypeID();
}

// 整数型 NSNumber 直接取值；浮点型须为整数值且在 long long 范围内。
static BOOL DKIntegerFromNumber(NSNumber *number, long long *value) {
    if (![number isKindOfClass:NSNumber.class] || DKIsBoolNumber(number)) return NO;
    switch (number.objCType[0]) {
        case 'c': case 's': case 'i': case 'l': case 'q':
        case 'C': case 'S': case 'I':
            *value = number.longLongValue;
            return YES;
        case 'L': case 'Q':
            if (number.unsignedLongLongValue > (unsigned long long)LLONG_MAX) return NO;
            *value = number.longLongValue;
            return YES;
        case 'f': case 'd': {
            double d = number.doubleValue;
            if (!isfinite(d) || d != floor(d) || d < -9223372036854775808.0 || d >= 9223372036854775808.0) return NO;
            *value = (long long)d;
            return YES;
        }
        default:
            return NO;
    }
}

// 纯数字字符串（可带负号），兼容早期把数值存成字符串的设置。
static BOOL DKIntegerFromString(NSString *text, long long *value) {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    BOOL negative = [trimmed hasPrefix:@"-"];
    NSString *digits = negative ? [trimmed substringFromIndex:1] : trimmed;
    if (digits.length == 0 || digits.length > 19) return NO;
    unsigned long long limit = negative ? (unsigned long long)LLONG_MAX + 1ULL : (unsigned long long)LLONG_MAX;
    unsigned long long number = 0;
    for (NSUInteger i = 0; i < digits.length; i++) {
        unichar c = [digits characterAtIndex:i];
        if (c < '0' || c > '9') return NO;
        unsigned int digit = c - '0';
        if (number > (limit - digit) / 10) return NO;
        number = number * 10 + digit;
    }
    *value = negative ? (long long)(0ULL - number) : (long long)number;
    return YES;
}

static BOOL DKValidID(id raw) {
    if (![raw isKindOfClass:NSString.class]) return NO;
    NSString *text = raw;
    if (text.length == 0 || text.length > kDKMaxIDLength) return NO;
    static NSCharacterSet *invalid;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *set = [NSCharacterSet.controlCharacterSet mutableCopy];
        [set formUnionWithCharacterSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        invalid = [set copy];
    });
    return [text rangeOfCharacterFromSet:invalid].location == NSNotFound;
}

NSUInteger DKSettingsTextWidth(NSString *text) {
    __block NSUInteger width = 0;
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length)
                             options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(NSString *piece, __unused NSRange range, __unused NSRange enclosing, __unused BOOL *stop) {
        width += (piece.length == 1 && [piece characterAtIndex:0] < 0x80) ? 1 : 2;
    }];
    return width;
}

@implementation DKSettingsValue

- (instancetype)initWithKind:(DKSettingsValueKind)kind key:(NSString *)key {
    if ((self = [super init])) {
        _kind = kind;
        _key = [key copy];
    }
    return self;
}

+ (instancetype)boolWithKey:(NSString *)key {
    return [[self alloc] initWithKind:DKSettingsValueKindBool key:key];
}

+ (instancetype)integerWithKey:(NSString *)key minimum:(long long)minimum maximum:(long long)maximum {
    DKSettingsValue *value = [[self alloc] initWithKind:DKSettingsValueKindInteger key:key];
    value->_minimum = minimum;
    value->_maximum = maximum;
    return value;
}

+ (instancetype)idSetWithPrefix:(NSString *)prefix {
    return [[self alloc] initWithKind:DKSettingsValueKindIDSet key:prefix];
}

+ (instancetype)stringWithKey:(NSString *)key maxWidth:(NSUInteger)maxWidth {
    DKSettingsValue *value = [[self alloc] initWithKind:DKSettingsValueKindString key:key];
    value->_maxWidth = maxWidth;
    return value;
}

+ (instancetype)imageWithName:(NSString *)name path:(NSString *)path types:(NSArray<NSString *> *)types
                     maxBytes:(NSUInteger)maxBytes minSide:(NSUInteger)minSide maxSide:(NSUInteger)maxSide
                       square:(BOOL)square {
    DKSettingsValue *value = [[self alloc] initWithKind:DKSettingsValueKindImage key:name];
    value->_path = [path copy];
    value->_imageTypes = [types copy];
    value->_maxBytes = maxBytes;
    value->_minSide = minSide;
    value->_maxSide = maxSide;
    value->_square = square;
    return value;
}

#pragma mark - 规范化

- (id)normalize:(id)raw reason:(NSString **)reason {
    if (self.kind != DKSettingsValueKindIDSet && (!raw || raw == NSNull.null)) return NSNull.null;
    switch (self.kind) {
        case DKSettingsValueKindBool: return [self normalizeBool:raw reason:reason];
        case DKSettingsValueKindInteger: return [self normalizeInteger:raw reason:reason];
        case DKSettingsValueKindIDSet: return [self normalizeIDSet:raw reason:reason];
        case DKSettingsValueKindImage: return [self normalizeImage:raw reason:reason];
        case DKSettingsValueKindString: return [self normalizeString:raw reason:reason];
    }
    return nil;
}

- (id)normalizeString:(id)raw reason:(NSString **)reason {
    if (![raw isKindOfClass:NSString.class]) {
        DKSetReason(reason, @"类型不符");
        return nil;
    }
    NSString *text = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (text.length == 0) return NSNull.null;
    if ([text rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound ||
        [text rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound) {
        DKSetReason(reason, @"包含换行或控制字符");
        return nil;
    }
    if (DKSettingsTextWidth(text) > self.maxWidth) {
        DKSetReason(reason, @"文字过长");
        return nil;
    }
    return text;
}

- (NSNumber *)normalizeBool:(id)raw reason:(NSString **)reason {
    if (DKIsBoolNumber(raw)) return [raw boolValue] ? @YES : @NO;
    long long number = 0;
    if (DKIntegerFromNumber(raw, &number) && (number == 0 || number == 1)) return number ? @YES : @NO;
    DKSetReason(reason, @"类型不符");
    return nil;
}

- (NSNumber *)normalizeInteger:(id)raw reason:(NSString **)reason {
    long long number = 0;
    BOOL parsed = [raw isKindOfClass:NSString.class] ? DKIntegerFromString(raw, &number) : DKIntegerFromNumber(raw, &number);
    if (!parsed) {
        DKSetReason(reason, @"类型不符");
        return nil;
    }
    if (number < self.minimum || number > self.maximum) {
        DKSetReason(reason, @"超出取值范围");
        return nil;
    }
    return @(number);
}

- (NSArray<NSString *> *)normalizeIDSet:(id)raw reason:(NSString **)reason {
    if (!raw || raw == NSNull.null) return @[];
    if (![raw isKindOfClass:NSArray.class]) {
        DKSetReason(reason, @"类型不符");
        return nil;
    }
    if ([raw count] > kDKMaxSetCount) {
        DKSetReason(reason, @"条目过多");
        return nil;
    }
    NSMutableSet<NSString *> *ids = [NSMutableSet set];
    for (id item in raw) {
        if (!DKValidID(item)) {
            DKSetReason(reason, @"包含无效的条目");
            return nil;
        }
        [ids addObject:item];
    }
    return [ids.allObjects sortedArrayUsingSelector:@selector(compare:)];
}

- (NSData *)normalizeImage:(id)raw reason:(NSString **)reason {
    if (![raw isKindOfClass:NSData.class]) {
        DKSetReason(reason, @"类型不符");
        return nil;
    }
    NSData *data = raw;
    if (data.length == 0 || data.length > self.maxBytes) {
        DKSetReason(reason, @"图片大小不符");
        return nil;
    }

    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) {
        DKSetReason(reason, @"不是有效的图片");
        return nil;
    }
    NSString *failure = nil;
    NSString *type = (__bridge NSString *)CGImageSourceGetType(source);
    size_t count = CGImageSourceGetCount(source);
    BOOL animatable = [type isEqualToString:@"com.compuserve.gif"];
    if (!type || ![self.imageTypes containsObject:type]) {
        failure = @"图片格式不受支持";
    } else if (count == 0 || (!animatable && count != 1)) {
        failure = @"不是有效的图片";
    } else {
        // 先读文件头里的尺寸，合规后再完整解码，避免为超大图片分配像素内存。
        NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
        NSInteger width = [properties[(__bridge NSString *)kCGImagePropertyPixelWidth] integerValue];
        NSInteger height = [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] integerValue];
        if (width <= 0 || height <= 0 || (self.square && width != height)
            || (NSUInteger)MIN(width, height) < self.minSide || (NSUInteger)MAX(width, height) > self.maxSide) {
            failure = @"图片尺寸不符";
        } else {
            NSDictionary *options = @{ (__bridge NSString *)kCGImageSourceShouldCache: @NO };
            CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, (__bridge CFDictionaryRef)options);
            CFDataRef pixels = image ? CGDataProviderCopyData(CGImageGetDataProvider(image)) : NULL;
            BOOL complete = CGImageSourceGetStatusAtIndex(source, 0) == kCGImageStatusComplete;
            if (!pixels || CFDataGetLength(pixels) == 0 || !complete) failure = @"图片已损坏";
            if (pixels) CFRelease(pixels);
            if (image) CGImageRelease(image);
        }
    }
    CFRelease(source);
    if (failure) {
        DKSetReason(reason, failure);
        return nil;
    }
    return data;
}

#pragma mark - 读写

- (id)currentValueInStore:(id<DKSettingsStore>)store {
    switch (self.kind) {
        case DKSettingsValueKindBool:
        case DKSettingsValueKindInteger:
        case DKSettingsValueKindString:
            return [self normalize:[store objectForKey:self.key] reason:NULL] ?: NSNull.null;
        case DKSettingsValueKindIDSet: {
            NSMutableArray<NSString *> *ids = [NSMutableArray array];
            for (NSString *key in [store dk_keysWithPrefix:self.key]) {
                NSString *identifier = [key substringFromIndex:self.key.length];
                NSNumber *on = [self normalizeBool:[store objectForKey:key] reason:NULL];
                if (identifier.length && on.boolValue) [ids addObject:identifier];
            }
            return [ids sortedArrayUsingSelector:@selector(compare:)];
        }
        case DKSettingsValueKindImage: {
            NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:self.path error:NULL];
            if (!attributes || attributes.fileSize == 0 || attributes.fileSize > self.maxBytes) return NSNull.null;
            return [NSData dataWithContentsOfFile:self.path] ?: NSNull.null;
        }
    }
    return NSNull.null;
}

- (void)writeValue:(id)value toStore:(id<DKSettingsStore>)store {
    switch (self.kind) {
        case DKSettingsValueKindBool:
        case DKSettingsValueKindInteger:
        case DKSettingsValueKindString:
            if (value == NSNull.null) [store removeObjectForKey:self.key];
            else [store setObject:value forKey:self.key];
            break;
        case DKSettingsValueKindIDSet: {
            NSSet<NSString *> *selected = [NSSet setWithArray:value];
            for (NSString *key in [store dk_keysWithPrefix:self.key]) {
                if (![selected containsObject:[key substringFromIndex:self.key.length]]) [store removeObjectForKey:key];
            }
            for (NSString *identifier in selected) {
                NSString *key = [self.key stringByAppendingString:identifier];
                if (![[self normalizeBool:[store objectForKey:key] reason:NULL] boolValue]) [store setObject:@YES forKey:key];
            }
            break;
        }
        case DKSettingsValueKindImage:
            break;
    }
}

@end
