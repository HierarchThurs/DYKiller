// 搜索框架加载后安装原生 Hook；诊断记录当前方法归属。
#import "DKSearchClean.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <string.h>

static void DKSearchInstallAvailableHooks(void) {
    DKSearchInstallNativeHooks();
    DKSearchInstallCameraHooks();
}

static void DKSearchImageAdded(const struct mach_header *header, intptr_t slide) {
    Dl_info image = {0};
    if (!dladdr(header, &image) || !image.dli_fname) return;
    const char *name = strrchr(image.dli_fname, '/');
    if (strcmp(name ? name + 1 : image.dli_fname, "AWESearchFramework") != 0) return;
    // 回调在加载器上下文内，只调度到主队列；类登记完成后按组安装一次。
    dispatch_async(dispatch_get_main_queue(), ^{ DKSearchInstallAvailableHooks(); });
}

NSDictionary *DKSearchCleanStatus(void) {
    NSArray *targets = @[
        @[ @"AWESearchMiddleNATabViewComponent", @"filerTabDataModel:", @YES ],
        @[ @"AWEVoiceSearchManager", @"shouldHiddenWithPagePositionType:", @NO ],
        @[ @"AWESearchRootStateContext", @"allowShowScanButton", @NO ],
        @[ @"AWESearchViewController", @"scanButton", @NO ],
        @[ @"AWESearchTopBarScanElement", @"scanButton", @NO ],
        @[ @"BDXLynxKitParams", @"globalProps", @NO ],
        @[ @"AWEBaseSettings", @"objectForKeyPath:defaultValue:stable:", @NO ],
        @[ @"AWESearchABTestServiceObjc", @"middlePageRankClose", @YES ],
        @[ @"LynxUI", @"setAccessibilityLabel:requestReset:", @NO ],
    ];
    Dl_info ownImage = {0};
    dladdr((void *)DKSearchCleanStatus, &ownImage);
    NSMutableArray *hooks = [NSMutableArray array];
    for (NSArray *target in targets) {
        Class cls = NSClassFromString(target[0]);
        SEL selector = NSSelectorFromString(target[1]);
        Method method = [target[2] boolValue] ? class_getClassMethod(cls, selector) : class_getInstanceMethod(cls, selector);
        Dl_info image = {0};
        if (method) dladdr((void *)method_getImplementation(method), &image);
        BOOL owned = ownImage.dli_fbase && image.dli_fbase == ownImage.dli_fbase;
        [hooks addObject:@{ @"class": target[0], @"selector": target[1], @"available": @(method != NULL),
                            @"owned": @(owned), @"image": image.dli_fname ? @(image.dli_fname) : @"" }];
    }
    return @{ @"hooks": hooks, @"remove_all_ranks": @(DKPrefBool(DKKeySearchRemoveAllRanks)) };
}

__attribute__((constructor))
static void DKSearchRuntimeStart(void) {
    DKSearchInstallAvailableHooks();
    _dyld_register_func_for_add_image(DKSearchImageAdded);
}
