#import "DKInteractionIcons.h"
#import "DKInteractionIconAssets.h"
#import "DKUtils.h"
#import "DouyinHeaders.h"
#import "DKSVGImage.h"
#import <objc/runtime.h>

@interface DKInteractionIconState : NSObject
@property (nonatomic, weak) UIImageView *view;
@property (nonatomic, strong) UIImage *nativeImage;
@property (nonatomic, strong) UIImage *replacement;
@property (nonatomic) NSUInteger depth;
@end
@implementation DKInteractionIconState
@end

static char kDKInteractionIconState;
static NSHashTable<AWEFeedVideoButton *> *gDKIconButtons;

static BOOL DKIconButtonInScope(AWEFeedVideoButton *button) {
    if (!DKPlayInteractionControllerForView(button)) return NO;
    Class stack = NSClassFromString(@"AWEElementStackView");
    for (UIView *parent = button.superview; parent; parent = parent.superview) {
        if ([parent isKindOfClass:stack]) return YES;
    }
    return NO;
}

static DKInteractionIconState *DKIconState(AWEFeedVideoButton *button, BOOL create) {
    DKInteractionIconState *state = objc_getAssociatedObject(button, &kDKInteractionIconState);
    if (!state && create) {
        state = [[DKInteractionIconState alloc] init];
        objc_setAssociatedObject(button, &kDKInteractionIconState, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!gDKIconButtons) gDKIconButtons = [NSHashTable weakObjectsHashTable];
        [gDKIconButtons addObject:button];
    }
    return state;
}

static void DKIconRestore(DKInteractionIconState *state) {
    if (state.replacement && state.view.image == state.replacement) state.view.image = state.nativeImage;
    state.replacement = nil;
}

static void DKIconApply(AWEFeedVideoButton *button) {
    if (!NSThread.isMainThread) return;
    DKInteractionIconSlot slot = DKInteractionIconSlotForName(button.imageNameString);
    BOOL inScope = slot != DKInteractionIconUnknown && DKIconButtonInScope(button);
    DKInteractionIconState *state = DKIconState(button, inScope);
    if (!state || state.depth) return;
    if (!inScope) { DKIconRestore(state); return; }
    UIImageView *view = button.buttonImageView;
    if (state.view != view) {
        DKIconRestore(state);
        state.view = view;
        state.nativeImage = view.image;
    } else if (!state.replacement || view.image != state.replacement) {
        state.nativeImage = view.image;
    }
    NSInteger style = DKPrefInteger(DKInteractionIconStyleKey(slot));
    CGFloat scale = button.window.screen.scale ?: UIScreen.mainScreen.scale;
    UIImage *image = DKInteractionIconImage(slot, style, view.bounds.size, scale, [button.imageNameString containsString:@"_4_light"]);
    if (!image) { DKIconRestore(state); return; }
    state.replacement = image;
    if (view.image != image) view.image = image;
}

// 原生 setter 的嵌套调用结束后统一应用；原生方法始终看到自己的最新图片。
static DKInteractionIconState *DKIconBeginWrite(AWEFeedVideoButton *button) {
    if (!NSThread.isMainThread) return nil;
    DKInteractionIconState *state = DKIconState(button, DKIconButtonInScope(button));
    if (state && state.depth++ == 0) DKIconRestore(state);
    return state;
}

static void DKIconEndWrite(AWEFeedVideoButton *button, DKInteractionIconState *state) {
    if (state && state.depth) state.depth--;
    DKIconApply(button);
}

void DKInteractionIconsRefresh(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DKInteractionIconsRefresh(); }); return; }
    DKInteractionIconAssetsReload();
    for (AWEFeedVideoButton *button in gDKIconButtons.allObjects) DKIconApply(button);
}

NSDictionary *DKInteractionIconsStatus(void) {
    NSMutableArray *assets = [NSMutableArray array];
    for (NSInteger slot = 0; slot < DKInteractionIconSlotCount; slot++) {
        [assets addObject:@{ @"slot": DKInteractionIconTitle((DKInteractionIconSlot)slot),
            @"style": @(DKPrefInteger(DKInteractionIconStyleKey((DKInteractionIconSlot)slot))),
            @"asset": DKInteractionIconDataDetail(DKInteractionIconData((DKInteractionIconSlot)slot)) }];
    }
    NSMutableArray *buttons = [NSMutableArray array];
    for (AWEFeedVideoButton *button in gDKIconButtons.allObjects) {
        if (!button.window) continue;
        DKInteractionIconState *state = DKIconState(button, NO);
        DKInteractionIconSlot slot = DKInteractionIconSlotForName(button.imageNameString);
        BOOL inScope = slot != DKInteractionIconUnknown && DKIconButtonInScope(button);
        NSInteger style = slot != DKInteractionIconUnknown ? DKPrefInteger(DKInteractionIconStyleKey(slot)) : 0;
        UIImageView *view = button.buttonImageView;
        // 以视图上的实际图片为准：缓存的替换图被宿主覆写后不再算已替换。
        BOOL applied = state.replacement != nil && view.image == state.replacement;
        CGSize size = view.bounds.size;
        NSString *fallback = applied ? @"" : !inScope ? @"outside_scope" : style == 0 ? @"default"
            : size.width <= 0 || size.height <= 0 ? @"image_view_unsized"
            : style == 3 ? @"custom_asset_missing_or_unrenderable" : @"render_unavailable";
        [buttons addObject:@{ @"name": button.imageNameString ?: @"", @"replaced": @(applied),
            @"in_scope": @(inScope), @"fallback": fallback, @"view_size": NSStringFromCGSize(size) }];
    }
    return @{ @"assets": assets, @"buttons": buttons, @"svg_renderer_available": @(DKSVGImageAvailable()) };
}

%hook AWEFeedVideoButton
- (void)didMoveToWindow { %orig; DKIconApply(self); }
- (void)layoutSubviews { %orig; DKIconApply(self); }
- (void)setImage:(UIImage *)image {
    DKInteractionIconState *state = DKIconBeginWrite(self);
    %orig;
    DKIconEndWrite(self, state);
}
- (void)setImageNameString:(NSString *)name {
    DKInteractionIconState *state = DKIconBeginWrite(self);
    %orig;
    DKIconEndWrite(self, state);
}
%end

// 图片视图的尺寸在容器布局时才排出；新建按钮写图与按钮布局时它还没有尺寸，容器布局后再应用一次。
%hook AWEFeedVideoButtonContainerView
- (void)layoutSubviews {
    %orig;
    UIView *button = self.superview;
    if ([button isKindOfClass:%c(AWEFeedVideoButton)]) DKIconApply((AWEFeedVideoButton *)button);
}
%end
