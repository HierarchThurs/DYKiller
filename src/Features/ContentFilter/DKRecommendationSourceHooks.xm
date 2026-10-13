// 页面配置后同步语义来源，不访问视图或改变数据控制器。
#import "DKContentFilter.h"
#import "DouyinHeaders.h"

static void DKFilterSyncFeedSource(AWEFeedTableViewController *owner, NSString *entry) {
    if (!NSThread.isMainThread) {
        __weak AWEFeedTableViewController *weakOwner = owner;
        dispatch_async(dispatch_get_main_queue(), ^{ if (weakOwner) DKFilterSyncFeedSource(weakOwner, entry); });
        return;
    }
    id data = DKFilterObject(owner, @selector(dataController));
    id source = DKFilterObject(owner, @selector(referString));
    if (![source isKindOfClass:NSString.class] || ![source length]) {
        source = DKFilterObject(owner, @selector(currentReferString));
    }
    DKFilterBindSource(owner, data, source);
    DKFilterEntry(entry, owner);
}

%group DKFilterFeedInit
%hook AWEFeedTableViewController
- (id)initWithType:(long long)type dataController:(id)data {
    id result = %orig;
    if (result) DKFilterSyncFeedSource(result, @"来源:初始化");
    return result;
}
%end
%end

%group DKFilterFeedData
%hook AWEFeedTableViewController
- (void)setDataController:(id)data {
    %orig;
    DKFilterSyncFeedSource(self, @"来源:数据控制器绑定");
}
%end
%end

%group DKFilterFeedRefer
%hook AWEFeedTableViewController
- (void)setReferString:(id)source {
    %orig;
    DKFilterSyncFeedSource(self, @"来源:语义来源绑定");
}
%end
%end

%group DKFilterFeedSetup
%hook AWEFeedTableViewController
- (void)setupFeedContainerWithType:(long long)type dataController:(id)data {
    %orig;
    DKFilterSyncFeedSource(self, @"来源:容器配置");
}
%end
%end

%ctor {
    Class cls = NSClassFromString(@"AWEFeedTableViewController");
    BOOL controller = [cls isSubclassOfClass:UIViewController.class];
    BOOL install = controller && DKFilterMethod(cls, @selector(initWithType:dataController:), "@", @[@"q", @"@"]);
    if (install) { %init(DKFilterFeedInit); }
    DKFilterRegisterHook(@"来源:初始化", install, NO);
    install = controller && DKFilterMethod(cls, @selector(setDataController:), "v", @[@"@"]);
    if (install) { %init(DKFilterFeedData); }
    DKFilterRegisterHook(@"来源:数据控制器绑定", install, NO);
    install = controller && DKFilterMethod(cls, @selector(setReferString:), "v", @[@"@"]);
    if (install) { %init(DKFilterFeedRefer); }
    DKFilterRegisterHook(@"来源:语义来源绑定", install, NO);
    install = controller && DKFilterMethod(cls, @selector(setupFeedContainerWithType:dataController:), "v", @[@"q", @"@"]);
    if (install) { %init(DKFilterFeedSetup); }
    DKFilterRegisterHook(@"来源:容器配置", install, NO);
}
