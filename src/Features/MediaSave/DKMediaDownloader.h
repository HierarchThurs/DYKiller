// 顺序下载：候选与镜像逐个重试，下载结果交给校验，校验不过就换下一个地址。
#ifndef DKMediaDownloader_h
#define DKMediaDownloader_h

#import "DKMediaSaveItem.h"

// 校验通过返回 nil，否则返回原因。
typedef NSString *(^DKMediaValidator)(NSURL *file);
typedef void (^DKMediaFetchCompletion)(NSURL *file, DKMediaCandidate *candidate, NSString *url, NSString *error);

@interface DKMediaDownloader : NSObject
- (instancetype)initWithDirectory:(NSURL *)directory;
// 当前下载任务的进度，0–1。
@property (atomic, readonly) double fraction;
- (void)fetch:(NSArray<DKMediaCandidate *> *)candidates
       accept:(NSString *)accept
     validate:(DKMediaValidator)validate
   completion:(DKMediaFetchCompletion)completion;
- (void)cancel;
@end

#endif
