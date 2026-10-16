// 特殊卡客户端插入路径上的推荐热点卡闸门。
#import "DKContentFilter.h"

@interface AWESpecialCardDispatchController : NSObject
@end

%group DKHotspotInsertGate
%hook AWESpecialCardDispatchController
// 宿主按业务询问是否取消插入；首页推荐的热点卡返回 YES，其余交给宿主原判定。
- (BOOL)callShouldCancelInsertCardForBusinessID:(id)businessID withAweme:(id)aweme isFromFeed:(BOOL)fromFeed willInsertForRowAtIndexPath:(id)indexPath {
    DKFilterInsertDecision decision = DKFilterHotspotInsert(businessID, aweme, DKFilterCurrentConfig());
    if (DKFilterIsHotspotBusiness(businessID)) DKFilterEntry(@"热点插卡闸门", self);
    if (decision != DKFilterInsertKeep) DKFilterRecordInsert(decision);
    if (decision == DKFilterInsertCancel) return YES;
    return %orig;
}
%end
%end

%ctor {
    Class dispatcher = NSClassFromString(@"AWESpecialCardDispatchController");
    SEL gate = @selector(callShouldCancelInsertCardForBusinessID:withAweme:isFromFeed:willInsertForRowAtIndexPath:);
    BOOL install = DKFilterMethod(dispatcher, gate, "B", @[@"@", @"@", @"B", @"@"]);
    if (install) { %init(DKHotspotInsertGate); }
    DKFilterRegisterHook(@"热点插卡闸门", install, NO);
}
