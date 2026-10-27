// 搜索中间页：区块配置来源、整块榜单与语音入口。
#import "DKSearchClean.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import <objc/runtime.h>

@interface BDXLynxKitParams : NSObject
@property (nonatomic, copy) NSString *originURL;
@end

@interface AWEVoiceSearchManager : NSObject
- (BOOL)isVoiceSearchMiddlePagePosition:(long long)position;
- (BOOL)isVoiceSearchSugPagePosition:(long long)position;
@end

%group DKSearchRanks
%hook AWESearchMiddleNATabViewComponent
// 移除全部榜单时返回空模型，走原生零尺寸分支。
+ (id)filerTabDataModel:(id)viewModel {
    id model = %orig;
    return DKPrefBool(DKKeySearchRemoveAllRanks) ? nil : model;
}
%end
%end

%group DKSearchSources
// Lynx 卡片的 abParams 与 settings 最终都经此交给 LynxView。
%hook BDXLynxKitParams
- (NSDictionary *)globalProps {
    return DKSearchCleanGlobalProps(%orig, self.originURL);
}
%end

// 原生中间页的各类型取值方法都汇到这里读取区块配置。
%hook AWEBaseSettings
- (id)objectForKeyPath:(NSString *)keyPath defaultValue:(id)defaultValue stable:(BOOL)stable {
    id value = %orig;
    return [keyPath isEqualToString:DKSearchPageConfigKey] ? DKSearchCleanPageConfig(value) : value;
}
%end

%hook AWESearchABTestServiceObjc
+ (BOOL)middlePageRankClose {
    return DKPrefBool(DKKeySearchRemoveAllRanks) || %orig;
}
%end
%end

%group DKSearchVoice
%hook AWEVoiceSearchManager
- (BOOL)shouldHiddenWithPagePositionType:(long long)position {
    if (DKPrefBool(DKKeySearchRemoveVoice) &&
        ([self isVoiceSearchMiddlePagePosition:position] || [self isVoiceSearchSugPagePosition:position])) return YES;
    return %orig;
}
%end
%end

void DKSearchInstallNativeHooks(void) {
    static BOOL ranksInstalled, voiceInstalled;
    Class ranks = NSClassFromString(@"AWESearchMiddleNATabViewComponent");
    if (!ranksInstalled && class_getClassMethod(ranks, @selector(filerTabDataModel:))) {
        %init(DKSearchRanks);
        ranksInstalled = YES;
    }
    Class voice = NSClassFromString(@"AWEVoiceSearchManager");
    if (!voiceInstalled && class_getInstanceMethod(voice, @selector(shouldHiddenWithPagePositionType:)) &&
        class_getInstanceMethod(voice, @selector(isVoiceSearchMiddlePagePosition:)) &&
        class_getInstanceMethod(voice, @selector(isVoiceSearchSugPagePosition:))) {
        %init(DKSearchVoice);
        voiceInstalled = YES;
    }
}

%ctor {
    %init(DKSearchSources);
}
