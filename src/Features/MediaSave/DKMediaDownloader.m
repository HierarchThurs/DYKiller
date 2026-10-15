#import "DKMediaDownloader.h"
#import "DKMediaFormat.h"

@interface DKMediaDownloader ()
@property (nonatomic, strong) NSURL *directory;
@property (nonatomic, strong) NSURLSession *session;
@property (atomic, strong) NSURLSessionTask *task;
@property (atomic, assign) BOOL cancelled;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation DKMediaDownloader

- (instancetype)initWithDirectory:(NSURL *)directory {
    if ((self = [super init])) {
        _directory = directory;
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        config.timeoutIntervalForRequest = 30;
        config.timeoutIntervalForResource = 300;
        config.HTTPMaximumConnectionsPerHost = 4;
        _session = [NSURLSession sessionWithConfiguration:config];
        _queue = dispatch_queue_create("com.dykiller.mediasave.download", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (double)fraction {
    NSURLSessionTask *task = self.task;
    if (!task || task.countOfBytesExpectedToReceive <= 0) return 0;
    return MIN(1.0, (double)task.countOfBytesReceived / (double)task.countOfBytesExpectedToReceive);
}

- (void)cancel {
    self.cancelled = YES;
    [self.task cancel];
    [self.session invalidateAndCancel];
}

- (void)fetch:(NSArray<DKMediaCandidate *> *)candidates accept:(NSString *)accept
     validate:(DKMediaValidator)validate completion:(DKMediaFetchCompletion)completion {
    // 新的下载开始前不再报告上一个任务的进度。
    self.task = nil;
    [self attempt:candidates candidate:0 url:0 accept:accept validate:validate lastError:nil completion:completion];
}

- (void)attempt:(NSArray<DKMediaCandidate *> *)candidates candidate:(NSUInteger)ci url:(NSUInteger)ui
         accept:(NSString *)accept validate:(DKMediaValidator)validate lastError:(NSString *)lastError
     completion:(DKMediaFetchCompletion)completion {
    if (self.cancelled) { completion(nil, nil, nil, @"已取消"); return; }
    if (ci >= candidates.count) { completion(nil, nil, nil, lastError ?: @"没有可用地址"); return; }
    DKMediaCandidate *candidate = candidates[ci];
    if (ui >= candidate.urls.count) {
        [self attempt:candidates candidate:ci + 1 url:0 accept:accept validate:validate lastError:lastError completion:completion];
        return;
    }
    NSString *urlString = candidate.urls[ui];
    NSURL *url = [NSURL URLWithString:urlString];
    void (^next)(NSString *) = ^(NSString *error) {
        [self attempt:candidates candidate:ci url:ui + 1 accept:accept validate:validate lastError:error completion:completion];
    };
    if (!url) { next(@"地址无效"); return; }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    if (accept.length) [request setValue:accept forHTTPHeaderField:@"Accept"];
    NSURL *destination = [self.directory URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    __weak typeof(self) weakSelf = self;
    NSURLSessionDownloadTask *task = [self.session downloadTaskWithRequest:request completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        NSString *failure = nil;
        if (self.cancelled) failure = @"已取消";
        else if (error) failure = error.localizedDescription ?: @"下载失败";
        else if (status < 200 || status >= 300) failure = [NSString stringWithFormat:@"HTTP %ld", (long)status];
        else if (![NSFileManager.defaultManager moveItemAtURL:location toURL:destination error:nil]) failure = @"无法写入临时文件";
        dispatch_async(self.queue, ^{
            if (self.cancelled) { completion(nil, nil, nil, @"已取消"); return; }
            NSString *reason = failure;
            NSURL *file = destination;
            if (!reason) {
                NSNumber *size = nil;
                [file getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
                // 文件名补上按文件头判定的扩展名，AVFoundation 与相册才能识别容器。
                NSString *extension = size.longLongValue > 0 ? DKMediaFileExtension(file) : nil;
                NSURL *named = extension ? [file URLByAppendingPathExtension:extension] : nil;
                if (named && [NSFileManager.defaultManager moveItemAtURL:file toURL:named error:nil]) file = named;
                reason = size.longLongValue > 0 ? (validate ? validate(file) : nil) : @"文件为空";
            }
            if (reason) {
                [NSFileManager.defaultManager removeItemAtURL:file error:nil];
                next(reason);
                return;
            }
            completion(file, candidate, urlString, nil);
        });
    }];
    self.task = task;
    [task resume];
}

@end
