// 榜单末尾的完整榜单入口：限定搜索榜单模板，同时阻断 Lynx 命中。
#import "DKSearchClean.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import <objc/runtime.h>

@interface DKSearchLynxView : UIView
@property (nonatomic, readonly) NSString *url;
@end

@interface DKSearchLynxContext : NSObject
@property (nonatomic, readonly) DKSearchLynxView *rootView;
@end

@interface LynxUI : NSObject
@property (nonatomic, readonly) UIView *view;
@property (nonatomic, readonly) DKSearchLynxContext *context;
@end

static char kDKSearchFooterTarget;
static char kDKSearchFooterOriginalHidden;

static BOOL DKSearchRemoveFooter(void) {
    return DKPrefBool(DKKeySearchRemoveAllRanks) || DKPrefBool(DKKeySearchRemoveRankFooter);
}

static void DKSearchApplyFooter(LynxUI *ui) {
    UIView *view = ui.view;
    BOOL remove = [objc_getAssociatedObject(ui, &kDKSearchFooterTarget) boolValue] &&
                  DKSearchRemoveFooter();
    NSNumber *original = objc_getAssociatedObject(view, &kDKSearchFooterOriginalHidden);
    if (remove) {
        if (!original) objc_setAssociatedObject(view, &kDKSearchFooterOriginalHidden, @(view.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        view.hidden = YES;
    } else if (original) {
        if (view.hidden) view.hidden = original.boolValue;
        objc_setAssociatedObject(view, &kDKSearchFooterOriginalHidden, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%hook LynxUI
- (void)setAccessibilityLabel:(NSString *)label requestReset:(BOOL)reset {
    %orig;
    BOOL target = [label isKindOfClass:NSString.class] && [label hasPrefix:@"查看完整"] &&
                  DKSearchTemplateMatches(self.context.rootView.url, @"search_transfer_rank");
    objc_setAssociatedObject(self, &kDKSearchFooterTarget, target ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (target || objc_getAssociatedObject(self.view, &kDKSearchFooterOriginalHidden)) DKSearchApplyFooter(self);
}
- (void)propsDidUpdate {
    %orig;
    if (objc_getAssociatedObject(self, &kDKSearchFooterTarget)) DKSearchApplyFooter(self);
}
- (BOOL)shouldHitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (objc_getAssociatedObject(self, &kDKSearchFooterTarget) && DKSearchRemoveFooter()) return NO;
    return %orig;
}
%end
