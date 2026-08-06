//
//  DKZipWriter.m
//  DYKiller
//
//  调试导出使用的最小 ZIP 写入器。
//  写入存储条目，并使用 zlib 计算 CRC32。
//

#import "DKZipWriter.h"
#import <CoreFoundation/CoreFoundation.h>
#import <zlib.h>

static void DKZipAppendUInt16(NSMutableData *data, uint16_t value) {
    uint16_t v = CFSwapInt16HostToLittle(value);
    [data appendBytes:&v length:sizeof(v)];
}

static void DKZipAppendUInt32(NSMutableData *data, uint32_t value) {
    uint32_t v = CFSwapInt32HostToLittle(value);
    [data appendBytes:&v length:sizeof(v)];
}

static void DKZipAppendUInt64(NSMutableData *data, uint64_t value) {
    uint64_t v = CFSwapInt64HostToLittle(value);
    [data appendBytes:&v length:sizeof(v)];
}

static NSString *DKZipRelativePath(NSString *path, NSString *rootDir) {
    NSString *prefix = [rootDir stringByAppendingString:@"/"];
    if ([path hasPrefix:prefix]) return [path substringFromIndex:prefix.length];
    return path.lastPathComponent ?: @"file";
}

static NSError *DKZipError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"DYKiller.Zip" code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"ZIP failed"}];
}

static NSData *DKZipLocalHeader(NSData *nameData, uint32_t crc, uint32_t size) {
    NSMutableData *d = [NSMutableData data];
    DKZipAppendUInt32(d, 0x04034b50);
    DKZipAppendUInt16(d, 20);
    DKZipAppendUInt16(d, 0x0800);
    DKZipAppendUInt16(d, 0);
    DKZipAppendUInt16(d, 0);
    DKZipAppendUInt16(d, 0);
    DKZipAppendUInt32(d, crc);
    DKZipAppendUInt32(d, size);
    DKZipAppendUInt32(d, size);
    DKZipAppendUInt16(d, (uint16_t)nameData.length);
    DKZipAppendUInt16(d, 0);
    [d appendData:nameData];
    return d;
}

static NSData *DKZipCentralHeader(NSData *nameData, uint32_t crc, uint32_t size, uint32_t offset) {
    NSMutableData *d = [NSMutableData data];
    DKZipAppendUInt32(d, 0x02014b50);
    DKZipAppendUInt16(d, 20);
    DKZipAppendUInt16(d, 20);
    DKZipAppendUInt16(d, 0x0800);
    DKZipAppendUInt16(d, 0);
    DKZipAppendUInt16(d, 0);
    DKZipAppendUInt16(d, 0);
    DKZipAppendUInt32(d, crc);
    DKZipAppendUInt32(d, size);
    DKZipAppendUInt32(d, size);
    DKZipAppendUInt16(d, (uint16_t)nameData.length);
    DKZipAppendUInt16(d, 0);
    DKZipAppendUInt16(d, 0);
    DKZipAppendUInt16(d, 0);
    DKZipAppendUInt16(d, 0);
    DKZipAppendUInt32(d, 0);
    DKZipAppendUInt32(d, offset);
    [d appendData:nameData];
    return d;
}

static NSData *DKZipEndRecords(uint64_t entryCount, uint64_t centralSize, uint64_t centralOffset) {
    NSMutableData *end = [NSMutableData data];
    BOOL needsZip64 = entryCount >= UINT16_MAX;
    if (needsZip64) {
        uint64_t zip64EndOffset = centralOffset + centralSize;
        DKZipAppendUInt32(end, 0x06064b50);
        DKZipAppendUInt64(end, 44);
        DKZipAppendUInt16(end, 45);
        DKZipAppendUInt16(end, 45);
        DKZipAppendUInt32(end, 0);
        DKZipAppendUInt32(end, 0);
        DKZipAppendUInt64(end, entryCount);
        DKZipAppendUInt64(end, entryCount);
        DKZipAppendUInt64(end, centralSize);
        DKZipAppendUInt64(end, centralOffset);

        DKZipAppendUInt32(end, 0x07064b50);
        DKZipAppendUInt32(end, 0);
        DKZipAppendUInt64(end, zip64EndOffset);
        DKZipAppendUInt32(end, 1);
    }

    uint16_t legacyEntryCount = entryCount >= UINT16_MAX ? UINT16_MAX : (uint16_t)entryCount;
    DKZipAppendUInt32(end, 0x06054b50);
    DKZipAppendUInt16(end, 0);
    DKZipAppendUInt16(end, 0);
    DKZipAppendUInt16(end, legacyEntryCount);
    DKZipAppendUInt16(end, legacyEntryCount);
    DKZipAppendUInt32(end, (uint32_t)centralSize);
    DKZipAppendUInt32(end, (uint32_t)centralOffset);
    DKZipAppendUInt16(end, 0);
    return end;
}

@implementation DKZipWriter

+ (BOOL)createZipAtPath:(NSString *)zipPath
                rootDir:(NSString *)rootDir
                  files:(NSArray<NSString *> *)files
               progress:(DKZipProgressBlock)progress
                  error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *parent = zipPath.stringByDeletingLastPathComponent;
    if (parent.length) {
        NSError *dirError = nil;
        if (![fm createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:&dirError] && dirError) {
            if (error) *error = dirError;
            return NO;
        }
    }

    [fm removeItemAtPath:zipPath error:nil];
    if (![fm createFileAtPath:zipPath contents:NSData.data attributes:nil]) {
        if (error) {
            *error = [NSError errorWithDomain:@"DYKiller.Zip"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"ZIP file creation failed"}];
        }
        return NO;
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:zipPath];
    if (!handle) {
        if (error) {
            *error = [NSError errorWithDomain:@"DYKiller.Zip"
                                         code:-2
                                     userInfo:@{NSLocalizedDescriptionKey: @"ZIP file handle creation failed"}];
        }
        return NO;
    }

    NSMutableData *central = [NSMutableData data];
    NSMutableSet<NSString *> *seenPaths = [NSMutableSet set];
    uint32_t offset = 0;
    uint64_t entryCount = 0;
    NSUInteger total = files.count;
    NSUInteger done = 0;

    for (NSString *file in files) {
        NSError *entryError = nil;
        @autoreleasepool {
            do {
                BOOL isDir = NO;
                if (![fm fileExistsAtPath:file isDirectory:&isDir] || isDir) {
                    entryError = DKZipError(-3, [NSString stringWithFormat:@"ZIP source file missing: %@", file]);
                    break;
                }

                NSString *relative = DKZipRelativePath(file, rootDir);
                if ([seenPaths containsObject:relative]) {   // 同一相对路径只写最终文件内容一次
                    done++;
                    break;
                }
                [seenPaths addObject:relative];
                NSData *content = [NSData dataWithContentsOfFile:file];
                NSData *nameData = [relative dataUsingEncoding:NSUTF8StringEncoding];
                if (!content || !nameData.length || nameData.length > UINT16_MAX || content.length > UINT32_MAX) {
                    entryError = DKZipError(-4, [NSString stringWithFormat:@"ZIP entry unsupported: %@", relative]);
                    break;
                }

                uint32_t size = (uint32_t)content.length;
                uint32_t crc = (uint32_t)crc32(0, content.bytes, (uInt)content.length);
                NSData *local = DKZipLocalHeader(nameData, crc, size);
                if (local.length + content.length > UINT32_MAX - offset) {
                    entryError = DKZipError(-8, @"ZIP32 data offset overflow");
                    break;
                }
                @try {
                    [handle writeData:local];
                    [handle writeData:content];
                } @catch (NSException *exception) {
                    entryError = DKZipError(-5, exception.reason ?: @"ZIP entry write failed");
                    break;
                }
                [central appendData:DKZipCentralHeader(nameData, crc, size, offset)];

                offset += (uint32_t)(local.length + content.length);
                entryCount++;
                done++;
                if (progress) progress((CGFloat)done / (CGFloat)MAX(total, 1));
            } while (NO);
        }
        if (entryError) {
            [handle closeFile];
            if (error) *error = entryError;
            return NO;
        }
    }

    if (central.length > UINT32_MAX) {
        [handle closeFile];
        if (error) *error = DKZipError(-9, @"ZIP32 central directory overflow");
        return NO;
    }
    uint64_t centralOffset = offset;
    uint64_t centralSize = central.length;
    @try {
        [handle writeData:central];
    } @catch (NSException *exception) {
        [handle closeFile];
        if (error) *error = DKZipError(-6, exception.reason ?: @"ZIP central directory write failed");
        return NO;
    }
    NSData *end = DKZipEndRecords(entryCount, centralSize, centralOffset);
    @try {
        [handle writeData:end];
    } @catch (NSException *exception) {
        [handle closeFile];
        if (error) *error = DKZipError(-7, exception.reason ?: @"ZIP footer write failed");
        return NO;
    }
    [handle closeFile];
    return YES;
}

@end
