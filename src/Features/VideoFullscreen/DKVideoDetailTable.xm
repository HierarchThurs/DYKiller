//
//  DKVideoDetailTable.xm
//  详情页在建行和分页计算前准备视频表，让原生行位置与 Cell 使用相同高度。
//

#import "DouyinHeaders.h"
#import "DKVideoFeedTable.h"
#import "DKVideoFullscreen.h"
#import <math.h>
#import <objc/runtime.h>

static BOOL gDKDetailHooksInstalled;
static const CGFloat kDKDetailHeightTolerance = 0.5;
static NSUInteger gDKDetailPrepareRuns;
static NSUInteger gDKDetailPrepareChanges;
struct DKDetailHeightStats {
    NSUInteger runs;
    NSUInteger changes;
};
static DKDetailHeightStats gDKDetailFixedStats = {};
static DKDetailHeightStats gDKDetailIndexStats = {};
static DKDetailHeightStats gDKDetailRowStats = {};

static void DKPrepareDetailTable(AWEAwemeDetailTableViewController *controller,
                                 UITableView *table) {
    if (!DKVideoFullscreenOn()) return;
    gDKDetailPrepareRuns++;
    if (DKVideoFeedTablePrepareForController(controller, table)) {
        gDKDetailPrepareChanges++;
    }
}

// 仅统一已接管表中的整页行高；原生特殊行、自动尺寸和未就绪尺寸继续使用原返回值。
static double DKDetailRowHeight(UITableView *table, double nativeHeight,
                                DKDetailHeightStats *stats) {
    if (!DKVideoFullscreenOn() || !NSThread.isMainThread) return nativeHeight;
    stats->runs++;
    NSNumber *original = DKVideoFeedTableOriginalHeight(table);
    CGFloat target = CGRectGetHeight(table.bounds);
    if (!original || !isfinite(nativeHeight) || !isfinite(target)
        || nativeHeight <= 0.0 || target <= original.doubleValue + kDKDetailHeightTolerance) {
        return nativeHeight;
    }
    if (fabs(nativeHeight - original.doubleValue) > kDKDetailHeightTolerance
        && fabs(nativeHeight - target) > kDKDetailHeightTolerance) {
        return nativeHeight;
    }
    if (fabs(nativeHeight - target) > kDKDetailHeightTolerance) stats->changes++;
    return target;
}

NSString *DKVideoDetailTableStats(void) {
    return [NSString stringWithFormat:
        @"详情行高 Hook=%@  详情建行前准备 跑=%lu 补正=%lu  固定行高 跑=%lu 修正=%lu  "
         "索引行高 跑=%lu 修正=%lu  表代理行高 跑=%lu 修正=%lu",
        gDKDetailHooksInstalled ? @"已安装" : @"入口缺失",
        (unsigned long)gDKDetailPrepareRuns, (unsigned long)gDKDetailPrepareChanges,
        (unsigned long)gDKDetailFixedStats.runs, (unsigned long)gDKDetailFixedStats.changes,
        (unsigned long)gDKDetailIndexStats.runs, (unsigned long)gDKDetailIndexStats.changes,
        (unsigned long)gDKDetailRowStats.runs, (unsigned long)gDKDetailRowStats.changes];
}

%group DKVideoDetailTableHooks

%hook AWEAwemeDetailTableViewController

- (void)setupDetailTableView {
    %orig;
    if (DKVideoFullscreenOn()) DKPrepareDetailTable(self, self.tableView);
}

- (void)viewWillLayoutSubviews {
    if (DKVideoFullscreenOn()) DKPrepareDetailTable(self, self.tableView);
    %orig;
    if (DKVideoFullscreenOn()) DKPrepareDetailTable(self, self.tableView);
}

- (double)fixedCellHeight {
    if (!DKVideoFullscreenOn()) return %orig;
    UITableView *table = self.tableView;
    DKPrepareDetailTable(self, table);
    double nativeHeight = %orig;
    return DKDetailRowHeight(table, nativeHeight, &gDKDetailFixedStats);
}

- (double)cellHeightAtIndex:(long long)index {
    if (!DKVideoFullscreenOn()) return %orig;
    UITableView *table = self.tableView;
    DKPrepareDetailTable(self, table);
    double nativeHeight = %orig;
    return DKDetailRowHeight(table, nativeHeight, &gDKDetailIndexStats);
}

- (double)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!DKVideoFullscreenOn()) return %orig;
    DKPrepareDetailTable(self, table);
    double nativeHeight = %orig;
    return DKDetailRowHeight(table, nativeHeight, &gDKDetailRowStats);
}

- (double)contentOffsetYForCellAtIndex:(long long)index {
    if (DKVideoFullscreenOn()) DKPrepareDetailTable(self, self.tableView);
    return %orig;
}

- (void)adjustTableViewHeightForTargetIndex:(long long)index {
    if (DKVideoFullscreenOn()) DKPrepareDetailTable(self, self.tableView);
    %orig;
    if (DKVideoFullscreenOn()) DKPrepareDetailTable(self, self.tableView);
}

%end

%end

%ctor {
    Class controllerClass = NSClassFromString(@"AWEAwemeDetailTableViewController");
    SEL selectors[] = {
        @selector(setupDetailTableView), @selector(viewWillLayoutSubviews),
        @selector(fixedCellHeight), @selector(cellHeightAtIndex:),
        @selector(tableView:heightForRowAtIndexPath:),
        @selector(contentOffsetYForCellAtIndex:),
        @selector(adjustTableViewHeightForTargetIndex:)
    };
    for (SEL selector : selectors) {
        if (!class_getInstanceMethod(controllerClass, selector)) return;
    }
    %init(DKVideoDetailTableHooks);
    gDKDetailHooksInstalled = YES;
}
