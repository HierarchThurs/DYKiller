// 通过原生底部容器归属定位栏目，叠加 transform，命中区域随栏目移动。
#import "DKRelatedBarOffset.h"
#import "DKProgressOffset.h"
#import "DKPlaybackOverlay.h"
#import "DKAdjustRange.h"
#import "DKViewAdjust.h"
#import "DKSettings.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import "DouyinHeaders.h"
#import <objc/runtime.h>

static NSHashTable<UIView *> *gDKRelatedBarStacks;
static char kDKRelatedBarOffsetOwnedKey;

void DKRelatedBarOffsetApplyStack(UIView *stack) {
    AWEPlayInteractionViewController *controller = (id)DKPlayInteractionControllerForView(stack);
    BOOL target = controller && controller.bottomContainerView == stack && !DKPlaybackOverlayIsPureControl(stack);
    BOOL owned = objc_getAssociatedObject(stack, &kDKRelatedBarOffsetOwnedKey) != nil;
    if (!target) {
        if (owned) {
            DKAdjustTransform(stack, CGAffineTransformIdentity);
            objc_setAssociatedObject(stack, &kDKRelatedBarOffsetOwnedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    if (!gDKRelatedBarStacks) gDKRelatedBarStacks = [NSHashTable weakObjectsHashTable];
    [gDKRelatedBarStacks addObject:stack];
    CGFloat offset = DKAdjustValue(DKKeyRelatedBarOffset);
    if (offset == 0 && !owned) return;
    DKAdjustTransform(stack, CGAffineTransformMakeTranslation(0, -offset));
    objc_setAssociatedObject(stack, &kDKRelatedBarOffsetOwnedKey, offset != 0 ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DKRelatedBarOffsetRefresh(void) {
    for (UIView *stack in gDKRelatedBarStacks.allObjects) DKRelatedBarOffsetApplyStack(stack);
}

NSString *DKRelatedBarOffsetStatus(void) {
    NSMutableString *text = [NSMutableString stringWithFormat:@"底部相关栏目上移=%ldpt 已见容器=%lu\n",
        (long)DKAdjustValue(DKKeyRelatedBarOffset), (unsigned long)gDKRelatedBarStacks.allObjects.count];
    for (UIView *stack in gDKRelatedBarStacks.allObjects) {
        if (stack.window) [text appendFormat:@"  底部栏目 frame=%@ ty=%.1f\n",
            NSStringFromCGRect([stack convertRect:stack.bounds toView:nil]), stack.transform.ty];
    }
    return text;
}

%ctor {
    DKSettingsRegister(DKKeyRelatedBarOffset, ^{
        AWESettingItemModel *item = DKMakeAdjustSliderWithNote(DKKeyRelatedBarOffset, @"底部相关栏目上移",
            @"上移：0 pt 为抖音原位。", ^NSString *(NSInteger value) { return DKRelatedBarOffsetNote(value); },
            ^(__unused NSInteger value) { DKRelatedBarOffsetRefresh(); });
        return DKSettingsWithInfo(item,
            @"整体上移底部相关栏目，点击区域随之移动；昵称文案、互动区、进度条与图片指示器保持各自位置。");
    });
}
