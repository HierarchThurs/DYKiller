#import "DKColorScheme.h"
#import "DKColorHex.h"
#import <math.h>

NSString *const DKColorSchemeDefaultColor = @"#FFFFFF";
NSString *const DKColorSchemeDefaultGradient = @"#FF2C55,#25F4EE,#FE2C55";

NSArray<NSString *> *DKColorSchemeModeTitles(void) {
    return @[ @"固定颜色", @"随机纯色", @"随机渐变", @"固定彩虹", @"自定义渐变", @"旋转彩虹" ];
}

DKColorSchemeMode DKColorSchemeStoredMode(NSString *key) {
    NSInteger value = [NSUserDefaults.standardUserDefaults integerForKey:key];
    return value >= 0 && (NSUInteger)value < DKColorSchemeModeTitles().count ? value : DKColorSchemeFixed;
}

NSString *DKColorSchemeStoredColor(NSString *key, BOOL gradient) {
    id raw = [NSUserDefaults.standardUserDefaults objectForKey:key];
    return DKColorHexNormalizeScheme(raw, gradient, NULL) ?: (gradient ? DKColorSchemeDefaultGradient : DKColorSchemeDefaultColor);
}

UIColor *DKColorSchemeRGB(NSString *hex) {
    NSString *canonical = DKColorHexNormalize(hex) ?: DKColorSchemeDefaultColor;
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:[canonical substringFromIndex:1]] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb >> 16) & 255) / 255.0 green:((rgb >> 8) & 255) / 255.0 blue:(rgb & 255) / 255.0 alpha:1];
}

NSString *DKColorSchemeSignature(DKColorSchemeMode mode, NSString *fixedHex, NSString *gradientHex) {
    NSString *value = mode == DKColorSchemeFixed ? fixedHex : mode == DKColorSchemeCustomGradient ? gradientHex : @"";
    return [NSString stringWithFormat:@"%ld/%@", (long)mode, value ?: @""];
}

static UIColor *DKRandomRGB(void) {
    return [UIColor colorWithRed:arc4random_uniform(256) / 255.0 green:arc4random_uniform(256) / 255.0
                            blue:arc4random_uniform(256) / 255.0 alpha:1];
}

NSArray<UIColor *> *DKColorSchemePalette(DKColorSchemeMode mode, NSString *fixedHex, NSString *gradientHex,
                                         NSUInteger rotation) {
    switch (mode) {
        case DKColorSchemeFixed: return @[ DKColorSchemeRGB(fixedHex) ];
        case DKColorSchemeRandom: return @[ DKRandomRGB() ];
        case DKColorSchemeRandomGradient: return @[ DKRandomRGB(), DKRandomRGB(), DKRandomRGB() ];
        case DKColorSchemeCustomGradient: {
            NSString *scheme = DKColorHexNormalizeScheme(gradientHex, YES, NULL) ?: DKColorSchemeDefaultGradient;
            NSMutableArray *colors = [NSMutableArray array];
            for (NSString *hex in [scheme componentsSeparatedByString:@","]) [colors addObject:DKColorSchemeRGB(hex)];
            return colors;
        }
        case DKColorSchemeRainbow:
        case DKColorSchemeRotatingRainbow: {
            NSArray *rainbow = @[ @"#FF0000", @"#FF8000", @"#FFFF00", @"#00FF00", @"#00FFFF", @"#0000FF", @"#800080" ];
            NSUInteger start = mode == DKColorSchemeRotatingRainbow ? rotation % rainbow.count : 0;
            NSMutableArray *colors = [NSMutableArray arrayWithCapacity:rainbow.count];
            for (NSUInteger i = 0; i < rainbow.count; i++) [colors addObject:DKColorSchemeRGB(rainbow[(start + i) % rainbow.count])];
            return colors;
        }
    }
    return @[ UIColor.whiteColor ];
}

UIColor *DKColorSchemeRender(NSArray<UIColor *> *colors, CGFloat start, CGFloat width, CGFloat scale) {
    if (colors.count == 1) return colors.firstObject;
    if (colors.count < 2 || !isfinite(width) || width <= 0) return UIColor.whiteColor;
    start = isfinite(start) && start > 0 ? start : 0;
    scale = scale > 0 && isfinite(scale) ? scale : 1;
    // 图案按图片宽度横向平铺，图片要覆盖到渐变终点，文字范围内才不会折回起点。
    CGFloat imageWidth = ceil((start + width) * scale) / scale;
    NSMutableArray *components = [NSMutableArray array];
    for (UIColor *color in colors) {
        CGFloat r = 0, g = 0, b = 0, a = 1;
        [color getRed:&r green:&g blue:&b alpha:&a];
        [components addObject:[NSString stringWithFormat:@"%.5f,%.5f,%.5f", r, g, b]];
    }
    NSString *key = [NSString stringWithFormat:@"%@/%.3f/%.3f/%.2f", [components componentsJoinedByString:@";"], start, width, scale];
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.totalCostLimit = 2 * 1024 * 1024; });
    UIColor *cached = [cache objectForKey:key];
    if (cached) return cached;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = scale;
    format.opaque = YES;
    CGSize size = CGSizeMake(imageWidth, 1 / scale);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        NSMutableArray *cgColors = [NSMutableArray array];
        for (UIColor *color in colors) [cgColors addObject:(__bridge id)color.CGColor];
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)cgColors, NULL);
        CGContextDrawLinearGradient(context.CGContext, gradient, CGPointMake(start, 0), CGPointMake(start + width, 0),
                                    kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
    }];
    UIColor *result = [UIColor colorWithPatternImage:image];
    [cache setObject:result forKey:key cost:(NSUInteger)ceil(imageWidth * scale) * 4];
    return result;
}
