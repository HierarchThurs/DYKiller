//
//  DKChatInputPendant.xm
//  DYKiller
//
//  小火人挂件（AWEIMStreakPendantView 里的 Lynx 容器）吸附输入区时，原生把它放在输入区左上角、
//  底边贴住原生白色输入底板的上沿。悬浮玻璃下底板透明，改为水平居中到输入行中线，落在输入胶囊上。
//  接管点是容器自己的 frame / center 写入：只改横向，纵向、尺寸与动画都沿用原生。
//  吸附期间横向位置由这里决定，拖动挂件只保留纵向。
//

#import "DKChatInputPendant.h"
#import "DKChatInput.h"
#import "DKGlassGuard.h"
#import "DouyinHeaders.h"
#import <math.h>
#import <objc/runtime.h>

static char kDKChatPendantNativeFrameKey;   // 容器上记原生最近一次写入的 frame
static NSHashTable<UIView *> *gDKChatPendantContainers;

// 输入行中线（挂件坐标系）；挂件未吸附输入区或功能不生效时返回 NAN。
static CGFloat DKChatPendantCenterX(AWEIMStreakPendantView *pendant) {
    if (!pendant.isInputAttached) return NAN;
    UIViewController *input = DKChatInputControllerForPageView(pendant);
    UIView *plate = DKChatInputObjectIvar(DKChatInputLayoutForController(input), "_textViewBackgroundView");
    if (!DKChatInputGlassWanted(input) || !plate.window || CGRectIsEmpty(plate.bounds)) return NAN;
    return CGRectGetMidX([plate convertRect:plate.bounds toView:pendant]);
}

// 只处理挂在小火人挂件上的容器：记下原生写入的 frame，吸附时把横向换成输入行中线。
static CGRect DKChatPendantFrame(UIView *container, CGRect native) {
    AWEIMStreakPendantView *pendant = (id)container.superview;
    if (!DKChatInputIsKind(pendant, @"AWEIMStreakPendantView")) return native;
    objc_setAssociatedObject(container, &kDKChatPendantNativeFrameKey, [NSValue valueWithCGRect:native],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gDKChatPendantContainers addObject:container];
    CGFloat centerX = DKChatPendantCenterX(pendant);
    if (isnan(centerX)) return native;
    native.origin.x = centerX - CGRectGetWidth(native) * 0.5;
    return native;
}

void DKChatInputPendantRefresh(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKChatInputPendantRefresh(); });
        return;
    }
    for (UIView *container in gDKChatPendantContainers.allObjects) {
        NSValue *native = objc_getAssociatedObject(container, &kDKChatPendantNativeFrameKey);
        if (native) container.frame = native.CGRectValue;
    }
}

%group DKChatInputPendantContainerHooks
// 小火人的 Lynx 容器是抖音的 Swift 类（类名带点），实际类在首次吸附时按实例取。
%hook DKChatPendantContainer
- (void)setFrame:(CGRect)frame {
    %orig(DKChatPendantFrame(self, frame));
}
- (void)setCenter:(CGPoint)center {
    UIView *container = self;
    CGSize size = container.bounds.size;
    CGRect frame = DKChatPendantFrame(container, CGRectMake(center.x - size.width * 0.5, center.y - size.height * 0.5,
                                                           size.width, size.height));
    %orig(CGPointMake(CGRectGetMidX(frame), center.y));
}
%end
%end

static void DKChatPendantInstall(UIView *container) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        %init(DKChatInputPendantContainerHooks, DKChatPendantContainer = [container class]);
    });
}

%group DKChatInputPendantHooks
// 吸附状态切换后原生会重排容器；这里先装好容器的写入 Hook，再按当前状态补写一次。
%hook AWEIMStreakPendantView
- (void)updateInputAttachedState:(BOOL)attached {
    %orig;
    UIView *container = DKChatInputObjectIvar(self, "_containerView");
    if (!container || container.superview != self) return;
    DKChatPendantInstall(container);
    NSValue *native = objc_getAssociatedObject(container, &kDKChatPendantNativeFrameKey);
    container.frame = native ? native.CGRectValue : container.frame;
}
%end
%end

%ctor {
    gDKChatPendantContainers = [NSHashTable weakObjectsHashTable];
    if (DKGlassOSAvailable()) {
        %init(DKChatInputPendantHooks);
    }
}
