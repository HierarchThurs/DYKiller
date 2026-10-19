#import "DKSVGImage.h"
#import <dlfcn.h>
#import <math.h>

typedef void *DKSVGDocument;
static DKSVGDocument (*DKSVGCreate)(CFDataRef, CFDictionaryRef);
static CGSize (*DKSVGSize)(DKSVGDocument);
static void (*DKSVGDraw)(CGContextRef, DKSVGDocument);
static void (*DKSVGRelease)(DKSVGDocument);

BOOL DKSVGImageAvailable(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/CoreSVG.framework/CoreSVG", RTLD_LAZY | RTLD_LOCAL);
        if (!handle) return;
        DKSVGCreate = dlsym(handle, "CGSVGDocumentCreateFromData");
        DKSVGSize = dlsym(handle, "CGSVGDocumentGetCanvasSize");
        DKSVGDraw = dlsym(handle, "CGContextDrawSVGDocument");
        DKSVGRelease = dlsym(handle, "CGSVGDocumentRelease");
    });
    return DKSVGCreate && DKSVGSize && DKSVGDraw && DKSVGRelease;
}

@interface DKSVGDocumentCheck : NSObject <NSXMLParserDelegate>
@property (nonatomic) NSUInteger depth;
@property (nonatomic) NSUInteger nodes;
@property (nonatomic) BOOL root;
@property (nonatomic, copy) NSString *failure;
@property (nonatomic, strong) NSMutableString *styleText;
@end

static BOOL DKSVGStyleAllowed(NSString *text) {
    NSString *lower = text.lowercaseString;
    if ([text containsString:@"\\"] || [lower containsString:@"@import"] || [lower containsString:@"@font-face"]) return NO;
    NSRegularExpression *urls = [NSRegularExpression regularExpressionWithPattern:@"url\\s*\\(\\s*([^)]*)\\)"
        options:NSRegularExpressionCaseInsensitive error:NULL];
    for (NSTextCheckingResult *match in [urls matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
        NSString *value = [[text substringWithRange:[match rangeAtIndex:1]]
            stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \t\r\n\"'"]];
        if (![value hasPrefix:@"#"]) return NO;
    }
    return YES;
}

@implementation DKSVGDocumentCheck
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)name namespaceURI:(NSString *)uri
 qualifiedName:(NSString *)qualified attributes:(NSDictionary<NSString *, NSString *> *)attributes {
    static NSSet *elements;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        elements = [NSSet setWithArray:@[ @"svg", @"g", @"defs", @"path", @"rect", @"circle", @"ellipse",
            @"line", @"polyline", @"polygon", @"linearGradient", @"radialGradient", @"stop", @"clipPath",
            @"mask", @"use", @"symbol", @"title", @"desc", @"style" ]];
    });
    self.depth++;
    self.nodes++;
    if ((!self.root && ![name isEqualToString:@"svg"]) || ![elements containsObject:name]
        || (uri.length && ![uri isEqualToString:@"http://www.w3.org/2000/svg"])
        || self.depth > 64 || self.nodes > 4096) {
        self.failure = @"SVG 包含不支持的元素或结构过于复杂";
    }
    self.root = YES;
    if ([name isEqualToString:@"style"]) self.styleText = [NSMutableString string];
    for (NSString *key in attributes) {
        NSString *lower = key.lowercaseString;
        if ([lower hasPrefix:@"on"] || !DKSVGStyleAllowed(attributes[key])
            || ([lower hasSuffix:@"href"] && ![attributes[key] hasPrefix:@"#"])) {
            self.failure = @"SVG 只支持静态图形和文档内引用";
        }
    }
    if (self.failure) [parser abortParsing];
}
- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)name namespaceURI:(NSString *)uri qualifiedName:(NSString *)qualified {
    if ([name isEqualToString:@"style"]) {
        if (!DKSVGStyleAllowed(self.styleText ?: @"")) {
            self.failure = @"SVG 不支持外部样式资源";
            [parser abortParsing];
        }
        self.styleText = nil;
    }
    if (self.depth) self.depth--;
}
- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string { [self.styleText appendString:string]; }
- (void)parser:(NSXMLParser *)parser foundCDATA:(NSData *)data {
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (text) [self.styleText appendString:text];
}
@end

static BOOL DKSVGCheck(NSData *data, NSString **reason) {
    NSString *text = data.length <= 512 * 1024 ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    NSString *lower = text.lowercaseString;
    NSString *failure = nil;
    if (!text.length || [lower containsString:@"<!doctype"] || [lower containsString:@"<!entity"]
        || [lower containsString:@"<?xml-stylesheet"] || [lower containsString:@"@import"]
        || [lower containsString:@"@font-face"]) failure = @"SVG 文件过大、编码无效或包含外部资源";
    if (!DKSVGStyleAllowed(text ?: @"")) failure = @"SVG 包含外部资源或不支持的样式转义";
    if (!failure) {
        NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
        parser.shouldProcessNamespaces = YES;
        parser.shouldResolveExternalEntities = NO;
        DKSVGDocumentCheck *check = [[DKSVGDocumentCheck alloc] init];
        parser.delegate = check;
        if (![parser parse] || !check.root) failure = check.failure ?: @"SVG 文档无效";
    }
    if (reason) *reason = failure;
    return !failure;
}

BOOL DKSVGImageInspect(NSData *data, CGSize *size, NSString **reason) {
    if (!DKSVGCheck(data, reason)) return NO;
    if (!DKSVGImageAvailable()) {
        if (reason) *reason = @"当前系统的 SVG 渲染器不可用";
        return NO;
    }
    DKSVGDocument document = DKSVGCreate((__bridge CFDataRef)data, NULL);
    CGSize canvas = document ? DKSVGSize(document) : CGSizeZero;
    if (document) DKSVGRelease(document);
    if (!isfinite(canvas.width) || !isfinite(canvas.height) || canvas.width <= 0 || canvas.height <= 0
        || canvas.width > 4096 || canvas.height > 4096) {
        if (reason) *reason = @"SVG 画布无效或超过 4096";
        return NO;
    }
    if (size) *size = canvas;
    return YES;
}

CGImageRef DKSVGImageCreate(NSData *data, CGSize pixels) {
    CGSize canvas;
    if (!DKSVGImageInspect(data, &canvas, NULL) || !isfinite(pixels.width) || !isfinite(pixels.height)
        || pixels.width < 1 || pixels.height < 1 || pixels.width > 2048 || pixels.height > 2048) return NULL;
    DKSVGDocument document = DKSVGCreate((__bridge CFDataRef)data, NULL);
    if (!document) return NULL;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, (size_t)ceil(pixels.width), (size_t)ceil(pixels.height), 8, 0,
        space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGImageRef image = NULL;
    if (context) {
        CGFloat scale = MIN(pixels.width / canvas.width, pixels.height / canvas.height);
        CGContextTranslateCTM(context, (pixels.width - canvas.width * scale) / 2, (pixels.height - canvas.height * scale) / 2);
        CGContextScaleCTM(context, scale, scale);
        DKSVGDraw(context, document);
        image = CGBitmapContextCreateImage(context);
        CGContextRelease(context);
    }
    DKSVGRelease(document);
    return image;
}
