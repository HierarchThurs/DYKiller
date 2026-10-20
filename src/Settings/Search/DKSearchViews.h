// 搜索覆盖层内部的几何、输入控件与结果列表契约。
#ifndef DKSearchViews_h
#define DKSearchViews_h
#import <UIKit/UIKit.h>
#import "DKGlassFlexView.h"
@class DKSearchEntry;
typedef struct {
    CGFloat diameter, edge, gap, radius;
    CGRect fabFrame, closeFrame, capsuleFrame, resultsFrame;
} DKSearchMetrics;
UIEdgeInsets DKSearchInsetsForHost(UIView *host);
DKSearchMetrics DKSearchMetricsMake(CGSize size, UIEdgeInsets insets, CGFloat keyboardTop);
@interface DKSearchGlassButton : DKGlassFlexView
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UIControl *hitControl;
@property (nonatomic, copy) NSString *symbolName;
- (void)dkSetSymbol:(NSString *)name animated:(BOOL)animated;
@end
@interface DKSearchCapsuleView : DKGlassFlexView
@property (nonatomic, strong) UIImageView *glyphView;
@property (nonatomic, strong) UITextField *textField;
- (void)dkSetContentAlpha:(CGFloat)alpha;
@end
@interface DKSearchPanelView : DKGlassFlexView
@property (nonatomic, assign) CGFloat radius;
@end
/// 圆钮与胶囊的玻璃容器：iOS 26 起把内部玻璃合成为一块，间距小于 mergeSpacing 时相互融合；自身不接收触摸。
@interface DKSearchGlassGroupView : UIVisualEffectView
@property (nonatomic, assign) CGFloat mergeSpacing;
@end
@interface DKSearchResultsView : UITableView <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSArray<DKSearchEntry *> *entries;
@property (nonatomic, copy) void (^didChooseEntry)(DKSearchEntry *entry);
@end
#endif
