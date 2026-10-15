//
//  DKTabBarRemoval.xm
//  功能：底栏项目移除 —— 朋友 / 商城 / 消息 / 我 / 拍摄逐项移除，勾选后立即生效。
//
//  实现：
//   - 按钮的 type 是抖音的 tab 类型枚举，经 AWENormalModeTabBarItemConfigsMap 换成 tabID 认人，
//     不依赖标题、顺序与 validIndex。
//   - 移除只写抖音按钮的 hidden（记下原值，取消时还原），不碰交互与透明度——那两样归悬浮玻璃底栏管。
//     玻璃底栏镜像时跳过隐藏按钮，开关玻璃两种模式共用这一处状态。
//   - 抖音每次布局都重设全部按钮 frame 且不跳过隐藏按钮，%orig 之后把剩余按钮在原占用区间内
//     等宽均分；取消移除后下一次布局自然复原。
//   - 其他插件（如 DYYY）也在底栏布局里逐轮重写 hidden 与 frame，谁的 hook 在外层取决于加载顺序。
//     按钮基类上的 setHidden: / setFrame: 守住结果：移除期间他人写的 hidden 只记作原值；
//     本轮均分之后到下一次主队列循环之前，他人写的横向位置按槽位改写。两种顺序结果一致。
//   - 拍摄移除时拦下拍摄按钮的气泡。
//

#import "DKTabBarRemoval.h"
#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKUtils.h"

#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const kDKTabMapClass = @"AWENormalModeTabBarItemConfigsMap";
static NSString *const kDKTabMapShared = @"sharedMap";
static NSString *const kDKTabMapLookup = @"getTabIdWithTabBarItemType:";

// 不由本功能隐藏时按钮应有的 hidden：隐藏前的值，以及移除期间他人写入的最新值。有值即「由本功能隐藏」。
static char kDKRemovalOriginalHiddenKey;
// 均分后的横向槽位（x 与宽度存在 CGRect 的 origin.x / size.width），只在锁定窗口内生效。
static char kDKRemovalSlotKey;

// 本功能自己在写 hidden / frame，两个守门 hook 放行。
static BOOL gRemovalWriting = NO;
// 本轮均分之后到下一次主队列循环之前为 YES：这段时间里他人写 frame 按槽位改写。
static BOOL gRemovalFrameLock = NO;

// 最近一次布局的抖音底栏，设置改动后据此立即重排。
static __weak AWENormalModeTabBar *gRemovalBar = nil;

static id DKRemovalValue(id object, NSString *key) {
    if (!object) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

#pragma mark - 项目表

// 设置页顺序。tabID 是抖音 tab 配置的标识，也是开关键的后缀，发布后不可改。
NSArray<NSString *> *DKTabBarRemovableTabIDs(void) {
    return @[ @"homepage_familiar", @"homepage_mall", @"homepage_notification", @"homepage_profile",
              @"homepage_publish" ];
}

NSString *DKTabBarRemovableTitle(NSString *tabID) {
    static NSDictionary<NSString *, NSString *> *titles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        titles = @{ @"homepage_familiar": @"朋友", @"homepage_mall": @"商城",
                    @"homepage_notification": @"消息", @"homepage_profile": @"我",
                    @"homepage_publish": @"拍摄" };
    });
    return tabID ? titles[tabID] : nil;
}

// 只认表内项目：备份恢复可能写入表外的 ID（如首页），运行期一律忽略。
static BOOL DKTabBarRemovalWants(NSString *tabID) {
    if (!DKTabBarRemovableTitle(tabID)) return NO;
    return DKPrefBool([DKKeyBottomBarHidePrefix stringByAppendingString:tabID]);
}

NSInteger DKTabBarRemovedCount(void) {
    NSInteger count = 0;
    for (NSString *tabID in DKTabBarRemovableTabIDs()) {
        if (DKTabBarRemovalWants(tabID)) count++;
    }
    return count;
}

// type → tabID 是抖音启动时注册的固定对应，按 type 缓存；取不到不缓存，配置可能尚未就绪。
NSString *DKTabBarButtonTabID(id button) {
    static NSMutableDictionary<NSNumber *, NSString *> *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];

    NSNumber *type = DKRemovalValue(button, @"type");
    if (![type isKindOfClass:NSNumber.class]) return nil;
    NSString *tabID = cache[type];
    if (tabID) return tabID;

    Class mapClass = NSClassFromString(kDKTabMapClass);
    SEL shared = NSSelectorFromString(kDKTabMapShared);
    SEL lookup = NSSelectorFromString(kDKTabMapLookup);
    if (![mapClass respondsToSelector:shared]) return nil;
    id map = ((id (*)(id, SEL))objc_msgSend)(mapClass, shared);
    if (![map respondsToSelector:lookup]) return nil;
    id value = ((id (*)(id, SEL, long long))objc_msgSend)(map, lookup, type.longLongValue);
    if (![value isKindOfClass:NSString.class] || [value length] == 0) return nil;
    cache[type] = value;
    return value;
}

BOOL DKTabBarRemovalHides(id button) {
    return button && objc_getAssociatedObject(button, &kDKRemovalOriginalHiddenKey) != nil;
}

#pragma mark - 移除

static NSArray<UIView *> *DKRemovalButtons(AWENormalModeTabBar *bar) {
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    for (id button in DKRemovalValue(bar, @"tabBarButtons")) {
        if ([button isKindOfClass:UIView.class]) [views addObject:button];
    }
    return views;
}

static void DKRemovalSetHidden(UIView *button, BOOL hidden) {
    if (button.isHidden == hidden) return;
    gRemovalWriting = YES;
    button.hidden = hidden;
    gRemovalWriting = NO;
}

static void DKRemovalSetFrame(UIView *button, CGRect frame) {
    if (CGRectEqualToRect(button.frame, frame)) return;
    gRemovalWriting = YES;
    button.frame = frame;
    gRemovalWriting = NO;
}

static void DKRemovalSetSlot(UIView *button, NSValue *slot) {
    if (objc_getAssociatedObject(button, &kDKRemovalSlotKey) == slot) return;
    objc_setAssociatedObject(button, &kDKRemovalSlotKey, slot, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// 逐帧路径：只在状态需要变化时写 hidden。还原时先摘标记，写入不再被守门 hook 拦。
static void DKRemovalApplyHidden(NSArray<UIView *> *buttons) {
    for (UIView *button in buttons) {
        BOOL wants = DKTabBarRemovalWants(DKTabBarButtonTabID(button));
        NSNumber *original = objc_getAssociatedObject(button, &kDKRemovalOriginalHiddenKey);
        if (wants) {
            if (!original) {
                objc_setAssociatedObject(button, &kDKRemovalOriginalHiddenKey, @(button.isHidden),
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            DKRemovalSetHidden(button, YES);
        } else if (original) {
            objc_setAssociatedObject(button, &kDKRemovalOriginalHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            DKRemovalSetHidden(button, original.boolValue);
        }
    }
}

// 锁定窗口开到下一次主队列循环：同一轮布局里在外层 hook 写下的 frame 都落在窗口内，
// 抖音下一轮布局写的是它自己的原始位置，均分区间据此重算。
static void DKRemovalLockFrames(void) {
    if (gRemovalFrameLock) return;
    gRemovalFrameLock = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        gRemovalFrameLock = NO;
    });
}

// 剩余按钮在抖音给全部按钮划定的区间内等宽均分，y 与高度保持抖音的值。
// 区间取自 %orig 刚写下的 frame（含被隐藏的按钮），抖音另有容器或侧边元素时也不越界。
static void DKRemovalRedistribute(NSArray<UIView *> *buttons) {
    BOOL removed = NO;
    UIView *container = buttons.firstObject.superview;
    CGFloat minX = CGFLOAT_MAX, maxX = -CGFLOAT_MAX;
    NSMutableArray<UIView *> *visible = [NSMutableArray array];
    for (UIView *button in buttons) {
        if (button.superview != container) return;      // 按钮分属不同容器时不重排
        if (DKTabBarRemovalHides(button)) removed = YES;
        minX = MIN(minX, CGRectGetMinX(button.frame));
        maxX = MAX(maxX, CGRectGetMaxX(button.frame));
        if (!button.isHidden) [visible addObject:button];
    }
    if (!removed || !container || visible.count == 0 || maxX <= minX) {
        for (UIView *button in buttons) DKRemovalSetSlot(button, nil);
        return;
    }

    [visible sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return [@(CGRectGetMinX(a.frame)) compare:@(CGRectGetMinX(b.frame))];
    }];
    CGFloat width = (maxX - minX) / visible.count;
    for (UIView *button in buttons) {
        NSUInteger index = [visible indexOfObjectIdenticalTo:button];
        if (index == NSNotFound) {
            DKRemovalSetSlot(button, nil);
            continue;
        }
        CGRect frame = button.frame;
        frame.origin.x = minX + width * index;
        frame.size.width = width;
        NSValue *slot = objc_getAssociatedObject(button, &kDKRemovalSlotKey);
        if (!slot || !CGRectEqualToRect(slot.CGRectValue, frame)) DKRemovalSetSlot(button, [NSValue valueWithCGRect:frame]);
        DKRemovalSetFrame(button, frame);
    }
    DKRemovalLockFrames();
}

void DKTabBarRemovalRefresh(void) {
    [gRemovalBar setNeedsLayout];
}

#pragma mark - Hook

%hook AWENormalModeTabBar

// %orig 前后各隐藏一次：同类 hook（悬浮玻璃底栏）在 %orig 之后读按钮，不论两者谁在外层，
// 读到的都是本轮最终的 hidden。均分必须在 %orig 写完 frame 之后。
- (void)layoutSubviews {
    gRemovalBar = self;
    DKRemovalApplyHidden(DKRemovalButtons(self));
    %orig;
    NSArray<UIView *> *buttons = DKRemovalButtons(self);
    DKRemovalApplyHidden(buttons);
    DKRemovalRedistribute(buttons);
}

%end

// 底栏按钮的公共基类，三种按钮都不自己实现这两个方法（40.7.0 ObjC 元数据核对）。
%hook AWENormalModeTabBarButton

- (void)setHidden:(BOOL)hidden {
    if (!gRemovalWriting && DKTabBarRemovalHides(self)) {
        objc_setAssociatedObject(self, &kDKRemovalOriginalHiddenKey, @(hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        hidden = YES;
    }
    %orig(hidden);
}

// 只改横向位置与宽度，纵向沿用写入方的值。
- (void)setFrame:(CGRect)frame {
    if (gRemovalFrameLock && !gRemovalWriting) {
        NSValue *slot = objc_getAssociatedObject(self, &kDKRemovalSlotKey);
        if (slot) {
            CGRect target = slot.CGRectValue;
            frame.origin.x = target.origin.x;
            frame.size.width = target.size.width;
        }
    }
    %orig(frame);
}

%end

// 拍摄按钮的气泡锚在按钮上方，按钮移除后不再弹。两个类分别对应两种拍摄按钮形态，方法存在才装。
%group DKRemovalPlusInnerBubble
%hook AWENormalModeTabBarGeneralPlusInnerButton
- (void)showBubbleWithText:(id)text {
    if (DKPrefBool(DKKeyHidePlusButton)) return;
    %orig;
}
%end
%end

%group DKRemovalPlusBubble
%hook AWENormalModeTabBarPlusButton
- (void)showBubbleWithText:(id)text {
    if (DKPrefBool(DKKeyHidePlusButton)) return;
    %orig;
}
%end
%end

%ctor {
    %init;
    SEL bubble = NSSelectorFromString(@"showBubbleWithText:");
    if (class_getInstanceMethod(NSClassFromString(@"AWENormalModeTabBarGeneralPlusInnerButton"), bubble)) {
        %init(DKRemovalPlusInnerBubble);
    }
    if (class_getInstanceMethod(NSClassFromString(@"AWENormalModeTabBarPlusButton"), bubble)) {
        %init(DKRemovalPlusBubble);
    }
}
