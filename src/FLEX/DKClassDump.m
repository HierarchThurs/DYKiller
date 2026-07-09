//
//  DKClassDump.m
//  DYKiller
//
//  基于 ObjC 运行时生成类头文件文本。
//  DKClassIsSafe 用于限制可内省类集合。
//  DKClassDumpAppImages 按镜像分组列出应用自有类。
//

#import "DKClassDump.h"
#import <mach-o/dyld.h>
#import <CoreFoundation/CoreFoundation.h>

#pragma mark - 安全内省检查

// 用 CFSet + NULL 回调按指针身份比较，用于跳过不安全类。
static CFSetRef DKUnsafeClassSet;
static Class DKcNSObject;
static Class DKcNSProxy;

__attribute__((constructor))
static void DKClassDumpInit(void) {
    DKcNSObject = [NSObject class];
    DKcNSProxy = [NSProxy class];

    static const char *const kUnsafeNames[] = {
        "__ARCLite__", "__NSCFCalendar", "__NSCFTimer", "NSCFTimer",
        "__NSGenericDeallocHandler", "NSAutoreleasePool", "NSPlaceholderNumber",
        "NSPlaceholderString", "NSPlaceholderValue", "Object", "VMUArchitecture",
        "JSExport", "__NSAtom", "_NSZombie_", "_CNZombie_", "__NSMessage",
        "__NSMessageBuilder", "FigIrisAutoTrimmerMotionSampleExport", "_UIPointVector",
    };
    NSUInteger n = sizeof(kUnsafeNames) / sizeof(kUnsafeNames[0]);
    const void **classes = malloc(n * sizeof(void *));
    NSUInteger count = 0;
    for (NSUInteger i = 0; i < n; i++) {
        Class c = objc_getClass(kUnsafeNames[i]);
        if (c) classes[count++] = (__bridge const void *)c;
    }
    DKUnsafeClassSet = CFSetCreate(kCFAllocatorDefault, classes, count, NULL);
    free(classes);
}

BOOL DKClassIsSafe(Class cls) {
    if (!cls) return NO;
    if (DKUnsafeClassSet && CFSetContainsValue(DKUnsafeClassSet, (__bridge const void *)cls)) return NO;
    // 无父类者只有 NSObject / NSProxy 两个已知根类是安全的
    if (!class_getSuperclass(cls)) {
        return cls == DKcNSObject || cls == DKcNSProxy;
    }
    return YES;
}

#pragma mark - 过滤

static BOOL DKIsLikelySwiftName(NSString *name) {
    if (name.length == 0) return YES;
    if ([name hasPrefix:@"_Tt"]) return YES;
    if ([name hasPrefix:@"Swift."]) return YES;
    if ([name hasPrefix:@"SwiftUI."]) return YES;
    if ([name containsString:@"<"]) return YES;
    if ([name containsString:@"`"]) return YES;
    if ([name containsString:@"."]) return YES;
    return NO;
}

BOOL DKClassNameIsRuntimeGenerated(NSString *name) {
    if (name.length == 0) return YES;
    if ([name hasPrefix:@"NSKVONotifying_"]) return YES;   // KVO 运行时子类
    if ([name containsString:@"_hmd_subfix_"]) return YES; // Heimdallr 崩溃修复子类
    if ([name containsString:@"_AWEPERF_"]) return YES;    // 性能监控子类
    if ([name containsString:@"_block_invoke"]) return YES;
    if ([name containsString:@"%"]) return YES;
    return NO;
}

// 只保留应用自身及其 Frameworks/PlugIns/Extensions 目录下的镜像，丢掉系统库。
static BOOL DKShouldSkipImage(NSString *imagePath) {
    if (imagePath.length == 0) return YES;
    if ([imagePath hasPrefix:@"/System/"]) return YES;
    if ([imagePath hasPrefix:@"/usr/lib/"]) return YES;

    NSString *bundlePath = NSBundle.mainBundle.bundlePath ?: @"";
    NSString *container = [bundlePath stringByDeletingLastPathComponent];

    if ([imagePath hasPrefix:bundlePath]) return NO;
    if ([imagePath hasPrefix:container] && ([imagePath containsString:@"/Frameworks/"] ||
                                            [imagePath containsString:@"/PlugIns/"] ||
                                            [imagePath containsString:@"/Extensions/"])) {
        return NO;
    }
    return YES;
}

#pragma mark - 类型编码 → 可读类型

static NSString *DKTypeFromEncoding(const char *encoding) {
    if (!encoding) return @"id";
    NSString *e = [NSString stringWithUTF8String:encoding];
    if (e.length == 0) return @"id";

    if ([e hasPrefix:@"@\""]) {
        NSRange r1 = [e rangeOfString:@"\""];
        NSRange r2 = [e rangeOfString:@"\"" options:NSBackwardsSearch];
        if (r1.location != NSNotFound && r2.location != NSNotFound && r2.location > r1.location) {
            NSString *cls = [e substringWithRange:NSMakeRange(r1.location + 1, r2.location - r1.location - 1)];
            if (cls.length) return [NSString stringWithFormat:@"%@ *", cls];
        }
    }

    switch ([e characterAtIndex:0]) {
        case 'v': return @"void";
        case '@': return @"id";
        case '#': return @"Class";
        case ':': return @"SEL";
        case 'c': return @"char";
        case 'C': return @"unsigned char";
        case 's': return @"short";
        case 'S': return @"unsigned short";
        case 'i': return @"int";
        case 'I': return @"unsigned int";
        case 'l': return @"long";
        case 'L': return @"unsigned long";
        case 'q': return @"long long";
        case 'Q': return @"unsigned long long";
        case 'f': return @"float";
        case 'd': return @"double";
        case 'B': return @"BOOL";
        case '*': return @"char *";
        case '^': return @"void *";
        case '{': return @"struct";
        case '[': return @"void *";
        default:  return @"id";
    }
}

#pragma mark - 属性 / 方法行

static NSString *DKPropertyLine(objc_property_t property) {
    const char *n = property_getName(property);
    if (!n) return nil;
    NSString *name = [NSString stringWithUTF8String:n];

    NSString *attrs = @"";
    const char *a = property_getAttributes(property);
    if (a) attrs = [NSString stringWithUTF8String:a];

    NSString *type = @"id";
    BOOL readonly = [attrs containsString:@",R"];
    BOOL copy = [attrs containsString:@",C"];
    BOOL weak = [attrs containsString:@",W"];
    BOOL nonatomic = [attrs containsString:@",N"];

    if ([attrs hasPrefix:@"T"]) {
        NSString *typePart = [[attrs substringFromIndex:1] componentsSeparatedByString:@","].firstObject ?: @"@";
        type = DKTypeFromEncoding(typePart.UTF8String);
    }

    NSMutableArray *parts = [NSMutableArray array];
    [parts addObject:(nonatomic ? @"nonatomic" : @"atomic")];
    if (readonly) [parts addObject:@"readonly"];
    if (copy) [parts addObject:@"copy"];
    else if (weak) [parts addObject:@"weak"];
    else if ([type containsString:@"*"] || [type isEqualToString:@"id"]) [parts addObject:@"strong"];
    else [parts addObject:@"assign"];

    return [NSString stringWithFormat:@"@property (%@) %@ %@;", [parts componentsJoinedByString:@", "], type, name];
}

static NSString *DKMethodLine(Method m, BOOL isClassMethod) {
    SEL sel = method_getName(m);
    if (!sel) return nil;

    const char *ret = method_copyReturnType(m);
    NSString *retType = DKTypeFromEncoding(ret);
    if (ret) free((void *)ret);

    NSString *name = NSStringFromSelector(sel);
    if (name.length == 0) return nil;

    unsigned int argCount = method_getNumberOfArguments(m);
    if (![name containsString:@":"] || argCount <= 2) {
        return [NSString stringWithFormat:@"%c (%@)%@;", isClassMethod ? '+' : '-', retType, name];
    }

    NSArray<NSString *> *parts = [name componentsSeparatedByString:@":"];
    NSMutableString *line = [NSMutableString stringWithFormat:@"%c (%@)", isClassMethod ? '+' : '-', retType];
    for (NSUInteger i = 0; i < parts.count - 1; i++) {
        NSString *label = parts[i];
        char *argTypeRaw = method_copyArgumentType(m, (unsigned int)i + 2);
        NSString *argType = DKTypeFromEncoding(argTypeRaw);
        if (argTypeRaw) free(argTypeRaw);
        if (i == 0) {
            [line appendFormat:@"%@:(%@)arg%lu", label.length ? label : @"method", argType, (unsigned long)i];
        } else {
            [line appendFormat:@" %@:(%@)arg%lu", label.length ? label : @"param", argType, (unsigned long)i];
        }
    }
    [line appendString:@";"];
    return line;
}

#pragma mark - 单类头文件

static NSString *DKHeaderForClass(Class cls, NSString *imageName) {
    if (!DKClassIsSafe(cls)) return nil;
    @try {
        NSString *className = NSStringFromClass(cls);
        if (className.length == 0) return nil;
        if (DKIsLikelySwiftName(className)) return nil;

        Class superCls = class_getSuperclass(cls);
        NSString *superName = superCls ? NSStringFromClass(superCls) : @"NSObject";

        NSMutableString *h = [NSMutableString string];
        [h appendString:@"//\n"];
        [h appendString:@"// Dumped by DYKiller DKClassDump\n"];
        [h appendFormat:@"// Bundle: %@\n", NSBundle.mainBundle.bundleIdentifier ?: @"Unknown"];
        [h appendFormat:@"// Image: %@\n", imageName ?: @"Unknown"];
        [h appendString:@"//\n\n"];
        [h appendString:@"#import <Foundation/Foundation.h>\n"];
        [h appendString:@"#import <UIKit/UIKit.h>\n\n"];

        unsigned int protocolCount = 0;
        Protocol *__unsafe_unretained *protocols = class_copyProtocolList(cls, &protocolCount);
        NSMutableArray *protocolNames = [NSMutableArray array];
        for (unsigned int i = 0; i < protocolCount; i++) {
            const char *pn = protocol_getName(protocols[i]);
            if (pn) [protocolNames addObject:[NSString stringWithUTF8String:pn]];
        }
        if (protocols) free(protocols);

        if (protocolNames.count) {
            [h appendFormat:@"@interface %@ : %@ <%@>\n\n", className, superName, [protocolNames componentsJoinedByString:@", "]];
        } else {
            [h appendFormat:@"@interface %@ : %@\n\n", className, superName];
        }

        unsigned int ivarCount = 0;
        Ivar *ivars = class_copyIvarList(cls, &ivarCount);
        if (ivarCount > 0) [h appendString:@"{\n"];
        for (unsigned int i = 0; i < ivarCount; i++) {
            const char *in = ivar_getName(ivars[i]);
            const char *it = ivar_getTypeEncoding(ivars[i]);
            if (in) [h appendFormat:@"    %@ %s;\n", DKTypeFromEncoding(it), in];
        }
        if (ivarCount > 0) [h appendString:@"}\n\n"];
        if (ivars) free(ivars);

        unsigned int propertyCount = 0;
        objc_property_t *props = class_copyPropertyList(cls, &propertyCount);
        if (propertyCount > 0) [h appendString:@"#pragma mark - Properties\n\n"];
        for (unsigned int i = 0; i < propertyCount; i++) {
            NSString *line = DKPropertyLine(props[i]);
            if (line.length) [h appendFormat:@"%@\n", line];
        }
        if (props) free(props);

        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        if (methodCount > 0) [h appendString:@"\n#pragma mark - Instance Methods\n\n"];
        for (unsigned int i = 0; i < methodCount; i++) {
            NSString *line = DKMethodLine(methods[i], NO);
            if (line.length) [h appendFormat:@"%@\n", line];
        }
        if (methods) free(methods);

        Class meta = object_getClass(cls);
        unsigned int classMethodCount = 0;
        Method *classMethods = class_copyMethodList(meta, &classMethodCount);
        if (classMethodCount > 0) [h appendString:@"\n#pragma mark - Class Methods\n\n"];
        for (unsigned int i = 0; i < classMethodCount; i++) {
            NSString *line = DKMethodLine(classMethods[i], YES);
            if (line.length) [h appendFormat:@"%@\n", line];
        }
        if (classMethods) free(classMethods);

        [h appendString:@"\n@end\n"];
        return h;
    } @catch (__unused NSException *e) {
        return nil;
    }
}

#pragma mark - 对外 API

NSString *DKClassDumpHeaderForClass(Class cls) {
    if (!DKClassIsSafe(cls)) return nil;
    NSString *imageName = @"Unknown";
    const char *img = class_getImageName(cls);
    if (img) imageName = [[NSString stringWithUTF8String:img] lastPathComponent] ?: @"Unknown";
    return DKHeaderForClass(cls, imageName);
}

NSArray<NSDictionary *> *DKClassDumpAppImages(void) {
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    uint32_t imageCount = _dyld_image_count();
    for (uint32_t i = 0; i < imageCount; i++) {
        const char *cpath = _dyld_get_image_name(i);
        if (!cpath) continue;

        NSString *imagePath = [NSString stringWithUTF8String:cpath];
        if (DKShouldSkipImage(imagePath)) continue;

        unsigned int classCount = 0;
        const char **names = objc_copyClassNamesForImage(cpath, &classCount);
        if (!names || classCount == 0) {
            if (names) free(names);
            continue;
        }

        NSMutableArray<NSString *> *safeNames = [NSMutableArray array];
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        for (unsigned int j = 0; j < classCount; j++) {
            const char *cn = names[j];
            if (!cn) continue;
            NSString *name = [NSString stringWithUTF8String:cn];
            if (DKIsLikelySwiftName(name) || DKClassNameIsRuntimeGenerated(name)) continue;
            if ([seen containsObject:name]) continue;   // 去重：同镜像内重名 → 避免 zip 同名条目
            [seen addObject:name];
            [safeNames addObject:name];
        }
        free(names);

        if (safeNames.count > 0) {
            [result addObject:@{
                @"imagePath": imagePath,
                @"imageName": imagePath.lastPathComponent ?: @"Image",
                @"classes": safeNames
            }];
        }
    }
    return result;
}
