// 评论区顶部业务行与评论分页的显示、隐藏和移除。
#import "DKCommentHeaderClean.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import "DKViewAdjust.h"
#import <objc/message.h>
#import <objc/runtime.h>

typedef void (^DKHeaderTopCallback)(BOOL, BOOL);
typedef void (^DKHeaderHeightCallback)(double);

@interface DKCommentHeaderSection : NSObject
@property (nonatomic, copy) void (^didUpdateHeight)(double);
@property (nonatomic, copy) void (^didTopBarUpdate)(BOOL, BOOL);
- (double)currentHeight;
- (void)updateLayout:(BOOL)animated completion:(id)completion;
@end

@interface DKCommentHeaderCell : UICollectionViewCell
@end

@interface DKCommentHeaderInner : UIViewController
- (double)heightForSegmentedControl;
@end

@interface DKHeaderSearchView : UIView
@end
@interface DKHeaderLunaView : UIView
@end
@interface DKHeaderPOIView : UIView
@end
@interface DKHeaderTemplateView : UIView
@end
@interface DKHeaderSeriesView : UIView
@end
@interface DKHeaderCountLabel : UIView
@end

@interface AWETabContainerSectionViewModel : NSObject
@end

@interface IESSegmentedControl : UIView
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic) NSInteger selectedIndex;
@end

#pragma mark - 判据表

static NSString *const kDKHeaderTemplateClass = @"AWECommentPanelHeaderSwiftImpl.CommentHeaderTemplateAnchorView";
static NSString *const kDKHeaderCountLabelClass = @"AWECommentSwiftBizUI.CommentInteractionBaseLabel";
static const NSUInteger kDKHeaderCommentsTab = 1;

static NSString *const kDKHeaderTabSuffix = @"隐藏保留分页位置与点击；移除后不再出现该分页。更改后重新打开评论区生效。";
static NSString *const kDKHeaderAnchorSuffix = @"隐藏保留原位置与点击；移除收拢占位并禁用入口。当前顶部业务标签被移除时，评论数量与放大、关闭按钮同行。更改后重新打开评论区生效。";

// 设置项：键、标题、说明，按设置页顺序排列。
static NSArray<NSArray<NSString *> *> *DKHeaderItems(void) {
    static NSArray *items;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        items = @[
            @[ DKKeyCommentAIParseMode, @"评论区AI解析", [@"评论区顶部的 AI 解析分页。" stringByAppendingString:kDKHeaderTabSuffix] ],
            @[ DKKeyCommentPlayerDiscussionMode, @"玩家讨论", [@"评论区顶部的「玩家讨论」分页。" stringByAppendingString:kDKHeaderTabSuffix] ],
            @[ DKKeyCommentStoreReviewMode, @"门店评价", [@"评论区顶部的「门店评价」分页。" stringByAppendingString:kDKHeaderTabSuffix] ],
            @[ DKKeyCommentSearchAnchorMode, @"大家都在搜", [@"评论区顶部的「大家都在搜」入口。" stringByAppendingString:kDKHeaderAnchorSuffix] ],
            @[ DKKeyCommentLunaAnchorMode, @"去汽水听", [@"评论区顶部的汽水音乐入口。" stringByAppendingString:kDKHeaderAnchorSuffix] ],
            @[ DKKeyCommentLocationMode, @"地点信息", [@"评论区顶部的地点信息。" stringByAppendingString:kDKHeaderAnchorSuffix] ],
            @[ DKKeyCommentGameAnchorMode, @"游戏标签", [@"评论区顶部的游戏标签。" stringByAppendingString:kDKHeaderAnchorSuffix] ],
            @[ DKKeyCommentSeriesAnchorMode, @"观看完整合集", [@"评论区顶部的「观看完整合集」入口。" stringByAppendingString:kDKHeaderAnchorSuffix] ],
        ];
    });
    return items;
}

// 业务行专属视图类 → 设置键。
static NSArray<NSArray<NSString *> *> *DKHeaderAnchorClasses(void) {
    static NSArray *anchors;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        anchors = @[
            @[ @"AWECommentSearchAnchorView", DKKeyCommentSearchAnchorMode ],
            @[ @"AWECommentGuideLunaAnchorView", DKKeyCommentLunaAnchorMode ],
            @[ @"AWEPOIEntryAnchorView", DKKeyCommentLocationMode ],
            @[ @"AWEShowPlayletCommentHeaderView", DKKeyCommentSeriesAnchorMode ],
        ];
    });
    return anchors;
}

// 通用模板视图按作品 commonAnchor.basicInfoModel.name 区分业务。
static NSString *DKHeaderTemplateKey(id name) {
    static NSDictionary<NSString *, NSString *> *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @{ @"poi_poi": DKKeyCommentLocationMode, @"game_pad": DKKeyCommentGameAnchorMode };
    });
    return [name isKindOfClass:NSString.class] ? keys[name] : nil;
}

// 评论分页 tab 值 → 设置键；评论 tab 不在表内，始终保留。
static NSString *DKHeaderTabKey(NSUInteger tab) {
    switch (tab) {
        case 16: return DKKeyCommentAIParseMode;
        case 14: return DKKeyCommentPlayerDiscussionMode;
        case 8: return DKKeyCommentStoreReviewMode;
        default: return nil;
    }
}

// 仅通过已公开给 ObjC 的无参对象 getter 取值，不解释 Swift 存储。
static id DKHeaderObject(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (!object || ![object respondsToSelector:selector]) return nil;
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static BOOL DKHeaderIsKind(id object, NSString *name) {
    Class cls = NSClassFromString(name);
    return cls && [object isKindOfClass:cls];
}

#pragma mark - 状态

@interface DKCommentHeaderState : NSObject
@property (nonatomic, weak) DKCommentHeaderSection *section;
@property (nonatomic, weak) UICollectionViewCell *cell;
@property (nonatomic, weak) id model;
@property (nonatomic, weak) UIView *leaf;
@property (nonatomic, weak) UIView *countLabel;
@property (nonatomic, copy) NSString *key;
@property (nonatomic) DKDisplayMode mode;
@property (nonatomic) double retainedHeight;
@property (nonatomic, weak) id tabSection;
@property (nonatomic, copy) void (^nativeHeight)(double);
@property (nonatomic, copy) void (^nativeTop)(BOOL, BOOL);
@property (nonatomic) double height;
@property (nonatomic) BOOL onlyCount;
@property (nonatomic) BOOL hasBiz;
@property (nonatomic) BOOL hasTopState;
@property (nonatomic) BOOL collapsed;
@property (nonatomic) BOOL scheduled;
@property (nonatomic) BOOL syncScheduled;
@end
@implementation DKCommentHeaderState
@end

static char kDKHeaderStateKey;
static char kDKHeaderHiddenTabsKey;
static char kDKHeaderHostHiddenKey;
static char kDKHeaderRemovedKey;
static char kDKHeaderCountPinKey;

// 以下状态只在主线程读写。
static BOOL gDKHeaderInternalWrite;
static NSUInteger gDKHeaderPinnedLabels;
static NSUInteger gDKHeaderHiddenBlocked;
static NSUInteger gDKHeaderFramePinned;
static NSUInteger gDKHeaderTabFilters;
static NSString *gDKHeaderHooks;
static __weak DKCommentHeaderState *gDKHeaderLastState;

static DKCommentHeaderState *DKHeaderState(DKCommentHeaderSection *section) {
    DKCommentHeaderState *state = objc_getAssociatedObject(section, &kDKHeaderStateKey);
    if (!state) {
        state = [DKCommentHeaderState new];
        state.section = section;
        objc_setAssociatedObject(section, &kDKHeaderStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    id owner = DKHeaderObject(section, @"viewController");
    if (DKHeaderIsKind(owner, @"AWECommentPanelContainerSwiftImpl.CommentContainerInnerViewController")) {
        DKCommentHeaderState *previous = objc_getAssociatedObject(owner, &kDKHeaderStateKey);
        if (previous != state) {
            state.tabSection = previous.tabSection;
            objc_setAssociatedObject(owner, &kDKHeaderStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    return state;
}

#pragma mark - 业务视图显隐

static void DKHeaderSync(DKCommentHeaderState *state);

// 合并到下一轮主队列同步，覆盖组件晚到挂载、其后没有 configCell 或 cell 布局回调的情况。
static void DKHeaderScheduleSync(DKCommentHeaderState *state) {
    if (state.syncScheduled) return;
    state.syncScheduled = YES;
    __weak DKCommentHeaderState *weakState = state;
    dispatch_async(dispatch_get_main_queue(), ^{
        DKCommentHeaderState *current = weakState;
        current.syncScheduled = NO;
        if (current.cell) DKHeaderSync(current);
    });
}

// 宿主写入的业务视图尚不是所属顶部的当前业务行时，安排一次同步。
static void DKHeaderNoteMount(UIView *view) {
    NSUInteger depth = 0;
    for (UIView *ancestor = view.superview; ancestor && depth < 6; ancestor = ancestor.superview, depth++) {
        DKCommentHeaderState *state = objc_getAssociatedObject(ancestor, &kDKHeaderStateKey);
        if (![state isKindOfClass:DKCommentHeaderState.class]) continue;
        if (state.cell == ancestor && state.leaf != view) DKHeaderScheduleSync(state);
        return;
    }
}

// 业务视图由组件 mount 反复写 hidden；守门记录宿主请求值，本模块移除期间保持隐藏。
static BOOL DKHeaderGuardHidden(UIView *view, BOOL hidden) {
    if (gDKHeaderInternalWrite) return hidden;
    objc_setAssociatedObject(view, &kDKHeaderHostHiddenKey, @(hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!objc_getAssociatedObject(view, &kDKHeaderRemovedKey)) {
        DKHeaderNoteMount(view);
        return hidden;
    }
    if (!hidden) gDKHeaderHiddenBlocked++;
    return YES;
}

static BOOL DKHeaderHostHidden(UIView *view) {
    NSNumber *host = objc_getAssociatedObject(view, &kDKHeaderHostHiddenKey);
    return host ? host.boolValue : view.hidden;
}

static void DKHeaderWriteHidden(UIView *view, BOOL hidden) {
    if (view.hidden == hidden) return;
    gDKHeaderInternalWrite = YES;
    view.hidden = hidden;
    gDKHeaderInternalWrite = NO;
}

static NSString *DKHeaderKey(UIView *view, DKCommentHeaderSection *section) {
    for (NSArray<NSString *> *anchor in DKHeaderAnchorClasses()) {
        if (DKHeaderIsKind(view, anchor[0])) return anchor[1];
    }
    if (!DKHeaderIsKind(view, kDKHeaderTemplateClass)) return nil;

    // 通用模板由当前作品 commonAnchor.basicInfoModel 构造。
    id owner = DKHeaderObject(section, @"viewController");
    if (![owner isKindOfClass:UIViewController.class]) return nil;
    for (UIViewController *vc = owner; vc; vc = vc.parentViewController) {
        if (!DKHeaderIsKind(vc, @"AWECommentContainerViewController")) continue;
        id model = DKHeaderObject(vc, @"model");
        id basic = DKHeaderObject(DKHeaderObject(model, @"commonAnchor"), @"basicInfoModel");
        return DKHeaderTemplateKey(DKHeaderObject(basic, @"name"));
    }
    return nil;
}

// 接受独占业务分支，以及原生单计数标题与一个业务分支并列的结构。
static UIView *DKHeaderLeaf(DKCommentHeaderState *state, NSString **key, UIView **countLabel) {
    UIView *root = state.cell.contentView;
    for (NSUInteger depth = 0; root && depth < 6; depth++) {
        if (DKHeaderHostHidden(root)) return nil;
        NSString *candidate = DKHeaderKey(root, state.section);
        if (candidate) {
            if (key) *key = candidate;
            return root;
        }
        UIView *branch = nil;
        for (UIView *child in root.subviews) {
            if (DKHeaderIsKind(child, kDKHeaderCountLabelClass) && !child.hidden) {
                if (*countLabel) return nil;
                *countLabel = child;
            } else {
                if (branch) return nil;
                branch = child;
            }
        }
        root = branch;
    }
    return nil;
}

static void DKHeaderApplyLeaf(UIView *leaf, DKDisplayMode mode) {
    if (!leaf) return;
    DKAdjustFade(leaf, mode == DKDisplayModeHide ? 0.0 : 1.0, CGSizeZero);
    NSArray<NSNumber *> *original = objc_getAssociatedObject(leaf, &kDKHeaderRemovedKey);
    BOOL remove = mode == DKDisplayModeRemove;
    BOOL host = DKHeaderHostHidden(leaf);
    if (remove && !original) {
        objc_setAssociatedObject(leaf, &kDKHeaderHostHiddenKey, @(host), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(leaf, &kDKHeaderRemovedKey,
            @[ @(leaf.userInteractionEnabled), @(leaf.accessibilityElementsHidden) ], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        leaf.userInteractionEnabled = NO;
        leaf.accessibilityElementsHidden = YES;
    } else if (!remove && original) {
        objc_setAssociatedObject(leaf, &kDKHeaderRemovedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        leaf.userInteractionEnabled = original[0].boolValue;
        leaf.accessibilityElementsHidden = original[1].boolValue;
    }
    if (remove || original) DKHeaderWriteHidden(leaf, host || remove);
}

#pragma mark - 计数单行

// 收拢中的计数 label：记录宿主最后请求的 frame，纵向居中到 row 顶部的保留单行。
@interface DKHeaderCountPin : NSObject
@property (nonatomic) CGRect hostFrame;
@property (nonatomic, weak) UIView *row;
@property (nonatomic) CGFloat rowHeight;
@end
@implementation DKHeaderCountPin
- (instancetype)init {
    if ((self = [super init])) gDKHeaderPinnedLabels++;
    return self;
}
- (void)dealloc {
    gDKHeaderPinnedLabels--;
}
@end

static CGRect DKHeaderPinnedFrame(UIView *label, DKHeaderCountPin *pin, CGRect frame) {
    UIView *row = pin.row;
    if (!row || !label.superview) return frame;
    CGFloat mid = [row convertPoint:CGPointMake(0.0, pin.rowHeight * 0.5) toView:label.superview].y;
    frame.origin.y = mid - frame.size.height * 0.5;
    return frame;
}

// 组件 mount 用 setFrame: 定位计数 label；收拢期间把宿主请求值改写到保留单行。
static CGRect DKHeaderGuardCountFrame(UIView *label, CGRect frame) {
    if (!gDKHeaderPinnedLabels || gDKHeaderInternalWrite) return frame;
    DKHeaderCountPin *pin = objc_getAssociatedObject(label, &kDKHeaderCountPinKey);
    if (!pin) return frame;
    pin.hostFrame = frame;
    CGRect pinned = DKHeaderPinnedFrame(label, pin, frame);
    if (!CGRectEqualToRect(pinned, frame)) gDKHeaderFramePinned++;
    return pinned;
}

static void DKHeaderWriteFrame(UIView *view, CGRect frame) {
    if (CGRectEqualToRect(view.frame, frame)) return;
    gDKHeaderInternalWrite = YES;
    view.frame = frame;
    gDKHeaderInternalWrite = NO;
}

// rowHeight > 0 时居中到 row 顶部的单行；0 时还原宿主最后请求的 frame。
static void DKHeaderPinCount(UIView *label, UIView *row, CGFloat rowHeight) {
    if (!label) return;
    DKHeaderCountPin *pin = objc_getAssociatedObject(label, &kDKHeaderCountPinKey);
    if (rowHeight <= 0.0) {
        if (!pin) return;
        CGRect host = pin.hostFrame;
        objc_setAssociatedObject(label, &kDKHeaderCountPinKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DKHeaderWriteFrame(label, host);
        return;
    }
    if (!pin) {
        pin = [DKHeaderCountPin new];
        pin.hostFrame = label.frame;
        objc_setAssociatedObject(label, &kDKHeaderCountPinKey, pin, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    pin.row = row;
    pin.rowHeight = rowHeight;
    DKHeaderWriteFrame(label, DKHeaderPinnedFrame(label, pin, pin.hostFrame));
}

// 原生标题栏提供单行几何；只读取其尺寸，不启用该隐藏视图或改动按钮。
static double DKHeaderCountRowHeight(DKCommentHeaderState *state) {
    UIViewController *owner = DKHeaderObject(state.section, @"viewController");
    if (![owner isKindOfClass:UIViewController.class] || !owner.isViewLoaded) return 0.0;
    for (UIView *view in owner.view.subviews) {
        if (DKHeaderIsKind(view, @"AWECommentPanelContainerSwiftImpl.CommentVCHeaderCloseBar")) {
            CGFloat height = view.bounds.size.height;
            if (height > 0.0 && height >= state.countLabel.bounds.size.height) return height;
        }
    }
    return 0.0;
}

#pragma mark - 同步与原生布局更新

static double DKHeaderEffectiveHeight(DKCommentHeaderState *state, double nativeHeight) {
    return state.collapsed ? state.retainedHeight : nativeHeight;
}

// 在当前配置/布局结束后走宿主的更新回调，合并同一轮重复通知。
static void DKHeaderScheduleLayout(DKCommentHeaderState *state) {
    if (state.scheduled) return;
    state.scheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        state.scheduled = NO;
        if (!state.section || !state.cell) return;
        if (state.hasTopState && state.nativeTop) {
            state.nativeTop(state.collapsed ? state.countLabel != nil : state.onlyCount, state.collapsed ? NO : state.hasBiz);
        }
        id owner = DKHeaderObject(state.section, @"viewController");
        SEL selector = NSSelectorFromString(@"segmentedControlForSectionController:");
        if (state.tabSection && [owner respondsToSelector:selector]) {
            ((id (*)(id, SEL, id))objc_msgSend)(owner, selector, state.tabSection);
        }
        if (state.nativeHeight) state.nativeHeight(DKHeaderEffectiveHeight(state, state.height));
        [state.section updateLayout:NO completion:nil];
    });
}

static void DKHeaderSync(DKCommentHeaderState *state) {
    NSString *key = nil;
    UIView *countLabel = nil;
    UIView *leaf = DKHeaderLeaf(state, &key, &countLabel);
    if (!leaf) countLabel = nil;
    if (state.leaf != leaf) DKHeaderApplyLeaf(state.leaf, DKDisplayModeShow);
    if (state.countLabel != countLabel) DKHeaderPinCount(state.countLabel, nil, 0.0);
    state.leaf = leaf;
    state.countLabel = countLabel;
    state.key = key;
    DKDisplayMode mode = key ? DKPrefDisplayMode(key) : DKDisplayModeShow;
    state.mode = mode;
    DKHeaderApplyLeaf(leaf, mode);
    id models = DKHeaderObject(state.section, @"modelsArray");
    BOOL singleItem = [models isKindOfClass:NSArray.class] && [models count] == 1 && [models firstObject] == state.model;
    double retainedHeight = countLabel ? DKHeaderCountRowHeight(state) : 0.0;
    BOOL collapsed = leaf && mode == DKDisplayModeRemove && singleItem && (!countLabel || retainedHeight > 0.0);
    BOOL changed = state.collapsed != collapsed || (collapsed && state.retainedHeight != retainedHeight);
    state.collapsed = collapsed;
    state.retainedHeight = retainedHeight;
    DKHeaderPinCount(countLabel, state.cell.contentView, collapsed ? retainedHeight : 0.0);
    gDKHeaderLastState = state;
    if (changed) DKHeaderScheduleLayout(state);
}

#pragma mark - 评论分页

static NSUInteger DKHeaderTab(id model) {
    if (!DKHeaderIsKind(model, @"AWECommentPanelContainerSwiftImpl.CommentTabModel")) return 0;
    SEL selector = NSSelectorFromString(@"tab");
    NSMethodSignature *signature = [model methodSignatureForSelector:selector];
    if (signature.numberOfArguments != 2 || strcmp(signature.methodReturnType, @encode(NSUInteger)) != 0) return 0;
    return ((NSUInteger (*)(id, SEL))objc_msgSend)(model, selector);
}

static DKDisplayMode DKHeaderTabMode(NSUInteger tab) {
    NSString *key = DKHeaderTabKey(tab);
    return key ? DKPrefDisplayMode(key) : DKDisplayModeShow;
}

// 只处理含评论 tab 的评论分页；保留其余项的顺序和对象身份。
static NSArray *DKHeaderFilterTabs(NSArray *models) {
    if (![models isKindOfClass:NSArray.class]) return models;
    BOOL hasComments = NO, removes = NO;
    for (id model in models) {
        NSUInteger tab = DKHeaderTab(model);
        if (tab == kDKHeaderCommentsTab) hasComments = YES;
        else if (DKHeaderTabMode(tab) == DKDisplayModeRemove) removes = YES;
    }
    if (!hasComments || !removes) return models;
    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:models.count];
    for (id model in models) {
        NSUInteger tab = DKHeaderTab(model);
        if (tab == kDKHeaderCommentsTab || DKHeaderTabMode(tab) != DKDisplayModeRemove) [filtered addObject:model];
    }
    gDKHeaderTabFilters++;
    return [filtered copy];
}

static void DKHeaderFadeTabs(IESSegmentedControl *control) {
    NSIndexSet *indexes = objc_getAssociatedObject(control, &kDKHeaderHiddenTabsKey);
    if (!indexes) return;
    for (UICollectionViewCell *cell in control.collectionView.visibleCells) {
        NSIndexPath *path = [control.collectionView indexPathForCell:cell];
        DKAdjustFade(cell.contentView, path && [indexes containsIndex:path.item] ? 0.0 : 1.0, CGSizeZero);
    }
    UIView *indicator = DKHeaderObject(control, @"segmentedIndicator");
    if ([indicator isKindOfClass:UIView.class]) {
        BOOL hidden = control.selectedIndex >= 0 && [indexes containsIndex:(NSUInteger)control.selectedIndex];
        DKAdjustFade(indicator, hidden ? 0.0 : 1.0, CGSizeZero);
    }
}

// 记录本评论分页控件上「隐藏」档的索引；非评论数据时还原本模块的淡出。
static void DKHeaderMarkTabs(id owner, id section, UIView *view) {
    if (!DKHeaderIsKind(view, @"IESSegmentedControl")) return;
    DKCommentHeaderState *state = objc_getAssociatedObject(owner, &kDKHeaderStateKey);
    if (!state) {
        state = [DKCommentHeaderState new];
        objc_setAssociatedObject(owner, &kDKHeaderStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    state.tabSection = section;
    id models = DKHeaderObject(DKHeaderObject(section, @"viewModel"), @"itemModelsArray");
    NSMutableIndexSet *hidden = [NSMutableIndexSet indexSet];
    BOOL matched = NO;
    if ([models isKindOfClass:NSArray.class]) {
        NSUInteger index = 0;
        for (id item in models) {
            NSUInteger tab = DKHeaderTab(item);
            if (tab == kDKHeaderCommentsTab) matched = YES;
            else if (DKHeaderTabMode(tab) == DKDisplayModeHide) [hidden addIndex:index];
            index++;
        }
    }
    objc_setAssociatedObject(view, &kDKHeaderHiddenTabsKey, matched ? [hidden copy] : [NSIndexSet indexSet], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKHeaderFadeTabs((IESSegmentedControl *)view);
    if (!matched) objc_setAssociatedObject(view, &kDKHeaderHiddenTabsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - 诊断

static NSString *DKHeaderModeText(DKDisplayMode mode) {
    return mode == DKDisplayModeRemove ? @"移除" : mode == DKDisplayModeHide ? @"隐藏" : @"显示";
}

static NSString *DKHeaderTitle(NSString *key) {
    for (NSArray<NSString *> *item in DKHeaderItems()) if ([item[0] isEqualToString:key]) return item[1];
    return key;
}

NSString *DKCommentHeaderStatus(void) {
    NSMutableString *out = [NSMutableString stringWithString:@"档位："];
    for (NSArray<NSString *> *item in DKHeaderItems()) {
        [out appendFormat:@" %@=%@", item[1], DKHeaderModeText(DKPrefDisplayMode(item[0]))];
    }
    [out appendFormat:@"\nHook：%@\n", gDKHeaderHooks ?: @"未安装"];
    DKCommentHeaderState *state = gDKHeaderLastState;
    if (state.cell) {
        UIView *leaf = state.leaf, *count = state.countLabel;
        [out appendFormat:@"最近顶部：业务=%@ 档位=%@ 收拢=%@ 单行高=%.1f 宿主高=%.1f 计数在行内=%@\n",
            leaf ? [NSString stringWithFormat:@"%@(%@)", NSStringFromClass(leaf.class), DKHeaderTitle(state.key)] : @"(无)",
            DKHeaderModeText(state.mode), state.collapsed ? @"是" : @"否", state.retainedHeight, state.height,
            count ? @"是" : @"否"];
        if (leaf) {
            [out appendFormat:@"业务视图：hidden=%d 宿主请求=%d 可交互=%d 淡出=%.2f\n",
                leaf.hidden, DKHeaderHostHidden(leaf), leaf.userInteractionEnabled, DKAdjustFadeFactor(leaf)];
        }
        if (count) [out appendFormat:@"计数：frame=%@\n", NSStringFromCGRect(count.frame)];
    } else {
        [out appendString:@"最近顶部：(本进程未配置评论区顶部)\n"];
    }
    [out appendFormat:@"守门累计：业务视图 hidden 改写=%lu 计数 frame 校正=%lu 收拢中的计数=%lu 分页过滤=%lu\n",
        (unsigned long)gDKHeaderHiddenBlocked, (unsigned long)gDKHeaderFramePinned,
        (unsigned long)gDKHeaderPinnedLabels, (unsigned long)gDKHeaderTabFilters];
    return out;
}

#pragma mark - Hook

%group DKCommentHeaderHooks
%hook DKCommentHeaderSection

- (void)setDidTopBarUpdate:(DKHeaderTopCallback)callback {
    DKCommentHeaderState *state = DKHeaderState(self);
    state.nativeTop = callback;
    if (!callback) { %orig(nil); return; }
    __weak DKCommentHeaderState *weakState = state;
    DKHeaderTopCallback wrapped = ^(BOOL onlyCount, BOOL hasBiz) {
        DKCommentHeaderState *current = weakState;
        current.onlyCount = onlyCount;
        current.hasBiz = hasBiz;
        current.hasTopState = YES;
        callback(current.collapsed ? current.countLabel != nil : onlyCount, current.collapsed ? NO : hasBiz);
    };
    %orig(wrapped);
}

- (void)setDidUpdateHeight:(DKHeaderHeightCallback)callback {
    DKCommentHeaderState *state = DKHeaderState(self);
    state.nativeHeight = callback;
    if (!callback) { %orig(nil); return; }
    __weak DKCommentHeaderState *weakState = state;
    DKHeaderHeightCallback wrapped = ^(double height) {
        DKCommentHeaderState *current = weakState;
        current.height = height;
        callback(DKHeaderEffectiveHeight(current, height));
    };
    %orig(wrapped);
}

- (double)currentHeight {
    double height = %orig;
    DKCommentHeaderState *state = DKHeaderState(self);
    state.height = height;
    return DKHeaderEffectiveHeight(state, height);
}

- (CGSize)sizeForItemAtIndex:(NSInteger)index model:(id)model collectionViewSize:(CGSize)size {
    CGSize result = %orig;
    DKCommentHeaderState *state = DKHeaderState(self);
    if (state.model == model && state.collapsed) result.height = state.retainedHeight;
    return result;
}

- (void)configCell:(UICollectionViewCell *)cell index:(NSInteger)index model:(id)model {
    DKCommentHeaderState *state = DKHeaderState(self);
    if (state.model != model || state.cell != cell) {
        DKHeaderApplyLeaf(state.leaf, DKDisplayModeShow);
        state.leaf = nil;
        DKHeaderPinCount(state.countLabel, nil, 0.0);
        state.countLabel = nil;
        state.retainedHeight = 0.0;
        if (state.collapsed) DKHeaderScheduleLayout(state);
        state.collapsed = NO;
    }
    state.cell = cell;
    state.model = model;
    objc_setAssociatedObject(cell, &kDKHeaderStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
    [self currentHeight];
    DKHeaderSync(state);
}
%end

%hook DKCommentHeaderCell
- (void)layoutSubviews {
    %orig;
    DKCommentHeaderState *state = objc_getAssociatedObject(self, &kDKHeaderStateKey);
    if (state.cell == self) DKHeaderSync(state);
}
%end

%hook DKCommentHeaderInner
- (UIView *)segmentedControlForSectionController:(id)section {
    UIView *view = %orig;
    DKHeaderMarkTabs(self, section, view);
    return view;
}
- (double)autoFullScreen_topContainerTotalHeight {
    double height = %orig;
    DKCommentHeaderState *state = objc_getAssociatedObject(self, &kDKHeaderStateKey);
    return state.collapsed ? state.retainedHeight + [self heightForSegmentedControl] : height;
}
- (double)pinchFullScreen_topContainerTotalHeight {
    double height = %orig;
    DKCommentHeaderState *state = objc_getAssociatedObject(self, &kDKHeaderStateKey);
    return state.collapsed ? state.retainedHeight + [self heightForSegmentedControl] : height;
}
%end
%end

// 业务视图与计数 label 的写入点守门；每个宿主类单独成组，类存在才安装。
%group DKHeaderSearchGuard
%hook DKHeaderSearchView
- (void)setHidden:(BOOL)hidden { %orig(DKHeaderGuardHidden(self, hidden)); }
%end
%end

%group DKHeaderLunaGuard
%hook DKHeaderLunaView
- (void)setHidden:(BOOL)hidden { %orig(DKHeaderGuardHidden(self, hidden)); }
%end
%end

%group DKHeaderPOIGuard
%hook DKHeaderPOIView
- (void)setHidden:(BOOL)hidden { %orig(DKHeaderGuardHidden(self, hidden)); }
%end
%end

%group DKHeaderTemplateGuard
%hook DKHeaderTemplateView
- (void)setHidden:(BOOL)hidden { %orig(DKHeaderGuardHidden(self, hidden)); }
%end
%end

%group DKHeaderSeriesGuard
%hook DKHeaderSeriesView
- (void)setHidden:(BOOL)hidden { %orig(DKHeaderGuardHidden(self, hidden)); }
%end
%end

%group DKHeaderCountGuard
%hook DKHeaderCountLabel
- (void)setFrame:(CGRect)frame { %orig(DKHeaderGuardCountFrame(self, frame)); }
%end
%end

%hook AWETabContainerSectionViewModel
- (NSArray *)itemModelsArray {
    return DKHeaderFilterTabs(%orig);
}
%end

%hook IESSegmentedControl
- (void)layoutSubviews {
    %orig;
    DKHeaderFadeTabs(self);
}
- (void)updateSelectedItemWithIndex:(NSInteger)index animated:(BOOL)animated {
    %orig;
    DKHeaderFadeTabs(self);
}
- (UICollectionViewCell *)collectionView:(UICollectionView *)collection cellForItemAtIndexPath:(NSIndexPath *)path {
    UICollectionViewCell *cell = %orig;
    NSIndexSet *indexes = objc_getAssociatedObject(self, &kDKHeaderHiddenTabsKey);
    if (indexes) DKAdjustFade(cell.contentView, [indexes containsIndex:path.item] ? 0.0 : 1.0, CGSizeZero);
    return cell;
}
%end

%ctor {
    NSMutableArray<NSString *> *installed = [NSMutableArray array];
    Class section = NSClassFromString(@"AWECommentPanelHeaderSwiftImpl.CommentPanelHeaderSectionController");
    Class cell = NSClassFromString(@"AWECommentPanelHeaderSwiftImpl.CommentPanelHeaderNewCell");
    Class inner = NSClassFromString(@"AWECommentPanelContainerSwiftImpl.CommentContainerInnerViewController");
    if (section && cell && inner) {
        %init(DKCommentHeaderHooks, DKCommentHeaderSection=section, DKCommentHeaderCell=cell, DKCommentHeaderInner=inner);
        [installed addObject:@"顶部"];
        Class search = NSClassFromString(@"AWECommentSearchAnchorView");
        if (search) { %init(DKHeaderSearchGuard, DKHeaderSearchView=search); [installed addObject:@"搜索守门"]; }
        Class luna = NSClassFromString(@"AWECommentGuideLunaAnchorView");
        if (luna) { %init(DKHeaderLunaGuard, DKHeaderLunaView=luna); [installed addObject:@"汽水守门"]; }
        Class poi = NSClassFromString(@"AWEPOIEntryAnchorView");
        if (poi) { %init(DKHeaderPOIGuard, DKHeaderPOIView=poi); [installed addObject:@"POI守门"]; }
        Class series = NSClassFromString(@"AWEShowPlayletCommentHeaderView");
        if (series) { %init(DKHeaderSeriesGuard, DKHeaderSeriesView=series); [installed addObject:@"合集守门"]; }
        Class tpl = NSClassFromString(kDKHeaderTemplateClass);
        if (tpl) { %init(DKHeaderTemplateGuard, DKHeaderTemplateView=tpl); [installed addObject:@"模板守门"]; }
        Class count = NSClassFromString(kDKHeaderCountLabelClass);
        if (count) { %init(DKHeaderCountGuard, DKHeaderCountLabel=count); [installed addObject:@"计数守门"]; }
    }
    %init;
    [installed addObject:@"分页"];
    gDKHeaderHooks = [installed componentsJoinedByString:@" "];

    for (NSArray<NSString *> *item in DKHeaderItems()) {
        NSString *key = item[0], *title = item[1], *info = item[2];
        DKSettingsRegister(key, ^{
            return DKSettingsWithInfo(DKMakeChoice(key, title, @[ @"显示", @"隐藏", @"移除" ]), info);
        });
    }
}
