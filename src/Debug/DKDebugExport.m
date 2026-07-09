//
//  DKDebugExport.m
//  DYKiller
//
//  只负责序列化：把上下文写成分类文件（page/、runtime/、ui/），再交 DKZipWriter 打包。
//

#import "DKDebugExport.h"
#import "DKKeys.h"
#import "DKZipWriter.h"
#import "DKClassDump.h"
#import <mach-o/dyld.h>
#import <objc/runtime.h>

#pragma mark - 文件工具

static NSString *DKSafeFileName(NSString *name) {
    if (!name.length) return @"Unknown";
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\?%*|\"<>:"];
    NSArray *parts = [name componentsSeparatedByCharactersInSet:bad];
    NSString *safe = [parts componentsJoinedByString:@"_"];
    return safe.length ? safe : @"Unknown";
}

static BOOL DKEnsureDir(NSString *path, NSError **error) {
    return [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:error];
}

static BOOL DKWriteData(NSString *path, NSData *data, NSMutableArray<NSString *> *files, NSError **error) {
    NSString *dir = path.stringByDeletingLastPathComponent;
    if (dir.length && !DKEnsureDir(dir, error)) return NO;
    BOOL ok = [data writeToFile:path options:NSDataWritingAtomic error:error];
    if (ok) [files addObject:path];
    return ok;
}

static BOOL DKWriteString(NSString *path, NSString *string, NSMutableArray<NSString *> *files, NSError **error) {
    return DKWriteData(path, [string dataUsingEncoding:NSUTF8StringEncoding] ?: NSData.data, files, error);
}

static BOOL DKWriteJSON(NSString *path, id object, NSMutableArray<NSString *> *files, NSError **error) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:error];
    if (!data) return NO;
    return DKWriteData(path, data, files, error);
}

static NSString *DKReadme(DKDebugExportContext *context, BOOL includeAppClasses) {
    NSMutableString *readme = [NSMutableString string];
    [readme appendString:@"DYKiller Debug Export\n"];
    [readme appendFormat:@"Generated: %@\n", context.metadata[@"generatedAt"]];
    [readme appendFormat:@"DYKiller: %@\n", DK_VERSION];
    [readme appendFormat:@"Bundle: %@\n", context.metadata[@"bundleIdentifier"]];
    [readme appendFormat:@"App: %@ %@ (%@)\n", context.metadata[@"bundleName"], context.metadata[@"appVersion"], context.metadata[@"buildVersion"]];
    [readme appendFormat:@"System: %@ %@\n", context.metadata[@"systemName"], context.metadata[@"systemVersion"]];
    [readme appendFormat:@"Tap: %@\n", context.metadata[@"tapPointInTargetWindow"][@"string"]];
    [readme appendFormat:@"Windows: %lu\n", (unsigned long)context.windowsJSON.count];
    [readme appendFormat:@"Mode: %@\n\n", includeAppClasses ? @"page + full app class-dump" : @"page only"];
    [readme appendString:@"Contents:\n"];
    [readme appendString:@"- page/: current UI windows, view tree, selected view, controllers, layers\n"];
    [readme appendString:@"- page/classes/: class-dump .h of every class on this page (incl. superclass chains)\n"];
    [readme appendString:@"- ui/: screenshot of the target key window\n"];
    if (includeAppClasses) {
        [readme appendString:@"- runtime/images.txt, runtime/classes-by-image/: class-dump .h of all app-owned classes\n"];
    }
    return readme;
}

#pragma mark - 类头文件导出

// 本页出现的类（含继承链）→ 每类一个头文件文本。
static void DKWritePageClasses(NSString *rootDir,
                               NSArray<NSString *> *classNames,
                               NSMutableArray<NSString *> *files,
                               NSError **error) {
    NSString *dir = [rootDir stringByAppendingPathComponent:@"page/classes"];
    for (NSString *name in [classNames sortedArrayUsingSelector:@selector(compare:)]) {
        @autoreleasepool {
            Class cls = NSClassFromString(name);
            NSString *header = cls ? DKClassDumpHeaderForClass(cls) : nil;  // 内含安全内省检查 + @try
            if (!header.length) continue;
            NSString *path = [dir stringByAppendingPathComponent:[DKSafeFileName(name) stringByAppendingString:@".h"]];
            DKWriteString(path, header, files, error);
        }
    }
}

static void DKWriteRuntimeImages(NSString *rootDir, NSMutableArray<NSString *> *files, NSError **error) {
    NSMutableString *out = [NSMutableString string];
    uint32_t imageCount = _dyld_image_count();
    for (uint32_t i = 0; i < imageCount; i++) {
        const char *image = _dyld_get_image_name(i);
        unsigned int classCount = 0;
        const char **classNames = image ? objc_copyClassNamesForImage(image, &classCount) : NULL;
        [out appendFormat:@"%u\t%u\t%s\n", i, classCount, image ?: ""];
        if (classNames) free(classNames);
    }
    DKWriteString([rootDir stringByAppendingPathComponent:@"runtime/images.txt"], out, files, error);
}

// 应用自有类（跳过系统/Swift/运行时子类）导出到 runtime 下的镜像分组目录。
static void DKWriteAppClasses(NSString *rootDir,
                              NSMutableArray<NSString *> *files,
                              NSError **error,
                              void (^progress)(NSString *text)) {
    NSArray<NSDictionary *> *images = DKClassDumpAppImages();
    NSString *baseDir = [rootDir stringByAppendingPathComponent:@"runtime/classes-by-image"];

    NSUInteger total = 0;
    for (NSDictionary *image in images) total += [image[@"classes"] count];

    NSUInteger index = 0;
    for (NSDictionary *image in images) {
        NSString *imageName = image[@"imageName"] ?: @"Image";
        NSString *dir = [baseDir stringByAppendingPathComponent:DKSafeFileName([imageName stringByDeletingPathExtension])];
        for (NSString *className in image[@"classes"]) {
            @autoreleasepool {
                index++;
                if (progress && (index == 1 || index % 200 == 0 || index == total)) {
                    progress([NSString stringWithFormat:@"导出 App 类 %lu/%lu\n%@",
                              (unsigned long)index, (unsigned long)total, className]);
                }
                Class cls = NSClassFromString(className);
                NSString *header = cls ? DKClassDumpHeaderForClass(cls) : nil;  // 内含安全内省检查 + @try
                if (!header.length) continue;
                NSString *path = [dir stringByAppendingPathComponent:[DKSafeFileName(className) stringByAppendingString:@".h"]];
                DKWriteString(path, header, files, error);
            }
        }
    }
}

#pragma mark - ZIP 生成流程

NSURL *DKDebugCreateExportZip(DKDebugExportContext *context,
                              BOOL includeAppClasses,
                              void (^progress)(NSString *text)) {
    NSString *rootName = [NSString stringWithFormat:@"DYKiller-Debug-%@-%@-%lld",
                          includeAppClasses ? @"full" : @"page",
                          NSBundle.mainBundle.bundleIdentifier ?: @"Aweme",
                          (long long)NSDate.date.timeIntervalSince1970];
    NSString *rootDir = [NSTemporaryDirectory() stringByAppendingPathComponent:rootName];
    NSString *zipPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[rootName stringByAppendingString:@".zip"]];
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm removeItemAtPath:rootDir error:nil];
    [fm removeItemAtPath:zipPath error:nil];

    NSError *error = nil;
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    DKEnsureDir(rootDir, &error);

    progress(@"写入页面结构...");
    DKWriteString([rootDir stringByAppendingPathComponent:@"README.txt"], DKReadme(context, includeAppClasses), files, &error);
    DKWriteJSON([rootDir stringByAppendingPathComponent:@"page/windows.json"], context.windowsJSON ?: @[], files, &error);
    DKWriteString([rootDir stringByAppendingPathComponent:@"page/view-tree.txt"], context.viewTreeText ?: @"", files, &error);
    DKWriteJSON([rootDir stringByAppendingPathComponent:@"page/view-tree.json"], context.viewTreeJSON ?: @[], files, &error);
    DKWriteJSON([rootDir stringByAppendingPathComponent:@"page/selected-view.json"], context.selectedViewJSON ?: @{}, files, &error);
    DKWriteString([rootDir stringByAppendingPathComponent:@"page/view-controllers.txt"], context.viewControllersText ?: @"", files, &error);
    DKWriteJSON([rootDir stringByAppendingPathComponent:@"page/layers.json"], context.layersJSON ?: @[], files, &error);
    if (context.screenshotPNG.length) {
        DKWriteData([rootDir stringByAppendingPathComponent:@"ui/screenshot.png"], context.screenshotPNG, files, &error);
    }

    progress(@"导出本页类头文件...");
    DKWritePageClasses(rootDir, context.pageClassNames ?: @[], files, &error);

    if (includeAppClasses) {
        progress(@"导出 runtime image 索引...");
        DKWriteRuntimeImages(rootDir, files, &error);
        progress(@"导出全 App 类头文件...");
        DKWriteAppClasses(rootDir, files, &error, progress);
    }

    if (error) {
        NSString *msg = error.localizedDescription ?: @"Unknown export error";
        DKWriteString([rootDir stringByAppendingPathComponent:@"EXPORT_ERROR.txt"], msg, files, nil);
    }

    progress(@"压缩 zip...");
    NSError *zipError = nil;
    BOOL ok = [DKZipWriter createZipAtPath:zipPath rootDir:rootDir files:files progress:nil error:&zipError];
    if (!ok || zipError) {
        DKWriteString([rootDir stringByAppendingPathComponent:@"ZIP_ERROR.txt"],
                      zipError.localizedDescription ?: @"ZIP failed",
                      files,
                      nil);
        [DKZipWriter createZipAtPath:zipPath rootDir:rootDir files:files progress:nil error:nil];
    }
    return [NSURL fileURLWithPath:zipPath];
}
