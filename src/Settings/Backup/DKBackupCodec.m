//
//  DKBackupCodec.m
//

#import "DKBackupCodec.h"
#import <CommonCrypto/CommonDigest.h>
#import <ImageIO/ImageIO.h>

NSString *const DKBackupErrorDomain = @"DYKiller.Backup";
const unsigned long long DKBackupMaxFileBytes = 16ULL * 1024 * 1024;

static NSString *const kDKFormat = @"DYKiller.settings-backup";
static const NSInteger kDKFormatVersion = 1;

// 结构上限：嵌套深度、各节条数、键长与来源字段长度。
static const NSUInteger kDKMaxDepth = 32;
static const NSUInteger kDKMaxSettings = 2048;
static const NSUInteger kDKMaxSets = 256;
static const NSUInteger kDKMaxFiles = 64;
static const NSUInteger kDKMaxKeyLength = 256;
static const NSUInteger kDKMaxSourceLength = 64;

NSError *DKBackupMakeError(DKBackupErrorCode code, NSString *detail) {
    NSString *message = detail;
    if (!message.length) {
        switch (code) {
            case DKBackupErrorUnreadable: message = @"无法读取文件"; break;
            case DKBackupErrorTooLarge: message = @"文件超过 16 MB"; break;
            case DKBackupErrorNotBackup: message = @"不是 DYKiller 备份文件"; break;
            case DKBackupErrorCorrupted: message = @"备份文件已损坏"; break;
            case DKBackupErrorNewerVersion: message = @"备份来自更新版本的 DYKiller，请先升级插件"; break;
            case DKBackupErrorWriteFailed: message = @"写入失败"; break;
        }
    }
    return [NSError errorWithDomain:DKBackupErrorDomain code:code userInfo:@{ NSLocalizedDescriptionKey: message ?: @"" }];
}

static BOOL DKFail(NSError **error, DKBackupErrorCode code) {
    if (error) *error = DKBackupMakeError(code, nil);
    return NO;
}

static NSString *DKSHA256(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

static NSISO8601DateFormatter *DKDateFormatter(void) {
    static NSISO8601DateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ formatter = [[NSISO8601DateFormatter alloc] init]; });
    return formatter;
}

NSString *DKBackupFileName(NSDate *date) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyyMMdd_HHmmss";
    return [NSString stringWithFormat:@"DYKiller_Backup_%@.dykbackup", [formatter stringFromDate:date]];
}

#pragma mark - 编码

static NSDictionary *DKFileRecord(DKSettingsValue *value, NSData *data) {
    NSString *type = nil;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (source) {
        type = [(__bridge NSString *)CGImageSourceGetType(source) copy];
        CFRelease(source);
    }
    return @{
        @"type": type ?: value.imageTypes.firstObject ?: @"public.data",
        @"bytes": @(data.length),
        @"sha256": DKSHA256(data),
        @"data": [data base64EncodedStringWithOptions:0],
    };
}

// 顶层按固定顺序拼接，各节内部键排序；图片数据放在最后一节。
static NSData *DKOrderedJSON(NSArray<NSArray *> *pairs, NSError **error) {
    NSJSONWritingOptions options = NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
        | NSJSONWritingWithoutEscapingSlashes | NSJSONWritingFragmentsAllowed;
    NSMutableString *json = [NSMutableString stringWithString:@"{\n"];
    for (NSUInteger index = 0; index < pairs.count; index++) {
        NSData *part = [NSJSONSerialization dataWithJSONObject:pairs[index][1] options:options error:error];
        if (!part) return nil;
        NSString *text = [[NSString alloc] initWithData:part encoding:NSUTF8StringEncoding];
        text = [text stringByReplacingOccurrencesOfString:@"\n" withString:@"\n  "];
        [json appendFormat:@"  \"%@\" : %@%@\n", pairs[index][0], text, index + 1 < pairs.count ? @"," : @""];
    }
    [json appendString:@"}\n"];
    return [json dataUsingEncoding:NSUTF8StringEncoding];
}

NSData *DKBackupEncode(NSArray<DKBackupEntry *> *entries, id<DKSettingsStore> store,
                       NSDictionary<NSString *, NSString *> *source, NSDate *date,
                       BOOL glassAvailable, NSError **error) {
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    NSMutableDictionary *sets = [NSMutableDictionary dictionary];
    NSMutableDictionary *files = [NSMutableDictionary dictionary];
    for (DKBackupEntry *entry in entries) {
        if (entry.gated && !glassAvailable) continue;
        for (DKSettingsValue *value in entry.values) {
            id current = [value currentValueInStore:store];
            switch (value.kind) {
                case DKSettingsValueKindBool:
                case DKSettingsValueKindInteger: settings[value.key] = current; break;
                case DKSettingsValueKindIDSet: sets[value.key] = current; break;
                case DKSettingsValueKindImage:
                    files[value.key] = [current isKindOfClass:NSData.class] ? DKFileRecord(value, current) : NSNull.null;
                    break;
            }
        }
    }

    NSError *jsonError = nil;
    NSData *data = DKOrderedJSON(@[
        @[ @"format", kDKFormat ],
        @[ @"version", @(kDKFormatVersion) ],
        @[ @"createdAt", [DKDateFormatter() stringFromDate:date] ],
        @[ @"source", source ?: @{} ],
        @[ @"settings", settings ],
        @[ @"sets", sets ],
        @[ @"files", files ],
    ], &jsonError);
    if (!data && error) *error = DKBackupMakeError(DKBackupErrorWriteFailed, @"无法生成备份数据");
    return data;
}

#pragma mark - 解码

// 解析前先线性扫一遍括号嵌套深度。
static BOOL DKDepthWithinLimit(NSData *data) {
    const uint8_t *bytes = data.bytes;
    NSUInteger depth = 0;
    BOOL inString = NO, escaped = NO;
    for (NSUInteger i = 0; i < data.length; i++) {
        uint8_t c = bytes[i];
        if (inString) {
            if (escaped) escaped = NO;
            else if (c == '\\') escaped = YES;
            else if (c == '"') inString = NO;
            continue;
        }
        if (c == '"') inString = YES;
        else if (c == '{' || c == '[') {
            if (++depth > kDKMaxDepth) return NO;
        } else if ((c == '}' || c == ']') && depth > 0) depth--;
    }
    return YES;
}

// 节缺省为空字典；存在则须为字典，键为不超长的字符串，条数不超上限。
static NSDictionary *DKSection(NSDictionary *root, NSString *name, NSUInteger limit, BOOL *valid) {
    id section = root[name];
    if (!section) return @{};
    if (![section isKindOfClass:NSDictionary.class] || [section count] > limit) {
        *valid = NO;
        return @{};
    }
    for (id key in section) {
        if (![key isKindOfClass:NSString.class] || [key length] == 0 || [key length] > kDKMaxKeyLength) {
            *valid = NO;
            return @{};
        }
    }
    return section;
}

static NSData *DKDecodeFile(id record, NSString **reason) {
    if (![record isKindOfClass:NSDictionary.class]) {
        *reason = @"类型不符";
        return nil;
    }
    id encoded = record[@"data"], bytes = record[@"bytes"], digest = record[@"sha256"];
    if (![encoded isKindOfClass:NSString.class] || ![bytes isKindOfClass:NSNumber.class] || ![digest isKindOfClass:NSString.class]
        || [encoded length] > DKBackupMaxFileBytes) {
        *reason = @"图片数据不完整";
        return nil;
    }
    NSData *data = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
    if (!data || data.length != [bytes unsignedLongLongValue]
        || ![DKSHA256(data) isEqualToString:[(NSString *)digest lowercaseString]]) {
        *reason = @"图片校验失败";
        return nil;
    }
    return data;
}

DKBackupDocument *DKBackupDecode(NSData *data, NSError **error) {
    if (data.length > DKBackupMaxFileBytes) {
        DKFail(error, DKBackupErrorTooLarge);
        return nil;
    }
    if (!DKDepthWithinLimit(data)) {
        DKFail(error, DKBackupErrorCorrupted);
        return nil;
    }
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![root isKindOfClass:NSDictionary.class] || ![root[@"format"] isEqual:kDKFormat]) {
        DKFail(error, DKBackupErrorNotBackup);
        return nil;
    }
    id version = root[@"version"];
    if (![version isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)version) == CFBooleanGetTypeID()
        || [version integerValue] < 1 || [version doubleValue] != (double)[version integerValue]) {
        DKFail(error, DKBackupErrorCorrupted);
        return nil;
    }
    if ([version integerValue] > kDKFormatVersion) {
        DKFail(error, DKBackupErrorNewerVersion);
        return nil;
    }

    BOOL valid = YES;
    NSDictionary *settings = DKSection(root, @"settings", kDKMaxSettings, &valid);
    NSDictionary *sets = DKSection(root, @"sets", kDKMaxSets, &valid);
    NSDictionary *fileRecords = DKSection(root, @"files", kDKMaxFiles, &valid);
    if (!valid) {
        DKFail(error, DKBackupErrorCorrupted);
        return nil;
    }

    DKBackupDocument *document = [[DKBackupDocument alloc] init];
    NSMutableDictionary<NSString *, NSString *> *source = [NSMutableDictionary dictionary];
    id sourceRoot = root[@"source"];
    if ([sourceRoot isKindOfClass:NSDictionary.class]) {
        for (NSString *field in @[ @"plugin", @"app", @"system" ]) {
            id text = sourceRoot[field];
            if ([text isKindOfClass:NSString.class] && [text length] <= kDKMaxSourceLength) source[field] = text;
        }
    }
    document.source = source;
    id createdAt = root[@"createdAt"];
    if ([createdAt isKindOfClass:NSString.class]) document.createdAt = [DKDateFormatter() dateFromString:createdAt];
    document.settings = settings;
    document.sets = sets;

    NSMutableDictionary *files = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *fileErrors = [NSMutableDictionary dictionary];
    for (NSString *name in fileRecords) {
        id record = fileRecords[name];
        if (record == NSNull.null) {
            files[name] = NSNull.null;
            continue;
        }
        NSString *reason = nil;
        NSData *file = DKDecodeFile(record, &reason);
        if (file) files[name] = file;
        else fileErrors[name] = reason;
    }
    document.files = files;
    document.fileErrors = fileErrors;
    return document;
}

NSData *DKBackupReadFile(NSString *path, NSError **error) {
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL];
    if (!attributes) {
        DKFail(error, DKBackupErrorUnreadable);
        return nil;
    }
    if (attributes.fileSize > DKBackupMaxFileBytes) {
        DKFail(error, DKBackupErrorTooLarge);
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:NULL];
    if (!data) DKFail(error, DKBackupErrorUnreadable);
    return data;
}

DKBackupDocument *DKBackupDefaultsDocument(NSArray<DKBackupEntry *> *entries) {
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    NSMutableDictionary *sets = [NSMutableDictionary dictionary];
    NSMutableDictionary *files = [NSMutableDictionary dictionary];
    for (DKBackupEntry *entry in entries) {
        for (DKSettingsValue *value in entry.values) {
            switch (value.kind) {
                case DKSettingsValueKindBool:
                case DKSettingsValueKindInteger: settings[value.key] = NSNull.null; break;
                case DKSettingsValueKindIDSet: sets[value.key] = @[]; break;
                case DKSettingsValueKindImage: files[value.key] = NSNull.null; break;
            }
        }
    }
    DKBackupDocument *document = [[DKBackupDocument alloc] init];
    document.settings = settings;
    document.sets = sets;
    document.files = files;
    return document;
}
