// 搜索中间页：原生榜单过滤、Lynx 显示配置与搜索入口显隐。
#import "DKSearchClean.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import <objc/runtime.h>

@interface AWESearchMiddleNASingleTabModel : NSObject
@property (nonatomic, copy) NSString *tabId;
@property (nonatomic, copy) NSString *tabName;
@end

@interface AWESearchMiddleNATabDataModel : NSObject <NSCopying>
@property (nonatomic, copy) NSArray<AWESearchMiddleNASingleTabModel *> *tabs;
@property (nonatomic, copy) NSString *landingTab;
@end

@interface BDXLynxKitParams : NSObject
@property (nonatomic, copy) NSString *originURL;
@end

@interface AWEVoiceSearchManager : NSObject
- (BOOL)isVoiceSearchMiddlePagePosition:(long long)position;
- (BOOL)isVoiceSearchSugPagePosition:(long long)position;
@end

%group DKSearchRanks
%hook AWESearchMiddleNATabViewComponent
+ (id)filerTabDataModel:(id)viewModel {
    AWESearchMiddleNATabDataModel *model = %orig;
    NSArray *tabs = model.tabs;
    if (![tabs isKindOfClass:NSArray.class]) return model;
    NSMutableArray *entries = [NSMutableArray arrayWithCapacity:tabs.count];
    for (AWESearchMiddleNASingleTabModel *tab in tabs) {
        if (tab.tabId.length) [entries addObject:@{ @"id": tab.tabId, @"title": tab.tabName ?: tab.tabId }];
    }
    DKSearchRecordRanks(entries);
    NSArray *visible = DKSearchVisibleRanks(tabs, ^NSString *(AWESearchMiddleNASingleTabModel *tab) {
        return tab.tabId;
    });
    if (visible == tabs) return model;
    // 空模型走原生零尺寸分支；非空副本同时校正落地页标识。
    if (!visible.count) return nil;
    AWESearchMiddleNATabDataModel *copy = [model copy];
    copy.tabs = visible;
    BOOL hasLanding = NO;
    for (AWESearchMiddleNASingleTabModel *tab in visible) {
        if ([tab.tabId isEqualToString:copy.landingTab]) hasLanding = YES;
    }
    if (!hasLanding) copy.landingTab = ((AWESearchMiddleNASingleTabModel *)visible.firstObject).tabId;
    return copy;
}
%end
%end

%group DKSearchLynxProps
%hook BDXLynxKitParams
- (NSDictionary *)globalProps {
    NSDictionary *props = %orig;
    return DKSearchCleanGlobalProps(props, self.originURL);
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
    %init(DKSearchLynxProps);
}