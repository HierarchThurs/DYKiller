//
//  DKTabBarProbe.xm
//  DYKiller
//
//  底栏探针：只读采集玻璃底栏、抖音自绘底栏与首页 feed 的运行时状态，随调试导出写入
//  probe/tabbar.txt。不改变任何状态。功能定型后整文件删除。
//

#import "DKTabBarProbe.h"
#import "DKGlassTabBar.h"
#import "DKFeedVideoFullscreen.h"
#import "DKDebugCapture.h"

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

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

// 拍摄圆键。effect 应为 UIGlassEffect 且 interactive=YES；图标应是裁掉透明留白后的尺寸
// （抖音原图 75×49，字形仅约 33×30），仍是 75×49 说明裁白没生效。
static void DKProbeAppendPlusKey(NSMutableString *out) {
    UIVisualEffectView *key = DKGlassPlusKeyCurrent();
    [out appendFormat:@"拍摄圆键             = %@\n", DKProbeDesc(key)];
    if (!key) return;

    [out appendFormat:@"  frame=%@  hidden=%@  界面风格=%@\n",
     NSStringFromCGRect(key.frame), key.isHidden ? @"YES" : @"NO",
     DKProbeStyleName(key.traitCollection.userInterfaceStyle)];
    [out appendFormat:@"  effect             = %@  interactive=%@\n",
     NSStringFromClass([key.effect class]),
     [DKProbeValue(key.effect, @"interactive") boolValue] ? @"YES" : @"NO"];
    if (@available(iOS 26.0, *)) {
        [out appendFormat:@"  圆角有效半径       = %.1f（直径 %.1f 的一半即为正圆）\n",
         [key effectiveRadiusForCorner:UIRectCornerTopLeft], CGRectGetWidth(key.bounds)];
    }
    for (UIView *content in key.contentView.subviews) {
        UIImage *image = [content isKindOfClass:UIImageView.class] ? ((UIImageView *)content).image : nil;
        [out appendFormat:@"    %@ frame=%@ 图标=%@\n", NSStringFromClass(content.class),
         NSStringFromCGRect(content.frame), image ? NSStringFromCGSize(image.size) : @"-"];
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

// 首页/朋友页全屏的验证依据：撑高 tableView 后 cell 与 HUD 各自的高度。
static void DKProbeAppendFeed(NSMutableString *out) {
    UIWindow *window = DKDebugTargetWindow();
    NSArray<UIView *> *tables = DKProbeFindSubviews(window, @"AWEFeedTableView");
    [out appendFormat:@"AWEFeedTableView × %lu\n", (unsigned long)tables.count];

    Class hudCls = NSClassFromString(@"AWEPlayInteractionViewController");
    for (UIView *view in tables) {
        if (![view isKindOfClass:UITableView.class]) continue;
        UITableView *table = (UITableView *)view;

        [out appendFormat:@"  frame=%@  clips=%@  superview高=%.1f\n",
         NSStringFromCGRect(table.frame), table.clipsToBounds ? @"YES" : @"NO",
         CGRectGetHeight(table.superview.bounds)];
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
    [out appendFormat:@"HUD 钉位命中统计: %@\n", DKFeedFullscreenStats()];
}

#pragma mark - 报告

NSString *DKTabBarProbeReport(void) {
    NSMutableString *out = [NSMutableString string];
    [out appendString:@"===== DYKiller 底栏探针 =====\n"];
    [out appendFormat:@"采集时间   : %@\n", NSDate.date];
    [out appendFormat:@"系统       : iOS %@\n", UIDevice.currentDevice.systemVersion];

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

    [out appendString:@"\n----- feed 几何（首页/朋友全屏验证）-----\n"];
    DKProbeAppendFeed(out);

    [out appendString:@"\n----- 进度条容器（黑垫层诊断）-----\n"];
    DKProbeAppendProgressContainer(out, DKDebugTargetWindow());

    return out;
}
