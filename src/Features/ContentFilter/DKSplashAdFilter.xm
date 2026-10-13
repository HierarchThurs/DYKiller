// 开屏广告解码与启动广告显示网关。
#import "DKContentFilter.h"
#import "DouyinHeaders.h"

static BOOL DKFilterSplashBlocked(id object, NSString *entry) {
    if (!DKFilterCurrentConfig().removeAds) return NO;
    DKFilterEntry(entry, object);
    DKFilterRecordAd(DKFilterAdPayload);
    return YES;
}

%group DKFilterSplashDictionary
%hook TTAdSplashModel
- (id)initWithDictionary:(id)raw {
    id result = %orig;
    return result && DKFilterSplashBlocked(result, @"开屏字典解码") ? nil : result;
}
%end
%end

%group DKFilterSplashCoder
%hook TTAdSplashModel
- (id)initWithCoder:(id)coder {
    id result = %orig;
    return result && DKFilterSplashBlocked(result, @"开屏缓存解码") ? nil : result;
}
%end
%end

%group DKFilterSplashShow
%hook AWEAwesomeSplashManager
- (BOOL)shouldShowAwesomeSplash {
    if (DKFilterSplashBlocked(self, @"启动广告显示")) return NO;
    return %orig;
}
%end
%end

%group DKFilterSplashCanShow
%hook AWEAwesomeSplashManager
- (BOOL)canShowSplashWithID:(id)identifier ttModel:(id)model {
    if (DKFilterSplashBlocked(self, @"启动广告显示条件")) return NO;
    return %orig;
}
%end
%end

%group DKFilterSplashOldAccessory
%hook AWEAwesomeSplashFeedCellOldAccessoryView
- (id)ddExtraView {
    if (DKFilterSplashBlocked(self, @"旧启动广告附件")) return nil;
    return %orig;
}
%end
%end

%ctor {
    Class cls = NSClassFromString(@"TTAdSplashModel");
    BOOL install = DKFilterMethod(cls, @selector(initWithDictionary:), "@", @[@"@"]);
    if (install) { %init(DKFilterSplashDictionary); }
    DKFilterRegisterHook(@"开屏字典解码", install, NO);
    install = DKFilterMethod(cls, @selector(initWithCoder:), "@", @[@"@"]);
    if (install) { %init(DKFilterSplashCoder); }
    DKFilterRegisterHook(@"开屏缓存解码", install, NO);
    cls = NSClassFromString(@"AWEAwesomeSplashManager");
    install = DKFilterMethod(cls, @selector(shouldShowAwesomeSplash), "B", @[]);
    if (install) { %init(DKFilterSplashShow); }
    DKFilterRegisterHook(@"启动广告显示", install, NO);
    install = DKFilterMethod(cls, @selector(canShowSplashWithID:ttModel:), "B", @[@"@", @"@"]);
    if (install) { %init(DKFilterSplashCanShow); }
    DKFilterRegisterHook(@"启动广告显示条件", install, NO);
    cls = NSClassFromString(@"AWEAwesomeSplashFeedCellOldAccessoryView");
    install = DKFilterMethod(cls, @selector(ddExtraView), "@", @[]);
    if (install) { %init(DKFilterSplashOldAccessory); }
    DKFilterRegisterHook(@"旧启动广告附件", install, YES);
}
