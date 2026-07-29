//
//  DouyinHeaders.h
//  抖音私有类的最小前向声明（只声明本插件用到的成员）。
//  按"功能类 / 设置系统"分区；新增功能用到新类时在对应区追加即可。
//

#ifndef DouyinHeaders_h
#define DouyinHeaders_h

#import <UIKit/UIKit.h>

#pragma mark - 详情页视频功能组用到的类

@interface AWEAwemeDetailTableViewController : UIViewController
@property (nonatomic, copy) NSString *referString;
- (BOOL)canShowFixedBottomBar;
- (void)setBottomBarHidden:(BOOL)hidden;
- (NSString *)realReferString;
@end

@interface AWEAwemeIMDetailTableViewController : AWEAwemeDetailTableViewController   // 私信「分享视频」详情页专属表控制器（作用域判定用）
@end

@interface AWEVideoModel : NSObject                                 // 视频信息（取宽高判比例）
@property (nonatomic, strong) NSNumber *width;
@property (nonatomic, strong) NSNumber *height;
@end

@interface AWEAwemeModel : NSObject                                 // 单条内容模型
@property (nonatomic, strong) AWEVideoModel *video;
@property (nonatomic, assign) long long awemeType;
@end

// 视频+交互合并容器。其 .view 用于视频容器布局调整。
@interface AWEDPlayerViewController_Merge : UIViewController
@property (nonatomic, strong) AWEAwemeModel *model;                 // 取视频宽高做比例限幅
@property (nonatomic, assign) BOOL hasInlandscape;                  // 横屏视频判据（横屏排除全屏）
@property (nonatomic, strong) UIView *gradientBackgroundView;       // 评论 shrink 会调整该渐变透明度
@property (nonatomic, copy) NSString *referString;                  // 页面来源，用于限定搜索详情页
- (BOOL)isInLandscapeFeedStatus;
- (void)videoDidShrink;
@end

// 视频播放控制器。抖音把横屏智能背景色画在 playerBackgroundView 上（插入其 view 的最底层）。
@interface AWEPlayVideoViewController : UIViewController
@property (nonatomic, strong) UIView *playerBackgroundView;
@end

@interface AWEDPlayerProgressContainerView : UIView                // 进度条容器；底边压着一条纯黑细条
@end

@interface AWEGradientView : UIView                                // HUD 可读性压暗渐变
@end

@interface AWEIMFeedVideoQuickReplayInputViewController : UIViewController  // 底部快捷回复栏控制器
@end

@interface AWEPlayInteractionViewController : UIViewController      // HUD 控制器；评论态其 view 顶部会被塞状态栏黑底，全屏时需压掉
@property (nonatomic, assign) BOOL hideMusicInfo;
@property (nonatomic, copy) NSString *referString;
@end

// 首页与朋友页共用的 feed 表；被底栏压掉一个底栏高，是首页全屏的源头层。
@interface AWEFeedTableView : UITableView
@end

#pragma mark - 底栏功能组用到的类

// 抖音自绘底栏。它自身的 hidden/alpha 是抖音全部显隐逻辑的唯一汇聚点，可直接当镜像源。
@interface AWENormalModeTabBar : UITabBar
@end

#pragma mark - 评论区功能组用到的类

@interface AWECommentContainerViewController : UIViewController
@end

@interface AWEListKitMagicCollectionView : UICollectionView
@end

@interface AWECommentInputBackgroundView : UIView                   // 详情页底部输入栏，是 AWECommentInputViewController 的根视图
@end

#pragma mark - 播放体验功能组用到的类

@interface AWEPlayInteractionFollowPromptView : UIView             // 头像下方「关注(+)」容器；整视图仅含 + 图标
@end

#pragma mark - 个人主页功能组用到的类

@interface AWEUserProfileUGCContributionGuideEmptyCollectionViewCell : UICollectionViewCell
@property (nonatomic, strong) UIView *bodyView;
+ (double)viewHeight;
@end

#pragma mark - 抖音设置系统（注入设置菜单用）

@interface AWESettingItemModel : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, assign) NSInteger type;
@property (nonatomic, copy) NSString *svgIconImageName;
@property (nonatomic, assign) NSInteger cellType;
@property (nonatomic, assign) NSInteger colorStyle;
@property (nonatomic, assign) BOOL isEnable;
@property (nonatomic, assign) BOOL isSwitchOn;
@property (nonatomic, copy) void (^cellTappedBlock)(void);
@property (nonatomic, copy) void (^switchChangedBlock)(void);
@end

@interface AWESettingSectionModel : NSObject
@property (nonatomic, assign) NSInteger type;
@property (nonatomic, assign) CGFloat sectionHeaderHeight;
@property (nonatomic, copy) NSString *sectionHeaderTitle;
@property (nonatomic, strong) NSArray *itemArray;
@end

@interface AWESettingBaseViewModel : NSObject
@end

@interface AWESettingsViewModel : AWESettingBaseViewModel
@property (nonatomic, assign) NSInteger colorStyle;
@property (nonatomic, strong) NSArray *sectionDataArray;
@property (nonatomic, weak) id controllerDelegate;
@end

@interface AWESettingBaseViewController : UIViewController
- (AWESettingBaseViewModel *)viewModel;
@end

@interface AWENavigationBar : UIView
@property (nonatomic, strong) UILabel *titleLabel;
@end

#endif /* DouyinHeaders_h */
