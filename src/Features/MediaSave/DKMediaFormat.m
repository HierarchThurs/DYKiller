#import "DKMediaFormat.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>
#import <math.h>

static NSString *DKBrand(const uint8_t *bytes) {
    return [[NSString alloc] initWithBytes:bytes length:4 encoding:NSASCIIStringEncoding] ?: @"";
}

DKMediaFileType DKMediaSniff(NSURL *file) {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:file error:nil];
    NSData *head = [handle readDataOfLength:256];
    [handle closeFile];
    if (head.length < 12) return DKMediaFileUnknown;
    const uint8_t *b = head.bytes;
    if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return DKMediaFileJPEG;
    if (b[0] == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G') return DKMediaFilePNG;
    if (b[0] == 'G' && b[1] == 'I' && b[2] == 'F') return DKMediaFileGIF;
    if (!memcmp(b, "RIFF", 4) && !memcmp(b + 8, "WEBP", 4)) return DKMediaFileWebP;
    if (memcmp(b + 4, "ftyp", 4)) return DKMediaFileUnknown;

    // ISO-BMFF：主品牌与兼容品牌一起判定。
    uint32_t boxSize = ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) | ((uint32_t)b[2] << 8) | b[3];
    NSUInteger end = MIN((NSUInteger)boxSize, head.length);
    NSMutableArray<NSString *> *brands = [NSMutableArray arrayWithObject:DKBrand(b + 8)];
    for (NSUInteger offset = 16; offset + 4 <= end; offset += 4) [brands addObject:DKBrand(b + offset)];
    if ([brands containsObject:@"vvic"]) return DKMediaFileVVIC;
    NSSet *heif = [NSSet setWithArray:@[@"heic", @"heix", @"hevc", @"hevx", @"heim", @"heis", @"mif1", @"msf1", @"avif"]];
    NSSet *video = [NSSet setWithArray:@[@"isom", @"iso2", @"iso4", @"iso5", @"iso6", @"mp41", @"mp42", @"avc1", @"qt  ", @"M4V ", @"dash", @"3gp4", @"3gp5"]];
    if ([heif containsObject:brands.firstObject]) return DKMediaFileHEIF;
    if ([video containsObject:brands.firstObject]) return DKMediaFileVideo;
    for (NSString *brand in brands) {
        if ([heif containsObject:brand]) return DKMediaFileHEIF;
        if ([video containsObject:brand]) return DKMediaFileVideo;
    }
    return DKMediaFileUnknown;
}

NSString *DKMediaFileTypeName(DKMediaFileType type) {
    switch (type) {
        case DKMediaFileJPEG: return @"jpeg";
        case DKMediaFilePNG: return @"png";
        case DKMediaFileGIF: return @"gif";
        case DKMediaFileWebP: return @"webp";
        case DKMediaFileHEIF: return @"heif";
        case DKMediaFileVVIC: return @"vvic";
        case DKMediaFileVideo: return @"video";
        case DKMediaFileUnknown: break;
    }
    return @"unknown";
}

NSString *DKMediaFileExtension(NSURL *file) {
    switch (DKMediaSniff(file)) {
        case DKMediaFileJPEG: return @"jpg";
        case DKMediaFilePNG: return @"png";
        case DKMediaFileGIF: return @"gif";
        case DKMediaFileWebP: return @"webp";
        case DKMediaFileHEIF: return @"heic";
        case DKMediaFileVVIC: return nil;
        case DKMediaFileVideo: break;
        case DKMediaFileUnknown: break;
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:file error:nil];
    NSData *head = [handle readDataOfLength:12];
    [handle closeFile];
    if (head.length < 12) return nil;
    const uint8_t *b = head.bytes;
    if (!memcmp(b + 4, "ftyp", 4)) {
        NSString *brand = DKBrand(b + 8);
        if ([brand isEqualToString:@"M4A "] || [brand isEqualToString:@"M4B "]) return @"m4a";
        return [brand isEqualToString:@"qt  "] ? @"mov" : @"mp4";
    }
    if (!memcmp(b, "ID3", 3) || (b[0] == 0xFF && (b[1] & 0xE0) == 0xE0)) return @"mp3";
    return nil;
}

BOOL DKMediaIsImageType(DKMediaFileType type) {
    return type == DKMediaFileJPEG || type == DKMediaFilePNG || type == DKMediaFileGIF
        || type == DKMediaFileWebP || type == DKMediaFileHEIF;
}

static NSString *DKFourCC(FourCharCode code) {
    char chars[5] = { (char)(code >> 24), (char)(code >> 16), (char)(code >> 8), (char)code, 0 };
    return [NSString stringWithUTF8String:chars] ?: @"";
}

BOOL DKMediaVideoPlayable(NSURL *file, NSString **codec) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:file options:nil];
    AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    id description = track.formatDescriptions.firstObject;
    if (!description) { if (codec) *codec = @"none"; return NO; }
    NSString *name = DKFourCC(CMFormatDescriptionGetMediaSubType((__bridge CMFormatDescriptionRef)description));
    if (codec) *codec = name;
    return [@[@"avc1", @"hvc1", @"hev1"] containsObject:name];
}

BOOL DKMediaVideoHasAudio(NSURL *file) {
    return [[AVURLAsset URLAssetWithURL:file options:nil] tracksWithMediaType:AVMediaTypeAudio].count > 0;
}

NSUInteger DKMediaFrameCount(NSURL *file) {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)file, NULL);
    if (!source) return 0;
    NSUInteger count = CGImageSourceGetCount(source);
    CFRelease(source);
    return count;
}

static BOOL DKSkipGIFSubblocks(const uint8_t *bytes, NSUInteger length, NSUInteger *offset) {
    while (*offset < length) {
        NSUInteger size = bytes[(*offset)++];
        if (!size) return YES;
        if (size > length - *offset) return NO;
        *offset += size;
    }
    return NO;
}

// GIF 子块必须完整结束并抵达 Trailer；ImageIO 会接受部分截断流。
static size_t DKGIFBlockFrames(NSData *data) {
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    if (length < 13 || (memcmp(bytes, "GIF87a", 6) && memcmp(bytes, "GIF89a", 6))) return 0;
    NSUInteger offset = 13 + ((bytes[10] & 0x80) ? (3 << ((bytes[10] & 7) + 1)) : 0);
    size_t frames = 0;
    while (offset < length) {
        uint8_t block = bytes[offset++];
        if (block == 0x3B) return offset == length ? frames : 0;
        if (block == 0x21) {
            if (offset >= length) return 0;
            offset++;
        } else if (block == 0x2C) {
            if (length - offset < 9) return 0;
            uint8_t packed = bytes[offset + 8];
            offset += 9 + ((packed & 0x80) ? (3 << ((packed & 7) + 1)) : 0);
            if (offset >= length) return 0;
            offset++; // LZW 最小码长，后续为图像数据子块。
            frames++;
        } else {
            return 0;
        }
        if (!DKSkipGIFSubblocks(bytes, length, &offset)) return 0;
    }
    return 0;
}

static BOOL DKGIFSourceValid(CGImageSourceRef source, size_t frames) {
    if (!source || !CGImageSourceGetType(source)
        || !CFEqual(CGImageSourceGetType(source), (__bridge CFStringRef)UTTypeGIF.identifier)
        || CGImageSourceGetStatus(source) != kCGImageStatusComplete) return NO;
    size_t count = CGImageSourceGetCount(source);
    if (!frames || count != frames) return NO;
    NSDictionary *options = @{(__bridge NSString *)kCGImageSourceShouldCacheImmediately: @YES};
    for (size_t i = 0; i < count; i++) {
        CGImageRef image = CGImageSourceCreateImageAtIndex(source, i, (__bridge CFDictionaryRef)options);
        BOOL valid = image && CGImageGetWidth(image) && CGImageGetHeight(image)
            && CGImageSourceGetStatusAtIndex(source, i) == kCGImageStatusComplete;
        if (image) CGImageRelease(image);
        if (!valid) return NO;
    }
    return count > 0;
}

BOOL DKMediaGIFValid(NSURL *file) {
    NSData *data = [NSData dataWithContentsOfURL:file options:NSDataReadingMappedIfSafe error:nil];
    size_t frames = DKGIFBlockFrames(data);
    if (!frames) return NO;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    BOOL valid = DKGIFSourceValid(source, frames);
    if (source) CFRelease(source);
    return valid;
}

@protocol DKHEIFAnimationDecoder <NSObject>
- (instancetype)initWithData:(NSData *)data;
- (NSUInteger)imageCount;
- (NSUInteger)loopCount;
- (double)frameDelayAtIndex:(NSUInteger)index;
- (CGImageRef)copyImageAtIndex:(NSUInteger)index CF_RETURNS_RETAINED;
@end

static id<DKHEIFAnimationDecoder> DKHEIFDecoder(NSURL *file) {
    Class cls = NSClassFromString(@"BDImageDecoderHeic");
    SEL selectors[] = {@selector(initWithData:), @selector(imageCount), @selector(loopCount),
                       @selector(frameDelayAtIndex:), @selector(copyImageAtIndex:)};
    const char *returns[] = {@encode(id), @encode(NSUInteger), @encode(NSUInteger), @encode(double), @encode(CGImageRef)};
    for (NSUInteger i = 0; i < 5; i++) {
        Method method = cls ? class_getInstanceMethod(cls, selectors[i]) : NULL;
        if (!method) return nil;
        NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        NSUInteger arguments = i == 1 || i == 2 ? 2 : 3;
        if (signature.numberOfArguments != arguments || strcmp(signature.methodReturnType, returns[i])) return nil;
        if (arguments == 3 && strcmp([signature getArgumentTypeAtIndex:2], i == 0 ? @encode(id) : @encode(NSUInteger))) return nil;
    }
    NSData *data = [NSData dataWithContentsOfURL:file options:NSDataReadingMappedIfSafe error:nil];
    return data.length ? [(id<DKHEIFAnimationDecoder>)[cls alloc] initWithData:data] : nil;
}

static double DKFrameDelay(CGImageSourceRef source, size_t index) {
    NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, index, NULL));
    NSArray *groups = @[
        @[(__bridge NSString *)kCGImagePropertyGIFDictionary, (__bridge NSString *)kCGImagePropertyGIFUnclampedDelayTime, (__bridge NSString *)kCGImagePropertyGIFDelayTime],
        @[(__bridge NSString *)kCGImagePropertyWebPDictionary, (__bridge NSString *)kCGImagePropertyWebPUnclampedDelayTime, (__bridge NSString *)kCGImagePropertyWebPDelayTime],
        @[(__bridge NSString *)kCGImagePropertyPNGDictionary, (__bridge NSString *)kCGImagePropertyAPNGUnclampedDelayTime, (__bridge NSString *)kCGImagePropertyAPNGDelayTime],
    ];
    for (NSArray *group in groups) {
        NSDictionary *dict = props[group[0]];
        double delay = [dict[group[1]] doubleValue];
        if (delay <= 0) delay = [dict[group[2]] doubleValue];
        if (delay > 0) return delay;
    }
    return 0.1;
}

NSData *DKMediaGIFData(NSURL *file) {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)file, NULL);
    if (!source) return nil;
    size_t count = CGImageSourceGetCount(source);
    BOOL heif = count > 1 && DKMediaSniff(file) == DKMediaFileHEIF;
    // HEIF 动画沿用宿主的逐帧解码器，读取完整画面及帧时长。
    id<DKHEIFAnimationDecoder> decoder = heif ? DKHEIFDecoder(file) : nil;
    if (heif && (!decoder || decoder.imageCount < 2)) { CFRelease(source); return nil; }
    if (decoder) count = decoder.imageCount;
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyProperties(source, NULL));
    NSNumber *loops = properties[(__bridge NSString *)kCGImagePropertyWebPDictionary][(__bridge NSString *)kCGImagePropertyWebPLoopCount]
        ?: properties[(__bridge NSString *)kCGImagePropertyPNGDictionary][(__bridge NSString *)kCGImagePropertyAPNGLoopCount]
        ?: properties[(__bridge NSString *)kCGImagePropertyGIFDictionary][(__bridge NSString *)kCGImagePropertyGIFLoopCount];
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destination = count ? CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, (__bridge CFStringRef)UTTypeGIF.identifier, count, NULL) : NULL;
    if (!destination) { CFRelease(source); return nil; }
    NSDictionary *fileProps = @{(__bridge NSString *)kCGImagePropertyGIFDictionary: @{
        (__bridge NSString *)kCGImagePropertyGIFLoopCount: decoder ? @(decoder.loopCount) : (loops ?: @0)}};
    CGImageDestinationSetProperties(destination, (__bridge CFDictionaryRef)fileProps);
    size_t added = 0;
    for (size_t i = 0; i < count; i++) {
        @autoreleasepool {
            CGImageRef image = decoder ? [decoder copyImageAtIndex:i] : CGImageSourceCreateImageAtIndex(source, i, NULL);
            if (!image) break;
            double delay = decoder ? [decoder frameDelayAtIndex:i] : DKFrameDelay(source, i);
            if (!isfinite(delay) || delay <= 0) delay = 0.1;
            NSDictionary *frameProps = @{(__bridge NSString *)kCGImagePropertyGIFDictionary: @{(__bridge NSString *)kCGImagePropertyGIFDelayTime: @(delay)}};
            CGImageDestinationAddImage(destination, image, (__bridge CFDictionaryRef)frameProps);
            CGImageRelease(image);
            added++;
        }
    }
    BOOL ok = added == count && count > 0 && CGImageDestinationFinalize(destination);
    CFRelease(destination);
    CFRelease(source);
    if (ok) {
        CGImageSourceRef output = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
        ok = DKGIFBlockFrames(data) == count && DKGIFSourceValid(output, count);
        if (output) CFRelease(output);
    }
    return ok ? data : nil;
}

NSData *DKMediaPNGData(NSURL *file) {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)file, NULL);
    if (!source) return nil;
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destination = image ? CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, (__bridge CFStringRef)UTTypePNG.identifier, 1, NULL) : NULL;
    BOOL ok = NO;
    if (destination) {
        CGImageDestinationAddImage(destination, image, NULL);
        ok = CGImageDestinationFinalize(destination);
        CFRelease(destination);
    }
    if (image) CGImageRelease(image);
    CFRelease(source);
    return ok ? data : nil;
}

NSData *DKMediaPhotoData(NSURL *file, DKMediaFileType type, NSString **uti) {
    BOOL animated = DKMediaFrameCount(file) > 1;
    if (type == DKMediaFileGIF || animated) {
        if (uti) *uti = UTTypeGIF.identifier;
        return type == DKMediaFileGIF ? (DKMediaGIFValid(file) ? [NSData dataWithContentsOfURL:file] : nil) : DKMediaGIFData(file);
    }
    if (type == DKMediaFileWebP) {
        if (uti) *uti = UTTypePNG.identifier;
        return DKMediaPNGData(file);
    }
    if (uti) {
        if (type == DKMediaFileJPEG) *uti = UTTypeJPEG.identifier;
        else if (type == DKMediaFilePNG) *uti = UTTypePNG.identifier;
        else *uti = UTTypeHEIC.identifier;
    }
    return [NSData dataWithContentsOfURL:file];
}
