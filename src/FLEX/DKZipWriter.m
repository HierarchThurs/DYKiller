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

static NSString *DKZipRelativePath(NSString *path, NSString *rootDir) {
    NSString *prefix = [rootDir stringByAppendingString:@"/"];
    if ([path hasPrefix:prefix]) return [path substringFromIndex:prefix.length];
    return path.lastPathComponent ?: @"file";
}

static NSData *DKZipLocalHeader(NSData *nameData, uint32_t crc, uint32_t size) {
    NSMutableData *d = [NSMutableData data];
    DKZipAppendUInt32(d, 0x04034b50);
    DKZipAppendUInt16(d, 20);
    DKZipAppendUInt16(d, 0);
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
    DKZipAppendUInt16(d, 0);
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
    uint16_t entryCount = 0;
    NSUInteger total = files.count;
    NSUInteger done = 0;

    for (NSString *file in files) {
        @autoreleasepool {
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:file isDirectory:&isDir] || isDir) {
                done++;
                continue;
            }

            NSData *content = [NSData dataWithContentsOfFile:file];
            NSString *relative = DKZipRelativePath(file, rootDir);
            if ([seenPaths containsObject:relative]) {   // 去重：同一相对路径只写一条，避免 zip 冲突
                done++;
                continue;
            }
            [seenPaths addObject:relative];
            NSData *nameData = [relative dataUsingEncoding:NSUTF8StringEncoding];
            if (!content || !nameData.length || nameData.length > UINT16_MAX || content.length > UINT32_MAX) {
                done++;
                continue;
            }

            uint32_t size = (uint32_t)content.length;
            uint32_t crc = (uint32_t)crc32(0, content.bytes, (uInt)content.length);
            NSData *local = DKZipLocalHeader(nameData, crc, size);
            [handle writeData:local];
            [handle writeData:content];
            [central appendData:DKZipCentralHeader(nameData, crc, size, offset)];

            offset += (uint32_t)(local.length + content.length);
            entryCount++;
            done++;
            if (progress) progress((CGFloat)done / (CGFloat)MAX(total, 1));
        }
    }

    uint32_t centralOffset = offset;
    [handle writeData:central];
    offset += (uint32_t)central.length;

    NSMutableData *end = [NSMutableData data];
    DKZipAppendUInt32(end, 0x06054b50);
    DKZipAppendUInt16(end, 0);
    DKZipAppendUInt16(end, 0);
    DKZipAppendUInt16(end, entryCount);
    DKZipAppendUInt16(end, entryCount);
    DKZipAppendUInt32(end, (uint32_t)central.length);
    DKZipAppendUInt32(end, centralOffset);
    DKZipAppendUInt16(end, 0);
    [handle writeData:end];
    [handle closeFile];
    return YES;
}

@end
