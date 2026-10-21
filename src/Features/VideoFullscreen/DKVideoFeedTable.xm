// 视频表撑高与 HUD 钉位：首页和详情页共用几何判据。
// 原生控制器布局前后分别同步子表，写入入口处理宿主主动改高。
// HUD 写入时取已保存的表原高；尚未入树的 HUD 在布局后同步。

#import "DKVideoFeedTable.h"
#import "DKVideoFullscreen.h"
#import "DouyinHeaders.h"
#import <objc/runtime.h>
#import <math.h>

// 覆盖 @3x 像素对齐带来的亚像素漂移。
static const CGFloat kDKFeedTolerance = 0.5;
// 表高至少要到容器的这个比例才认作「已排好、只差一个底栏」，排除布局早期的半成品尺寸。
static const CGFloat kDKFeedMinHeightRatio = 0.5;
// 从 HUD 往上找视频表的最大层数（图文内容多两层容器，取 8 有余量）。
static const NSUInteger kDKFeedAncestorLimit = 8;

// 撑高前的表高。挂在表上，既是还原依据，也是 HUD 的钉位目标。
static char kDKFeedOriginalHeightKey;
static char kDKPadFeedBottomReserveKey;
// 所有撑高过的表（弱引用），供关闭开关时立即还原。多页并存时可能不止一张。
static NSHashTable<UITableView *> *gStretchedTables = nil;

#pragma mark - 命中统计

// HUD 写入时拦截与布局后同步分别计数。
static NSUInteger gHitSetFrame = 0;
static NSUInteger gHitFallback = 0;
// 表写入与控制器布局分别计数。
static NSUInteger gHitTableSetFrame = 0;
// 控制器布局完成后补正已进入视图树的子表，并分别统计首页与详情入口。
static NSUInteger gHitTableLayout = 0;
struct DKFeedTableLayoutStats {
    NSUInteger runs;
    NSUInteger adjustments;
};
static DKFeedTableLayoutStats gFeedTableLayoutStats = {};
static DKFeedTableLayoutStats gDetailTableLayoutStats = {};
static DKFeedTableLayoutStats gFeedTableLayoutPreStats = {};
static DKFeedTableLayoutStats gDetailTableLayoutPreStats = {};

NSString *DKVideoFeedTableStats(void) {
    return [NSString stringWithFormat:
            @"HUD setFrame=%lu  HUD 布局后兜底=%lu  表 setFrame补正=%lu  表控制器布局补正=%lu  "
             "首页控制器布局 跑=%lu 补正=%lu  详情控制器布局 跑=%lu 补正=%lu  "
             "首页原生布局前 跑=%lu 补正=%lu  详情原生布局前 跑=%lu 补正=%lu  %@",
            (unsigned long)gHitSetFrame,
            (unsigned long)gHitFallback,
            (unsigned long)gHitTableSetFrame,
            (unsigned long)gHitTableLayout,
            (unsigned long)gFeedTableLayoutStats.runs,
            (unsigned long)gFeedTableLayoutStats.adjustments,
            (unsigned long)gDetailTableLayoutStats.runs,
            (unsigned long)gDetailTableLayoutStats.adjustments,
            (unsigned long)gFeedTableLayoutPreStats.runs,
            (unsigned long)gFeedTableLayoutPreStats.adjustments,
            (unsigned long)gDetailTableLayoutPreStats.runs,
            (unsigned long)gDetailTableLayoutPreStats.adjustments,
            DKVideoPadFeedTableStats()];
}

#pragma mark - 目标判定

Class DKVideoFeedTableClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(@"AWEFeedDataSafeTableView"); });
    return cls;
}

UIView *DKFeedTableForView(UIView *view) {
    Class tableCls = DKVideoFeedTableClass();
    if (!tableCls) return nil;

    UIView *ancestor = view.superview;
    for (NSUInteger i = 0; ancestor && i < kDKFeedAncestorLimit; i++, ancestor = ancestor.superview) {
        if ([ancestor isKindOfClass:tableCls]) return ancestor;
    }
    return nil;
}

NSNumber *DKVideoFeedTableOriginalHeight(UIView *table) {
    NSNumber *original = objc_getAssociatedObject(table, &kDKFeedOriginalHeightKey);
    if (original && UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        NSNumber *reserve = objc_getAssociatedObject(table, &kDKPadFeedBottomReserveKey);
        CGFloat full = CGRectGetHeight(table.superview ? table.superview.bounds : table.bounds);
        CGFloat native = full - reserve.doubleValue;
        if (reserve && isfinite(native) && native > 0.0) return @(native);
    }
    return original;
}

// 该视图所在视频表撑高前的高度，也就是 HUD 的钉位目标；不在撑高作用域内返回 0。
static CGFloat DKFeedOriginalHeight(UIView *view) {
    if (!DKVideoFullscreenOn()) return 0.0;
    return DKVideoFeedTableOriginalHeight(DKFeedTableForView(view)).doubleValue;
}

#pragma mark - 撑高视频表

// 共享撑高规则同时供表写入与控制器布局入口调用。首页表自己实现 setFrame:，
// 详情表继承基类的写入入口；已达到目标高度的写入直接放行。
static CGRect DKFeedTableAdjustFrameToHeight(UITableView *table, CGRect frame, CGFloat target) {
    if (!DKVideoFullscreenOn()) {
        // 关闭后一律放行，抖音写什么就是什么；标记清掉以免 HUD 继续被钉。
        objc_setAssociatedObject(table, &kDKFeedOriginalHeightKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(table, &kDKPadFeedBottomReserveKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return CGRectNull;
    }

    CGFloat current = CGRectGetHeight(frame);
    // 容器不比来意的高度更高 → 这张表没被底栏压缩过（搜索页、好友聊天页就是这种），不在作用域内；
    // 高度不到容器一半 → 布局早期的半成品，记下它会把 HUD 钉到错误的位置。
    if (!isfinite(target) || !isfinite(current)
        || target <= 0.0
        || current >= target - kDKFeedTolerance
        || current < target * kDKFeedMinHeightRatio) {
        return CGRectNull;
    }

    if (!objc_getAssociatedObject(table, &kDKFeedOriginalHeightKey)) {
        objc_setAssociatedObject(table, &kDKFeedOriginalHeightKey, @(current),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gStretchedTables addObject:table];
        // iPad 保存底部预留，HUD 和关闭恢复按当前容器高度求原生高度。
        if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            objc_setAssociatedObject(table, &kDKPadFeedBottomReserveKey, @(target - current),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    frame.size.height = target;
    return frame;
}

CGRect DKVideoFeedTableAdjustFrame(UITableView *table, CGRect frame) {
    return DKFeedTableAdjustFrameToHeight(table, frame,
        CGRectGetHeight(table.superview.bounds));
}

// 详情表在建行前可能尚未挂入父视图，此时取已加载控制器根视图的高度。
// 首次写表尺寸之前记录真实原高，供首个 Cell 的 HUD 钉位使用。
BOOL DKVideoFeedTablePrepareForController(UIViewController *controller, UITableView *table) {
    if (!DKVideoFullscreenOn() || !NSThread.isMainThread || !table) return NO;
    Class tableClass = DKVideoFeedTableClass();
    UIView *root = controller.viewIfLoaded;
    if (!tableClass || ![table isKindOfClass:tableClass] || !root) return NO;
    UIWindow *window = table.window ?: root.window;
    if (window && window.windowLevel != UIWindowLevelNormal) return NO;
    if (table.superview && ![table isDescendantOfView:root]) return NO;
    if (!CGAffineTransformIsIdentity(table.transform)) return NO;

    CGFloat target = table.superview
        ? CGRectGetHeight(table.superview.bounds) : CGRectGetHeight(root.bounds);
    CGRect adjusted = DKFeedTableAdjustFrameToHeight(table, table.frame, target);
    if (CGRectIsNull(adjusted)) return NO;
    table.frame = adjusted;
    return YES;
}

// 在写入时就改成满高：抖音把表高改回原值（如关闭评论区）的那一刻即被顶回去，
// 不必等下一次布局。事后在 layoutSubviews 里改会留下「切一下才恢复」的空窗。
%hook AWEFeedDataSafeTableView

- (void)setFrame:(CGRect)frame {
    CGRect adjusted = DKVideoFeedTableAdjustFrame(self, frame);
    if (CGRectIsNull(adjusted)) {
        %orig;
        return;
    }
    gHitTableSetFrame++;
    %orig(adjusted);
}

%end

%hook AWEFeedTableView

- (void)setFrame:(CGRect)frame {
    CGRect adjusted = DKVideoFeedTableAdjustFrame(self, frame);
    if (CGRectIsNull(adjusted)) {
        %orig;
        return;
    }
    gHitTableSetFrame++;
    %orig(adjusted);
}

%end

// Auto Layout 应用后、原生控制器布局前统一表高，使尺寸适配器按同一高度计算行高与滚动锚点。
// 原生布局结束后沿用同一规则补正子表；两阶段分别计数。
static void DKSyncFeedTableLayout(UITableView *table, DKFeedTableLayoutStats *stats) {
    stats->runs++;
    if (!table) return;

    CGRect adjusted = DKVideoFeedTableAdjustFrame(table, table.frame);
    if (CGRectIsNull(adjusted)) return;

    table.frame = adjusted;
    gHitTableLayout++;
    stats->adjustments++;
}

%hook AWEFeedTableViewController

- (void)viewDidLayoutSubviews {
    if (DKVideoFullscreenOn()) DKSyncFeedTableLayout(self.tableView, &gFeedTableLayoutPreStats);
    %orig;
    if (!DKVideoFullscreenOn()) return;
    DKSyncFeedTableLayout(self.tableView, &gFeedTableLayoutStats);
}

%end

%hook AWEAwemeDetailTableViewController

- (void)viewDidLayoutSubviews {
    if (DKVideoFullscreenOn()) DKSyncFeedTableLayout(self.tableView, &gDetailTableLayoutPreStats);
    %orig;
    if (!DKVideoFullscreenOn()) return;
    DKSyncFeedTableLayout(self.tableView, &gDetailTableLayoutStats);
}

%end

#pragma mark - HUD 钉位

// iPad 旋转会通过 autoresizing 同时增减 HUD 高度；评论原生缩小态继续由宿主管理。
static BOOL DKFeedHUDPinsBothDirections(UIView *view) {
    if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad) return NO;
    if (DKCommentFreezeOn()) return YES;
    id owner = view.nextResponder;
    return [owner respondsToSelector:@selector(isCommentVCShowing)] && ![owner isCommentVCShowing];
}

// 由 DKVideoGeometry.xm 的总入口调用，调用方已确认写入方是 AWEPlayInteractionViewController。
// HUD 根视图是裸 UIView、没有类可挂，只能这样拦。返回 CGRectNull 表示放行。
//
// 不在已撑高的表内就在这里放行——那种页面的 HUD 本来就该跟着页面走；误钉成 Cell 满高会让
// 好友聊天页的文案/昵称/点赞栏整体下移一个底栏高。
CGRect DKFeedHUDAdjustFrame(UIView *view, CGRect frame) {
    if (!DKVideoFullscreenOn()) return CGRectNull;

    UIView *table = DKFeedTableForView(view);
    if (!table) return CGRectNull;

    NSNumber *original = DKVideoFeedTableOriginalHeight(table);
    if (!original) return CGRectNull;

    // iPad 按当前基线处理旋转的增高与缩短；其他情况保留原生缩小态。
    CGFloat pinned = original.doubleValue;
    if (DKFeedHUDPinsBothDirections(view)) {
        if (fabs(CGRectGetMinY(frame)) <= kDKFeedTolerance
            && fabs(CGRectGetHeight(frame) - pinned) <= kDKFeedTolerance) return CGRectNull;
        frame.origin.y = 0.0;
    } else if (CGRectGetHeight(frame) <= pinned + kDKFeedTolerance) return CGRectNull;

    gHitSetFrame++;
    frame.size.height = pinned;
    return frame;
}

// HUD 已进入层级后按表的原高同步尺寸；顶部黑遮罩由页面修饰模块维护。
%hook AWEPlayInteractionViewController

- (void)viewDidLayoutSubviews {
    %orig;

    // 已经在 HUD 控制器内部，不必再判类型。
    UIView *view = self.viewIfLoaded;
    if (!view) return;

    CGFloat original = DKFeedOriginalHeight(view);
    if (original <= 0.0) return;

    CGRect frame = view.frame;
    BOOL heightFits = DKFeedHUDPinsBothDirections(view)
        ? fabs(CGRectGetHeight(frame) - original) <= kDKFeedTolerance
        : CGRectGetHeight(frame) <= original + kDKFeedTolerance;
    if (fabs(CGRectGetMinY(frame)) <= kDKFeedTolerance
        && heightFits) {
        return;
    }

    view.frame = CGRectMake(CGRectGetMinX(frame), 0.0, CGRectGetWidth(frame), original);
    gHitFallback++;
}

%end

#pragma mark - 还原

// 关闭开关时立刻把表高还回去，不必等抖音下一次写 frame。
static void DKVideoFeedTableRestore(void) {
    for (UITableView *table in gStretchedTables.allObjects) {
        NSNumber *original = DKVideoFeedTableOriginalHeight(table);
        if (!original) continue;

        objc_setAssociatedObject(table, &kDKFeedOriginalHeightKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(table, &kDKPadFeedBottomReserveKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CGRect frame = table.frame;
        frame.size.height = original.doubleValue;
        table.frame = frame;
    }
    [gStretchedTables removeAllObjects];
}

%ctor {
    gStretchedTables = [NSHashTable weakObjectsHashTable];
    DKVideoFullscreenRegisterRestore(DKVideoFeedTableRestore);
}
