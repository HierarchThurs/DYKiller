// 广告过滤在列表写入前创建新数组，保留宿主持有的原数组。
#import "DKContentFilter.h"
#import "DouyinHeaders.h"

static id DKFilterAdList(id controller, id array, NSString *entry) {
    if (!DKFilterCurrentConfig().removeAds || DKFilterIsClass(controller, @"AWEUserPostsDataManager")) return array;
    DKFilterEntry(entry, controller);
    return DKFilterArray(array, controller, DKFilterStageAds);
}

%group DKFilterAdDataSource
%hook AWEListDataController
- (void)setDataSource:(id)array {
    DKFilterWithBatch(^id {
        %orig(DKFilterAdList(self, array, @"广告列表写入"));
        return nil;
    });
}
%end
%end

%group DKFilterAdFilteredSource
%hook AWEListDataController
- (void)setFilteredDataSource:(id)array {
    DKFilterWithBatch(^id {
        %orig(DKFilterAdList(self, array, @"广告已筛列表写入"));
        return nil;
    });
}
%end
%end

%group DKFilterAdMixList
%hook AWEMixVideoListDataController
- (void)setDataSource:(id)array {
    DKFilterWithBatch(^id {
        %orig(DKFilterAdList(self, array, @"合集广告列表"));
        return nil;
    });
}
%end
%end

%group DKFilterAdMixDetail
%hook AWEMixVideoDetailPlayListDataController
- (void)setDataSource:(id)array {
    DKFilterWithBatch(^id {
        %orig(DKFilterAdList(self, array, @"合集详情广告列表"));
        return nil;
    });
}
%end
%end

%group DKFilterAdMixRelated
%hook AWEMixVideoRelatedListDataController
- (void)setDataSource:(id)array {
    DKFilterWithBatch(^id {
        %orig(DKFilterAdList(self, array, @"关联合集广告列表"));
        return nil;
    });
}
%end
%end

%ctor {
    Class base = NSClassFromString(@"AWEListDataController");
    SEL selector = @selector(setDataSource:);
    BOOL install = DKFilterMethod(base, selector, "v", @[@"@"]);
    if (install) { %init(DKFilterAdDataSource); }
    DKFilterRegisterHook(@"广告列表写入", install, NO);
    install = DKFilterMethod(base, @selector(setFilteredDataSource:), "v", @[@"@"]);
    if (install) { %init(DKFilterAdFilteredSource); }
    DKFilterRegisterHook(@"广告已筛列表写入", install, NO);
    Class cls = NSClassFromString(@"AWEMixVideoListDataController");
    install = base && [cls isSubclassOfClass:base] && DKFilterOwnMethod(cls, selector)
        && DKFilterMethod(cls, selector, "v", @[@"@"]);
    if (install) { %init(DKFilterAdMixList); }
    DKFilterRegisterHook(@"合集广告列表", install, NO);
    cls = NSClassFromString(@"AWEMixVideoDetailPlayListDataController");
    install = base && [cls isSubclassOfClass:base] && DKFilterOwnMethod(cls, selector)
        && DKFilterMethod(cls, selector, "v", @[@"@"]);
    if (install) { %init(DKFilterAdMixDetail); }
    DKFilterRegisterHook(@"合集详情广告列表", install, NO);
    cls = NSClassFromString(@"AWEMixVideoRelatedListDataController");
    install = base && [cls isSubclassOfClass:base] && DKFilterOwnMethod(cls, selector)
        && DKFilterMethod(cls, selector, "v", @[@"@"]);
    if (install) { %init(DKFilterAdMixRelated); }
    DKFilterRegisterHook(@"关联合集广告列表", install, NO);
}
