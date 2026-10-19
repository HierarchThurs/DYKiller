#import "DKInteractionIconAssets.h"
#import "DKInteractionIconDraw.h"
#import <math.h>

static NSString *DKIconAssetPath(DKInteractionIconSlot slot) {
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    return [[support stringByAppendingPathComponent:@"DYKiller/InteractionIcons"]
        stringByAppendingPathComponent:[DKInteractionIconAssetKey(slot) stringByAppendingString:@".asset"]];
}

DKSettingsValue *DKInteractionIconValue(DKInteractionIconSlot slot) {
    return [DKSettingsValue imageWithName:DKInteractionIconAssetKey(slot) path:DKIconAssetPath(slot)
        types:@[ @"public.png", @"public.svg-image" ] maxBytes:512 * 1024 minSide:1 maxSide:512 square:NO];
}

static NSMutableDictionary<NSNumber *, id> *DKIconDataCache(void) {
    static NSMutableDictionary *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });
    return cache;
}

static NSCache<NSString *, UIImage *> *DKIconImages(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; cache.totalCostLimit = 8 * 1024 * 1024; });
    return cache;
}

NSData *DKInteractionIconData(DKInteractionIconSlot slot) {
    id value = DKIconDataCache()[@(slot)];
    if (!value) {
        value = [DKInteractionIconValue(slot) currentValueInStore:NSUserDefaults.standardUserDefaults];
        if ([value isKindOfClass:NSData.class]) value = [DKInteractionIconValue(slot) normalize:value reason:NULL] ?: NSNull.null;
        DKIconDataCache()[@(slot)] = value;
    }
    return [value isKindOfClass:NSData.class] ? value : nil;
}

NSString *DKInteractionIconDetail(DKInteractionIconSlot slot) {
    return [DKInteractionIconDataDetail(DKInteractionIconData(slot)) componentsSeparatedByString:@" · "].firstObject;
}

BOOL DKInteractionIconStore(DKInteractionIconSlot slot, NSData *data, NSString **reason) {
    DKSettingsValue *value = DKInteractionIconValue(slot);
    if (data && ![value normalize:data reason:reason]) return NO;
    NSFileManager *manager = NSFileManager.defaultManager;
    NSError *error = nil;
    if (data) {
        if (![manager createDirectoryAtPath:value.path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error]
            || ![data writeToFile:value.path options:NSDataWritingAtomic error:&error]
            || ![data isEqual:[NSData dataWithContentsOfFile:value.path]]) {
            if (reason) *reason = error.localizedDescription ?: @"图片写入后核对失败";
            return NO;
        }
    } else if ([manager fileExistsAtPath:value.path] && ![manager removeItemAtPath:value.path error:&error]) {
        if (reason) *reason = error.localizedDescription;
        return NO;
    }
    return YES;
}

static UIImage *DKIconRenderData(NSData *data, CGSize size, CGFloat scale) {
    CGImageRef image = DKInteractionIconRasterize(data, CGSizeMake(size.width * scale, size.height * scale));
    UIImage *result = image ? [UIImage imageWithCGImage:image scale:scale orientation:UIImageOrientationUp] : nil;
    if (image) CGImageRelease(image);
    return result;
}

UIImage *DKInteractionIconCustom(DKInteractionIconSlot slot, CGSize size, CGFloat scale) {
    return DKInteractionIconImage(slot, 3, size, scale, NO);
}

UIImage *DKInteractionIconImage(DKInteractionIconSlot slot, NSInteger style, CGSize size, CGFloat scale, BOOL light) {
    if (style < 1 || style > 3 || !isfinite(size.width) || !isfinite(size.height) || !isfinite(scale)
        || size.width <= 0 || size.height <= 0 || scale <= 0 || MAX(size.width, size.height) * scale > 2048) return nil;
    NSString *key = [NSString stringWithFormat:@"%ld/%ld/%g/%g/%g/%d", (long)slot, (long)style, size.width, size.height, scale, light];
    UIImage *image = [DKIconImages() objectForKey:key];
    if (image) return image;
    if (style == 3) {
        NSData *data = DKInteractionIconData(slot);
        if (data) image = DKIconRenderData(data, size, scale);
    } else {
        UIGraphicsImageRendererFormat *format = UIGraphicsImageRendererFormat.preferredFormat;
        format.opaque = NO;
        format.scale = scale;
        image = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
            CGFloat side = MIN(size.width, size.height);
            CGContextSetShadowWithColor(context.CGContext, CGSizeMake(0, .5), light ? 1.4 : 1.2,
                [UIColor colorWithWhite:0 alpha:light ? .55 : .34].CGColor);
            CGContextBeginTransparencyLayer(context.CGContext, NULL);
            DKInteractionIconDraw(context.CGContext, slot, style, CGRectMake((size.width - side) / 2, (size.height - side) / 2, side, side));
            CGContextEndTransparencyLayer(context.CGContext);
        }];
    }
    image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    if (image) [DKIconImages() setObject:image forKey:key cost:(NSUInteger)(size.width * scale * size.height * scale * 4)];
    return image;
}

void DKInteractionIconAssetsReload(void) {
    [DKIconDataCache() removeAllObjects];
    [DKIconImages() removeAllObjects];
}
