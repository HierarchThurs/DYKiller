#import "DKFlexKingProviderSDK.h"
#import "DKMediaSaveDiagnostics.h"
#import "DKTabBarProbe.h"
#import "DKVideoFeedTable.h"
#import "DKVideoFullscreen.h"
#import <objc/runtime.h>
#import <dlfcn.h>

static NSString * const DKFlexKingProviderID = @"dykiller_debug";
static id DKFKProviderObject(NSString *className) {
    Class cls=NSClassFromString(className);return cls?[[cls alloc]init]:nil;
}
static NSDictionary *DKFKProviderSnapshot(void) {
    NSMutableDictionary *result=[@{@"product":@"DYKiller",@"version":DK_VERSION ?: @"unknown",@"build_identifier":@"control-version",@"probe_source":@"DKTabBarProbeReport",@"probe":DKTabBarProbeReport() ?: @"",@"video_table_stats":DKVideoFeedTableStats() ?: @"",@"video_container_pin_stats":DKVideoContainerPinStats() ?: @"",@"video_container_move_stats":DKVideoContainerMoveStats() ?: @"",@"fullscreen_enabled":@(DKVideoFullscreenOn()),@"media_save":DKMediaSaveDiagnostics() ?: @"",@"scope_limit":@"Current IMP plus existing counters/probe only. Historical IMP chain, original-vs-rewritten values, per-instance guard reasons, and hook calls not instrumented by DYKiller are explicitly unavailable in this Provider revision."} mutableCopy];
    Class detail=NSClassFromString(@"AWEAwemeDetailTableViewController");SEL selector=NSSelectorFromString(@"viewDidLayoutSubviews");Method method=detail?class_getInstanceMethod(detail,selector):NULL;
    if(method){IMP imp=method_getImplementation(method);Dl_info info={0};dladdr((void *)imp,&info);result[@"detail_layout_hook"]=@{@"class":NSStringFromClass(detail),@"selector":NSStringFromSelector(selector),@"current_imp":[NSString stringWithFormat:@"%p",imp],@"image_path":info.dli_fname?@(info.dli_fname):@"",@"symbol":info.dli_sname?@(info.dli_sname):@"",@"encoding":@(method_getTypeEncoding(method))};}
    else result[@"detail_layout_hook"]=@{@"state":@"method_unavailable"};
    return result;
}
static void DKRegisterFLEXKingDebugProvider(void) {
    typedef BOOL (*DKFKRegisterProviderFunction)(FLEXKingProvider *, NSError **);
    DKFKRegisterProviderFunction registerProvider =
        (DKFKRegisterProviderFunction)dlsym(RTLD_DEFAULT, "FLEXKingRegisterProvider");
    if (!registerProvider) return;
    id provider=DKFKProviderObject(@"FLEXKingProvider");id operation=DKFKProviderObject(@"FLEXKingProviderOperation");
    if(!provider||!operation)return;
    if (![provider respondsToSelector:NSSelectorFromString(@"setProductVersion:")]
        || ![provider respondsToSelector:NSSelectorFromString(@"setBuildIdentifier:")]
        || ![provider respondsToSelector:NSSelectorFromString(@"setLimits:")]
        || ![operation respondsToSelector:NSSelectorFromString(@"setLimits:")]) return;
    [provider setValue:@2 forKey:@"sdkVersion"];
    [provider setValue:DKFlexKingProviderID forKey:@"identifier"];
    [provider setValue:@"DYKiller Debug Evidence" forKey:@"title"];
    [provider setValue:DK_VERSION ?: @"unknown" forKey:@"productVersion"];
    [provider setValue:@"control-version" forKey:@"buildIdentifier"];
    [provider setValue:@{@"max_result_bytes":@262144,@"max_event_rate_per_second":@10} forKey:@"limits"];
    [operation setValue:@"snapshot" forKey:@"name"];
    [operation setValue:@"DYKiller 诊断快照" forKey:@"title"];
    [operation setValue:@"读取插件版本、布局 Hook 当前实现及现有专项探针" forKey:@"operationDescription"];
    [operation setValue:@{@"type":@"object",@"properties":@{},@"additionalProperties":@NO} forKey:@"parameters"];
    [operation setValue:@{@"type":@"object"} forKey:@"result"];
    [operation setValue:@{@"max_bytes":@262144} forKey:@"limits"];
    [operation setValue:@NO forKey:@"mutates"];
    [operation setValue:^id(NSDictionary *arguments,NSError **error){ return DKFKProviderSnapshot(); } forKey:@"handler"];
    [provider setValue:@[operation] forKey:@"operations"];
    NSError *error=nil;
    if(!registerProvider(provider,&error)) NSLog(@"DYKiller FLEXKing Provider registration failed: %@",error.localizedDescription ?: @"unknown");
}
__attribute__((constructor)) static void DKInstallFLEXKingDebugProvider(void) {
    dispatch_async(dispatch_get_main_queue(),^{DKRegisterFLEXKingDebugProvider();});
}
