//
//  DKZipWriter.h
//  DYKiller
//
//  调试导出使用的最小 ZIP 写入器。
//  以不压缩方式写入文件，并使用 zlib 计算 CRC32。
//

#ifndef DKZipWriter_h
#define DKZipWriter_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^DKZipProgressBlock)(CGFloat progress);

@interface DKZipWriter : NSObject

+ (BOOL)createZipAtPath:(NSString *)zipPath
                rootDir:(NSString *)rootDir
                  files:(NSArray<NSString *> *)files
               progress:(DKZipProgressBlock _Nullable)progress
                  error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

#endif /* DKZipWriter_h */
