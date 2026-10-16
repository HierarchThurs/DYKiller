//
//  DKElementRowHiding.xm
//  DYKiller
//
//  行显隐在 -setHidden: 汇聚点决定：实际写入「抖音请求值 || 应移除」，抖音请求值记在关联对象上，
//  不应移除时原样还原。隐藏行由 UIStackView 跳过，上下元素按抖音原生排布收拢。
//

#import "DKElementRowHiding.h"
#import "DouyinHeaders.h"
#import "DKInteractionAppearance.h"
#import "DKPlaybackClean.h"
#import <objc/runtime.h>

static char kDKRowHostHiddenKey;
static char kDKRowRemovedKey;

BOOL DKElementRowShouldRemove(UIView *row) {
    return DKPlaybackCleanRowRemoved(row) || DKInteractionRowRemoved(row);
}

void DKElementRowSync(UIView *row) {
    if (!row) return;
    BOOL removed = objc_getAssociatedObject(row, &kDKRowRemovedKey) != nil;
    BOOL remove = DKElementRowShouldRemove(row);
    if (!removed && !remove) return;

    NSNumber *host = objc_getAssociatedObject(row, &kDKRowHostHiddenKey);
    BOOL hostHidden = host ? host.boolValue : row.hidden;
    if (removed != remove || row.hidden != (hostHidden || remove)) [row setHidden:hostHidden];
}

%hook AWEBaseElementView

- (void)setHidden:(BOOL)hidden {
    BOOL remove = DKElementRowShouldRemove(self);
    objc_setAssociatedObject(self, &kDKRowHostHiddenKey, @(hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &kDKRowRemovedKey, remove ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(hidden || remove);
}

%end

%ctor {
    %init;
}
