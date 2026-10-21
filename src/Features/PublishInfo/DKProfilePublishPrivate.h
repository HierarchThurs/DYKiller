#import "DouyinHeaders.h"

@class AWEUserWorkCellContext;

@interface AWEUserWorkCellComponentConfig : NSObject
@property (nonatomic) NSInteger profileTabType;
@end

@interface AWEUserWorkCellBaseComponent : NSObject
@property (nonatomic, strong) AWEAwemeModel *data;
@property (nonatomic, strong) AWEUserWorkCellContext *context;
- (void)setNeedsUpdate;
@end

@interface AWEUserWorkCellContext : NSObject
@property (nonatomic, strong) AWEAwemeModel *data;
@property (nonatomic, strong) AWEUserWorkCellComponentConfig *componentConfig;
@property (nonatomic) CGSize cellSize;
@end

@interface AWEUserWorkCellViewModel : NSObject
@property (nonatomic, strong) AWEUserWorkCellContext *cellContext;
@property (nonatomic, strong) AWEUserWorkCellBaseComponent *rootComponent;
@property (nonatomic) CGFloat width;
@property (nonatomic, strong) NSIndexPath *indexPath;
- (void)refreshWithWidth:(CGFloat)width indexPath:(NSIndexPath *)indexPath;
@end

@interface AWEUserWorkCollectionViewComponentCell : UICollectionViewCell
@property (nonatomic, strong) AWEUserWorkCellViewModel *viewModel;
@property (nonatomic, strong) UIImageView *coverContainerView;
- (void)configWithViewModel:(AWEUserWorkCellViewModel *)viewModel;
@end

@interface AWEUserWorkCellNormalRootComponent_NEWAPI : AWEUserWorkCellBaseComponent
@property (nonatomic, strong) NSArray *subComponents;
@end

@interface AWEUserWorkCellCoverContainerComponent_NEWAPI : AWEUserWorkCellBaseComponent
@property (nonatomic, strong) NSArray *subComponents;
@end

@interface AWEUserWorkCellLeftBottomContainerComponent_NEWAPI : AWEUserWorkCellBaseComponent
@property (nonatomic, strong) NSDictionary *componentDict;
@end

@interface AWEUserWorkCellIconLabelStarAtlasTagLabelComponent_NEWAPI : AWEUserWorkCellBaseComponent
@property (nonatomic, strong) AWERLVirtualView *iconViewVirtualView;
@property (nonatomic, strong) AWERLVirtualView *countLabelVirtualView;
@end

@interface AWEUserWorkWaterFallBottomView : UIView
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UIImageView *iconImageView;
@property (nonatomic, strong) UIButton *iconCountActionBtn;
- (void)setDateStringWith:(NSString *)date;
@end

@interface AWEUserWorkCellWaterFallBottomContainerComponent_NEWAPI : AWEUserWorkCellBaseComponent
@property (nonatomic, strong) AWERLVirtualView *containerVirtualView;
- (void)configBottomView:(AWEUserWorkWaterFallBottomView *)view;
@end

@interface AWEProfileWaterfallHelper : NSObject
- (CGFloat)calculateCellHeight:(NSInteger)style model:(AWEAwemeModel *)model cellWidth:(CGFloat)width
                       isMine:(BOOL)mine interactionTopPadding:(CGFloat)padding
       forceHiddenInteraction:(BOOL)hidden profileTabType:(NSInteger)tabType;
@end
