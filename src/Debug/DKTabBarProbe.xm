//
//  DKTabBarProbe.xm
//  DYKiller
//
//  底栏探针：只读采集玻璃底栏、抖音自绘底栏与首页 feed 的运行时状态，随调试导出写入
//  probe/tabbar.txt。不改变任何状态。功能定型后整文件删除。
//

#import "DKTabBarProbe.h"
#import "DouyinHeaders.h"
#import "DKCommentGlass.h"
#import "DKGlassTabBar.h"
#import "DKVideoFeedTable.h"
#import "DKVideoFullscreen.h"
#import "DKDebugCapture.h"

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <math.h>

#pragma mark - 采集小工具

static id DKProbeValue(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *DKProbeDesc(id object) {
    if (!object) return @"(nil)";
    return [NSString stringWithFormat:@"%@ %p", NSStringFromClass([object class]), object];
}

static NSString *DKProbeColorDesc(UIColor *color) {
    if (![color isKindOfClass:UIColor.class]) return @"(nil)";
    CGFloat red = 0.0, green = 0.0, blue = 0.0, alpha = 0.0;
    if (![color getRed:&red green:&green blue:&blue alpha:&alpha]) {
        [color getWhite:&red alpha:&alpha];
        green = blue = red;
    }
    return [NSString stringWithFormat:@"rgba(%.3f,%.3f,%.3f,%.3f)", red, green, blue, alpha];
}

static NSString *DKProbeStyleName(UIUserInterfaceStyle style) {
    switch (style) {
        case UIUserInterfaceStyleLight: return @"浅色";
        case UIUserInterfaceStyleDark:  return @"深色";
        default:                        return @"未指定";
    }
}

static UIView *DKProbeFindSubview(UIView *root, NSString *className) {
    for (UIView *subview in root.subviews) {
        if ([NSStringFromClass(subview.class) containsString:className]) return subview;
        UIView *found = DKProbeFindSubview(subview, className);
        if (found) return found;
    }
    return nil;
}

/// 只收直接命中的层，不再向命中层内部下探，避免内部类名含同一子串时重复计数。
static NSArray<UIView *> *DKProbeFindSubviews(UIView *root, NSString *className) {
    NSMutableArray<UIView *> *result = [NSMutableArray array];
    for (UIView *subview in root.subviews) {
        if ([NSStringFromClass(subview.class) containsString:className]) {
            [result addObject:subview];
        } else {
            [result addObjectsFromArray:DKProbeFindSubviews(subview, className)];
        }
    }
    return result;
}

static UITabBarController *DKProbeTabBarController(void) {
    UIViewController *root = DKDebugTargetWindow().rootViewController;
    if (!root) return nil;

    NSMutableArray<UIViewController *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count > 0) {
        UIViewController *vc = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([vc isKindOfClass:UITabBarController.class]) return (UITabBarController *)vc;
        [queue addObjectsFromArray:vc.childViewControllers];
        if (vc.presentedViewController) [queue addObject:vc.presentedViewController];
    }
    return nil;
}

#pragma mark - 各分节

// 玻璃质感与深色适配的判据：backgroundEffect 读到 nil 或 UIGlassEffect 才是出厂的液态玻璃；
// 读到 UIBlurEffect 说明被降级成了老毛玻璃。trait 各级对照用于定位深色不跟随的源头。
static void DKProbeAppendGlassBar(NSMutableString *out, UITabBarController *controller) {
    UITabBar *bar = DKGlassTabBarCurrent();
    [out appendFormat:@"玻璃底栏             = %@\n", DKProbeDesc(bar)];
    if (!bar) {
        [out appendString:@"（功能关闭时不建立）\n"];
        return;
    }

    [out appendFormat:@"  frame=%@  hidden=%@  alpha=%.3f\n",
     NSStringFromCGRect(bar.frame), bar.isHidden ? @"YES" : @"NO", bar.alpha];
    [out appendFormat:@"  standardAppearance.backgroundEffect   = %@\n",
     bar.standardAppearance.backgroundEffect ?: (id)@"(nil)"];
    [out appendFormat:@"  scrollEdgeAppearance.backgroundEffect = %@\n",
     bar.scrollEdgeAppearance.backgroundEffect ?: (id)@"(nil)"];
    // 标题走的是 image 槽（模板图），title 恒为空，认人靠 accessibilityLabel。
    // badgeValue 为原生角标：nil=无，""=纯红点，其余为显示的数字或文案。
    [out appendFormat:@"  items=%lu  selectedItem=%@\n",
     (unsigned long)bar.items.count, bar.selectedItem.accessibilityLabel ?: @"(nil)"];
    for (UITabBarItem *item in bar.items) {
        [out appendFormat:@"    %@  标题图=%@  badgeValue=%@\n", item.accessibilityLabel ?: @"(nil)",
         item.image ? NSStringFromCGSize(item.image.size) : @"(无)",
         item.badgeValue ? [NSString stringWithFormat:@"\"%@\"", item.badgeValue] : @"(nil)"];
    }

    // 子视图挂载是否成功：父视图应为 AWENormalModeTabBar，显隐由它继承。
    [out appendFormat:@"  superview          = %@（hidden=%@ alpha=%.3f）\n",
     DKProbeDesc(bar.superview), bar.superview.isHidden ? @"YES" : @"NO", bar.superview.alpha];

    // 深浅色定位：抖音把 window 的 override 钉死为浅色，真值只能从场景取。
    // 「场景」与「玻璃底栏」两行一致即为修好；场景是深色而玻璃底栏是浅色则说明覆盖没生效。
    UIWindowScene *scene = bar.window.windowScene;
    [out appendString:@"  界面风格 trait：\n"];
    [out appendFormat:@"    场景     = %@\n", DKProbeStyleName(scene.traitCollection.userInterfaceStyle)];
    [out appendFormat:@"    window   = %@（override=%@）\n",
     DKProbeStyleName(bar.window.traitCollection.userInterfaceStyle),
     DKProbeStyleName(bar.window.overrideUserInterfaceStyle)];
    [out appendFormat:@"    抖音底栏 = %@\n",
     DKProbeStyleName(bar.superview.traitCollection.userInterfaceStyle)];
    [out appendFormat:@"    玻璃底栏 = %@（override=%@）\n",
     DKProbeStyleName(bar.traitCollection.userInterfaceStyle),
     DKProbeStyleName(bar.overrideUserInterfaceStyle)];

    // 文字居中的判据：标题图的 frame 应在按钮内纵向居中（按钮 54 高时 y≈(54−图高)/2）。
    UIView *platter = DKProbeFindSubview(bar, @"_UITabBarItemPlatterView");
    [out appendFormat:@"  platter            = %@  frame=%@\n",
     DKProbeDesc(platter), platter ? NSStringFromCGRect(platter.frame) : @"-"];
    for (UIView *button in DKProbeFindSubviews(platter, @"_UITabButton")) {
        UIView *image = DKProbeFindSubview(button, @"ImageView");
        UIView *label = DKProbeFindSubview(button, @"Label");
        [out appendFormat:@"    按钮 frame=%@  标题图 frame=%@  残留文字 frame=%@\n",
         NSStringFromCGRect(button.frame),
         image ? NSStringFromCGRect(image.frame) : @"(无)",
         label ? NSStringFromCGRect(label.frame) : @"(无)"];
    }

    [out appendFormat:@"  抖音 selectedIndex = %lu\n", (unsigned long)controller.selectedIndex];
}

// UIGlassEffectStyle：0=Regular，1=Clear。用数值对照，避免在低 SDK 编译期引用枚举。
static NSString *DKProbeGlassStyleName(id styleValue) {
    if (!styleValue || styleValue == (id)[NSNull null]) return @"-";
    switch ([styleValue integerValue]) {
        case 0: return @"Regular";
        case 1: return @"Clear";
        default: return [NSString stringWithFormat:@"%@", styleValue];
    }
}

// 拍摄圆键。effect 应为 UIGlassEffect 且 interactive=YES。
// 不访问 contentView：该属性会懒创建内部视图，导出路径曾因此在后台线程踩雷。
static void DKProbeAppendPlusKey(NSMutableString *out) {
    UIVisualEffectView *key = DKGlassPlusKeyCurrent();
    [out appendFormat:@"拍摄圆键             = %@\n", DKProbeDesc(key)];
    if (!key) return;

    UIVisualEffect *effect = key.effect;
    [out appendFormat:@"  frame=%@  hidden=%@  alpha=%.3f  界面风格=%@\n",
     NSStringFromCGRect(key.frame), key.isHidden ? @"YES" : @"NO", key.alpha,
     DKProbeStyleName(key.traitCollection.userInterfaceStyle)];
    [out appendFormat:@"  effect             = %@  style=%@  interactive=%@\n",
     effect ? NSStringFromClass(effect.class) : @"(nil)",
     DKProbeGlassStyleName(DKProbeValue(effect, @"style")),
     [DKProbeValue(effect, @"interactive") boolValue] ? @"YES" : @"NO"];
    if (@available(iOS 26.0, *)) {
        [out appendFormat:@"  圆角有效半径       = %.1f（直径 %.1f 的一半即为正圆）\n",
         [key effectiveRadiusForCorner:UIRectCornerTopLeft], CGRectGetWidth(key.bounds)];
    }
}

// 评论面板玻璃：验收 Clear 材质、alpha、场景 trait 与有效圆角。
// 只检查槽位现有子树，不访问 glass.contentView。
static void DKProbeAppendCommentGlass(NSMutableString *out) {
    UIView *slot = DKCommentGlassCurrentSlot();
    [out appendFormat:@"面板槽位             = %@\n", DKProbeDesc(slot)];
    if (!slot) {
        [out appendString:@"  本次会话未接管过评论面板（功能关闭，或没找到槽位）。\n"];
        return;
    }

    UIWindowScene *scene = slot.window.windowScene;
    [out appendFormat:@"  frame=%@  bg=%@\n",
     NSStringFromCGRect(slot.frame), DKProbeColorDesc(slot.backgroundColor)];
    [out appendFormat:@"  masksToBounds=%@  cornerRadius=%.1f  cornerCurve=%@\n",
     slot.layer.masksToBounds ? @"YES" : @"NO", slot.layer.cornerRadius, slot.layer.cornerCurve];
    [out appendFormat:@"  场景外观           = %@  window override=%@  槽位 trait=%@\n",
     DKProbeStyleName(scene.traitCollection.userInterfaceStyle),
     DKProbeStyleName(slot.window.overrideUserInterfaceStyle),
     DKProbeStyleName(slot.traitCollection.userInterfaceStyle)];

    UIView *first = slot.subviews.firstObject;
    [out appendFormat:@"  最底层子视图       = %@（共 %lu 个）\n",
     first ? NSStringFromClass(first.class) : @"(无)", (unsigned long)slot.subviews.count];

    if (![first isKindOfClass:UIVisualEffectView.class]) {
        [out appendString:@"  最底层不是 effect view：玻璃没挂上，或已被别的插件接管。\n"];
        return;
    }

    UIVisualEffectView *glass = (UIVisualEffectView *)first;
    UIVisualEffect *effect = glass.effect;
    [out appendFormat:@"玻璃层               = %@\n", DKProbeDesc(glass)];
    [out appendFormat:@"  frame=%@  alpha=%.3f  hidden=%@\n",
     NSStringFromCGRect(glass.frame), glass.alpha, glass.isHidden ? @"YES" : @"NO"];
    // style 属性由 _style ivar 支持，但 +effectWithStyle: 不写它（模拟器实测 Clear 建出来的
    // effect 回读仍是 0），所以只打真正决定材质的 _UIViewGlass 描述。
    [out appendFormat:@"  effect             = %@  interactive=%@  tintColor=%@\n",
     effect ? NSStringFromClass(effect.class) : @"(nil)",
     [DKProbeValue(effect, @"interactive") boolValue] ? @"YES" : @"NO",
     DKProbeColorDesc(DKProbeValue(effect, @"tintColor"))];
    [out appendFormat:@"  glass              = %@\n", DKProbeValue(effect, @"glass") ?: @"(读不到)"];
    [out appendFormat:@"  界面风格           = %@（override=%@）\n",
     DKProbeStyleName(glass.traitCollection.userInterfaceStyle),
     DKProbeStyleName(glass.overrideUserInterfaceStyle)];
    if (@available(iOS 26.0, *)) {
        [out appendFormat:@"  圆角有效半径       = 左上 %.1f  右上 %.1f  左下 %.1f  右下 %.1f\n",
         [glass effectiveRadiusForCorner:UIRectCornerTopLeft],
         [glass effectiveRadiusForCorner:UIRectCornerTopRight],
         [glass effectiveRadiusForCorner:UIRectCornerBottomLeft],
         [glass effectiveRadiusForCorner:UIRectCornerBottomRight]];
    }
}

// 玻璃底栏显隐的镜像源。抖音那套显隐逻辑最终都汇聚到这里的 hidden/alpha。
static void DKProbeAppendDouyinBar(NSMutableString *out, UITabBarController *controller) {
    UIView *bar = DKProbeValue(controller, @"awe_tabBar");
    [out appendFormat:@"awe_tabBar           = %@\n", DKProbeDesc(bar)];
    if (bar) {
        [out appendFormat:@"  hidden=%@  alpha=%.3f  frame=%@\n",
         bar.isHidden ? @"YES" : @"NO", bar.alpha, NSStringFromCGRect(bar.frame)];
    }

    NSArray *buttons = DKProbeValue(controller, @"buttons");
    [out appendFormat:@"buttons.count        = %lu\n", (unsigned long)buttons.count];
    for (id button in buttons) {
        UIView *view = [button isKindOfClass:UIView.class] ? button : nil;
        NSString *title = DKProbeValue(DKProbeValue(DKProbeValue(button, @"innerView"), @"label"), @"text");
        [out appendFormat:@"  %@ 文字=%@ hidden=%@ type=%@ validIndex=%@\n",
         NSStringFromClass([button class]), title ?: view.accessibilityLabel ?: @"(nil)",
         view.isHidden ? @"YES" : @"NO",
         DKProbeValue(button, @"type") ?: @"?", DKProbeValue(button, @"validIndex") ?: @"?"];

        // 角标镜像的源：这里的读数应与上面 items 的 badgeValue 一一对上。
        UIView *badge = DKProbeFindSubview(view, @"DUXBadge");
        if (badge) {
            [out appendFormat:@"    DUXBadge hidden=%@ alpha=%.2f text=%@ number=%@\n",
             badge.isHidden ? @"YES" : @"NO", badge.alpha,
             DKProbeValue(badge, @"badgeText") ?: @"(nil)",
             DKProbeValue(badge, @"badgeNumber") ?: @"(nil)"];
        }
    }
}

// 进度条底边黑垫层的诊断：view tree 与 layers.json 都不采 backgroundColor，
// 这里补齐，用于确认清除签名为何命中或不命中。
static void DKProbeAppendProgressContainer(NSMutableString *out, UIView *root) {
    for (UIView *container in DKProbeFindSubviews(root, @"AWEDPlayerProgressContainerView")) {
        [out appendFormat:@"  %@ frame=%@\n", DKProbeDesc(container), NSStringFromCGRect(container.frame)];
        for (UIView *view in container.subviews) {
            CGFloat red = 0.0, green = 0.0, blue = 0.0, alpha = -1.0;
            UIColor *color = view.backgroundColor;
            if (color && ![color getRed:&red green:&green blue:&blue alpha:&alpha]) {
                [color getWhite:&red alpha:&alpha];
                green = blue = red;
            }
            [out appendFormat:@"    %@ frame=%@ hidden=%@ opaque=%@ bg=%@\n",
             NSStringFromClass(view.class), NSStringFromCGRect(view.frame),
             view.isHidden ? @"YES" : @"NO", view.isOpaque ? @"YES" : @"NO",
             color ? [NSString stringWithFormat:@"rgba(%.3f,%.3f,%.3f,%.3f)", red, green, blue, alpha]
                   : @"(nil)"];
        }
    }
}

// 评论态顶部黑遮罩：满宽 × 窗口安全区高的不透明黑条，直属 HUD 根视图。
//
// 找不到时也要打印一行，并带上当时那把尺子的读数：这条 bug 反复了三个版本，就是因为
// 「本来就没有遮罩」与「签名没匹配上」在报告里长得一模一样，看不出是哪一种。
static void DKProbeAppendStatusBarCover(NSMutableString *out, UIView *hudView) {
    CGFloat safeTop = DKHUDStatusBarCoverHeight(hudView);
    for (UIView *view in hudView.subviews) {
        if (object_getClass(view) != [UIView class]) continue;
        CGRect frame = view.frame;
        if (fabs(CGRectGetMinY(frame)) > 1.0
            || fabs(CGRectGetWidth(frame) - CGRectGetWidth(hudView.bounds)) > 1.0
            || fabs(CGRectGetHeight(frame) - safeTop) > 2.0) {
            continue;
        }
        [out appendFormat:@"  顶部遮罩         = %@ frame=%@ hidden=%@ bg=%@\n",
         DKProbeDesc(view), NSStringFromCGRect(frame),
         view.isHidden ? @"YES" : @"NO", DKProbeColorDesc(view.backgroundColor)];
        return;
    }
    [out appendFormat:@"  顶部遮罩         = 未命中（窗口安全区高=%.1f，视图自身=%.1f）\n",
     safeTop, hudView.safeAreaInsets.top];
}

// 视频冻结的验收面：播放器容器被抖音缩小时改的是 frame。
//
// 「满屏」不能拿父视图 bounds 当尺子：好友聊天页的容器本就该比父视图高一个底栏（钉到 Cell 满高
// 才能覆盖物理屏幕），拿父视图比会把达标判成不达标。改为直接问功能自己的钉位目标。
// HUD 根视图单列一行：它被误钉成 Cell 满高时，文案/昵称/点赞栏会整体下移一个底栏高。
static void DKProbeAppendFrozenMedia(NSMutableString *out) {
    UIWindow *window = DKDebugTargetWindow();
    UIView *slot = DKCommentGlassCurrentSlot();
    [out appendFormat:@"评论面板在屏     = %@\n",
     (slot.window && !slot.hidden) ? @"是" : @"否"];

    Class playerCls = NSClassFromString(@"AWEDPlayerViewController_Merge");
    Class hudCls = NSClassFromString(@"AWEPlayInteractionViewController");
    NSUInteger found = 0;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:window];
    while (queue.count > 0) {
        UIView *node = queue.firstObject;
        [queue removeObjectAtIndex:0];

        if (hudCls && [node.nextResponder isKindOfClass:hudCls]) {
            [out appendFormat:@"HUD 根视图       = %@\n", DKProbeDesc(node)];
            [out appendFormat:@"  frame=%@  父视图=%@\n",
             NSStringFromCGRect(node.frame), NSStringFromCGRect(node.superview.bounds)];
            DKProbeAppendStatusBarCover(out, node);
            continue;
        }
        if (playerCls && [node.nextResponder isKindOfClass:playerCls]) {
            found++;
            CGRect target = DKVideoContainerTargetFrame(node);
            [out appendFormat:@"播放器容器       = %@\n", DKProbeDesc(node)];
            [out appendFormat:@"  frame=%@  父视图=%@\n",
             NSStringFromCGRect(node.frame), NSStringFromCGRect(node.superview.bounds)];
            [out appendFormat:@"  钉位目标         = %@\n",
             CGRectIsNull(target) ? @"(不在作用域)" : NSStringFromCGRect(target)];
            [out appendFormat:@"  达标？           = %@\n",
             CGRectIsNull(target) ? @"—"
                : (DKRectsClose(node.frame, target) ? @"是" : @"否（被缩放或平移）")];
            continue;
        }
        [queue addObjectsFromArray:node.subviews];
    }
    if (found == 0) [out appendString:@"播放器容器       = (本页没有)\n"];
    [out appendFormat:@"容器重钉命中统计: %@\n", DKVideoContainerPinStats()];
}

// 图文缩放看容器入口；最终背景还要同时核对整页底色与可见 Cell 的贴底压暗。
// 内容层类名随实现变（图片 / LivePhoto / 各版新类型），追类名两版都有漏网，报告也不该再按类名找。
// 「内容满幅？」直接对上首页那条实测的 {0,0,428,926} → {0,47,428,249.32}。
// 「图文底色」问的是功能自己那把尺子（DKRichBackdropColor）：它为 nil 就是这一页延伸不了背景。
static void DKProbeAppendRichContent(NSMutableString *out) {
    Class containerCls = NSClassFromString(@"RichContentContainerViewController");
    NSUInteger found = 0;
    NSMutableArray<UIView *> *queue =
        [NSMutableArray arrayWithObject:DKDebugTargetWindow()];
    while (queue.count > 0) {
        UIView *node = queue.firstObject;
        [queue removeObjectAtIndex:0];

        if (containerCls && [node.nextResponder isKindOfClass:containerCls]) {
            found++;
            RichContentContainerViewController *container =
                (RichContentContainerViewController *)node.nextResponder;
            [out appendFormat:@"图文容器         = %@\n", DKProbeDesc(container)];
            [out appendFormat:@"  view frame=%@  clips=%@  父视图=%@\n",
             NSStringFromCGRect(node.frame), node.clipsToBounds ? @"YES" : @"NO",
             NSStringFromCGRect(node.superview.bounds)];
            UIColor *backdrop = DKRichBackdropColor(container);
            [out appendFormat:@"  图文底色 = %@%@\n", DKProbeColorDesc(backdrop),
             backdrop ? @"（AWEKnowledgeGradientView 渐变末色）"
                      : @"（没找到整页背景渐变，本页不延伸）"];

            UIView *knowledge = DKProbeFindSubview(node, @"AWEKnowledgeGradientView");
            if (knowledge) {
                [out appendFormat:@"  整页背景层 = %@ frame=%@ bounds=%@ transform=%@\n",
                 DKProbeDesc(knowledge),
                 NSStringFromCGRect(knowledge.frame),
                 NSStringFromCGRect(knowledge.bounds),
                 NSStringFromCGAffineTransform(knowledge.transform)];
            } else {
                [out appendString:@"  整页背景层 = (没找到)\n"];
            }

            UIView *collection = DKProbeFindSubview(node, @"AWEStoryContainerCollectionView");
            if (collection) {
                CGRect frame = collection.frame;
                BOOL full = fabs(CGRectGetMinY(frame)) <= 0.5
                    && fabs(CGRectGetHeight(frame) - CGRectGetHeight(node.bounds)) <= 0.5;
                [out appendFormat:@"  内容集合视图 = %@ frame=%@  满幅？= %@\n",
                 DKProbeDesc(collection), NSStringFromCGRect(frame),
                 full ? @"是" : @"否（被缩小或上移）"];
                [out appendFormat:@"  %@\n", DKRichBottomGradientStats(collection)];
            } else {
                [out appendString:@"  内容集合视图 = (没找到)\n"];
            }
            continue;
        }
        [queue addObjectsFromArray:node.subviews];
    }
    if (found == 0) [out appendString:@"图文容器         = (本页没有图文)\n"];
}

// 视频表是「视频不全屏」的第一嫌疑：容器比表更高就说明这张表被底栏压缩过、该撑而没撑。
// 作用域是基类，首页/朋友页与好友聊天/搜索/其他用户主页的表都在这里，逐张给出撑高结论。
static void DKProbeAppendFeed(NSMutableString *out) {
    UIWindow *window = DKDebugTargetWindow();
    Class tableCls = DKVideoFeedTableClass();
    NSMutableArray<UITableView *> *tables = [NSMutableArray array];
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:window];
    while (pending.count > 0) {
        UIView *node = pending.firstObject;
        [pending removeObjectAtIndex:0];
        if (tableCls && [node isKindOfClass:tableCls]) {
            [tables addObject:(UITableView *)node];
            continue;
        }
        [pending addObjectsFromArray:node.subviews];
    }
    [out appendFormat:@"视频表（AWEFeedDataSafeTableView 及子类）× %lu   视频全屏开关=%@\n",
     (unsigned long)tables.count, DKVideoFullscreenOn() ? @"开" : @"关"];

    Class hudCls = NSClassFromString(@"AWEPlayInteractionViewController");
    for (UITableView *table in tables) {
        CGFloat container = CGRectGetHeight(table.superview.bounds);
        NSNumber *original = DKVideoFeedTableOriginalHeight(table);

        [out appendFormat:@"  %@  frame=%@  clips=%@  superview高=%.1f\n",
         DKProbeDesc(table), NSStringFromCGRect(table.frame),
         table.clipsToBounds ? @"YES" : @"NO", container];
        [out appendFormat:@"  撑高原高=%@  已撑高？= %@\n",
         original ? [NSString stringWithFormat:@"%.1f", original.doubleValue] : @"(未记录)",
         original ? @"是"
                  : (CGRectGetHeight(table.frame) < container - 0.5
                        ? @"否（容器更高，本该撑高）" : @"否（本就满高，不需要撑）")];
        [out appendFormat:@"  contentOffset=%@  contentSize=%@\n",
         NSStringFromCGPoint(table.contentOffset), NSStringFromCGSize(table.contentSize)];

        for (UITableViewCell *cell in table.visibleCells) {
            [out appendFormat:@"  cell frame=%@  contentView高=%.1f\n",
             NSStringFromCGRect(cell.frame), CGRectGetHeight(cell.contentView.bounds)];
            NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:cell.subviews];
            while (queue.count > 0) {
                UIView *node = queue.firstObject;
                [queue removeObjectAtIndex:0];
                if (hudCls && [node.nextResponder isKindOfClass:hudCls]) {
                    [out appendFormat:@"    HUD %@ frame=%@\n",
                     DKProbeDesc(node), NSStringFromCGRect(node.frame)];
                    continue;
                }
                [queue addObjectsFromArray:node.subviews];
            }
        }
    }
    [out appendFormat:@"HUD 钉位命中统计: %@\n", DKVideoFeedTableStats()];
}

#pragma mark - 报告

NSString *DKTabBarProbeReport(void) {
    if (![NSThread isMainThread]) {
        return @"===== DYKiller 探针 =====\n错误: 探针必须在主线程调用（禁止后台读 UIKit）。\n";
    }

    NSMutableString *out = [NSMutableString string];
    [out appendString:@"===== DYKiller 底栏探针 =====\n"];
    [out appendFormat:@"采集时间   : %@\n", NSDate.date];
    [out appendFormat:@"系统       : iOS %@\n", UIDevice.currentDevice.systemVersion];
    [out appendFormat:@"线程       : 主线程\n"];

    // 评论面板与底栏互斥可见，这一节放在底栏之前，避免被「没找到 UITabBarController」挡掉。
    [out appendString:@"\n----- 评论面板玻璃 -----\n"];
    DKProbeAppendCommentGlass(out);

    [out appendString:@"\n----- 视频冻结 -----\n"];
    DKProbeAppendFrozenMedia(out);

    [out appendString:@"\n----- 图文 -----\n"];
    DKProbeAppendRichContent(out);

    // 视频表这一节必须在「没找到 UITabBarController 就返回」之前：其他用户主页、搜索页这些
    // 被 push 出来的页面正是最需要看表撑高结论的地方，挡在后面就永远采不到。
    [out appendString:@"\n----- 视频表（撑高验证）-----\n"];
    DKProbeAppendFeed(out);

    [out appendString:@"\n----- 进度条容器（黑垫层诊断）-----\n"];
    DKProbeAppendProgressContainer(out, DKDebugTargetWindow());

    UITabBarController *controller = DKProbeTabBarController();
    if (!controller) {
        [out appendString:@"\n没找到 UITabBarController，本页可能不在主 tab 容器内。\n"];
        return out;
    }

    [out appendString:@"\n----- 悬浮玻璃底栏 -----\n"];
    DKProbeAppendGlassBar(out, controller);
    DKProbeAppendPlusKey(out);

    [out appendString:@"\n----- 抖音自绘底栏（镜像源）-----\n"];
    DKProbeAppendDouyinBar(out, controller);

    return out;
}
