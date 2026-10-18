//
//  DKTabBarProbe.xm
//  DYKiller
//
//  底栏探针：只读采集玻璃底栏、抖音自绘底栏与首页 feed 的运行时状态，随调试导出写入
//  probe/tabbar.txt。不改变任何状态。功能定型后整文件删除。
//

#import "DKContentFilter.h"
#import "DKDoubleTapComment.h"
#import "DKMediaSaveDiagnostics.h"
#import "DKTabBarProbe.h"
#import "DKPlusIcon.h"
#import "DKTabBarAppearance.h"
#import "DKInteractionAppearance.h"
#import "DKInfoAppearance.h"
#import "DKPlaybackClean.h"
#import "DKProgressAlwaysVisible.h"
#import "DKProgressTime.h"
#import "DKAdjustRange.h"
#import "DKTabBarBackdrop.h"
#import "DKTopBarAlpha.h"
#import "DKTabBarRemoval.h"
#import "DouyinHeaders.h"
#import "DKCommentGlass.h"
#import "DKCommentHeaderClean.h"
#import "DKGlassFlexView.h"
#import "DKGlassTabBar.h"
#import "DKKeys.h"
#import "DKShareSelectionHooks.h"
#import "DKUtils.h"
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

static NSString *DKProbeGestureStateName(UIGestureRecognizerState state) {
    switch (state) {
        case UIGestureRecognizerStatePossible:  return @"Possible";
        case UIGestureRecognizerStateBegan:     return @"Began";
        case UIGestureRecognizerStateChanged:   return @"Changed";
        case UIGestureRecognizerStateEnded:     return @"Ended";
        case UIGestureRecognizerStateCancelled: return @"Cancelled";
        case UIGestureRecognizerStateFailed:    return @"Failed";
        default: return [NSString stringWithFormat:@"%ld", (long)state];
    }
}

// 长按拖动切页归 UIKit 的悬浮底栏所有，但抖音在窗口上也挂了一条长按（视频面板），
// 窗口是底栏的祖先，两条会抢同一次触摸。长按拖动几次后导出，看 AWEMaskWindowLongPressGestureRecognizer
// 的 state：Failed 说明 UIKit 赢了、拖动正常；若它 Began/Changed 而底栏没反应，就是被它抢走了。
static void DKProbeAppendWindowGestures(NSMutableString *out, UIWindow *window) {
    [out appendFormat:@"窗口手势（%@）\n", window ? NSStringFromClass(window.class) : @"(无窗口)"];
    for (UIGestureRecognizer *gesture in window.gestureRecognizers) {
        NSString *duration = [gesture isKindOfClass:UILongPressGestureRecognizer.class]
            ? [NSString stringWithFormat:@"  minDuration=%.2f",
               ((UILongPressGestureRecognizer *)gesture).minimumPressDuration]
            : @"";
        [out appendFormat:@"  %@  enabled=%@  state=%@  delegate=%@%@\n",
         NSStringFromClass(gesture.class),
         gesture.isEnabled ? @"YES" : @"NO",
         DKProbeGestureStateName(gesture.state),
         gesture.delegate ? NSStringFromClass([gesture.delegate class]) : @"(nil)",
         duration];
    }
}

// 标题图自带颜色（AlwaysOriginal），选中与未选中各一张。回读每颗按钮实际显示的是哪一张，
// 用来判定悬浮 provider 认不认 selectedImage——认，选中与未选中才有浓度差。
static NSString *DKProbeTitleImageSource(UIView *imageView, UITabBar *bar) {
    UIImage *shown = [imageView isKindOfClass:UIImageView.class]
        ? ((UIImageView *)imageView).image : nil;
    if (!shown) return @"(无)";
    for (UITabBarItem *item in bar.items) {
        if (shown == item.selectedImage) return @"选中图";
        if (shown == item.image) return @"未选中图";
    }
    return @"其他";
}

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
    // tintColor 单打一行。材质档位不打——style 属性由 _style ivar 支持而 +effectWithStyle:
    // 不写它，读回恒为 0，无论装的是哪一档都会显示 Regular。
    UIVisualEffect *barEffect = bar.standardAppearance.backgroundEffect;
    [out appendFormat:@"  standardAppearance.backgroundEffect   = %@\n", barEffect ?: (id)@"(nil)"];
    [out appendFormat:@"  scrollEdgeAppearance.backgroundEffect = %@\n",
     bar.scrollEdgeAppearance.backgroundEffect ?: (id)@"(nil)"];
    [out appendFormat:@"  backgroundEffect.tintColor            = %@\n",
     DKProbeColorDesc(DKProbeValue(barEffect, @"tintColor"))];
    // 标题走的是 image 槽（模板图），title 恒为空，认人靠 accessibilityLabel。
    // badgeValue 为原生角标：nil=无，""=纯红点，其余为显示的数字或文案。
    [out appendFormat:@"  items=%lu  selectedItem=%@\n",
     (unsigned long)bar.items.count, bar.selectedItem.accessibilityLabel ?: @"(nil)"];
    for (UITabBarItem *item in bar.items) {
        [out appendFormat:@"    %@  未选中图=%@  选中图=%@  badgeValue=%@\n",
         item.accessibilityLabel ?: @"(nil)",
         item.image ? NSStringFromCGSize(item.image.size) : @"(无)",
         item.selectedImage ? NSStringFromCGSize(item.selectedImage.size) : @"(无)",
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
    // 胶囊清透与否只看这一行：appearance.backgroundEffect 是旧 API，悬浮 provider 不读，
    // 真正渲染胶囊的是 platter 自己的 glassEffect。
    [out appendFormat:@"  platter 玻璃       = %@\n", DKGlassPlatterGlassStatus()];
    // 胶囊宽度与整组居中的读数：目标与实测应一致，内缩应为「实测」。
    [out appendFormat:@"  胶囊几何           = %@\n", DKGlassGeometryStatus()];
    // 内容取色的唯一读数：极性判定、写下去的两个色、判定依据。
    [out appendFormat:@"  内容取色           = %@\n", DKGlassInkStatus()];
    // 悬浮底栏把每个 tab 画两遍：SelectedContentView 那份是选中样子（只在透镜内可见），
    // ContentView 那份是未选中样子。「显示的是」这一列是浓度差有没有生效的判据——
    // 两份必须分别取到选中图与未选中图。不打 tintColor：标题图走 AlwaysOriginal，
    // 那个值不参与绘制（未选中副本上它是 trait 推出来的，读了只会误导）。
    for (UIView *button in DKProbeFindSubviews(platter, @"_UITabButton")) {
        UIView *image = DKProbeFindSubview(button, @"ImageView");
        UIView *label = DKProbeFindSubview(button, @"Label");
        BOOL selectedCopy = [NSStringFromClass(button.superview.class)
                             containsString:@"SelectedContentView"];
        [out appendFormat:@"    %@ frame=%@  标题图 frame=%@  残留文字 frame=%@  显示的是=%@\n",
         selectedCopy ? @"选中副本" : @"未选中副本",
         NSStringFromCGRect(button.frame),
         image ? NSStringFromCGRect(image.frame) : @"(无)",
         label ? NSStringFromCGRect(label.frame) : @"(无)",
         DKProbeTitleImageSource(image, bar)];
    }

    [out appendFormat:@"  抖音 selectedIndex = %lu\n", (unsigned long)controller.selectedIndex];

    DKProbeAppendWindowGestures(out, bar.window);
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
    [out appendFormat:@"  effect             = %@  interactive=%@  tintColor=%@\n",
     effect ? NSStringFromClass(effect.class) : @"(nil)",
     [DKProbeValue(effect, @"interactive") boolValue] ? @"YES" : @"NO",
     DKProbeColorDesc(DKProbeValue(effect, @"tintColor"))];
    if (@available(iOS 26.0, *)) {
        [out appendFormat:@"  圆角有效半径       = %.1f（直径 %.1f 的一半即为正圆）\n",
         [key effectiveRadiusForCorner:UIRectCornerTopLeft], CGRectGetWidth(key.bounds)];
    }
    // 自定义图标走原色不模板化，内缩也换一档；这两个读数是它有没有生效的唯一凭据。
    // 内缩取 DKGlassPlusIconInset()，与实际布局同源，不在这里另写一个数字。
    UIImage *custom = DKPlusIconCustom();
    if (custom) {
        [out appendFormat:@"  自定义图标         = 已设置 %.0f×%.0f  ·  图标内缩 %.1f\n",
         custom.size.width * custom.scale, custom.size.height * custom.scale,
         DKGlassPlusIconInset()];
    } else {
        [out appendFormat:@"  自定义图标         = 未设置  ·  图标内缩 %.1f\n",
         DKGlassPlusIconInset()];
    }
}

// 所有活动窗口。浮层窗口盖在主窗口之上，而探针其余各节与导出的 view-tree 都只看主窗口——
// beta12「播放时进全屏评论区，评论内容全没了」就败在这个盲区：抖音的内嵌画中画
// AWEDPlayerPiPWindow（windowLevel 2000）被钉位撑成全屏盖住了评论区，主窗口那边一切正常。
static void DKProbeAppendWindows(NSMutableString *out) {
    Class playerCls = NSClassFromString(@"AWEDPlayerViewController_Merge");

    for (UIWindow *window in DKDebugActiveWindows()) {
        [out appendFormat:@"%@  level=%.0f%@  frame=%@  root=%@\n",
         DKProbeDesc(window), window.windowLevel,
         window.isKeyWindow ? @"（key）" : @"",
         NSStringFromCGRect(window.frame),
         window.rootViewController ? NSStringFromClass(window.rootViewController.class) : @"(nil)"];

        if (window.windowLevel == UIWindowLevelNormal) continue;

        // 浮层窗口里若也有视频容器，它不在几何作用域内，frame 该保持抖音自己的值。
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:window];
        while (queue.count > 0) {
            UIView *node = queue.firstObject;
            [queue removeObjectAtIndex:0];

            if (playerCls && [node.nextResponder isKindOfClass:playerCls]) {
                [out appendFormat:@"    内含播放器容器 = %@ frame=%@  父视图=%@（不在几何作用域）\n",
                 DKProbeDesc(node), NSStringFromCGRect(node.frame),
                 NSStringFromCGRect(node.superview.bounds)];
                break;
            }
            [queue addObjectsFromArray:node.subviews];
        }
    }

    // 闸门生效的判据是这一行与上面的窗口列表一起看：命中 > 0 且列表里没有 AWEDPlayerPiPWindow
    // 才算关住；命中恒为 0 说明钩子没被调用，签名得重找。
    [out appendFormat:@"%@\n", DKCommentPiPGateStats()];
    // 半屏评论区那份应是命中 > 0 且 alpha=1；全屏那份 alpha 应回到 0（抖音原生行为）。
    [out appendFormat:@"%@\n", DKCommentDanmakuStats()];
    // 全屏评论区下让视频播到结尾再导出。三个读数各答一个问题：补播有没有发（钩子层对不对）、
    // 期间有没有 pause（是被拒还是播起来又被停）、放行前闸门原本怎么答（这次放行需不需要）。
    [out appendFormat:@"%@\n", DKCommentLoopResumeStats()];
}

// 面板底色 = 槽位子树里**广度优先**第一个「满幅 + 不透明」的底色，**隐藏的也算**：抖音把它写在
// 头部关闭栏 / 时间提示栏那两块常年 alpha=0 的底板上，24 份导出（含未热更的）全都有，
// 是跨版本最稳的取色点。必须广度优先——深度优先会先撞进列表，取到里面那块与面板无关的满幅垫层。
//
// 这段判据只服务诊断：功能侧靠 AB 网关在源头关掉不透明绘制，不需要认底色。留在这里是为了
// 抖音改了网关方法名时，「残留面板底色」能立刻从 0 变成正数。
static UIColor *DKProbePanelBaseColor(UIView *slot) {
    NSMutableArray<UIView *> *level = [NSMutableArray arrayWithObject:slot];
    CGFloat width = CGRectGetWidth(slot.bounds);
    for (NSUInteger depth = 0; depth <= 14 && level.count > 0; depth++) {
        NSMutableArray<UIView *> *next = [NSMutableArray array];
        for (UIView *node in level) {
            UIColor *color = node.backgroundColor;
            if (node != slot && color && CGColorGetAlpha(color.CGColor) >= 0.99
                && fabs(CGRectGetWidth(node.bounds) - width) <= 1.0
                && CGRectGetHeight(node.bounds) >= 8.0) {
                return color;
            }
            for (UIView *sub in node.subviews) {
                if (![sub isKindOfClass:UIVisualEffectView.class]) [next addObject:sub];
            }
        }
        level = next;
    }
    return nil;
}

// 槽位子树里还剩多少块面板底色会盖住玻璃。热更新的不透明绘制把它刷进列表容器和每一个 UIKit
// 文字视图，网关拦住了这里就是 0——这一行是「文字带底色块 / 整块面板变色」的唯一判据。
// 只数等于面板底色的：徽章、tab 下划线这些自带彩色的不透明底本来就该留着。
// 面板底色没认出来（base 为 nil）时退化成数全部可见的不透明底色，好分辨是哪一种失败。
static BOOL DKProbeColorMatches(UIColor *color, UIColor *base) {
    CGFloat r1 = 0.0, g1 = 0.0, b1 = 0.0, a1 = 0.0, r2 = 0.0, g2 = 0.0, b2 = 0.0, a2 = 0.0;
    if (![color getRed:&r1 green:&g1 blue:&b1 alpha:&a1]) return NO;
    if (![base getRed:&r2 green:&g2 blue:&b2 alpha:&a2]) return NO;
    return fabs(r1 - r2) <= 1.0 / 255.0 && fabs(g1 - g2) <= 1.0 / 255.0 && fabs(b1 - b2) <= 1.0 / 255.0;
}

static void DKProbeCollectCovers(UIView *view, UIColor *base, NSMutableArray<UIView *> *out) {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:UIVisualEffectView.class]) continue;
        if (sub.hidden || sub.alpha < 0.01) continue;
        UIColor *color = sub.backgroundColor;
        if (color && CGColorGetAlpha(color.CGColor) >= 0.99
            && (!base || DKProbeColorMatches(color, base))) {
            [out addObject:sub];
        }
        DKProbeCollectCovers(sub, base, out);
    }
}

// 输入区里还剩几块「满幅不透明底」。艾特面板、表情面板及其 tab 条的白底都该被实现层清掉，
// 这里独立数一遍：>0 就是漏了哪一类，直接把类名和 frame 打出来。
// 与实现层不同，这里**不跳过** UIControl / UILabel / UIImageView——满幅不透明的控件同样会
// 在玻璃上糊出一块，漏进来要看得见。
static void DKProbeCollectFullWidthCovers(UIView *view, UIView *root, NSUInteger depth,
                                          NSMutableArray<UIView *> *out) {
    if (depth > 8) return;
    CGFloat width = CGRectGetWidth(root.bounds);
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:UIVisualEffectView.class]) continue;
        if (sub.hidden || sub.alpha < 0.01) continue;
        UIColor *color = sub.backgroundColor;
        if (color && CGColorGetAlpha(color.CGColor) >= 0.99
            && fabs(CGRectGetWidth(sub.bounds) - width) <= 1.0
            && CGRectGetHeight(sub.bounds) >= 8.0) {
            [out addObject:sub];
        }
        DKProbeCollectFullWidthCovers(sub, root, depth + 1, out);
    }
}

// 折叠提示条：抖音拿它那块不透明底盖住旧的时间 / 回复 label。实现层清底色的同时要替抖音把被
// 罩住的兄弟藏起来，两件事必须同进同出——这一行独立数三个量，任何一边落单都能立刻看出来：
// 「亮着的折叠条」「其中底色还不透明的」「被我们藏起来的兄弟」。
// 底色还不透明 > 0 → 玻璃上有白板；亮着的条数 > 0 而被藏兄弟 = 0 → 两层文字会叠在一起。
static void DKProbeCollectFoldRows(UIView *view, Class foldClass, NSUInteger depth,
                                   NSMutableArray<UIView *> *out) {
    if (depth > 4 || !foldClass) return;
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:foldClass]) { [out addObject:sub]; continue; }
        DKProbeCollectFoldRows(sub, foldClass, depth + 1, out);
    }
}

// 视图连同每一级祖先都可见。「移除评论区底栏」把整个输入栏容器压成 alpha 0，玻璃跟着看不见；
// 只看玻璃自己，会把「本来就不该让位」误报成「该让没让」。
static BOOL DKProbeChainVisible(UIView *view) {
    for (UIView *node = view; node; node = node.superview) {
        if (!node || node.hidden || node.alpha < 0.01) return NO;
    }
    return view != nil;
}

// 小表情栏靠「透出输入栏那块玻璃」取得同档观感，自己不挂玻璃。两条读数各答一个问题：
// 底色清了没有（清不掉就是一条黑杠），以及输入栏玻璃在不在它背后（不在就是一条原始视频）。
// 它在另一个窗口里，两个窗口都是满屏同原点，各自的窗口坐标可以直接比。
static void DKProbeAppendCommentEmoticonBar(NSMutableString *out, UIView *backdropGlass) {
    UIView *panel = DKCommentGlassCurrentEmoticonPanel();
    if (!panel || !panel.window) {
        [out appendString:@"小表情栏             = (不在屏)\n"];
        return;
    }

    CGRect panelRect = [panel convertRect:panel.bounds toView:nil];
    [out appendFormat:@"小表情栏             = %@  窗口矩形=%@  窗口=%@\n",
     DKProbeDesc(panel), NSStringFromCGRect(panelRect), NSStringFromClass(panel.window.class)];
    [out appendFormat:@"  底色               = %@\n", DKProbeColorDesc(panel.backgroundColor)];

    if (!backdropGlass.window || !DKProbeChainVisible(backdropGlass)) {
        [out appendString:@"  背后是输入栏玻璃   = 否（输入栏没有可见玻璃）\n"];
        return;
    }
    CGRect glassRect = [backdropGlass convertRect:backdropGlass.bounds toView:nil];
    [out appendFormat:@"  背后是输入栏玻璃   = %@  玻璃窗口矩形=%@\n",
     CGRectContainsRect(CGRectInset(glassRect, -0.5, -0.5), panelRect) ? @"是" : @"否",
     NSStringFromCGRect(glassRect)];
}

// 评论面板玻璃：验收配置目标、公开属性、flex 交互、场景 trait 与有效圆角。
// 只检查槽位现有子树，不访问 glass.contentView。
static void DKProbeAppendCommentGlass(NSMutableString *out) {
    BOOL enabled = DKPrefBool(DKKeyCommentGlass);
    BOOL clear = DKPrefBool(DKKeyCommentGlassClear);
    [out appendFormat:@"总开关               = %@  配置目标=%@  interactive=固定 YES\n",
     enabled ? @"开" : @"关", clear ? @"Clear" : @"Regular"];

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

    UIColor *base = DKProbePanelBaseColor(slot);
    [out appendFormat:@"  面板底色           = %@\n", DKProbeColorDesc(base)];
    [out appendFormat:@"  绘制优化网关       = 已拦截 %lu 次%@\n",
     (unsigned long)DKCommentGlassRenderOptimizeBlocks(),
     DKCommentGlassRenderOptimizeBlocks() == 0 ? @"（抖音没走这个网关，看下面的残留判断有没有被刷色）" : @""];

    NSMutableArray<UIView *> *covers = [NSMutableArray array];
    DKProbeCollectCovers(slot, base, covers);
    [out appendFormat:@"  残留面板底色       = %lu 处%@\n", (unsigned long)covers.count,
     base ? @"" : @"（面板底色没认出来，这里是全部可见不透明底色）"];
    for (NSUInteger i = 0; i < covers.count && i < 5; i++) {
        UIView *cover = covers[i];
        [out appendFormat:@"    %@ frame=%@ bg=%@\n",
         DKProbeDesc(cover), NSStringFromCGRect(cover.frame),
         DKProbeColorDesc(cover.backgroundColor)];
    }

    Class foldClass = NSClassFromString(@"AWECommentPanelListSwiftImpl.CommentFoldDisplayView");
    NSMutableArray<UIView *> *folds = [NSMutableArray array];
    DKProbeCollectFoldRows(slot, foldClass, 0, folds);
    if (!foldClass) {
        [out appendString:@"  折叠提示条         = （类不在，抖音改名了）\n"];
    } else if (folds.count > 0) {
        NSUInteger active = 0, opaque = 0, masked = 0;
        for (UIView *fold in folds) {
            if (fold.hidden || fold.alpha < 0.01) continue;
            active++;
            if (fold.backgroundColor
                && CGColorGetAlpha(fold.backgroundColor.CGColor) >= 0.99) opaque++;
            for (UIView *sibling in fold.superview.subviews) {
                if (sibling != fold && sibling.hidden
                    && CGRectContainsRect(fold.frame, sibling.frame)) masked++;
            }
        }
        [out appendFormat:@"  折叠提示条         = 在场 %lu 条  亮着 %lu 条  底色仍不透明 %lu 条"
                          @"  被藏兄弟 %lu 个\n",
         (unsigned long)folds.count, (unsigned long)active,
         (unsigned long)opaque, (unsigned long)masked];
    } else {
        [out appendString:@"  折叠提示条         = 本页没有\n"];
    }

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
    [out appendFormat:@"  effect             = %@  interactive=%@  tintColor=%@\n",
     effect ? NSStringFromClass(effect.class) : @"(nil)",
     [DKProbeValue(effect, @"interactive") boolValue] ? @"YES" : @"NO",
     DKProbeColorDesc(DKProbeValue(effect, @"tintColor"))];
    // iOS 27 的私有描述可能把公开 Clear 构造也打成 regular，只作原始诊断、不作档位判据。
    [out appendFormat:@"  UIKit 私有诊断    = %@\n", DKProbeValue(effect, @"glass") ?: @"(读不到)"];
    // interactive 是否真的落地，看两条：effect 上写没写、系统有没有据此挂上 flex 交互。
    // 「重定向目标」为 nil 或指回玻璃自己，说明 -_flexInteractionGestureView 的重写没被 UIKit 读到。
    [out appendFormat:@"  flex 交互已挂      = %@  重定向目标=%@\n",
     DKGlassFlexInstalled(glass) ? @"是" : @"否",
     DKProbeDesc(DKGlassFlexResolvedSource(glass))];
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

    // 整个输入区（底色槽、艾特面板、表情面板）共用挂在容器上的这一块玻璃，与主面板玻璃上下拼接。
    // 「主面板让位」用「两块玻璃的边到底重不重合」量，不复用实现里的判据：「工具栏透出评论行」
    // 和「面板中间一条没有玻璃」在观感上分不开，但在这里一个是「叠了 N pt」、一个是「缺 N pt」。
    UIView *backdrop = DKCommentGlassCurrentInputContainer();
    UIView *backdropGlass = backdrop.subviews.firstObject;
    if (![backdropGlass isKindOfClass:UIVisualEffectView.class]) backdropGlass = nil;
    UIVisualEffect *backdropEffect = ((UIVisualEffectView *)backdropGlass).effect;

    [out appendFormat:@"输入栏容器           = %@  frame=%@  bg=%@\n",
     DKProbeDesc(backdrop), NSStringFromCGRect(backdrop.frame),
     DKProbeColorDesc(backdrop.backgroundColor)];
    if (backdrop) {
        [out appendFormat:@"  玻璃层             = %@  frame=%@\n",
         DKProbeDesc(backdropGlass), NSStringFromCGRect(backdropGlass.frame)];
        [out appendFormat:@"  effect             = %@  interactive=%@  tintColor=%@\n",
         backdropEffect ? NSStringFromClass(backdropEffect.class) : @"(nil)",
         [DKProbeValue(backdropEffect, @"interactive") boolValue] ? @"YES" : @"NO",
         DKProbeColorDesc(DKProbeValue(backdropEffect, @"tintColor"))];
        [out appendFormat:@"  flex 交互已挂      = %@  重定向目标=%@\n",
         DKGlassFlexInstalled(backdropGlass) ? @"是" : @"否",
         DKProbeDesc(DKGlassFlexResolvedSource(backdropGlass))];
        [out appendFormat:@"  界面风格           = %@（override=%@）\n",
         DKProbeStyleName(backdropGlass.traitCollection.userInterfaceStyle),
         DKProbeStyleName(backdropGlass.overrideUserInterfaceStyle)];
        [out appendFormat:@"  尺寸跟随           = %@\n",
         backdropGlass && CGSizeEqualToSize(backdropGlass.bounds.size, backdrop.bounds.size)
             ? @"是" : @"否"];
        if (@available(iOS 26.0, *)) {
            // 艾特 / 表情面板把输入区顶出主面板时顶边是压在视频上的自由边，该有 8pt 圆角；
            // 贴着主面板玻璃时必须是 0，否则两角会露出原始视频。
            UIVisualEffectView *bar = (UIVisualEffectView *)backdropGlass;
            [out appendFormat:@"  顶部有效半径       = 左上 %.1f  右上 %.1f\n",
             [bar effectiveRadiusForCorner:UIRectCornerTopLeft],
             [bar effectiveRadiusForCorner:UIRectCornerTopRight]];
        }
        // 艾特面板、表情面板及其 tab 条的白底都要被满幅清扫清掉；>0 就是漏了。
        NSMutableArray<UIView *> *inputCovers = [NSMutableArray array];
        DKProbeCollectFullWidthCovers(backdrop, backdrop, 0, inputCovers);
        [out appendFormat:@"  容器内残留不透明底 = %lu 处\n", (unsigned long)inputCovers.count];
        for (NSUInteger i = 0; i < inputCovers.count && i < 5; i++) {
            UIView *cover = inputCovers[i];
            [out appendFormat:@"    %@ frame=%@ bg=%@\n",
             DKProbeDesc(cover), NSStringFromCGRect(cover.frame),
             DKProbeColorDesc(cover.backgroundColor)];
        }
    }

    BOOL barCovers = backdropEffect && backdropGlass.window == slot.window
        && DKProbeChainVisible(backdropGlass);
    CGRect barCover = barCovers ? [backdropGlass convertRect:backdropGlass.bounds toView:slot]
                                : CGRectZero;
    if (barCovers && CGRectGetMinY(barCover) <= 0.5) {
        // 艾特 / 表情面板把输入区顶到了主面板槽位之上：整块槽位都被盖住，主面板玻璃应当整块收起。
        [out appendFormat:@"主面板让位           = 整块被盖住（输入栏玻璃顶边 %.1f）  面板玻璃已隐藏？= %@\n",
         CGRectGetMinY(barCover), glass.isHidden ? @"是" : @"否（这一段是两层玻璃）"];
    } else if (!barCovers) {
        [out appendFormat:@"主面板让位           = 不该让（%@）  满幅？= %@\n",
         backdropEffect ? @"输入栏不可见" : @"输入栏没有可用玻璃",
         fabs(CGRectGetHeight(glass.frame) - CGRectGetHeight(slot.bounds)) <= 0.5 ? @"是" : @"否"];
    } else {
        CGRect cover = barCover;
        CGFloat overlap = CGRectGetMaxY(glass.frame) - CGRectGetMinY(cover);
        NSString *verdict = fabs(overlap) <= 0.5 ? @"是"
            : (overlap > 0 ? [NSString stringWithFormat:@"否，叠了 %.1fpt（这一段两层玻璃，一块亮度台阶）", overlap]
                           : [NSString stringWithFormat:@"否，缺 %.1fpt（这一段没有玻璃，露原始视频）", -overlap]);
        [out appendFormat:@"主面板让位           = %@%@\n", verdict,
         glass.isHidden ? @"（但面板玻璃是隐藏的，这一段没有玻璃）" : @""];
        [out appendFormat:@"  面板玻璃底边       = %.1f  输入栏玻璃顶边 = %.1f  槽位高 = %.1f\n",
         CGRectGetMaxY(glass.frame), CGRectGetMinY(cover), CGRectGetHeight(slot.bounds)];
    }

    DKProbeAppendCommentEmoticonBar(out, backdropGlass);

    // 输入框胶囊会在常驻态与回复态之间改变尺寸，探针直接核对玻璃是否仍与槽位等大。
    UIView *field = DKCommentGlassCurrentField();
    if (!field) return;
    UIView *fieldGlass = field.subviews.firstObject;
    UIVisualEffect *fieldEffect = [fieldGlass isKindOfClass:UIVisualEffectView.class]
        ? ((UIVisualEffectView *)fieldGlass).effect : nil;
    [out appendFormat:@"输入框槽位           = %@  frame=%@\n",
     DKProbeDesc(field), NSStringFromCGRect(field.frame)];
    [out appendFormat:@"  玻璃层             = %@  frame=%@\n",
     DKProbeDesc(fieldGlass), NSStringFromCGRect(fieldGlass.frame)];
    [out appendFormat:@"  effect             = %@  interactive=%@  tintColor=%@\n",
     fieldEffect ? NSStringFromClass(fieldEffect.class) : @"(nil)",
     [DKProbeValue(fieldEffect, @"interactive") boolValue] ? @"YES" : @"NO",
     DKProbeColorDesc(DKProbeValue(fieldEffect, @"tintColor"))];
    [out appendFormat:@"  flex 交互已挂      = %@  重定向目标=%@\n",
     DKGlassFlexInstalled(fieldGlass) ? @"是" : @"否",
     DKProbeDesc(DKGlassFlexResolvedSource(fieldGlass))];
    if ([fieldGlass isKindOfClass:UIVisualEffectView.class]) {
        UIVisualEffectView *fieldEffectView = (UIVisualEffectView *)fieldGlass;
        [out appendFormat:@"  界面风格           = %@（override=%@）\n",
         DKProbeStyleName(fieldEffectView.traitCollection.userInterfaceStyle),
         DKProbeStyleName(fieldEffectView.overrideUserInterfaceStyle)];
    }
    [out appendFormat:@"  尺寸跟随           = %@\n",
     [fieldGlass isKindOfClass:UIVisualEffectView.class]
         && CGSizeEqualToSize(fieldGlass.bounds.size, field.bounds.size) ? @"是" : @"否"];
}

// 评论面板缩放（半屏 → 全屏）。验收「玻璃背后是不是视频那一页」，判据是两条同时成立：
// 视频子树重新进入层级 + 全屏容器底色已清。只满足一条都看不见视频，报告要能区分是哪一条没成。
// 背后 HUD 打原始读数不下结论：抖音自己在评论态藏的是 HUD 里的元素，根视图本身并不隐藏。
static void DKProbeAppendCommentZoom(NSMutableString *out) {
    Class fullCls = NSClassFromString(@"AWECommentFullScreenContainerViewController");
    Class playerCls = NSClassFromString(@"AWEDPlayerViewController_Merge");
    Class hudCls = NSClassFromString(@"AWEPlayInteractionViewController");

    UIView *fullView = nil;
    UIView *playerView = nil;
    UIView *hudView = nil;
    NSMutableArray<UIView *> *queue =
        [NSMutableArray arrayWithObject:DKDebugTargetWindow()];
    while (queue.count > 0) {
        UIView *node = queue.firstObject;
        [queue removeObjectAtIndex:0];

        UIResponder *owner = node.nextResponder;
        if (!fullView && fullCls && [owner isKindOfClass:fullCls]) fullView = node;
        if (!playerView && playerCls && [owner isKindOfClass:playerCls]) playerView = node;
        if (!hudView && hudCls && [owner isKindOfClass:hudCls]) hudView = node;
        [queue addObjectsFromArray:node.subviews];
    }

    [out appendFormat:@"全屏评论容器     = %@\n", DKProbeDesc(fullView.nextResponder)];
    if (fullView) {
        UIViewController *full = (UIViewController *)fullView.nextResponder;
        UIColor *color = fullView.backgroundColor;
        BOOL cleared = !color || CGColorGetAlpha(color.CGColor) < 0.01;

        [out appendFormat:@"  frame=%@  clips=%@\n",
         NSStringFromCGRect(fullView.frame), fullView.clipsToBounds ? @"YES" : @"NO"];
        [out appendFormat:@"  容器底色         = %@%@\n", DKProbeColorDesc(color),
         cleared ? @"（已清）" : @"（未接管，背后被它挡住）"];

        NSMutableArray<NSString *> *children = [NSMutableArray array];
        for (UIViewController *child in full.childViewControllers) {
            [children addObject:NSStringFromClass(child.class)];
        }
        [out appendFormat:@"  子控制器         = %@\n",
         children.count ? [children componentsJoinedByString:@"、"] : @"(无)"];

        UIView *slot = DKCommentGlassCurrentSlot();
        [out appendFormat:@"  面板槽位在其内   = %@  槽位 frame=%@\n",
         (slot && [slot isDescendantOfView:fullView]) ? @"是" : @"否",
         slot ? NSStringFromCGRect(slot.frame) : @"—"];

        [out appendFormat:@"  背后垫层         = %@\n",
         (playerView && cleared) ? @"已垫回（玻璃背后是视频那一页）"
            : (playerView ? @"视频在场但容器底色没清" : @"视频子树不在层级里")];
        [out appendFormat:@"  背后 HUD         = %@\n",
         hudView ? [NSString stringWithFormat:@"%@ frame=%@ hidden=%@ alpha=%.2f",
                    DKProbeDesc(hudView), NSStringFromCGRect(hudView.frame),
                    hudView.isHidden ? @"YES" : @"NO", hudView.alpha]
                 : @"(不在层级里)"];
    }
    [out appendFormat:@"%@\n", DKVideoContainerMoveStats()];
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
        id label = DKProbeValue(DKProbeValue(button, @"innerView"), @"label");
        NSString *title = DKProbeValue(label, @"text");
        // 文字色是内容取色的判据输入：抖音每页重算它，首页白、浅色列表页近黑。
        // tabID 是「移除底栏项目」认人的依据；「本插件移除」表示 hidden 由该功能写入。
        [out appendFormat:@"  %@ 文字=%@ 文字色=%@ hidden=%@%@ type=%@ tabID=%@ validIndex=%@ frame=%@\n",
         NSStringFromClass([button class]), title ?: view.accessibilityLabel ?: @"(nil)",
         DKProbeColorDesc(DKProbeValue(label, @"textColor")),
         view.isHidden ? @"YES" : @"NO", DKTabBarRemovalHides(button) ? @"（本插件移除）" : @"",
         DKProbeValue(button, @"type") ?: @"?", DKTabBarButtonTabID(button) ?: @"(nil)",
         DKProbeValue(button, @"validIndex") ?: @"?",
         view ? NSStringFromCGRect(view.frame) : @"-"];

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

static void DKProbeAppendGlassLine(NSMutableString *out, NSString *label, UIView *host) {
    UIView *glass = nil;
    for (UIView *sub in host.subviews) {
        if ([sub isKindOfClass:DKGlassFlexView.class]) {
            glass = sub;
            break;
        }
    }
    UIVisualEffect *effect = [glass isKindOfClass:UIVisualEffectView.class]
        ? ((UIVisualEffectView *)glass).effect : nil;
    [out appendFormat:@"%@ = %@  glass=%@  effect=%@  tint=%@  跟随=%@\n",
     label, DKProbeDesc(host),
     glass ? NSStringFromCGRect(glass.frame) : @"(无)",
     effect ? NSStringFromClass(effect.class) : @"(nil)",
     DKProbeColorDesc(DKProbeValue(effect, @"tintColor")),
     (glass && CGSizeEqualToSize(glass.bounds.size, host.bounds.size)) ? @"是" : @"否"];
}

static void DKProbeAppendShareInput(NSMutableString *out) {
    [out appendFormat:@"%@\n", DKShareSelectionDiagnostics()];
    Class overlayCls = NSClassFromString(@"AWEIMShareImpl.ShareAdditionTextView");
    Class toolbarCls = NSClassFromString(@"AWEIMShareInputEmoticonToolBarView");
    UIView *overlay = nil;
    UIView *toolbar = nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:DKDebugTargetWindow()];
    while (queue.count > 0) {
        UIView *node = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (overlayCls && !overlay && [node isKindOfClass:overlayCls]) overlay = node;
        if (toolbarCls && !toolbar && [node isKindOfClass:toolbarCls]) toolbar = node;
        if (overlay && toolbar) break;
        [queue addObjectsFromArray:node.subviews];
    }

    [out appendFormat:@"覆盖层             = %@  hidden=%@  bg=%@\n",
     DKProbeDesc(overlay), overlay.hidden ? @"YES" : @"NO",
     DKProbeColorDesc(overlay.backgroundColor)];
    if (overlay) {
        UIView *host = [overlay isKindOfClass:UIVisualEffectView.class]
            ? ((UIVisualEffectView *)overlay).contentView : overlay;
        DKProbeAppendGlassLine(out, @"  覆盖层玻璃       ", host);
        if ([overlay isKindOfClass:UIVisualEffectView.class]) {
            [out appendFormat:@"  原生 effect      = %@\n",
             ((UIVisualEffectView *)overlay).effect
                 ? NSStringFromClass(((UIVisualEffectView *)overlay).effect.class) : @"(nil)"];
        }
        for (UIView *sub in host.subviews) {
            CGFloat height = CGRectGetHeight(sub.bounds);
            if (height > 0.1 && height < 1.5 && CGRectGetWidth(sub.bounds) >= 200.0) {
                [out appendFormat:@"  顶部分割线       = hidden=%@ frame=%@\n",
                 sub.hidden ? @"YES" : @"NO", NSStringFromCGRect(sub.frame)];
                break;
            }
        }
        NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:overlay];
        while (stack.count > 0) {
            UIView *node = stack.lastObject;
            [stack removeLastObject];
            NSString *className = NSStringFromClass(node.class);
            BOOL semanticSendButton = [className containsString:@"ShareAdditionTextButton"];
            BOOL titleSendButton = [node isKindOfClass:UIControl.class]
                && CGRectGetHeight(node.bounds) >= 36.0;
            if (semanticSendButton || titleSendButton) {
                NSString *title = DKProbeValue(node, @"currentTitle")
                    ?: node.accessibilityLabel ?: @"";
                if (semanticSendButton || [title containsString:@"发送"]) {
                    NSString *label = title.length ? title : @"ShareAdditionTextButton";
                    DKProbeAppendGlassLine(out,
                        [NSString stringWithFormat:@"  按钮「%@」     ", label], node);
                    [out appendFormat:@"    frame=%@  UIButton=%@  currentTitle=%@  bg=%@\n",
                        NSStringFromCGRect(node.frame),
                        [node isKindOfClass:UIButton.class] ? @"YES" : @"NO",
                        DKProbeValue(node, @"currentTitle") ?: @"(nil)",
                        DKProbeColorDesc(node.backgroundColor)];
                }
            }
            [stack addObjectsFromArray:node.subviews];
        }
    }

    [out appendFormat:@"表情栏             = %@  hidden=%@\n",
     DKProbeDesc(toolbar), toolbar.hidden ? @"YES" : @"NO"];
    if (toolbar) {
        UIView *slot = DKProbeValue(toolbar, @"inputControlBar");
        if (!slot) {
            for (UIView *sub in toolbar.subviews) {
                CGFloat height = CGRectGetHeight(sub.bounds);
                if (height >= 32.0 && height <= 48.0) { slot = sub; break; }
            }
        }
        if (slot) DKProbeAppendGlassLine(out, @"  控制条玻璃       ", slot);
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
            [out appendFormat:@"  容器钉位达标？   = %@\n",
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
        CGFloat height = CGRectGetHeight(table.frame);
        NSNumber *original = DKVideoFeedTableOriginalHeight(table);
        NSString *stretchStatus;
        if (!DKVideoFullscreenOn()) {
            stretchStatus = original ? @"否（功能关闭，原高标记待清除）" : @"否（功能关闭）";
        } else if (container <= 0.0) {
            stretchStatus = @"待判定（父容器尺寸未就绪）";
        } else if (original) {
            stretchStatus = fabs(height - container) <= 0.5
                ? @"是" : @"否（已记录原高，但表高与容器不一致）";
        } else {
            stretchStatus = height < container - 0.5
                ? @"否（容器更高，本该撑高）" : @"否（本就满高，不需要撑）";
        }

        [out appendFormat:@"  %@  frame=%@  clips=%@  superview高=%.1f\n",
         DKProbeDesc(table), NSStringFromCGRect(table.frame),
         table.clipsToBounds ? @"YES" : @"NO", container];
        [out appendFormat:@"  撑高原高=%@  已撑高？= %@\n",
         original ? [NSString stringWithFormat:@"%.1f", original.doubleValue] : @"(未记录)",
         stretchStatus];
        [out appendFormat:@"  contentOffset=%@  contentSize=%@\n",
         NSStringFromCGPoint(table.contentOffset), NSStringFromCGSize(table.contentSize)];

        for (UITableViewCell *cell in table.visibleCells) {
            NSIndexPath *indexPath = [table indexPathForCell:cell];
            CGRect rowRect = indexPath ? [table rectForRowAtIndexPath:indexPath] : CGRectNull;
            CGRect windowRect = [cell convertRect:cell.bounds toView:table.window];
            BOOL pageSized = fabs(CGRectGetHeight(cell.bounds) - height) <= 0.5;
            BOOL contentSized = fabs(CGRectGetHeight(cell.contentView.bounds) - height) <= 0.5;
            [out appendFormat:@"  cell frame=%@  contentView高=%.1f\n",
             NSStringFromCGRect(cell.frame), CGRectGetHeight(cell.contentView.bounds)];
            [out appendFormat:@"    indexPath=%@  原生行矩形=%@  窗口矩形=%@  Cell/内容满高=%@/%@\n",
             indexPath ?: (id)@"(未绑定)",
             CGRectIsNull(rowRect) ? @"(未绑定)" : NSStringFromCGRect(rowRect),
             NSStringFromCGRect(windowRect), pageSized ? @"是" : @"否", contentSized ? @"是" : @"否"];
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
    [out appendFormat:@"详情行高命中统计: %@\n", DKVideoDetailTableStats()];
}

// 直播预览的 chrome 挂在 4 层容器的高度上，表被撑高后整体下移一个底栏高，靠 transform 抬回。
// 逐个容器给出位移量、具名槽位与抬升目标——「抬升目标 × 0」就是贴底签名没命中。
static void DKProbeAppendLivePreview(NSMutableString *out) {
    Class containerCls = NSClassFromString(@"AWELivePreStream4LayerContainerView");
    NSMutableArray<UIView *> *containers = [NSMutableArray array];
    NSMutableArray<UIView *> *pending =
        [NSMutableArray arrayWithObject:DKDebugTargetWindow()];
    while (pending.count > 0) {
        UIView *node = pending.firstObject;
        [pending removeObjectAtIndex:0];
        if (containerCls && [node isKindOfClass:containerCls]) {
            [containers addObject:node];
            continue;
        }
        [pending addObjectsFromArray:node.subviews];
    }

    if (containers.count == 0) {
        [out appendString:@"4 层容器         = (本页没有直播预览)\n"];
        return;
    }

    for (UIView *container in containers) {
        [out appendFormat:@"%@\n%@", DKProbeDesc(container), DKLiveChromeStats(container)];
    }
    // 两个同步点分开计：冷启动第一个直播的抬升必然出自槽位那一处，它恒为 0 就是那条路没走通。
    [out appendFormat:@"抬升命中统计: %@\n", DKLiveChromeLiftStats()];
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
    // 窗口这一节排在最前：其余各节与导出的 view-tree / 截图都只看主窗口，浮层窗口是盲区。
    [out appendString:@"\n----- 窗口 -----\n"];
    DKProbeAppendWindows(out);

    [out appendString:@"\n----- 内容过滤 -----\n"];
    [out appendString:DKContentFilterDiagnostics()];

    [out appendString:@"\n----- 双击打开评论区 -----\n"];
    [out appendString:DKDoubleTapCommentDiagnostics()];

    [out appendString:@"\n----- 媒体保存 -----\n"];
    [out appendString:DKMediaSaveDiagnostics()];

    [out appendString:@"\n----- 评论面板玻璃 -----\n"];
    DKProbeAppendCommentGlass(out);

    [out appendString:@"\n----- 评论面板缩放 -----\n"];
    DKProbeAppendCommentZoom(out);

    [out appendString:@"\n----- 评论区顶部 -----\n"];
    [out appendString:DKCommentHeaderStatus()];

    [out appendString:@"\n----- 视频冻结 -----\n"];
    DKProbeAppendFrozenMedia(out);

    [out appendString:@"\n----- 图文 -----\n"];
    DKProbeAppendRichContent(out);

    // 视频表这一节必须在「没找到 UITabBarController 就返回」之前：其他用户主页、搜索页这些
    // 被 push 出来的页面正是最需要看表撑高结论的地方，挡在后面就永远采不到。
    [out appendString:@"\n----- 视频表（撑高验证）-----\n"];
    DKProbeAppendFeed(out);

    [out appendString:@"\n----- 直播预览 -----\n"];
    DKProbeAppendLivePreview(out);

    [out appendString:@"\n----- 进度条容器（黑垫层诊断）-----\n"];
    DKProbeAppendProgressContainer(out, DKDebugTargetWindow());

    [out appendString:@"\n----- 进度条常显 -----\n"];
    [out appendString:DKProgressAlwaysVisibleStatus()];

    [out appendString:@"\n----- 显示视频时长 -----\n"];
    [out appendString:DKProgressTimeStatus()];

    [out appendString:@"\n----- 分享面板输入 -----\n"];
    DKProbeAppendShareInput(out);

    [out appendString:@"\n----- 互动按钮外观 -----\n"];
    [out appendString:DKInteractionAppearanceStatus()];

    [out appendString:@"\n----- 昵称文案外观 -----\n"];
    [out appendString:DKInfoAppearanceStatus()];

    [out appendString:@"\n----- 播放页精简 -----\n"];
    [out appendString:DKPlaybackCleanStatus()];

    [out appendString:@"\n----- 顶栏透明度 -----\n"];
    [out appendString:DKTopBarAlphaStatus()];

    [out appendString:@"\n----- 调整范围 -----\n"];
    [out appendString:DKAdjustRangeStatus()];

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

    // 玻璃底栏关闭时，视频页底栏背景是否让位，以及三个判据输入。
    [out appendString:@"\n----- 底栏背景让位 -----\n"];
    [out appendString:DKTabBarBackdropStatus()];

    // 外观定制：各项原文、自定义文字与覆盖层状态，判断改字与图标模式是否生效。
    [out appendString:@"\n----- 外观定制 -----\n"];
    [out appendString:DKTabBarAppearanceStatus()];

    return out;
}
