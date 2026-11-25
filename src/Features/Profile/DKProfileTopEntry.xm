#import "DouyinHeaders.h"
#import "DKProfileSettingsEntry.h"

#import <objc/runtime.h>

@interface AWEProfileNavigationBaseComponent (DKProfileTopEntry)
- (UIView *)navigationContainerView;
- (NSArray<UIView *> *)currentLeftShowViews;
- (NSArray<UIView *> *)currentRightShowViews;
@end

@interface DKProfileTopEntryButton : UIButton
@property (nonatomic, strong) UIView *disc;
@property (nonatomic, strong) UIImageView *lightGear;
@property (nonatomic, strong) UIImageView *darkGear;
@end

@implementation DKProfileTopEntryButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _disc = [UIView new];
    _disc.userInteractionEnabled = NO;
    [self addSubview:_disc];
    _lightGear = [UIImageView new];
    _lightGear.contentMode = UIViewContentModeScaleAspectFit;
    _lightGear.tintColor = UIColor.whiteColor;
    [self addSubview:_lightGear];
    _darkGear = [UIImageView new];
    _darkGear.contentMode = UIViewContentModeScaleAspectFit;
    _darkGear.tintColor = [UIColor colorWithRed:22.0/255.0 green:24.0/255.0 blue:35.0/255.0 alpha:1.0];
    [self addSubview:_darkGear];
    DKProfileEntryConfigureButton(self);
    return self;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return [super pointInside:point withEvent:event] || CGRectContainsPoint(self.disc.frame, point);
}
@end

static char kDKProfileTopEntryButtonKey;
static NSMapTable<UIView *, AWEProfileNavigationBaseComponent *> *gDKProfileTopEntryComponents;
static const CGFloat kDKProfileTopEntryGap = 12.0;

static BOOL DKProfileTopEntryIsMine(AWEProfileNavigationBaseComponent *component) {
    AWEProfileContext *context = [component respondsToSelector:@selector(profileContext)] ? component.profileContext : nil;
    return [context respondsToSelector:@selector(isCurrentUser)] && [context isCurrentUser];
}

static BOOL DKProfileTopEntryIsVisible(UIView *view, UIView *container) {
    return [view isKindOfClass:UIView.class] && view.superview == container
        && !view.hidden && view.alpha > 0.01 && !CGRectIsEmpty(view.bounds);
}

static void DKProfileTopEntryRemove(UIView *container) {
    DKProfileTopEntryButton *button = objc_getAssociatedObject(container, &kDKProfileTopEntryButtonKey);
    if (!button) return;
    [button removeFromSuperview];
    objc_setAssociatedObject(container, &kDKProfileTopEntryButtonKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static NSArray<UIImageView *> *DKProfileTopEntryMenuIcons(UIView *entrance) {
    NSMutableArray<UIImageView *> *icons = [NSMutableArray arrayWithCapacity:2];
    for (UIView *view in entrance.subviews) {
        if ([view isKindOfClass:UIImageView.class] && !CGRectIsEmpty(view.bounds)
            && CGRectGetWidth(view.bounds) < CGRectGetWidth(entrance.bounds)) [icons addObject:(UIImageView *)view];
    }
    return icons;
}

static void DKProfileTopEntryMirrorIcon(UIImageView *gear, UIImageView *source, UIView *menu) {
    CGRect frame = [source convertRect:source.bounds toView:menu];
    gear.image = DKProfileEntryGearImage(source.bounds.size);
    gear.frame = frame;
    gear.hidden = source.hidden || source.superview.hidden;
    gear.alpha = source.alpha * source.superview.alpha;
}

static BOOL DKProfileTopEntryPlace(UIView *container, AWEProfileNavigationBaseComponent *component) {
    Class entranceClass = objc_getClass("AWELeftSideBarEntranceView");
    UIView *menu = nil;
    UIView *entrance = nil;
    CGFloat rightEdge = CGRectGetMaxX(container.bounds);
    for (UIView *view in component.currentRightShowViews) {
        if (!DKProfileTopEntryIsVisible(view, container)) continue;
        rightEdge = MIN(rightEdge, CGRectGetMinX(view.frame));
        if (![view isKindOfClass:UIButton.class]) continue;
        for (UIView *child in view.subviews) {
            if (![child isKindOfClass:entranceClass]) continue;
            menu = view;
            entrance = child;
            break;
        }
    }
    if (!menu) return NO;

    CGFloat leftEdge = CGRectGetMinX(container.bounds);
    for (UIView *view in component.currentLeftShowViews) {
        if (DKProfileTopEntryIsVisible(view, container)) leftEdge = MAX(leftEdge, CGRectGetMaxX(view.frame));
    }
    CGRect frame = menu.frame;
    frame.origin.x = rightEdge - kDKProfileTopEntryGap - CGRectGetWidth(frame);
    if (CGRectGetMinX(frame) < leftEdge + kDKProfileTopEntryGap) return NO;

    UIView *disc = nil;
    for (UIView *view in menu.subviews) {
        if (view.class == UIView.class && view.layer.cornerRadius > 0.0) {
            disc = view;
            break;
        }
    }
    NSArray<UIImageView *> *icons = DKProfileTopEntryMenuIcons(entrance);
    if (!disc || icons.count != 2) return NO;

    DKProfileTopEntryButton *button = objc_getAssociatedObject(container, &kDKProfileTopEntryButtonKey);
    if (!button) {
        button = [[DKProfileTopEntryButton alloc] initWithFrame:frame];
        objc_setAssociatedObject(container, &kDKProfileTopEntryButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [container addSubview:button];
    }
    button.frame = frame;
    button.alpha = menu.alpha;
    button.accessibilityLabel = DKProfileEntryTitle();
    button.disc.frame = [disc convertRect:disc.bounds toView:menu];
    button.disc.layer.cornerRadius = disc.layer.cornerRadius;
    button.disc.backgroundColor = disc.backgroundColor;
    button.disc.hidden = disc.hidden;
    button.disc.alpha = disc.alpha;
    DKProfileTopEntryMirrorIcon(button.lightGear, icons[0], menu);
    DKProfileTopEntryMirrorIcon(button.darkGear, icons[1], menu);
    return YES;
}

void DKProfileTopEntryLayout(UIView *container) {
    AWEProfileNavigationBaseComponent *component = [gDKProfileTopEntryComponents objectForKey:container];
    if (!DKProfileEntryInTopBar() || !DKProfileTopEntryIsMine(component) || !DKProfileTopEntryPlace(container, component)) {
        DKProfileTopEntryRemove(container);
    }
}

UIView *DKProfileTopEntryHit(UIView *container, CGPoint point, UIEvent *event) {
    DKProfileTopEntryButton *button = objc_getAssociatedObject(container, &kDKProfileTopEntryButtonKey);
    if (!DKProfileEntryInTopBar() || button.superview != container || container.hidden || container.alpha <= 0.01
        || !container.userInteractionEnabled || !CGRectContainsPoint(container.bounds, point)) return nil;
    return [button hitTest:[button convertPoint:point fromView:container] withEvent:event];
}

void DKProfileTopEntryRefresh(void) {
    for (UIView *container in gDKProfileTopEntryComponents.keyEnumerator.allObjects) DKProfileTopEntryLayout(container);
}

static void DKProfileTopEntrySync(AWEProfileNavigationBaseComponent *component) {
    if (!NSThread.isMainThread || ![component respondsToSelector:@selector(navigationContainerView)]
        || ![component respondsToSelector:@selector(currentLeftShowViews)]
        || ![component respondsToSelector:@selector(currentRightShowViews)]) return;
    UIView *container = component.navigationContainerView;
    if (![container isKindOfClass:objc_getClass("AWEProfileNavigationContainerView")]) return;
    if (!DKProfileTopEntryIsMine(component)) {
        if ([gDKProfileTopEntryComponents objectForKey:container] == component) {
            [gDKProfileTopEntryComponents removeObjectForKey:container];
            DKProfileTopEntryRemove(container);
        }
        return;
    }
    [gDKProfileTopEntryComponents setObject:component forKey:container];
    DKProfileTopEntryLayout(container);
}

static void DKProfileTopEntrySyncMenu(AWEProfileNavMoreFuncItemController *controller) {
    id component = [controller respondsToSelector:@selector(delegate)] ? controller.delegate : nil;
    if ([component isKindOfClass:%c(AWEProfileNavigationBaseComponent)]) DKProfileTopEntrySync(component);
}

%hook AWEProfileNavigationBaseComponent
- (void)reloadData {
    %orig;
    DKProfileTopEntrySync(self);
}

- (void)navigationStickToTop:(BOOL)stick {
    %orig;
    DKProfileTopEntrySync(self);
}

- (void)updateWithAlpha:(double)alpha force:(BOOL)force {
    %orig;
    DKProfileTopEntrySync(self);
}

- (void)refreshNavigationAlphaIfNeed {
    %orig;
    DKProfileTopEntrySync(self);
}

- (void)onAWEUIThemeChangeNotification {
    %orig;
    DKProfileTopEntrySync(self);
}
%end

%group DKProfileTopEntryMenuHooks
%hook AWEProfileNavMoreFuncItemController
- (void)onNavigationStickToTop:(BOOL)stick {
    %orig;
    DKProfileTopEntrySyncMenu(self);
}

- (void)onThemeChange:(BOOL)light {
    %orig;
    DKProfileTopEntrySyncMenu(self);
}

- (void)navigationThemeDidChangeWithIsLightTheme:(BOOL)light {
    %orig;
    DKProfileTopEntrySyncMenu(self);
}
%end
%end

static BOOL DKProfileTopEntryMenuHasStateMethod(Class cls, SEL selector) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != 3) return NO;
    char result[8], argument[8];
    method_getReturnType(method, result, sizeof(result));
    method_getArgumentType(method, 2, argument, sizeof(argument));
    return strcmp(result, @encode(void)) == 0 && strcmp(argument, @encode(BOOL)) == 0;
}

%ctor {
    gDKProfileTopEntryComponents = [NSMapTable weakToWeakObjectsMapTable];
    %init;
    Class menuClass = %c(AWEProfileNavMoreFuncItemController);
    if (DKProfileTopEntryMenuHasStateMethod(menuClass, @selector(onNavigationStickToTop:))
        && DKProfileTopEntryMenuHasStateMethod(menuClass, @selector(onThemeChange:))
        && DKProfileTopEntryMenuHasStateMethod(menuClass, @selector(navigationThemeDidChangeWithIsLightTheme:))) {
        %init(DKProfileTopEntryMenuHooks);
    }
}
