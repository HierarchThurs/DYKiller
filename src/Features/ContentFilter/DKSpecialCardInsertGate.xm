// 首页推荐特殊卡的客户端插入闸门，按类别开关及总开关判定。
#import "DKContentFilter.h"

@interface AWESpecialCardDispatchController : NSObject
@end

%group DKSpecialCardInsertGate
%hook AWESpecialCardDispatchController
// 宿主按业务询问是否取消插入；开关覆盖且确认为首页推荐时返回 YES，其余交给宿主原判定。
- (BOOL)callShouldCancelInsertCardForBusinessID:(id)businessID withAweme:(id)aweme isFromFeed:(BOOL)fromFeed willInsertForRowAtIndexPath:(id)indexPath {
    DKFilterConfig config = DKFilterCurrentConfig();
    if (!config.removeCards) return %orig;
    DKFilterEntry(@"特殊卡插卡闸门", self);
    DKFilterInsertDecision decision = DKFilterSpecialCardInsert(businessID, aweme, config);
    if (decision != DKFilterInsertKeep) DKFilterRecordInsert(decision, DKFilterCardKindForBusiness(businessID));
    if (decision == DKFilterInsertCancel) return YES;
    return %orig;
}
%end
%end

%ctor {
    Class dispatcher = NSClassFromString(@"AWESpecialCardDispatchController");
    SEL gate = @selector(callShouldCancelInsertCardForBusinessID:withAweme:isFromFeed:willInsertForRowAtIndexPath:);
    BOOL install = DKFilterMethod(dispatcher, gate, "B", @[@"@", @"@", @"B", @"@"]);
    if (install) { %init(DKSpecialCardInsertGate); }
    DKFilterRegisterHook(@"特殊卡插卡闸门", install, NO);
}
