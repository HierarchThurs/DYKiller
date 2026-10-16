// 推荐网络转换与冷启动缓存的批次入口。
#import "DKContentFilter.h"
#import "DouyinHeaders.h"

static BOOL DKFilterBatchEnabled(DKFilterConfig config) {
    return config.lowLikes || config.removeLive || config.removeAds || config.removeMusic || config.removeHotspot;
}

static id DKFilterTransfer(id controller, id array, NSString *entry, id (^native)(id)) {
    return DKFilterWithBatch(^id {
        if (!DKFilterBatchEnabled(DKFilterCurrentConfig())) return native(array);
        DKFilterEntry(entry, controller);
        id input = DKFilterArray(array, controller, DKFilterStageLive);
        id result = native(input);
        return DKFilterArray(result, controller, DKFilterStageAds | DKFilterStageMusic | DKFilterStageHotspot | DKFilterStageLikes);
    });
}

%group DKFilterHotTransfer
%hook AWEHotListDataController
- (id)transferAwemeListIfNeededWithArray:(id)array isInitFetch:(BOOL)initial {
    return DKFilterTransfer(self, array, @"HotList 转换", ^id(id input) {
        return %orig(input, initial);
    });
}
%end
%end

%group DKFilterMultiTransfer
%hook AWEFeedMultiQueueDataController
- (id)transferAwemeListIfNeededWithArray:(id)array isInitFetch:(BOOL)initial {
    return DKFilterTransfer(self, array, @"多队列转换", ^id(id input) {
        return %orig(input, initial);
    });
}
%end
%end

%group DKFilterDefaultTransfer
%hook AWEDCFeedDefaultDataController
- (id)transferAwemeListIfNeededWithArray:(id)array isInitFetch:(BOOL)initial {
    return DKFilterTransfer(self, array, @"默认数据队列转换", ^id(id input) {
        return %orig(input, initial);
    });
}
%end
%end

%group DKFilterHotCache
%hook AWEHotListDataController
- (void)p_handleFeedCacheList:(id)array completion:(id)completion {
    DKFilterWithBatch(^id {
        id input = array;
        if (DKFilterBatchEnabled(DKFilterCurrentConfig())) {
            DKFilterEntry(@"HotList 缓存", self);
            input = DKFilterArray(array, self, DKFilterStageAll);
        }
        %orig(input, completion);
        return nil;
    });
}
%end
%end

%ctor {
    Class base = NSClassFromString(@"AWEListDataController");
    SEL transfer = @selector(transferAwemeListIfNeededWithArray:isInitFetch:);
    Class hot = NSClassFromString(@"AWEHotListDataController");
    BOOL install = base && [hot isSubclassOfClass:base] && DKFilterOwnMethod(hot, transfer)
        && DKFilterMethod(hot, transfer, "@", @[@"@", @"B"]);
    if (install) { %init(DKFilterHotTransfer); }
    DKFilterRegisterHook(@"HotList 转换", install, NO);
    Class multi = NSClassFromString(@"AWEFeedMultiQueueDataController");
    install = base && [multi isSubclassOfClass:base] && DKFilterOwnMethod(multi, transfer)
        && DKFilterMethod(multi, transfer, "@", @[@"@", @"B"]);
    if (install) { %init(DKFilterMultiTransfer); }
    DKFilterRegisterHook(@"多队列转换", install, NO);
    Class defaults = NSClassFromString(@"AWEDCFeedDefaultDataController");
    install = base && [defaults isSubclassOfClass:base] && DKFilterOwnMethod(defaults, transfer)
        && DKFilterMethod(defaults, transfer, "@", @[@"@", @"B"]);
    if (install) { %init(DKFilterDefaultTransfer); }
    DKFilterRegisterHook(@"默认数据队列转换", install, NO);
    install = base && [hot isSubclassOfClass:base]
        && DKFilterMethod(hot, @selector(p_handleFeedCacheList:completion:), "v", @[@"@", @"@?"]);
    if (install) { %init(DKFilterHotCache); }
    DKFilterRegisterHook(@"HotList 缓存", install, NO);
}
