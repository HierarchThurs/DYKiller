//
//  DKVideoFeedTable.xm
//  「视频表被底栏压掉一个底栏高」这一类裁剪源头的修正：撑高表，再把 HUD 钉回撑高前的高度。
//
//  这类表 clipsToBounds=YES，cell 与 contentView 都等于表高，所以表一撑高整条 cell 链就变满高、
//  视频随之铺满；HUD（文案/昵称/点赞栏/进度条）的高度钉回原值，底部锚定元素才留在原处。
//
//  作用域是基类 AWEFeedDataSafeTableView，不是某一页：
//
//      AWEFeedTableView        : AWEFeedDataSafeTableView   （首页 / 朋友页）
//      AWEAwemeDetailTableView : AWEFeedDataSafeTableView   （好友聊天 / 搜索 / 其他用户主页）
//
//  同一个基类下这两种表都可能被压缩，也都可能本来就是满高，所以判据放在基类上，
//  再由「容器比表更高」这个结构条件决定要不要撑——满高的表天然跳过，新增子类也自动覆盖。
//
//  视频容器本身不归本文件管：它在所有页面遵循同一条规则，定义与拦截都在 DKVideoGeometry.xm。
//
//  HUD 钉位保留两条路径，各有职责，缺一不可：
//    · 拦 setFrame: —— 写入时就改值，抖音读回来即是钉后的值，不会逐帧拉扯，也没有闪烁；
//    · 布局后兜底 —— HUD 有相当一部分 frame 写入发生在它还没进入视图层级、取不到原高的时刻，
//      那些写入只能放行，靠这一步在布局结束后补正。
//  （实测 setBounds:/setCenter: 两条通道命中数恒为 0，未挂。）
//

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
// 所有撑高过的表（弱引用），供关闭开关时立即还原。多页并存时可能不止一张。
static NSHashTable<UITableView *> *gStretchedTables = nil;

#pragma mark - 命中统计

// 这两个数一起看才有意义：写入时拦截 vs 布局后兜底。首页/朋友页实测比例约 130:6，
// 是「写入时拦截不能砍成事后纠正」的直接依据。
static NSUInteger gHitSetFrame = 0;
static NSUInteger gHitFallback = 0;

NSString *DKVideoFeedTableStats(void) {
    return [NSString stringWithFormat:@"HUD setFrame=%lu  HUD 布局后兜底=%lu",
            (unsigned long)gHitSetFrame, (unsigned long)gHitFallback];
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
    return objc_getAssociatedObject(table, &kDKFeedOriginalHeightKey);
}

// 该视图所在视频表撑高前的高度，也就是 HUD 的钉位目标；不在撑高作用域内返回 0。
static CGFloat DKFeedOriginalHeight(UIView *view) {
    if (!DKVideoFullscreenOn()) return 0.0;
    return DKVideoFeedTableOriginalHeight(DKFeedTableForView(view)).doubleValue;
}

#pragma mark - 撑高视频表

// 撑高规则的唯一实现。两处 %hook 只是入口：AWEFeedTableView 自己实现了 setFrame:，挂基类拦不到它；
// AWEAwemeDetailTableView 没实现，只能靠基类那一层。子类先命中改成满高，super 再进基类那一层时
// current 已等于 target，守卫直接跳过，天然幂等。
CGRect DKVideoFeedTableAdjustFrame(UITableView *table, CGRect frame) {
    if (!DKVideoFullscreenOn()) {
        // 关闭后一律放行，抖音写什么就是什么；标记清掉以免 HUD 继续被钉。
        objc_setAssociatedObject(table, &kDKFeedOriginalHeightKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return CGRectNull;
    }

    CGFloat target = table.superview ? CGRectGetHeight(table.superview.bounds) : 0.0;
    CGFloat current = CGRectGetHeight(frame);
    // 容器不比来意的高度更高 → 这张表没被底栏压缩过（搜索页、好友聊天页就是这种），不在作用域内；
    // 高度不到容器一半 → 布局早期的半成品，记下它会把 HUD 钉到错误的位置。
    if (target <= 0.0
        || current >= target - kDKFeedTolerance
        || current < target * kDKFeedMinHeightRatio) {
        return CGRectNull;
    }

    if (!objc_getAssociatedObject(table, &kDKFeedOriginalHeightKey)) {
        objc_setAssociatedObject(table, &kDKFeedOriginalHeightKey, @(current),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gStretchedTables addObject:table];
    }
    frame.size.height = target;
    return frame;
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
    %orig(adjusted);
}

%end

#pragma mark - HUD 钉位

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

    // 只拦「被设成撑高后的满高」这一种写入；缩小态（如评论展开）一律放行。
    CGFloat pinned = original.doubleValue;
    if (CGRectGetHeight(frame) <= pinned + kDKFeedTolerance) return CGRectNull;

    gHitSetFrame++;
    frame.size.height = pinned;
    return frame;
}

// 补正那些在取不到原高的时刻被放行的写入，布局结束后拉回「顶边贴合、高度为原高」。
// 不是冗余兜底：实测每页仍有 4~11 次命中，是 HUD 尚未进入视图层级那几次写入的唯一出路。
%hook AWEPlayInteractionViewController

- (void)viewDidLayoutSubviews {
    %orig;

    // 已经在 HUD 控制器内部，不必再判类型。
    UIView *view = self.viewIfLoaded;
    if (!view) return;

    CGFloat original = DKFeedOriginalHeight(view);
    if (original <= 0.0) return;

    CGRect frame = view.frame;
    if (fabs(CGRectGetMinY(frame)) <= kDKFeedTolerance
        && CGRectGetHeight(frame) <= original + kDKFeedTolerance) {
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
