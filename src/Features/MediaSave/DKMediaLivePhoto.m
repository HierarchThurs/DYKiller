#import "DKMediaLivePhoto.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString *const DKStillImageTimeKey = @"com.apple.quicktime.still-image-time";

static BOOL DKWritePairedPhoto(NSURL *image, NSURL *output, NSString *identifier) {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)image, NULL);
    if (!source) return NO;
    NSMutableDictionary *props = [CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL)) mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *maker = [props[(__bridge NSString *)kCGImagePropertyMakerAppleDictionary] mutableCopy] ?: [NSMutableDictionary dictionary];
    maker[@"17"] = identifier;
    props[(__bridge NSString *)kCGImagePropertyMakerAppleDictionary] = maker;
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)output, (__bridge CFStringRef)UTTypeJPEG.identifier, 1, NULL);
    BOOL ok = NO;
    if (destination) {
        CGImageDestinationAddImageFromSource(destination, source, 0, (__bridge CFDictionaryRef)props);
        ok = CGImageDestinationFinalize(destination);
        CFRelease(destination);
    }
    CFRelease(source);
    return ok;
}

static AVMetadataItem *DKContentIdentifierItem(NSString *identifier) {
    AVMutableMetadataItem *item = [AVMutableMetadataItem metadataItem];
    item.keySpace = AVMetadataKeySpaceQuickTimeMetadata;
    item.key = AVMetadataQuickTimeMetadataKeyContentIdentifier;
    item.value = identifier;
    return item;
}

static AVAssetWriterInputMetadataAdaptor *DKStillImageAdaptor(AVAssetWriter *writer) {
    NSArray *specs = @[@{
        (__bridge NSString *)kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier:
            [NSString stringWithFormat:@"mdta/%@", DKStillImageTimeKey],
        (__bridge NSString *)kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType:
            (__bridge NSString *)kCMMetadataBaseDataType_SInt8,
    }];
    CMFormatDescriptionRef description = NULL;
    CMMetadataFormatDescriptionCreateWithMetadataSpecifications(kCFAllocatorDefault, kCMMetadataFormatType_Boxed,
                                                                (__bridge CFArrayRef)specs, &description);
    if (!description) return nil;
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeMetadata outputSettings:nil sourceFormatHint:description];
    CFRelease(description);
    if (![writer canAddInput:input]) return nil;
    [writer addInput:input];
    return [AVAssetWriterInputMetadataAdaptor assetWriterInputMetadataAdaptorWithAssetWriterInput:input];
}

static void DKWritePairedMovie(NSURL *video, NSURL *output, NSString *identifier, void (^done)(NSString *error)) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:video options:nil];
    NSError *error = nil;
    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:&error];
    AVAssetWriter *writer = reader ? [AVAssetWriter assetWriterWithURL:output fileType:AVFileTypeQuickTimeMovie error:&error] : nil;
    if (!reader || !writer) { done(error.localizedDescription ?: @"无法读取实况视频"); return; }
    writer.metadata = @[DKContentIdentifierItem(identifier)];

    NSMutableArray<NSArray *> *pairs = [NSMutableArray array];
    BOOL hasVideo = NO;
    for (AVAssetTrack *track in asset.tracks) {
        if (![track.mediaType isEqualToString:AVMediaTypeVideo] && ![track.mediaType isEqualToString:AVMediaTypeAudio]) continue;
        AVAssetReaderTrackOutput *outputTrack = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:nil];
        CMFormatDescriptionRef hint = (__bridge CMFormatDescriptionRef)track.formatDescriptions.firstObject;
        AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:track.mediaType outputSettings:nil sourceFormatHint:hint];
        input.expectsMediaDataInRealTime = NO;
        if ([track.mediaType isEqualToString:AVMediaTypeVideo]) input.transform = track.preferredTransform;
        if (![reader canAddOutput:outputTrack] || ![writer canAddInput:input]) continue;
        [reader addOutput:outputTrack];
        [writer addInput:input];
        [pairs addObject:@[outputTrack, input]];
        hasVideo = hasVideo || [track.mediaType isEqualToString:AVMediaTypeVideo];
    }
    if (!hasVideo) { done(@"实况视频没有视频轨"); return; }
    AVAssetWriterInputMetadataAdaptor *adaptor = DKStillImageAdaptor(writer);

    if (![writer startWriting] || ![reader startReading]) {
        done(writer.error.localizedDescription ?: reader.error.localizedDescription ?: @"实况视频写入失败");
        return;
    }
    [writer startSessionAtSourceTime:kCMTimeZero];
    if (adaptor) {
        AVMutableMetadataItem *still = [AVMutableMetadataItem metadataItem];
        still.keySpace = AVMetadataKeySpaceQuickTimeMetadata;
        still.key = DKStillImageTimeKey;
        still.value = @(-1);
        still.dataType = (__bridge NSString *)kCMMetadataBaseDataType_SInt8;
        CMTimeRange range = CMTimeRangeMake(CMTimeMake(0, 1000), CMTimeMake(200, 3000));
        [adaptor appendTimedMetadataGroup:[[AVTimedMetadataGroup alloc] initWithItems:@[still] timeRange:range]];
        [adaptor.assetWriterInput markAsFinished];
    }

    dispatch_group_t group = dispatch_group_create();
    for (NSArray *pair in pairs) {
        AVAssetReaderTrackOutput *source = pair[0];
        AVAssetWriterInput *input = pair[1];
        dispatch_queue_t queue = dispatch_queue_create("com.dykiller.mediasave.livephoto", DISPATCH_QUEUE_SERIAL);
        dispatch_group_enter(group);
        __block BOOL finished = NO;
        [input requestMediaDataWhenReadyOnQueue:queue usingBlock:^{
            while (!finished && input.readyForMoreMediaData) {
                CMSampleBufferRef buffer = reader.status == AVAssetReaderStatusReading ? [source copyNextSampleBuffer] : NULL;
                BOOL appended = buffer && [input appendSampleBuffer:buffer];
                if (buffer) CFRelease(buffer);
                if (!appended) {
                    finished = YES;
                    [input markAsFinished];
                    dispatch_group_leave(group);
                }
            }
        }];
    }
    dispatch_group_notify(group, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (reader.status == AVAssetReaderStatusFailed) {
            [writer cancelWriting];
            done(reader.error.localizedDescription ?: @"实况视频读取失败");
            return;
        }
        [writer finishWritingWithCompletionHandler:^{
            done(writer.status == AVAssetWriterStatusCompleted ? nil : (writer.error.localizedDescription ?: @"实况视频写入失败"));
        }];
    });
}

void DKMediaMakeLivePhoto(NSURL *image, NSURL *video, NSURL *directory,
                          void (^completion)(NSURL *photo, NSURL *movie, NSString *error)) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *identifier = NSUUID.UUID.UUIDString;
        NSURL *photo = [directory URLByAppendingPathComponent:[identifier stringByAppendingPathExtension:@"jpg"]];
        NSURL *movie = [directory URLByAppendingPathComponent:[identifier stringByAppendingPathExtension:@"mov"]];
        if (!DKWritePairedPhoto(image, photo, identifier)) { completion(nil, nil, @"实况封面写入失败"); return; }
        DKWritePairedMovie(video, movie, identifier, ^(NSString *error) {
            completion(error ? nil : photo, error ? nil : movie, error);
        });
    });
}
