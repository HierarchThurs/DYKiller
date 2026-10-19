// 图片导入的格式识别、尺寸说明与 PNG 归一化。
#import "DKInteractionIconFile.h"
#import "DKSVGImage.h"
#import <ImageIO/ImageIO.h>
#import <math.h>

NSString *DKInteractionIconDataDetail(NSData *data) {
    if (!data) return @"未设置";
    CGSize size;
    if (DKSVGImageInspect(data, &size, NULL)) return [NSString stringWithFormat:@"SVG · %g×%g", size.width, size.height];
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    NSDictionary *properties = source ? CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL)) : nil;
    if (source) CFRelease(source);
    return properties ? [NSString stringWithFormat:@"PNG · %@×%@", properties[(__bridge NSString *)kCGImagePropertyPixelWidth],
        properties[(__bridge NSString *)kCGImagePropertyPixelHeight]] : @"图片无效";
}

NSData *DKInteractionIconNormalize(NSData *data, BOOL album, NSString **reason) {
    if (!data.length || data.length > 16 * 1024 * 1024) {
        if (reason) *reason = @"图片文件为空或超过 16 MB";
        return nil;
    }
    if (!album && DKSVGImageInspect(data, NULL, NULL)) return data;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) {
        if (reason) {
            NSString *svgReason = nil;
            DKSVGImageInspect(data, NULL, &svgReason);
            *reason = svgReason ?: @"请选择有效的 PNG 或 SVG";
        }
        return nil;
    }
    BOOL valid = CGImageSourceGetCount(source) == 1 && (album || CFEqual(CGImageSourceGetType(source), CFSTR("public.png")));
    NSDictionary *options = @{ (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @512 };
    CGImageRef image = valid ? CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options) : NULL;
    BOOL complete = CGImageSourceGetStatusAtIndex(source, 0) == kCGImageStatusComplete;
    CFRelease(source);
    if (!image || !complete) {
        if (image) CGImageRelease(image);
        if (reason) *reason = @"图片格式不受支持或文件已损坏";
        return nil;
    }
    NSMutableData *png = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)png, CFSTR("public.png"), 1, NULL);
    if (destination) CGImageDestinationAddImage(destination, image, NULL);
    BOOL saved = destination && CGImageDestinationFinalize(destination);
    if (destination) CFRelease(destination);
    CGImageRelease(image);
    if (!saved || png.length > 512 * 1024) {
        if (reason) *reason = @"图片归一化失败或结果超过 512 KB";
        return nil;
    }
    return png;
}

CGImageRef DKInteractionIconRasterize(NSData *data, CGSize pixels) {
    if (!isfinite(pixels.width) || !isfinite(pixels.height) || pixels.width < 1 || pixels.height < 1
        || pixels.width > 2048 || pixels.height > 2048) return NULL;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return DKSVGImageCreate(data, pixels);
    NSDictionary *options = @{ (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @(ceil(MAX(pixels.width, pixels.height))) };
    CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (!image) return NULL;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, (size_t)ceil(pixels.width), (size_t)ceil(pixels.height), 8, 0,
        space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGImageRef result = NULL;
    if (context) {
        CGFloat width = CGImageGetWidth(image), height = CGImageGetHeight(image);
        CGFloat scale = MIN(pixels.width / width, pixels.height / height);
        CGContextDrawImage(context, CGRectMake((pixels.width - width * scale) / 2,
            (pixels.height - height * scale) / 2, width * scale, height * scale), image);
        result = CGBitmapContextCreateImage(context);
        CGContextRelease(context);
    }
    CGImageRelease(image);
    return result;
}

