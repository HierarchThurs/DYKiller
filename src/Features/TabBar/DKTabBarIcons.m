//
//  DKTabBarIcons.m
//  DYKiller
//

#import "DKTabBarIcons.h"
#import "DKTabBarIconDraw.h"

static BOOL DKTabBarGlyphForTabID(NSString *tabID, DKTabBarGlyph *glyph) {
    static NSDictionary<NSString *, NSNumber *> *glyphs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        glyphs = @{ @"homepage_home": @(DKTabBarGlyphHome), @"homepage_mall": @(DKTabBarGlyphMall),
                    @"homepage_familiar": @(DKTabBarGlyphFriends), @"homepage_notification": @(DKTabBarGlyphMessage),
                    @"homepage_profile": @(DKTabBarGlyphMe) };
    });
    NSNumber *value = tabID ? glyphs[tabID] : nil;
    if (!value) return NO;
    if (glyph) *glyph = (DKTabBarGlyph)value.integerValue;
    return YES;
}

BOOL DKTabBarHasIcon(NSString *tabID) {
    return DKTabBarGlyphForTabID(tabID, NULL);
}

static NSCache<NSString *, UIImage *> *DKIconCache(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });
    return cache;
}

static UIImage *DKRender(NSString *cacheKey, CGFloat side, UIImageRenderingMode mode,
                         void (^draw)(CGContextRef context, CGRect rect)) {
    if (side <= 0) return nil;
    NSString *key = [NSString stringWithFormat:@"%@|%.2f", cacheKey, side];
    UIImage *cached = [DKIconCache() objectForKey:key];
    if (cached) return cached;

    UIGraphicsImageRendererFormat *format = UIGraphicsImageRendererFormat.preferredFormat;
    format.opaque = NO;
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:format]
        imageWithActions:^(UIGraphicsImageRendererContext *context) {
            draw(context.CGContext, CGRectMake(0, 0, side, side));
        }];
    image = [image imageWithRenderingMode:mode];
    if (image) [DKIconCache() setObject:image forKey:key];
    return image;
}

UIImage *DKTabBarIconTemplate(NSString *tabID, BOOL selected, CGFloat side) {
    DKTabBarGlyph glyph;
    if (!DKTabBarGlyphForTabID(tabID, &glyph)) return nil;
    NSString *key = [NSString stringWithFormat:@"tab|%@|%d", tabID, selected];
    return DKRender(key, side, UIImageRenderingModeAlwaysTemplate, ^(CGContextRef context, CGRect rect) {
        DKTabBarDrawGlyph(context, glyph, selected, rect, UIColor.blackColor.CGColor);
    });
}

UIImage *DKTabBarCameraTemplate(CGFloat side) {
    return DKRender(@"camera", side, UIImageRenderingModeAlwaysTemplate, ^(CGContextRef context, CGRect rect) {
        DKTabBarDrawCamera(context, rect, UIColor.blackColor.CGColor);
    });
}

UIImage *DKTabBarCameraAccent(CGFloat side) {
    return DKRender(@"camera-accent", side, UIImageRenderingModeAlwaysOriginal, ^(CGContextRef context, CGRect rect) {
        DKTabBarDrawCameraAccent(context, rect);
    });
}
