// 内置互动图标：24×24 网格、圆角线条及激活态渐变。
#import "DKInteractionIconDraw.h"
#import "DKTabBarIconDraw.h"

static void DKIconPath(CGContextRef context, const char *data, CGPathDrawingMode mode) {
    CGPathRef path = DKSVGPathCreate(data);
    if (!path) return;
    CGContextAddPath(context, path);
    CGContextDrawPath(context, mode);
    CGPathRelease(path);
}

static const char *const kDKHeart = "M12 20.1c-.28 0-.55-.08-.79-.25C7.6 17.3 3.1 13.85 3.1 9.35 3.1 6.55 5.2 4.45 7.9 4.45c1.7 0 3.15.85 4.1 2.2.95-1.35 2.4-2.2 4.1-2.2 2.7 0 4.8 2.1 4.8 4.9 0 4.5-4.5 7.95-8.11 10.5-.24.17-.51.25-.79.25Z";
static const char *const kDKHeartGloss = "M6.4 9.45c0-1.35.85-2.4 2.1-2.65";
static const char *const kDKThumbCuff = "M3.05 12.65A1.4 1.4 0 0 1 4.45 11.25L5.15 11.25A1.4 1.4 0 0 1 6.55 12.65L6.55 18.85A1.4 1.4 0 0 1 5.15 20.25L4.45 20.25A1.4 1.4 0 0 1 3.05 18.85Z";
static const char *const kDKThumbHand = "M8.8 10.75A1 1 0 0 1 8.85 10.45L10.52 5.09A1.4 1.4 0 0 1 12.16 4.14L12.56 4.23A1.4 1.4 0 0 1 13.65 5.46L13.94 8.47A1.2 1.2 0 0 0 15.14 9.55L17.67 9.55A2.8 2.8 0 0 1 20.44 12.75L19.67 18.02A2.6 2.6 0 0 1 17.1 20.25L10.3 20.25A1.5 1.5 0 0 1 8.8 18.75Z";
static const char *const kDKThumbFinger = "M16.3 14.9H18.4";
static const char *const kDKThumbGloss = "M10.75 8.8l.65-2.45";
static const char *const kDKStar = "M10.59 4.84A1.55 1.55 0 0 1 13.41 4.84L14.86 8.07A0.7 0.7 0 0 0 15.43 8.48L18.94 8.86A1.55 1.55 0 0 1 19.81 11.55L17.19 13.92A0.7 0.7 0 0 0 16.98 14.58L17.7 18.04A1.55 1.55 0 0 1 15.41 19.71L12.35 17.95A0.7 0.7 0 0 0 11.65 17.95L8.59 19.71A1.55 1.55 0 0 1 6.3 18.04L7.02 14.58A0.7 0.7 0 0 0 6.81 13.92L4.19 11.55A1.55 1.55 0 0 1 5.06 8.86L8.57 8.48A0.7 0.7 0 0 0 9.14 8.07Z";
static const char *const kDKStarGloss = "M7.2 10.4l2-.26";
static const char *const kDKBookmark = "M5.5 6.75A2.9 2.9 0 0 1 8.4 3.85L15.6 3.85A2.9 2.9 0 0 1 18.5 6.75L18.5 18.37A1.35 1.35 0 0 1 16.42 19.5L12.76 17.14A1.4 1.4 0 0 0 11.24 17.14L7.58 19.5A1.35 1.35 0 0 1 5.5 18.37Z";
static const char *const kDKBookmarkGloss = "M8.55 10.4V8.05";
static const char *const kDKBubbleRect = "M8 4.5h8a4.5 4.5 0 0 1 4.5 4.5v3.5a4.5 4.5 0 0 1-4.5 4.5h-4.25l-2.6 2.3a.75.75 0 0 1-1.15-.6V17a4.5 4.5 0 0 1-4.5-4.5V9A4.5 4.5 0 0 1 8 4.5Z";
static const char *const kDKBubbleLines = "M8.25 9.35h7.5M8.25 12.6h4.25";
static const char *const kDKBubbleOval = "M12 4.4c4.5 0 8.15 3.1 8.15 6.95S16.5 18.3 12 18.3c-.95 0-1.86-.13-2.7-.38l-3.6 1.83a.5.5 0 0 1-.7-.58l.88-3.2C4.6 14.73 3.85 13.1 3.85 11.35 3.85 7.5 7.5 4.4 12 4.4Z";
static const char *const kDKShareArrow = "M20.14 8.94A2.2 2.2 0 0 1 20.14 11.86L16.77 15.65A1.1 1.1 0 0 1 14.85 14.91L14.85 14.75A0.8 0.8 0 0 0 14.05 13.95C13.62 13.95 13.18 13.95 12.76 13.97C12.34 13.99 11.93 14.01 11.53 14.07C11.14 14.12 10.75 14.19 10.38 14.29C10.01 14.4 9.64 14.53 9.3 14.72C8.97 14.91 8.63 15.13 8.35 15.43C8.06 15.72 7.79 16.08 7.6 16.5C7.4 16.93 7.24 17.47 7.19 17.98A2.1 2.1 0 0 1 3.01 17.52C3.1 16.69 3.26 15.85 3.48 15.07C3.7 14.28 3.98 13.53 4.34 12.83C4.7 12.13 5.13 11.45 5.63 10.84C6.13 10.23 6.71 9.66 7.33 9.18C7.95 8.69 8.64 8.26 9.36 7.91C10.08 7.57 10.86 7.3 11.64 7.12C12.42 6.95 13.24 6.85 14.05 6.85A0.8 0.8 0 0 0 14.85 6.05L14.85 5.89A1.1 1.1 0 0 1 16.77 5.15Z";
static const char *const kDKPlane = "M17.85 3.68A2 2 0 0 1 20.32 6.15L16.63 19.16A1.7 1.7 0 0 1 13.43 19.37L10.98 13.65A1.2 1.2 0 0 0 10.35 13.02L4.63 10.57A1.7 1.7 0 0 1 4.84 7.37Z";
static const char *const kDKPlaneFold = "M10.79 13.21 16.57 7.43";

void DKInteractionIconDraw(CGContextRef context, DKInteractionIconSlot slot, NSInteger style, CGRect rect) {
    if (!context || slot < 0 || slot >= DKInteractionIconSlotCount || (style != 1 && style != 2)) return;
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, rect.origin.x, rect.origin.y);
    CGContextScaleCTM(context, rect.size.width / 24, rect.size.height / 24);
    CGContextSetLineWidth(context, 1.75);
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineJoin(context, kCGLineJoinRound);
    CGContextSetRGBStrokeColor(context, 1, 1, 1, 1);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    const char *body = NULL, *extra = NULL, *detail = NULL, *gloss = NULL;
    switch (slot) {
        case DKInteractionIconLikeBefore: case DKInteractionIconLikeAfter:
            body = style == 1 ? kDKHeart : kDKThumbHand;
            extra = style == 2 ? kDKThumbCuff : NULL;
            detail = style == 2 ? kDKThumbFinger : NULL;
            gloss = style == 1 ? kDKHeartGloss : kDKThumbGloss;
            break;
        case DKInteractionIconFavoriteBefore: case DKInteractionIconFavoriteAfter:
            body = style == 1 ? kDKStar : kDKBookmark;
            gloss = style == 1 ? kDKStarGloss : kDKBookmarkGloss;
            break;
        case DKInteractionIconComment: body = style == 1 ? kDKBubbleRect : kDKBubbleOval; break;
        case DKInteractionIconShare: body = style == 1 ? kDKShareArrow : kDKPlane; break;
        default: break;
    }
    if (DKInteractionIconIsActive(slot)) {
        CGContextBeginTransparencyLayer(context, NULL);
        DKIconPath(context, body, kCGPathFillStroke);
        if (extra) DKIconPath(context, extra, kCGPathFillStroke);
        CGContextSetBlendMode(context, kCGBlendModeSourceIn);
        CGFloat pink[] = { 1, .396, .522, 1, .996, .173, .333, 1 };
        CGFloat gold[] = { 1, .863, .369, 1, 1, .710, .141, 1 };
        CGFloat locations[] = { 0, 1 };
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGGradientRef gradient = CGGradientCreateWithColorComponents(space,
            slot == DKInteractionIconLikeAfter ? pink : gold, locations, 2);
        CGContextDrawLinearGradient(context, gradient, CGPointMake(12, 4), CGPointMake(12, 20.5),
            kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        CGContextSetBlendMode(context, kCGBlendModeNormal);
        CGContextEndTransparencyLayer(context);
        CGContextSetRGBStrokeColor(context, 1, 1, 1, .55);
        CGContextSetLineWidth(context, 1.3);
        DKIconPath(context, gloss, kCGPathStroke);
    } else {
        DKIconPath(context, body, kCGPathStroke);
        if (extra) DKIconPath(context, extra, kCGPathStroke);
        if (detail) DKIconPath(context, detail, kCGPathStroke);
        if (slot == DKInteractionIconComment) {
            if (style == 1) DKIconPath(context, kDKBubbleLines, kCGPathStroke);
            else for (NSInteger i = 0; i < 3; i++) {
                CGContextFillEllipseInRect(context, CGRectMake(8.45 + i * 3.55 - 1.1, 10.25, 2.2, 2.2));
            }
        }
        if (slot == DKInteractionIconShare && style == 2) DKIconPath(context, kDKPlaneFold, kCGPathStroke);
    }
    CGContextRestoreGState(context);
}
