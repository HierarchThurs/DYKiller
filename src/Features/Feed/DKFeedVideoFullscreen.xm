//
//  DKFeedVideoFullscreen.xm
//  首页与朋友页：视频画面铺满整屏，HUD（文案/昵称/点赞栏/进度条）保持原位不下移。
//
//  这两页的裁剪源头是 AWEFeedTableView 自己——它被底栏压掉一个底栏高且 clipsToBounds=YES，
//  cell 与 contentView 都等于它的高度。故撑高 tableView 即可让整条 cell 链变满高、视频随之铺满；
//  再把 HUD 的高度钉回撑高前的值，底部锚定元素就留在原处。
//
//  详情页全屏（DKDetailVideoFullscreen）的源头不同：那边 contentView 本就是满高、只有视频容器
//  被裁，所以拦视频容器的 frame 即可。两者不能互相套用。
//
//  HUD 钉位保留两条路径，各有职责，缺一不可：
//    · 拦 setFrame: —— 写入时就改值，抖音读回来即是钉后的值，不会逐帧拉扯，也没有闪烁；
//    · 布局后兜底 —— HUD 有相当一部分 frame 写入发生在它还没进入视图层级、取不到原高的时刻，
//      那些写入只能放行，靠这一步在布局结束后补正。
//  （beta2 实测：setBounds:/setCenter: 两条通道命中数恒为 0，已删除。）
//

#import "DKFeedVideoFullscreen.h"
#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import <objc/runtime.h>
#import <math.h>

// 覆盖 @3x 像素对齐带来的亚像素漂移。
static const CGFloat kDKFeedTolerance = 0.5;
// 表高至少要到容器的这个比例才认作「已排好、只差一个底栏」，排除布局早期的半成品尺寸。
static const CGFloat kDKFeedMinHeightRatio = 0.5;
// 从 HUD 往上找 feed 表的最大层数（图文内容多两层容器，取 8 有余量）。
static const NSUInteger kDKFeedAncestorLimit = 8;

// 撑高前的表高。挂在 AWEFeedTableView 上，既是还原依据，也是 HUD 的钉位目标。
static char kDKFeedOriginalHeightKey;
// 最近一次撑高过的 feed 表，供关闭开关时立即还原。
static __weak AWEFeedTableView *gFeedTable = nil;

#pragma mark - 命中统计

static NSUInteger gHitSetFrame = 0;
static NSUInteger gHitFallback = 0;
static NSUInteger gHitMerge = 0;
static NSUInteger gMissNoOriginal = 0;

NSString *DKFeedFullscreenStats(void) {
    return [NSString stringWithFormat:
            @"HUD setFrame=%lu  HUD 布局后兜底=%lu  视频容器还原=%lu  取不到原高而放行=%lu",
            (unsigned long)gHitSetFrame, (unsigned long)gHitFallback,
            (unsigned long)gHitMerge, (unsigned long)gMissNoOriginal];
}

#pragma mark - 目标判定

static Class DKFeedTableViewClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(@"AWEFeedTableView"); });
    return cls;
}

static Class DKPlayInteractionClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(@"AWEPlayInteractionViewController"); });
    return cls;
}

static Class DKMergeClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(@"AWEDPlayerViewController_Merge"); });
    return cls;
}

static UIView *DKFeedTableForView(UIView *view) {
    Class tableCls = DKFeedTableViewClass();
    if (!tableCls) return nil;

    UIView *ancestor = view.superview;
    for (NSUInteger i = 0; ancestor && i < kDKFeedAncestorLimit; i++, ancestor = ancestor.superview) {
        if ([ancestor isKindOfClass:tableCls]) return ancestor;
    }
    return nil;
}

BOOL DKFeedFullscreenActiveForView(UIView *view) {
    if (!DKPrefBool(DKKeyFeedVideoFullscreen)) return NO;
    return objc_getAssociatedObject(DKFeedTableForView(view), &kDKFeedOriginalHeightKey) != nil;
}

// 该视图所在 feed 表撑高前的高度，也就是 HUD 的钉位目标；不在撑高作用域内返回 0。
static CGFloat DKFeedOriginalHeight(UIView *view) {
    if (!DKPrefBool(DKKeyFeedVideoFullscreen)) return 0.0;
    NSNumber *original =
        objc_getAssociatedObject(DKFeedTableForView(view), &kDKFeedOriginalHeightKey);
    return original.doubleValue;
}

// 这条 setFrame: 要拦的两类视图（HUD 根视图、视频容器）都是裸 UIView，没有类可挂，只能挂
// 全局 UIView。守卫因此必须尽量便宜：只取一次 nextResponder、最多两次类型判断，不是目标
// 立刻放行。返回 0 表示放行，否则为该写入应被改成的高度。
static CGFloat DKFeedTargetHeight(UIView *view, CGRect frame) {
    UIResponder *owner = view.nextResponder;
    Class hudCls = DKPlayInteractionClass();
    BOOL isHUD = hudCls && [owner isKindOfClass:hudCls];
    if (!isHUD) {
        Class mergeCls = DKMergeClass();
        if (!mergeCls || ![owner isKindOfClass:mergeCls]) return 0.0;
    }

    CGFloat original = DKFeedOriginalHeight(view);
    if (original <= 0.0) {
        if (isHUD) gMissNoOriginal++;
        return 0.0;
    }

    CGFloat current = CGRectGetHeight(frame);
    if (isHUD) {
        // HUD：只拦「被设成撑高后的满高」这一种写入；缩小态（如评论展开）一律放行。
        if (current <= original + kDKFeedTolerance) return 0.0;
        gHitSetFrame++;
        return original;
    }

    // 视频容器：评论区关闭时抖音会把它还原成「撑高前的高度」——cell 早已是满高，于是底部
    // 露出黑边，要等滑动触发 cell 复用才会恢复。这里在写入时就把那个陈旧值顶成满高。
    // 只认「恰好等于原高」这一种写入：评论展开时的缩小态是别的值，不与抖音抢。
    if (fabs(current - original) > kDKFeedTolerance) return 0.0;
    CGFloat container = CGRectGetHeight(view.superview.bounds);
    if (container <= original + kDKFeedTolerance) return 0.0;
    gHitMerge++;
    return container;
}

#pragma mark - 撑高 feed 表

// 在写入时就改成满高：抖音把表高改回原值（如关闭评论区）的那一刻即被顶回去，
// 不必等下一次布局。事后在 layoutSubviews 里改会留下「切一下才恢复」的空窗。
%hook AWEFeedTableView

- (void)setFrame:(CGRect)frame {
    if (!DKPrefBool(DKKeyFeedVideoFullscreen)) {
        // 关闭后一律放行，抖音写什么就是什么，标记清掉以免 HUD 继续被钉。
        objc_setAssociatedObject(self, &kDKFeedOriginalHeightKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        %orig;
        return;
    }

    gFeedTable = self;
    CGFloat target = self.superview ? CGRectGetHeight(self.superview.bounds) : 0.0;
    CGFloat current = CGRectGetHeight(frame);
    // 容器不比来意的高度更高 → 这条 feed 没被底栏压缩过，不在作用域内；
    // 高度不到容器一半 → 布局早期的半成品，记下它会把 HUD 钉到错误的位置。
    if (target <= 0.0
        || current >= target - kDKFeedTolerance
        || current < target * kDKFeedMinHeightRatio) {
        %orig;
        return;
    }

    if (!objc_getAssociatedObject(self, &kDKFeedOriginalHeightKey)) {
        objc_setAssociatedObject(self, &kDKFeedOriginalHeightKey, @(current),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    frame.size.height = target;
    %orig(frame);
}

%end

#pragma mark - HUD 钉回原高 / 视频容器顶回满高

// 在写入时改值而非事后纠正：抖音读回来的就是钉后的值，不会与我们逐帧拉扯。
%hook UIView

- (void)setFrame:(CGRect)frame {
    CGFloat target = DKFeedTargetHeight(self, frame);
    if (target <= 0.0) {
        %orig;
        return;
    }
    frame.size.height = target;
    %orig(frame);
}

%end

// 兜底：补正那些在取不到原高的时刻被放行的写入，布局结束后拉回「顶边贴合、高度为原高」。
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

#pragma mark - 设置项注册

// 关闭开关时立刻把表高还回去，不必等抖音下一次写 frame。
static void DKFeedRestoreTable(void) {
    AWEFeedTableView *table = gFeedTable;
    NSNumber *original = objc_getAssociatedObject(table, &kDKFeedOriginalHeightKey);
    if (!original) return;

    objc_setAssociatedObject(table, &kDKFeedOriginalHeightKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGRect frame = table.frame;
    frame.size.height = original.doubleValue;
    table.frame = frame;
}

%ctor {
    DKSettingsRegisterItem(@"首页", ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(
            DKKeyFeedVideoFullscreen,
            @"首页/朋友视频全屏",
            @"视频铺满整屏，文案与进度条保持原位；勿与其他插件的全屏同时开启"
        );
        void (^origBlock)(void) = [item.switchChangedBlock copy];
        item.switchChangedBlock = ^{
            if (origBlock) origBlock();
            if (!DKPrefBool(DKKeyFeedVideoFullscreen)) DKFeedRestoreTable();
        };
        return item;
    });
}
