//
//  DKTabBarIconDraw.m
//  DYKiller
//
//  图形按设计稿逐条还原：实心版的「白 / 黑」mask 在这里对应「正常绘制 / Clear 混合挖空」，
//  实心主体同时描边，保持与线框版相同的外轮廓与圆角。
//

#import "DKTabBarIconDraw.h"

#import <math.h>
#import <stdlib.h>

static const CGFloat kDKLineWidth = 1.75;

#pragma mark - SVG path 解析

typedef struct {
    const char *cursor;
} DKPathScanner;

static void DKSkipSeparators(DKPathScanner *scanner) {
    while (*scanner->cursor == ' ' || *scanner->cursor == ',' || *scanner->cursor == '\t' ||
           *scanner->cursor == '\n' || *scanner->cursor == '\r') {
        scanner->cursor++;
    }
}

// strtod 自然处理紧凑写法：".65.65" 读到第二个点停下，"1-.84" 读到负号停下。
static BOOL DKReadNumber(DKPathScanner *scanner, CGFloat *value) {
    DKSkipSeparators(scanner);
    char *end = NULL;
    double number = strtod(scanner->cursor, &end);
    if (end == scanner->cursor) return NO;
    scanner->cursor = end;
    *value = (CGFloat)number;
    return YES;
}

static BOOL DKNextIsNumber(DKPathScanner *scanner) {
    DKSkipSeparators(scanner);
    char c = *scanner->cursor;
    return (c >= '0' && c <= '9') || c == '-' || c == '+' || c == '.';
}

// 端点参数化的圆弧转为三次贝塞尔（SVG 规范 F.6.5），每段不超过 90°。
static void DKAddArc(CGMutablePathRef path, CGPoint from, CGFloat rx, CGFloat ry, CGFloat rotation,
                     BOOL largeArc, BOOL sweep, CGPoint to) {
    if (CGPointEqualToPoint(from, to)) return;
    rx = fabs(rx);
    ry = fabs(ry);
    if (rx == 0 || ry == 0) {
        CGPathAddLineToPoint(path, NULL, to.x, to.y);
        return;
    }
    CGFloat phi = rotation * M_PI / 180.0;
    CGFloat cosPhi = cos(phi), sinPhi = sin(phi);
    CGFloat dx = (from.x - to.x) / 2.0, dy = (from.y - to.y) / 2.0;
    CGFloat x1 = cosPhi * dx + sinPhi * dy;
    CGFloat y1 = -sinPhi * dx + cosPhi * dy;

    CGFloat lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry);
    if (lambda > 1) {
        rx *= sqrt(lambda);
        ry *= sqrt(lambda);
    }
    CGFloat numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1;
    CGFloat denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1;
    // 弦长恰为直径时分子可能是 -ε，钳到 0。
    CGFloat coefficient = denominator > 0 ? sqrt(fmax(0, numerator / denominator)) : 0;
    if (largeArc == sweep) coefficient = -coefficient;
    CGFloat cxPrime = coefficient * rx * y1 / ry;
    CGFloat cyPrime = -coefficient * ry * x1 / rx;
    CGFloat cx = cosPhi * cxPrime - sinPhi * cyPrime + (from.x + to.x) / 2.0;
    CGFloat cy = sinPhi * cxPrime + cosPhi * cyPrime + (from.y + to.y) / 2.0;

    CGFloat ux = (x1 - cxPrime) / rx, uy = (y1 - cyPrime) / ry;
    CGFloat vx = (-x1 - cxPrime) / rx, vy = (-y1 - cyPrime) / ry;
    CGFloat start = atan2(uy, ux);
    CGFloat delta = atan2(ux * vy - uy * vx, ux * vx + uy * vy);
    if (!sweep && delta > 0) delta -= 2 * M_PI;
    if (sweep && delta < 0) delta += 2 * M_PI;

    NSInteger segments = (NSInteger)ceil(fabs(delta) / (M_PI / 2.0) - 1e-9);
    if (segments < 1) segments = 1;
    CGFloat step = delta / segments;
    CGFloat handle = 4.0 / 3.0 * tan(step / 4.0);
    CGFloat angle = start;
    for (NSInteger i = 0; i < segments; i++) {
        CGFloat a1 = angle, a2 = angle + step;
        CGFloat c1x = cos(a1) - handle * sin(a1), c1y = sin(a1) + handle * cos(a1);
        CGFloat c2x = cos(a2) + handle * sin(a2), c2y = sin(a2) - handle * cos(a2);
        CGFloat ex = cos(a2), ey = sin(a2);
        CGPoint p1 = CGPointMake(cx + rx * (cosPhi * c1x) - ry * (sinPhi * c1y), cy + rx * (sinPhi * c1x) + ry * (cosPhi * c1y));
        CGPoint p2 = CGPointMake(cx + rx * (cosPhi * c2x) - ry * (sinPhi * c2y), cy + rx * (sinPhi * c2x) + ry * (cosPhi * c2y));
        CGPoint p3 = (i == segments - 1) ? to
            : CGPointMake(cx + rx * (cosPhi * ex) - ry * (sinPhi * ey), cy + rx * (sinPhi * ex) + ry * (cosPhi * ey));
        CGPathAddCurveToPoint(path, NULL, p1.x, p1.y, p2.x, p2.y, p3.x, p3.y);
        angle = a2;
    }
}

CGPathRef DKSVGPathCreate(const char *data) {
    if (!data) return NULL;
    CGMutablePathRef path = CGPathCreateMutable();
    DKPathScanner scanner = { data };
    CGPoint current = CGPointZero, start = CGPointZero, lastControl = CGPointZero;
    char command = 0, previous = 0;

    while (1) {
        DKSkipSeparators(&scanner);
        char c = *scanner.cursor;
        if (c == '\0') break;
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) {
            command = c;
            scanner.cursor++;
        } else if (!command || !DKNextIsNumber(&scanner)) {
            CGPathRelease(path);
            return NULL;
        }
        BOOL relative = command >= 'a' && command <= 'z';
        char upper = relative ? (char)(command - 32) : command;
        CGFloat ox = relative ? current.x : 0, oy = relative ? current.y : 0;
        CGFloat v[7];

        switch (upper) {
            case 'Z':
                CGPathCloseSubpath(path);
                current = start;
                command = 0;                       // Z 不带参数，后面必须是新的命令字母
                break;
            case 'M':
                if (!DKReadNumber(&scanner, &v[0]) || !DKReadNumber(&scanner, &v[1])) goto fail;
                current = CGPointMake(ox + v[0], oy + v[1]);
                start = current;
                CGPathMoveToPoint(path, NULL, current.x, current.y);
                command = relative ? 'l' : 'L';     // 之后的坐标对是隐式 L
                break;
            case 'L':
                if (!DKReadNumber(&scanner, &v[0]) || !DKReadNumber(&scanner, &v[1])) goto fail;
                current = CGPointMake(ox + v[0], oy + v[1]);
                CGPathAddLineToPoint(path, NULL, current.x, current.y);
                break;
            case 'H':
                if (!DKReadNumber(&scanner, &v[0])) goto fail;
                current.x = ox + v[0];
                CGPathAddLineToPoint(path, NULL, current.x, current.y);
                break;
            case 'V':
                if (!DKReadNumber(&scanner, &v[0])) goto fail;
                current.y = oy + v[0];
                CGPathAddLineToPoint(path, NULL, current.x, current.y);
                break;
            case 'C':
                for (int i = 0; i < 6; i++) if (!DKReadNumber(&scanner, &v[i])) goto fail;
                CGPathAddCurveToPoint(path, NULL, ox + v[0], oy + v[1], ox + v[2], oy + v[3], ox + v[4], oy + v[5]);
                lastControl = CGPointMake(ox + v[2], oy + v[3]);
                current = CGPointMake(ox + v[4], oy + v[5]);
                break;
            case 'S': {
                for (int i = 0; i < 4; i++) if (!DKReadNumber(&scanner, &v[i])) goto fail;
                BOOL smooth = previous == 'C' || previous == 'S';
                CGPoint c1 = smooth ? CGPointMake(2 * current.x - lastControl.x, 2 * current.y - lastControl.y) : current;
                CGPathAddCurveToPoint(path, NULL, c1.x, c1.y, ox + v[0], oy + v[1], ox + v[2], oy + v[3]);
                lastControl = CGPointMake(ox + v[0], oy + v[1]);
                current = CGPointMake(ox + v[2], oy + v[3]);
                break;
            }
            case 'A': {
                for (int i = 0; i < 7; i++) if (!DKReadNumber(&scanner, &v[i])) goto fail;
                CGPoint to = CGPointMake(ox + v[5], oy + v[6]);
                DKAddArc(path, current, v[0], v[1], v[2], v[3] != 0, v[4] != 0, to);
                current = to;
                break;
            }
            default:
                goto fail;
        }
        previous = upper;
    }
    return path;

fail:
    CGPathRelease(path);
    return NULL;
}

#pragma mark - 绘制原语（24 单位坐标）

static void DKDrawPath(CGContextRef context, const char *data, CGPathDrawingMode mode, CGFloat lineWidth) {
    CGPathRef path = DKSVGPathCreate(data);
    if (!path) return;
    CGContextAddPath(context, path);
    CGContextSetLineWidth(context, lineWidth);
    CGContextDrawPath(context, mode);
    CGPathRelease(path);
}

static void DKDrawCircle(CGContextRef context, CGFloat cx, CGFloat cy, CGFloat r, CGPathDrawingMode mode, CGFloat lineWidth) {
    CGContextAddEllipseInRect(context, CGRectMake(cx - r, cy - r, r * 2, r * 2));
    CGContextSetLineWidth(context, lineWidth);
    CGContextDrawPath(context, mode);
}

// 设计稿里 mask 的「黑」：Clear 混合把已画内容挖掉。
static void DKBeginCut(CGContextRef context) {
    CGContextSetBlendMode(context, kCGBlendModeClear);
}

static void DKEndCut(CGContextRef context) {
    CGContextSetBlendMode(context, kCGBlendModeNormal);
}

static void DKBeginGlyph(CGContextRef context, CGRect rect, CGColorRef color) {
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, CGRectGetMinX(rect), CGRectGetMinY(rect));
    CGFloat scale = CGRectGetWidth(rect) / 24.0;
    CGContextScaleCTM(context, scale, scale);
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineJoin(context, kCGLineJoinRound);
    if (color) {
        CGContextSetFillColorWithColor(context, color);
        CGContextSetStrokeColorWithColor(context, color);
    }
}

#pragma mark - 路径（与设计稿一致）

static const char *const kDKHouse = "M4.75 10.05 11.1 4.7a1.4 1.4 0 0 1 1.8 0l6.35 5.35a1.9 1.9 0 0 1 .68 1.45v6.1a2.25 2.25 0 0 1-2.25 2.25H6.32a2.25 2.25 0 0 1-2.25-2.25v-6.1a1.9 1.9 0 0 1 .68-1.45Z";
static const char *const kDKArchDoor = "M9.9 19.85v-3.45a2.1 2.1 0 0 1 4.2 0v3.45";
static const char *const kDKArchDoorCut = "M9.9 21.3v-4.9a2.1 2.1 0 0 1 4.2 0v4.9Z";
static const char *const kDKBag = "M6.15 8.55h11.7a1 1 0 0 1 1 1.08l-.7 8.95a2.1 2.1 0 0 1-2.1 1.92H7.95a2.1 2.1 0 0 1-2.1-1.92l-.7-8.95a1 1 0 0 1 1-1.08Z";
static const char *const kDKHandle = "M9.1 8.55V7.3a2.9 2.9 0 0 1 5.8 0v1.25";
static const char *const kDKSmile = "M9.55 12.35a2.45 2.45 0 0 0 4.9 0";
static const char *const kDKFrontBody = "M3.65 19.6c.5-3.15 2.85-5.3 5.75-5.3s5.25 2.15 5.75 5.3";
static const char *const kDKFrontBodyFill = "M3.65 19.6c.5-3.15 2.85-5.3 5.75-5.3s5.25 2.15 5.75 5.3a.85.85 0 0 1-.84.98H4.49a.85.85 0 0 1-.84-.98Z";
static const char *const kDKBackHead = "M14.85 5.79a2.7 2.7 0 1 1 0 4.42";
static const char *const kDKBackBody = "M16.9 14.25c2.15.45 3.6 2.35 3.85 5.35";
static const char *const kDKBackBodyFill = "M14.6 14.35c3.4-1.15 5.95.95 6.15 5.2a.85.85 0 0 1-.85.95h-5.3Z";
static const char *const kDKBubble = "M12 4.4c4.5 0 8.15 3.1 8.15 6.95S16.5 18.3 12 18.3c-.95 0-1.86-.13-2.7-.38l-3.6 1.83a.5.5 0 0 1-.7-.58l.88-3.2C4.6 14.73 3.85 13.1 3.85 11.35 3.85 7.5 7.5 4.4 12 4.4Z";
static const char *const kDKMeBody = "M4.9 19.75c.6-3.6 3.55-5.75 7.1-5.75s6.5 2.15 7.1 5.75";
static const char *const kDKMeBodyFill = "M4.9 19.75c.6-3.6 3.55-5.75 7.1-5.75s6.5 2.15 7.1 5.75a.8.8 0 0 1-.79.93H5.69a.8.8 0 0 1-.79-.93Z";
static const char *const kDKCamera = "M5.6 6.8h2.4l1.15-1.8a1.6 1.6 0 0 1 1.35-.75h3a1.6 1.6 0 0 1 1.35.75L16 6.8h2.4a2.85 2.85 0 0 1 2.85 2.85v7.25a2.85 2.85 0 0 1-2.85 2.85H5.6a2.85 2.85 0 0 1-2.85-2.85V9.65A2.85 2.85 0 0 1 5.6 6.8Z";

// 照相机镜头与闪光点：镜头半径 3.45，镜头环挖空到描边外沿，环内补回镜片。
static const CGFloat kDKLensX = 12.0, kDKLensY = 13.2, kDKLensRadius = 3.45;
static const CGFloat kDKFlashX = 17.75, kDKFlashY = 9.75, kDKFlashRadius = 1.0;
static const CGFloat kDKMessageDotsY = 11.35;
static const CGFloat kDKMessageDotsX[3] = { 8.45, 12.0, 15.55 };

#pragma mark - tab 图标

static void DKDrawHome(CGContextRef context, BOOL filled) {
    if (filled) {
        DKDrawPath(context, kDKHouse, kCGPathFillStroke, kDKLineWidth);
        DKBeginCut(context);
        DKDrawPath(context, kDKArchDoorCut, kCGPathFill, 0);
        DKEndCut(context);
    } else {
        DKDrawPath(context, kDKHouse, kCGPathStroke, kDKLineWidth);
        DKDrawPath(context, kDKArchDoor, kCGPathStroke, kDKLineWidth);
    }
}

static void DKDrawMall(CGContextRef context, BOOL filled) {
    if (filled) {
        DKDrawPath(context, kDKBag, kCGPathFillStroke, kDKLineWidth);
        DKDrawPath(context, kDKHandle, kCGPathStroke, kDKLineWidth);
        DKBeginCut(context);
        DKDrawPath(context, kDKSmile, kCGPathStroke, kDKLineWidth);
        DKEndCut(context);
    } else {
        DKDrawPath(context, kDKBag, kCGPathStroke, kDKLineWidth);
        DKDrawPath(context, kDKHandle, kCGPathStroke, kDKLineWidth);
        DKDrawPath(context, kDKSmile, kCGPathStroke, kDKLineWidth);
    }
}

// 实心版：先画后面的人，再按前面的人轮廓外扩一圈挖出缝隙，最后画前面的人。
static void DKDrawFriends(CGContextRef context, BOOL filled) {
    if (filled) {
        DKDrawCircle(context, 16.4, 8.0, 2.7, kCGPathFillStroke, kDKLineWidth);
        DKDrawPath(context, kDKBackBodyFill, kCGPathFillStroke, kDKLineWidth);
        DKBeginCut(context);
        DKDrawCircle(context, 9.4, 8.0, 3.0, kCGPathFillStroke, kDKLineWidth + 2.2);
        DKDrawPath(context, kDKFrontBodyFill, kCGPathFillStroke, kDKLineWidth + 2.2);
        DKEndCut(context);
        DKDrawCircle(context, 9.4, 8.0, 3.0, kCGPathFillStroke, kDKLineWidth);
        DKDrawPath(context, kDKFrontBodyFill, kCGPathFillStroke, kDKLineWidth);
    } else {
        DKDrawCircle(context, 9.4, 8.0, 3.0, kCGPathStroke, kDKLineWidth);
        DKDrawPath(context, kDKFrontBody, kCGPathStroke, kDKLineWidth);
        DKDrawPath(context, kDKBackHead, kCGPathStroke, kDKLineWidth);
        DKDrawPath(context, kDKBackBody, kCGPathStroke, kDKLineWidth);
    }
}

static void DKDrawMessage(CGContextRef context, BOOL filled) {
    if (filled) {
        DKDrawPath(context, kDKBubble, kCGPathFillStroke, kDKLineWidth);
        DKBeginCut(context);
        for (int i = 0; i < 3; i++) DKDrawCircle(context, kDKMessageDotsX[i], kDKMessageDotsY, 1.2, kCGPathFill, 0);
        DKEndCut(context);
    } else {
        DKDrawPath(context, kDKBubble, kCGPathStroke, kDKLineWidth);
        for (int i = 0; i < 3; i++) DKDrawCircle(context, kDKMessageDotsX[i], kDKMessageDotsY, 1.1, kCGPathFill, 0);
    }
}

static void DKDrawMe(CGContextRef context, BOOL filled) {
    if (filled) {
        DKDrawCircle(context, 12.0, 7.9, 3.45, kCGPathFillStroke, kDKLineWidth);
        DKDrawPath(context, kDKMeBodyFill, kCGPathFillStroke, kDKLineWidth);
    } else {
        DKDrawCircle(context, 12.0, 7.9, 3.45, kCGPathStroke, kDKLineWidth);
        DKDrawPath(context, kDKMeBody, kCGPathStroke, kDKLineWidth);
    }
}

void DKTabBarDrawGlyph(CGContextRef context, DKTabBarGlyph glyph, BOOL filled, CGRect rect, CGColorRef color) {
    if (!context) return;
    DKBeginGlyph(context, rect, color);
    switch (glyph) {
        case DKTabBarGlyphHome: DKDrawHome(context, filled); break;
        case DKTabBarGlyphMall: DKDrawMall(context, filled); break;
        case DKTabBarGlyphFriends: DKDrawFriends(context, filled); break;
        case DKTabBarGlyphMessage: DKDrawMessage(context, filled); break;
        case DKTabBarGlyphMe: DKDrawMe(context, filled); break;
    }
    CGContextRestoreGState(context);
}

#pragma mark - 照相机

static void DKCutLensAndFlash(CGContextRef context) {
    DKBeginCut(context);
    DKDrawCircle(context, kDKLensX, kDKLensY, kDKLensRadius + kDKLineWidth / 2.0, kCGPathFill, 0);
    DKDrawCircle(context, kDKFlashX, kDKFlashY, kDKFlashRadius, kCGPathFill, 0);
    DKEndCut(context);
}

void DKTabBarDrawCamera(CGContextRef context, CGRect rect, CGColorRef color) {
    if (!context) return;
    DKBeginGlyph(context, rect, color);
    DKDrawPath(context, kDKCamera, kCGPathFillStroke, kDKLineWidth);
    DKCutLensAndFlash(context);
    DKDrawCircle(context, kDKLensX, kDKLensY, fmax(kDKLensRadius - kDKLineWidth / 2.0 - 0.3, 0.8), kCGPathFill, 0);
    CGContextRestoreGState(context);
}

// 青、红的取值与抖音拍摄键一致。镜头整圈挖空，彩色只在机身左右边缘露出。
void DKTabBarDrawCameraAccent(CGContextRef context, CGRect rect) {
    if (!context) return;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    const CGFloat cyan[4] = { 0x25 / 255.0, 0xF4 / 255.0, 0xEE / 255.0, 1.0 };
    const CGFloat red[4] = { 0xFE / 255.0, 0x2C / 255.0, 0x55 / 255.0, 1.0 };
    CGColorRef cyanColor = CGColorCreate(space, cyan);
    CGColorRef redColor = CGColorCreate(space, red);

    DKBeginGlyph(context, rect, NULL);
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, -0.9, 0);
    CGContextSetFillColorWithColor(context, cyanColor);
    CGContextSetStrokeColorWithColor(context, cyanColor);
    DKDrawPath(context, kDKCamera, kCGPathFillStroke, kDKLineWidth);
    CGContextRestoreGState(context);

    CGContextSaveGState(context);
    CGContextTranslateCTM(context, 0.9, 0);
    CGContextSetFillColorWithColor(context, redColor);
    CGContextSetStrokeColorWithColor(context, redColor);
    DKDrawPath(context, kDKCamera, kCGPathFillStroke, kDKLineWidth);
    CGContextRestoreGState(context);

    DKCutLensAndFlash(context);
    CGContextRestoreGState(context);

    CGColorRelease(cyanColor);
    CGColorRelease(redColor);
    CGColorSpaceRelease(space);
}
