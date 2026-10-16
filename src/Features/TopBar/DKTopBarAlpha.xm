//
//  DKTopBarAlpha.xm
//  功能：顶栏入口 —— 首页顶栏透明度，一处作用于左侧栏入口、全部频道与搜索图标。
//
//  实现：
//   - 三类元素同在 AWEFeedTopBarContainer 内，在容器上挂半透明 mask 整体淡出。
//   - 不写 alpha：槽位的 hitTest 在内容近乎透明时返回 nil；抖音打开评论区时对容器写 hidden，与 mask 互不干扰。
//     0% 时仍可点击。
//   - 评论区打开时右上角的搜索图标副本不在容器内，由 DKTopBarEntrance.xm 按 DKTopBarAlphaFactor 处理。
//

#import "DKTopBarAlpha.h"
#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"

static NSHashTable<UIView *> *gDKTopBars;

CGFloat DKTopBarAlphaFactor(void) {
    return DKPrefFraction(DKKeyTopBarAlpha, 100);
}

static void DKTopBarAlphaApply(UIView *container) {
    if (!gDKTopBars) gDKTopBars = [NSHashTable weakObjectsHashTable];
    [gDKTopBars addObject:container];
    // mask 外扩容器尺寸，覆盖越出容器的槽位内层与红点。
    DKAdjustFade(container, DKTopBarAlphaFactor(), container.bounds.size);
}

void DKTopBarAlphaRefresh(void) {
    for (UIView *container in gDKTopBars.allObjects) DKTopBarAlphaApply(container);
}

NSString *DKTopBarAlphaStatus(void) {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"顶栏透明度=%.0f%%  已见顶栏容器=%lu\n", DKTopBarAlphaFactor() * 100.0,
        (unsigned long)gDKTopBars.allObjects.count];
    for (UIView *container in gDKTopBars.allObjects) {
        [out appendFormat:@"  %@ frame=%@ hidden=%d alpha=%.2f 淡出=%.2f 在窗口=%@\n",
            NSStringFromClass(container.class), NSStringFromCGRect(container.frame), container.isHidden,
            container.alpha, DKAdjustFadeFactor(container), container.window ? @"是" : @"否"];
    }
    return out;
}

%hook AWEFeedTopBarContainer

- (void)layoutSubviews {
    %orig;
    DKTopBarAlphaApply(self);
}

- (void)didMoveToWindow {
    %orig;
    if (self.window) DKTopBarAlphaApply(self);
}

%end
