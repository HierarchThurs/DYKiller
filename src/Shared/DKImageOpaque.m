#import "DKImageOpaque.h"
#import <objc/runtime.h>

static char kDKImageOpaqueKey;

static CGRect DKImageScanOpaque(CGImageRef source) {
    size_t width = CGImageGetWidth(source);
    size_t height = CGImageGetHeight(source);
    if (width == 0 || height == 0) return CGRectNull;

    uint8_t *alpha = (uint8_t *)calloc(width * height, sizeof(uint8_t));
    if (!alpha) return CGRectNull;
    CGContextRef context = CGBitmapContextCreate(alpha, width, height, 8, width, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    if (!context) {
        free(alpha);
        return CGRectNull;
    }
    CGContextDrawImage(context, CGRectMake(0.0, 0.0, width, height), source);
    CGContextRelease(context);

    size_t minX = width, minY = height, maxX = 0, maxY = 0;
    for (size_t y = 0; y < height; y++) {
        for (size_t x = 0; x < width; x++) {
            if (alpha[y * width + x] == 0) continue;
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
        }
    }
    free(alpha);
    if (minX > maxX || minY > maxY) return CGRectNull;
    return CGRectMake(minX, minY, maxX - minX + 1, maxY - minY + 1);
}

CGRect DKImageOpaquePixelRect(UIImage *image) {
    CGImageRef source = image.CGImage;
    if (!source) return CGRectNull;
    NSValue *cached = objc_getAssociatedObject(image, &kDKImageOpaqueKey);
    if (cached) return cached.CGRectValue;
    CGRect rect = DKImageScanOpaque(source);
    objc_setAssociatedObject(image, &kDKImageOpaqueKey, [NSValue valueWithCGRect:rect], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return rect;
}
