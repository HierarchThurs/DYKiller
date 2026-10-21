// iPad 推荐页在计算整页行高前准备视频表，覆盖评论分栏与旋转引起的重建。

#import "DouyinHeaders.h"
#import "DKVideoFeedTable.h"
#import "DKVideoFullscreen.h"
#import <math.h>
#import <objc/runtime.h>

static BOOL gDKPadFeedHeightInstalled;
static NSUInteger gDKPadFeedHeightRuns;
static NSUInteger gDKPadFeedPrepareChanges;
static NSUInteger gDKPadFeedHeightChanges;
static const CGFloat kDKPadFeedHeightTolerance = 0.5;

NSString *DKVideoPadFeedTableStats(void) {
    return [NSString stringWithFormat:@"iPad 首页行高 Hook=%@ 跑=%lu 表准备=%lu 行高修正=%lu",
        gDKPadFeedHeightInstalled ? @"已安装" : @"未启用",
        (unsigned long)gDKPadFeedHeightRuns, (unsigned long)gDKPadFeedPrepareChanges,
        (unsigned long)gDKPadFeedHeightChanges];
}

%group DKVideoPadFeedTableHooks

%hook AWEFeedTableViewController

- (double)cellHeight {
    if (!DKVideoFullscreenOn() || !NSThread.isMainThread) return %orig;
    UITableView *table = self.tableView;
    if (!table || !CGAffineTransformIsIdentity(table.transform)) return %orig;
    gDKPadFeedHeightRuns++;
    if (DKVideoFeedTablePrepareForController(self, table)) gDKPadFeedPrepareChanges++;
    double nativeHeight = %orig;

    // 仅接管已撑高表中的整页行，保留原生特殊高度与未就绪尺寸。
    NSNumber *original = DKVideoFeedTableOriginalHeight(table);
    CGFloat target = CGRectGetHeight(table.bounds);
    if (!original || !isfinite(nativeHeight) || !isfinite(target) || nativeHeight <= 0.0
        || target <= original.doubleValue + kDKPadFeedHeightTolerance
        || (fabs(nativeHeight - original.doubleValue) > kDKPadFeedHeightTolerance
            && fabs(nativeHeight - target) > kDKPadFeedHeightTolerance)) {
        return nativeHeight;
    }
    if (fabs(nativeHeight - target) > kDKPadFeedHeightTolerance) gDKPadFeedHeightChanges++;
    return target;
}

%end

%end

%ctor {
    if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad) return;
    Class controllerClass = NSClassFromString(@"AWEFeedTableViewController");
    if (!class_getInstanceMethod(controllerClass, @selector(cellHeight))) return;
    %init(DKVideoPadFeedTableHooks);
    gDKPadFeedHeightInstalled = YES;
}
