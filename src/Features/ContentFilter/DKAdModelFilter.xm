// 作品和搜索模型构建后阻断明确广告；原生错误参数保持透传。
#import "DKContentFilter.h"
#import "DouyinHeaders.h"

static BOOL DKFilterRejectModel(id result, id raw, NSString *entry, BOOL dedicated) {
    if (!result || !DKFilterCurrentConfig().removeAds) return NO;
    DKFilterEntry(entry, result);
    DKFilterAdReason reason = DKFilterAdModel(result) | DKFilterAdRaw(raw);
    if (dedicated && [raw isKindOfClass:NSDictionary.class] && [raw count]) reason |= DKFilterAdPayload;
    if (!reason) return NO;
    DKFilterRecordAd(reason);
    return YES;
}

%group DKFilterAwemeModel
%hook AWEAwemeModel
- (id)initWithDictionary:(id)raw error:(NSError **)error {
    id result = %orig;
    return DKFilterRejectModel(result, raw, @"广告作品构建", NO) ? nil : result;
}
%end
%end

%group DKFilterSearchModel
%hook AWEGeneralSearchModel
- (id)initWithDictionary:(id)raw error:(NSError **)error {
    id result = %orig;
    return DKFilterRejectModel(result, raw, @"搜索广告卡构建", NO) ? nil : result;
}
%end
%end

%group DKFilterOriginalAd
%hook AWEOriginalAdModel
- (id)initWithDictionary:(id)raw error:(NSError **)error {
    id result = %orig;
    return DKFilterRejectModel(result, raw, @"广告专用载荷", YES) ? nil : result;
}
%end
%end

%ctor {
    SEL selector = @selector(initWithDictionary:error:);
    Class cls = NSClassFromString(@"AWEAwemeModel");
    BOOL install = DKFilterMethod(cls, selector, "@", @[@"@", @"^@"]);
    if (install) { %init(DKFilterAwemeModel); }
    DKFilterRegisterHook(@"广告作品构建", install, NO);
    cls = NSClassFromString(@"AWEGeneralSearchModel");
    install = DKFilterMethod(cls, selector, "@", @[@"@", @"^@"]);
    if (install) { %init(DKFilterSearchModel); }
    DKFilterRegisterHook(@"搜索广告卡构建", install, NO);
    cls = NSClassFromString(@"AWEOriginalAdModel");
    install = DKFilterMethod(cls, selector, "@", @[@"@", @"^@"]);
    if (install) { %init(DKFilterOriginalAd); }
    DKFilterRegisterHook(@"广告专用载荷", install, NO);
}
