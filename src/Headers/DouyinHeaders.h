//
//  DouyinHeaders.h
//  抖音私有类的最小前向声明（只声明本插件用到的成员）。
//  按"功能类 / 设置系统"分区；新增功能用到新类时在对应区追加即可。
//

#ifndef DouyinHeaders_h
#define DouyinHeaders_h

#import <UIKit/UIKit.h>

#pragma mark - 播放交互右侧功能区

@interface AWEElementStackView : UIStackView
@end

@interface AWEFeedVideoButton : UIButton
@property (nonatomic, copy) NSString *imageNameString;
@property (nonatomic, readonly, strong) UIImageView *buttonImageView;
@property (nonatomic, strong) UIImageView *aweImageView;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UILabel *buttonLabel;
@property (nonatomic, strong) UIView *containerView;
@end

// AWEFeedVideoButton 的图片容器，buttonImageView 的尺寸在它布局时排出。
@interface AWEFeedVideoButtonContainerView : UIView
@end

@interface AWEPlayInteractionListenFeedView : UIView
- (void)layoutWithSize:(CGSize)size;
@end

@interface AWEMusicCoverButton : UIButton
@end

@interface AWEPlayInteractionUserProfileContainerView : UIView
@end

@interface AWEPlayInteractionUserProfilePictureView : UIView
@property (nonatomic, strong) UIButton *avatarButton;
- (CGRect)getAvatarFrame;
@end

@interface AWEPlayInteractionFollowPromptView : UIView
@end

#pragma mark - 播放页精简用到的类

// 元素栈的一行；element 为元素对象（AWEBaseElement 子类）。
@interface AWEBaseElementView : UIView
@end

// 播放页中部「全屏观看」入口及其控制器。
@interface AWELandscapeFeedEntryView : UIView
@end

@interface AWEPlayInteractionLandscapeFeedController : NSObject
- (BOOL)enableShowEntryView;
@end

// 作者元素的昵称右侧标签管理器；activedComponents 为当前显示的标签组件。
@interface AWEVideoTagsPriorityManager : NSObject
- (void)updateWithData:(id)data context:(id)context;
@end

// 标签元素（AWEPlayInteractionTagsElement）里的三类子视图。
@interface AFDRecommendToFriendEntranceLabel : UIView
@end

@interface AWEFeedRelationView : UIView
@end

@interface AWEPlayInteractionGeneralTagView : UIView
@end

#pragma mark - 详情页视频功能组用到的类

@class AWEAwemeDetailTableView;

@interface AWEAwemeDetailTableViewController : UIViewController
@property (nonatomic, strong) AWEAwemeDetailTableView *tableView;
@property (nonatomic, copy) NSString *referString;
- (BOOL)canShowFixedBottomBar;
- (void)setBottomBarHidden:(BOOL)hidden;
- (NSString *)realReferString;
- (void)setupDetailTableView;
- (double)fixedCellHeight;
- (double)cellHeightAtIndex:(long long)index;
- (double)contentOffsetYForCellAtIndex:(long long)index;
- (void)adjustTableViewHeightForTargetIndex:(long long)index;
@end

@interface AWEAwemeIMDetailTableViewController : AWEAwemeDetailTableViewController   // 私信「分享视频」详情页专属表控制器（作用域判定用）
@end

@interface AWEVideoModel : NSObject                                 // 视频信息（取宽高判比例）
@property (nonatomic, strong) NSNumber *width;
@property (nonatomic, strong) NSNumber *height;
@end

@interface AWEAwemeModel : NSObject                                 // 单条内容模型
@property (nonatomic, strong) AWEVideoModel *video;
@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, assign) long long awemeType;
- (id)initWithDictionary:(id)raw error:(NSError **)error;
@end

// 视频+交互合并容器。其 .view 用于视频容器布局调整。
@interface AWEDPlayerViewController_Merge : UIViewController
@property (nonatomic, strong) AWEAwemeModel *model;                 // 取视频宽高做比例限幅
@property (nonatomic, assign) BOOL hasInlandscape;                  // 本次播放点过「全屏观看」：退出横屏不清零，播放结束才清零
@property (nonatomic, strong) UIView *gradientBackgroundView;       // 评论 shrink 会调整该渐变透明度
@property (nonatomic, copy) NSString *referString;                  // 页面来源，用于限定搜索详情页
- (BOOL)isInLandscapeFeedStatus;
- (void)videoDidShrink;
- (BOOL)isPlaying;
- (void)play;                                                       // 真正的播放入口，经 videoShouldPlay
- (void)pause;
- (BOOL)shouldPreventPlay;                                          // videoShouldPlay 的第一条判据
- (BOOL)videoShouldPlay;                                            // 播放前的总闸门
@end

// 视频播放控制器。抖音把横屏智能背景色画在 playerBackgroundView 上（插入其 view 的最底层）。
// playerWillLoopPlaying: 是播放引擎的循环回调，本类自己实现（发 OnPlayerWillLoopPlayingEvent、
// 写 loopTimes、finishLogIfNeeded），播完一遍必到；它是 Merge 的子控制器。
@interface AWEPlayVideoViewController : UIViewController
@property (nonatomic, strong) UIView *playerBackgroundView;
- (void)playerWillLoopPlaying:(id)player;
@end

@interface AWEDPlayerProgressContainerView : UIView                // 进度条容器；底边压着一条纯黑细条
@end

@interface AWEGradientView : UIView                                // HUD 可读性压暗渐变
@end

@interface AWEDPlayerComponentInteraction : NSObject
@property (nonatomic, strong) AWEAwemeModel *model;
@property (nonatomic, strong) id playerController;
- (void)addGradientViews;
- (void)hideGradientViewIfNeeded:(id)player;
@end

@interface AWEIMFeedVideoQuickReplayInputViewController : UIViewController  // 底部快捷回复栏控制器
@end

@interface AWEPlayInteractionViewController : UIViewController      // HUD 控制器；评论态其 view 顶部会被塞状态栏黑底，全屏时需压掉
@property (nonatomic, assign) BOOL hideMusicInfo;
@property (nonatomic, copy) NSString *referString;
- (void)performCommentAction;
- (BOOL)isCommentVCShowing;
- (void)onPlayer:(id)player didDoubleClick:(id)event;
- (void)onVideoPlayerViewDoubleClicked:(id)event;
@end

@interface AFDStoryPlayInteractionViewController : AWEPlayInteractionViewController
@end

// 图文整页的背景层，挂在图文列表控制器 view 的直接子层，与内容类型无关。
// +layerClass 是 CAGradientLayer；全屏时用 transform 纵向拉伸以延伸到底栏（不改 frame）。
@interface AWEKnowledgeGradientView : UIView
@end

// 图文横滑内容集合；完成 visibleCells 布局后同步贴底压暗，并解除其祖先链上的实际裁剪点。
@interface AWEStoryContainerCollectionView : UICollectionView
@end

// 图文的顶层容器控制器。首页、朋友页、好友聊天页三种图文列表实现都挂在它下面，
// 且全部类导出里只有它声明 updateShrinkState:——那是图文版的 videoDidShrink。
@interface RichContentContainerViewController : UIViewController
@property (nonatomic, readonly, strong) UIViewController *contentListViewController;  // 图文列表实现，背景渐变挂在它 view 下
- (void)updateShrinkState:(BOOL)shrink insets:(UIEdgeInsets)insets animated:(BOOL)animated;
@end

// 视频表的基类。首页/朋友页的 AWEFeedTableView 与好友聊天/搜索/其他用户主页的
// AWEAwemeDetailTableView 都从它派生；被底栏压掉一个底栏高时就是视频不全屏的源头层。
@interface AWEFeedDataSafeTableView : UITableView
@end

@interface AWEFeedTableView : AWEFeedDataSafeTableView              // 首页 / 朋友页
@end

@interface AWEAwemeDetailTableView : AWEFeedDataSafeTableView        // 好友聊天 / 搜索 / 用户作品详情
@end

// 视频表控制器。40.7.0 中表可能先在未挂入父视图时完成 setFrame:，在控制器布局完成后补一次子表修正。
@interface AWEFeedTableViewController : UIViewController
@property (nonatomic, strong) AWEFeedTableView *tableView;
@property (nonatomic, strong) id dataController;
@property (nonatomic, copy) NSString *referString;
- (id)initWithType:(long long)type dataController:(id)data;
- (void)setupFeedContainerWithType:(long long)type dataController:(id)data;
- (NSString *)currentReferString;
@end

// 直播预览的四层容器（背景 / 画面 / 内容 / 控件）。画面与背景按窗口尺寸排，chrome 挂在容器高度上：
// 表被撑高后容器跟着变高，贴底的那套元素就整体下移一个底栏高，需要叠 transform 抬回去。
// 具名槽位除 bottomDarkWatermark 外均为调试探针采集用。
@interface AWELivePreStream4LayerContainerView : UIView
@property (nonatomic, strong) UIImageView *bottomDarkWatermark;     // 底部暗水印，抬升目标之一
@property (nonatomic, readonly, strong) UIView *gradientContainerView;
@property (nonatomic, readonly, strong) UIView *controlContainer;
@property (nonatomic, strong) UIView *leftContainer;
@property (nonatomic, strong) UIView *centerContainer;
@property (nonatomic, strong) UIView *bottomContainer;
@end

#pragma mark - 底栏功能组用到的类

// iPad 紧凑底栏两侧的元素按钮（连播 / 弹幕 / 倍速等）。图标、文字与折叠态都由抖音按 viewModel 绘制。
@interface AWETabBarElementButton : UIButton
@property (nonatomic, strong) UILabel *elementLabel;
@end

// 元素按钮容器：按钮放在 scrollView 里，elementButtons 是复用池，不在当前列表里的按钮 hidden=YES。
// 容器 frame 由底栏布局写入，scrollView 与按钮 frame 由 p_refreshLayout 写入。
@interface AWETabBarElementContainerView : UIView
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) NSMutableArray *elementButtons;
- (void)p_refreshLayout;
@end

// 抖音自绘底栏。它自身的 hidden/alpha 是抖音全部显隐逻辑的唯一汇聚点，可直接当镜像源。
@interface AWENormalModeTabBar : UITabBar
@property (nonatomic, strong) AWETabBarElementContainerView *leftElementContainerView;
@property (nonatomic, strong) AWETabBarElementContainerView *rightElementContainerView;
@end

// 底栏文字视图的配置（文字项为 TextViewUIConfig、首页为 FeedUIConfig，均继承此类）。抖音按选中状态与明暗进度
// 算好的文字色同步写进 textColor，文字视图再经绑定延后同步到 label。
@interface AWENormalModeTabBarInnerViewUIConfig : NSObject
@property (nonatomic, strong) UIColor *textColor;
@end

// 商城底栏宿主控制器（AWEECNewBottomMallViewController / AWEECNewMallViewController 的基类）。
// mallMainVC 为实际承载 Mita 页面树的 IESECMallCoreViewController。
@interface AWEECMallBaseViewController : UIViewController
@property (nonatomic, strong) UIViewController *mallMainVC;
@end

@interface AWEECNewBottomMallViewController : AWEECMallBaseViewController
- (void)buildUI;
@end

@interface AWEECNewMallViewController : AWEECMallBaseViewController
- (void)buildUI;
@end

// 个人主页二级分页容器（收藏页 AWEFavoriteV2ViewController_New 等的内部列表控制器）。
@interface AWETabContainerSectionController : NSObject
- (UIViewController *)tabContentViewController;
@end

@interface AWEProfileBaseContainerViewController : UIViewController
@property (nonatomic, assign) BOOL isInUserHomePage;
@property (nonatomic, assign) BOOL isInLandingPage;
@property (nonatomic, strong) AWETabContainerSectionController *tabContainerSectionController;
- (UICollectionView *)awe_baseCollectionView;
- (double)heightForSectionController:(id)sectionController;
- (void)setupCollectionView:(UICollectionView *)collectionView;
@end

#pragma mark - 评论区功能组用到的类

@interface AWECommentContainerViewController : UIViewController
@end

// 评论图片大图页。主集合视图按 item 分页，底部输入栏是其根视图的独立子层。
// backButton 是左上角返回键，点击走 previewDismissByClickBackBtn。
@interface AWECommentMediaFeedViewController : UIViewController
@property (nonatomic, assign) long long currentIndex;
@property (nonatomic, strong) UIButton *backButton;
- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath;
- (void)previewDismissByClickBackBtn;
@end

// 大图页内部图片 Cell。mediaContainerView 承载静态图片或 Live Photo 预览。
@interface AWECommentMediaFeedImageCell : UICollectionViewCell
- (UIView *)mediaContainerView;
@end

// 评论区放大到全屏时被 push 上来的容器。它带整套 transition_* 协议方法，配 AWECommentFullScreenZoomTransition
// 与 CommentFullScreenZoomAnimator——是自定义交互式转场的目标，不能拦下这次 push 改用控制器包含：
// 转场框架在 push 之前已建好 context 并禁用交互，吞掉 %orig 它的完成回调就永远不来。
@interface AWECommentFullScreenContainerViewController : UIViewController
@end

// 视频侧的评论面板控制器。内嵌画中画（全屏评论区里把视频交出去、缩成右上角小窗）归它管，
// enableShowInnerPiPWhenFullScreen 是这条功能的唯一闸门：enter / show / exit /
// tryToPause / tryToPlay / viewDidLoad / commentVC 每个入口都先问它。
@interface AWEPlayInteractionCommentPanelController : NSObject
- (BOOL)enableShowInnerPiPWhenFullScreen;
@end

// 弹幕渲染结构：正文与点赞数字都可能使用 AWEDanmakuContentLabel，调用方须通过 contentLabel 关系区分。
@interface AWEDanmakuContentLabel : UILabel
@property (nonatomic, assign) long long type;
@property (nonatomic, copy) NSString *danmakuText;
@property (nonatomic, copy) NSArray *danmakuStyleList;
@property (nonatomic, strong) UIColor *strokeColor;
@property (nonatomic, assign) double strokeWidth;
- (id)initWithFrame:(CGRect)frame textColor:(UIColor *)textColor type:(long long)type;
@end

@interface AWEDanmakuItemDescriptor : NSObject
@property (nonatomic, readonly) id danmakuModel;
@end

@interface AWEDanmakuDiggNumView : UIView
@property (nonatomic, strong) UIImageView *diggImageView;
@property (nonatomic, strong) AWEDanmakuContentLabel *diggNumLabel;
- (void)updateDiggImageAndDiggLabel;
- (void)configDanmakuDiggImageWithModel:(id)model;
- (void)updateLayOutIfNeed;
@end

@interface AWEDanmakuItemCommonView : UIView
@property (nonatomic, strong) AWEDanmakuContentLabel *contentLabel;
@property (nonatomic, strong) AWEDanmakuDiggNumView *diggNumView;
@property (nonatomic, strong) id danmaKuModel;
- (void)updateWithDescriptor:(id)descriptor;
- (void)prepareForReuse;
- (void)updateDanmaKuUnitView;
@end

@interface AWEDanmakuItemAuthorView : AWEDanmakuItemCommonView
@end
@interface AWEDanmakuItemActivityView : AWEDanmakuItemCommonView
@end
@interface AWEDanmakuItemAdView : AWEDanmakuItemCommonView
@end

@interface AWEPlayInteractionDanmakuStylesInfo : NSObject
@property (nonatomic, assign) double danmakuAlpha;
@end
@interface AWEDanmakuConfigSettingManager : NSObject
@property (nonatomic, strong) AWEPlayInteractionDanmakuStylesInfo *verticalStylesInfo;
@property (nonatomic, strong) AWEPlayInteractionDanmakuStylesInfo *landscapeStylesInfo;
+ (instancetype)sharedInstance;
@end

// 弹幕渲染层。抖音开评论面板时就是把这一层的 alpha 压成 0（实测半屏 / 全屏都是），
// 容器与各条弹幕视图本身不动。
@interface DDanmakuPlayerView : UIView
@end

// 弹幕渲染引擎。DDanmakuPlayer 在弹幕层每轮布局时把 frame 写成弹幕层 bounds，
// 宽度变化会让在屏弹幕按新宽度重排。view 是引擎挂载的宿主视图。
@interface DDanmakuRenderEngine : NSObject
@property (nonatomic, strong) UIView *view;
@property (nonatomic, assign) CGRect frame;
@end

// 首页弹幕业务控制器。viewDidLayoutSubviews 用弹幕容器父视图的 bounds 与 lastDanmakuContainerBounds
// 比较，不同即重新布局弹幕，并经容器控制器 pause → clearAllDisplayingDanmakus → play 重新开始。
@interface AWEDanmakuFeedController : NSObject
@property (nonatomic, readonly) UIView *danmakuContainerView;
@property (nonatomic, assign) CGRect lastDanmakuContainerBounds;
@end

@interface AWEListKitMagicCollectionView : UICollectionView
@end

// 评论区「不透明绘制优化」的 AB 网关（class-dump 自 39.9.0 的 AwemeCore，纯 ObjC 类）。
// 热更新翻的是实验位 AWERenderingOptimize4；打开后抖音把面板底色写进列表容器与每一个
// UIKit 文字视图的 backgroundColor。参数是抖音自己的上下文，本项目不解读。
@interface AWECommentABTestSettings : NSObject
+ (BOOL)enableCommentRenderingOptimize:(id)context;
// 打开时评论图片大图页在每次 viewDidLayoutSubviews 里按自己的口径重设集合视图 frame 并回卷到 currentIndex。
+ (BOOL)enableCommentAdaptiveWindowResponsiveLayout;
@end

@interface AWECommentInputBackgroundView : UIView                   // 详情页底部输入栏，是 AWECommentInputViewController 的根视图
@end

@interface AWEIMEmoticonPanelContainerView : UIView                 // 表情面板；评论区复用 IM 那一套，挂在输入容器里
@end

// 回复输入区上方那条小表情栏。它是键盘的输入附件，住在 UITextEffectsWindow 里，
// 不在评论控制器的视图树内——只能按类名挂钩，遍历评论容器找不到它。
@interface AWECommentMiniEmoticonPanelView : UIView
@end

// 零评论作品打开评论面板时，输入区上方那条「发布你的第一条评论」引导栏。同样住在
// UITextEffectsWindow 里；底色由输入区在每次键盘弹出 / 收起时写入（40.8.0 实测）。
@interface AWECommentPublishGuidanceView : UIView
@end

// 点工具栏「@」拉起的艾特面板（横排头像 / 搜索结果表 / 加载与出错页）。
// obtainPanelColor 是它唯一的取底色口：39.9.0 反汇编实测本类内 5 处引用，
// 5 处的返回值都直接进 setBackgroundColor:，没有一处当文字色或描边色用。
@interface AWECommentSearchViewController : UIViewController
- (id)obtainPanelColor;
@end

#pragma mark - 分享面板功能组用到的类

// DUX 底栏弹层的通用基类。分享面板容器与分享评论面板（评论长按面板）都从它派生，
// 后者的类名带点、Logos 挂不上，只能挂基类再按类名判定。
@interface DUXContentSheet : UIViewController
@end

// DUX 底栏弹层外壳。contentView 是带 20pt 顶圆角的 DUXVisualEffectView，目前几乎不模糊。
@interface AWESharePanelContainerViewController : UIViewController
@end

@interface AWESharePanelViewController : UIViewController
- (void)awe_themeReload;
@end

// 功能圆钮：主 imageView 承载圆底或合成图，smallImageView 承载独立小图标。
@interface AWESharePanelFunctionCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIImageView *smallImageView;
- (void)setupViews;
- (void)updateWithViewModel:(id)viewModel bigFontAdapter:(id)adapter;
- (void)updateImageViewWithViewModel:(id)viewModel;
@end

@interface AWEShareContext : NSObject
@property (nonatomic, readonly) AWEAwemeModel *aweme;
@end

@interface AWESharePanelFunctionsDataManager : NSObject
@property (nonatomic, copy) NSArray *dataSource;
- (void)fetchSharePanelFunctionConfigWithScene:(id)scene shareContext:(AWEShareContext *)context
                         customConfiguration:(id)configuration shareView:(id)shareView;
@end

// 分享评论面板里「复制该评论」「收藏」那种行。白卡片底不是 backgroundColor，
// 而是行内一层非视图 CALayer（ivar contentShapeLayer），整段 section 拼成一张卡。
@interface CommentLongPressPanelNormalBaseCell : UICollectionViewCell
@end

// 键盘拉起后挂在输入覆盖层下方；setTabBackgroundColor: 会重刷底色。
@interface AWEIMShareInputEmoticonToolBarView : UIView
@property (nonatomic, strong) UIView *inputControlBar;
@property (nonatomic, strong) UIView *panelContainerView;
@property (nonatomic, strong) UIView *lineSeparator;
- (void)setTabBackgroundColor:(id)color;
@end

// IM 通用底部提示壳，直接挂在窗口的 UITransitionView 下，不属于任何 VC。
// 白底 + 圆角 12，contentView 是本次要接管的分享提示。
@interface AWEIMBottomTipsContainerView : UIView
@property (nonatomic, strong) UIView *contentView;
- (void)show;
@end

// 分享成功提示「已私信给 xxx / 捎句话 >」：头像 28×28、标题近黑、tips 与 tag 为彩色。
@interface AWEIMBottomShareTipsView : UIView
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *tipsLabel;
- (void)updateTipsLabelWithText:(id)text;
@end

#pragma mark - 应用内通知功能组用到的类

@interface AFDSnackBar : UIView
@property (nonatomic, strong) UIView *bodyView;
@property (nonatomic, strong) id delegate;
- (void)showWithBodyView:(UIView *)bodyView;
@end

@interface AFDSnackBarCustomView : UIView
@end

@interface AWEPlayInteractionSnackBarConfig : NSObject
@property (nonatomic, copy) NSString *identifier;
@end

@interface DUXBottomNotification : UIView
- (void)showOnView:(UIView *)view bottomOffset:(double)offset;
@end

@interface AWEPlayInteractionSnackBar : DUXBottomNotification
@property (nonatomic, strong) AWEPlayInteractionSnackBarConfig *snakeBarConfig;
@end

@interface AWEInnerNotificationContainerView : UIView
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIStackView *contentContainerView;
- (void)renderModel:(id)model context:(id)context;
- (void)viewDidDisappear:(BOOL)animated reason:(long long)reason;
@end

@interface AWEInnerPushCommonView : UIView
@property (nonatomic, strong) UIView *leftExtraIconBackgroundView;
@property (nonatomic, strong) UIImageView *leftExtraIcon;
@property (nonatomic, strong) UIButton *rightActionButton;
@property (nonatomic, strong) UIStackView *middleContentTextStackView;
- (void)updateViewWithRequest:(id)request notificationContent:(id)content viewModel:(id)viewModel;
@end

#pragma mark - 播放体验功能组用到的类

// 关联视频与同体系中长视频详情的原生双击入口。
@interface AWERelatedVideoVideoPlayerViewController : UIViewController
- (void)handleDoubleTap:(id)gesture;
@end

@interface AWERelatedVideoDetailVideoViewController : UIViewController
@end

@interface AWERelatedVideoDetailVideoInteractView : UIView
- (void)handleVideoDoubleTapped;
- (void)onCommentButtonClicked;
@end

// 听抖音页的原生双击与评论入口。
@interface AWEListenFeedOptimizedInteractionViewController : UIViewController
- (void)handleDoubleTap:(id)gesture;
@end

@interface AWEListenFeedPlayControlView : UIView
- (void)commentButtonClicked:(id)sender;
@end

// 播放进度条（首页、朋友页共用）。progressSliderDelegate 为 AWEDProgressCoreContainer。
// sliderRightView 是整宽的未播放轨道（底色即 maximumTrackTintColor），已播段与拇指是叠在其上的图层。
@interface AWEFeedProgressSlider : UIView
@property (nonatomic, weak) id progressSliderDelegate;
@property (nonatomic, strong) UIView *sliderRightView;
@end

// 进度条章节点：按 progressWidth 把章节时间换成点位（加在进度条上），吸附区间与拖动换算同一口径。
// shouldFollowSliderWidthForChapterPoints 为 NO 时章节控制器固定取屏宽 − 24；
// progressTimingViewDidLayoutSubviews 是它自己的重排入口（重置章节缩略图索引、updateChapterSlider、openChapterLoopIfNeed）。
@interface AWEDProgressChapterContainer : NSObject
- (AWEFeedProgressSlider *)progressSlider;
- (double)progressWidth;
- (BOOL)shouldFollowSliderWidthForChapterPoints;
- (BOOL)isChapterStyle;
- (void)progressTimingViewDidLayoutSubviews;
@end

// 进度条各模块共用的共享数据中枢；sharedDataOfID: 按数据 ID 现取（不少为按需求值的块）。
@interface AWEArchEventDataController : NSObject
- (id)sharedDataOfID:(id)dataID;
@end

// 进度条共享数据的 ID；progressStatusVideoDuration 为作品时长（毫秒，NSNumber）。
@interface AWEDProgressCoreDataID : NSObject
+ (id)progressStatusVideoDuration;
@end

// feed 页进度条布局策略：常态 / 唤醒 frame 与 progressWidth 都由左右边距 progressSliderLeftRightArea 算出
// （progressWidth = 布局宽 − 2 × 边距，常态 frame = {边距, y, progressWidth, 2}），每次取 frame 都现取边距。
// 纵向：进度条底边 = 容器高 − posAdjustY + sliderYOffset，常态与唤醒 frame 每次现取 posAdjustY；底部背景不用它。
@interface AWEDProgressLayoutFeedStrategy : NSObject
- (AWEArchEventDataController *)edc;
- (double)posAdjustY;
@end

// 图文作品底部的图片指示器（分段条 / 圆点）。Masonry 约束在左侧栈下方；
// currentProgressViewFrame 为当前一段在本视图坐标里的 frame。
@interface AWEStoryProgressContainerView : UIView
- (CGRect)currentProgressViewFrame;
@end

@class AWEDProgressStateChangeContainer;

// 进度条的总控：播放进度经 updateProgressSliderWithTime:totalDuration: 送到这里（播放中约 0.5 s 一次），
// setProgressState: 写 1 常态 / 2 唤醒态（暂停、拖动）。videoDuration 为作品时长（毫秒），
// lastProgressDuration 为最近一次送来的播放时间（秒）。常态是否透明经它转问 AWEDProgressHidePluginContainer。
// edc 与其布局策略的 edc 为同一个对象。
@interface AWEDProgressCoreContainer : NSObject
- (AWEFeedProgressSlider *)progressSlider;
- (AWEDProgressChapterContainer *)chapterContainer;
- (AWEDProgressStateChangeContainer *)stateChangeContainer;
- (AWEArchEventDataController *)edc;
- (double)videoDuration;
- (double)lastProgressDuration;
- (BOOL)shouldTransparentProgressSliderOnStableState;
@end

// 进度条常态是否透明的判定方：抖音按视频时长返回，短视频为 YES。
@interface AWEDProgressHidePluginContainer : NSObject
- (BOOL)shouldTransparentProgressSliderOnStableState;
@end

// feed 进度条背景的实际属主；getter 返回创建并挂在进度容器中的底边背景。
@interface AWEDProgressFeedContainer : NSObject
- (UIView *)progressSliderUnderView;
@end

// 进度条状态机：常态 / 唤醒态的外观在这里套用；currentState 1 为常态、2 为唤醒态（暂停）。
@interface AWEDProgressStateChangeContainer : NSObject
- (long long)currentState;
- (AWEFeedProgressSlider *)progressSlider;
- (BOOL)shouldTransparentProgressSliderOnStableState;
- (void)reapplyCurrentStateAppearance;
- (UIView *)progressSliderUnderView;
- (void)updateProgressSliderUnderView;
@end

#pragma mark - 内容过滤用到的类

@interface AWEListDataController : NSObject
- (void)setDataSource:(id)array;
- (void)setFilteredDataSource:(id)array;
@end

@interface AWEHotListDataController : AWEListDataController
- (id)transferAwemeListIfNeededWithArray:(id)array isInitFetch:(BOOL)initial;
- (void)p_handleFeedCacheList:(id)array completion:(id)completion;
@end

@interface AWEFeedMultiQueueDataController : AWEListDataController
- (id)transferAwemeListIfNeededWithArray:(id)array isInitFetch:(BOOL)initial;
@end

@interface AWEDCFeedDefaultDataController : AWEListDataController
- (id)transferAwemeListIfNeededWithArray:(id)array isInitFetch:(BOOL)initial;
@end

@interface AWEMixVideoListDataController : AWEListDataController
@end
@interface AWEMixVideoDetailPlayListDataController : AWEListDataController
@end
@interface AWEMixVideoRelatedListDataController : AWEMixVideoListDataController
@end

@interface AWEGeneralSearchModel : NSObject
- (id)initWithDictionary:(id)raw error:(NSError **)error;
@end
@interface AWEOriginalAdModel : NSObject
- (id)initWithDictionary:(id)raw error:(NSError **)error;
@end
@interface TTAdSplashModel : NSObject
- (id)initWithDictionary:(id)raw;
- (id)initWithCoder:(id)coder;
@end
@interface AWEAwesomeSplashManager : NSObject
- (BOOL)shouldShowAwesomeSplash;
- (BOOL)canShowSplashWithID:(id)identifier ttModel:(id)model;
@end
@interface AWEAwesomeSplashFeedCellOldAccessoryView : NSObject
- (id)ddExtraView;
@end

#pragma mark - 顶部频道功能组用到的类

@interface AWEHPTabNodeModel : NSObject                            // 服务端下发的顶栏频道模型
@property (nonatomic, copy) NSString *channelID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) BOOL isMainTab;
@property (nonatomic, assign) BOOL deletable;
@end

@interface AWEFeedChannelObject : NSObject
@property (nonatomic, readonly) NSString *channelID;
@property (nonatomic, readonly) NSString *channelTitle;          // 顶栏实际文案（同城显示为城市名）
@end

@interface AWEFeedChannelManager : NSObject                        // 首页顶栏频道管理器
- (NSArray *)currentChannels;
- (void)reloadChannelWithChannelModels:(id)models currentChannelIDList:(id)channelIDs
                            reloadType:(id)reloadType selectedChannelID:(id)selectedChannelID;
@end

#pragma mark - 顶栏入口功能组用到的类

@interface AWEFeedTopBarContainer : UIView                         // 首页顶栏容器：左侧栏入口、频道与搜索槽位
@end

@interface AWEHPTopBarCTAItemView : UIView                         // 顶栏左右两侧的入口槽位（侧边栏 / 搜索）
@end

@interface AWELeftSideBarEntranceView : UIView                     // 左侧栏入口（≡）
@end

@interface AWEHPDiscoverFeedEntranceView : UIView                  // 顶栏搜索入口
@end

@interface AWELeftSideBarManager : NSObject
- (BOOL)canShowLeftSideBarWithPanGesture:(id)identification;
@end

// 顶栏搜索入口的控制器。评论区打开时由它配置一份搜索图标副本（普通 UIView），放在首页根视图上。
@interface AWEHPTopBarSearchEntranceController : NSObject
- (void)setupCopyFeedDiscoverEntranceView:(UIView *)view;
@end

#pragma mark - 未读红点功能组用到的类

// 抖音通用红点（点状 / 数字 / 文字三种样式）。显示时写 hidden=NO；清除时写 YES 并移出父视图（40.8.0 反汇编）。
@interface DUXBadge : UIView
@property (nonatomic, assign) unsigned long long badgeNumber;
@property (nonatomic, copy) NSString *badgeText;
@end

#pragma mark - 朋友页精简用到的类

// 朋友页顶栏。左侧入口容器 publishEntranceView 内是日常相机（头像和加号），右侧为朋友申请按钮（含未读角标）。
@interface AWEFamiliarNavView : UIView
@property (nonatomic, strong, readonly) UIView *publishEntranceView;
@property (nonatomic, strong, readonly) UIButton *friendsRequestButton;
@end

// 朋友页「限时日常 ▾」胶囊；显隐由天窗胶囊协调器写 hidden。
@interface AWEFamiliarSkylightBubbleView : UIView
@end

@interface AFDFamiliarViewController : UIViewController
- (void)showStorySkylightCapsuleIfNeeded;
- (void)dismissStorySkylightCapsule;
@end

// 朋友页天窗（限时日常头像列表）。点胶囊、刷新后自动展开、下拉手势开始与拖动都先过 enableOpenWithEnterMethod:。
@interface AWEFamiliarSkylightViewController : UIViewController
- (BOOL)enableOpenWithEnterMethod:(id)enterMethod;
- (BOOL)isOpening;
@end

// 头像下方「私信」图标的控制器。shouldShowSendMessageView: 决定是否显示，sendMessageView 内含阴影与图标。
@interface AWEPlayInteractionUserAvatarContext : NSObject
@property (nonatomic, strong, readonly) id model;
@end

@interface AWEPlayInteractionUserAvatarSendMsgController : NSObject
@property (nonatomic, strong, readonly) AWEPlayInteractionUserAvatarContext *userAvatarContext;
@property (nonatomic, strong, readonly) UIView *sendMessageView;
- (BOOL)shouldShowSendMessageView:(id)model;
- (void)showSendMessageViewWithAnimation:(BOOL)animated;
- (void)hideSendMessageView;
@end

// 朋友页内容流响应的条目；type 8 为「看看朋友推荐的作品」卡片，其 aweme 带 friendRecommendCard。
@interface AWEConcernCardModel : NSObject
@property (nonatomic, assign, readonly) NSInteger type;
@property (nonatomic, strong, readonly) AWEAwemeModel *aweme;
@end

@interface AWEAwemeModel (DKFriendRecommendCard)
- (id)friendRecommendCard;
@end

// 朋友页内容流响应（网络与预加载）；数据控制器经 cardList 读取条目。
@interface AWEFamiliarFeedResponseModel : NSObject
- (NSArray *)cardList;
@end

@interface AWEFamiliarFeedPreloadResponse : NSObject
- (NSArray *)cardList;
@end

#pragma mark - 消息页精简用到的类

// 消息页导航栏组件。每个槽位是一组候选按钮组件，布局时取第一个 canShowInNaviBar 为真的组件；
// 右一（加号位）是右侧容器的锚，右二（搜索位）挂在右一左边。
@interface AWEIMMessageTabNaviBarComponent : NSObject
@property (nonatomic, copy) NSArray *rightFirstBtnComponents;
@property (nonatomic, copy) NSArray *rightSecondBtnComponents;
- (void)reloadNaviBarButtons;
@end

// 导航栏按钮组件：左一侧边栏、左二运营位（装扮商店）、右二搜索、右一加号。
@interface AWEIMMessageTabSideBarButtonComponent : NSObject
- (BOOL)canShowInNaviBar;
@end

@interface AWEIMMessageTabNavBarResourceSlotComponent : NSObject
- (BOOL)canShowInNaviBar;
@end

@interface AWEIMMessageTabNavBarResourceSlotComponentV2 : NSObject
- (BOOL)canShowInNaviBar;
@end

@interface AWEIMMessageTabSearchComponent : NSObject
- (BOOL)canShowInNaviBar;
@end

@interface AWEIMMessageTabPlusButtonComponent : NSObject
- (BOOL)canShowInNaviBar;
@end

// 头像行的差异数据快照；条目标识即头像行的视图模型。
@interface RxDiffableDataSourceSnapshot : NSObject
- (NSArray *)sectionIdentifiers;
- (NSArray *)itemIdentifiers;
- (NSArray *)itemIdentifiersInSectionWithIdentifier:(id)sectionIdentifier;
- (void)deleteItemsWithIdentifiers:(NSArray *)identifiers;
@end

@interface RxCollectionViewDiffableDataSource : NSObject
- (RxDiffableDataSourceSnapshot *)snapshot;
@end

// 头像行条目：vmType 1 好友、4 状态设置、8 业务入口；业务入口为 AWEIMSkylightBizViewModel 及其子类。
@interface AWEIMOnlineContactAvatarViewModel : NSObject
@property (nonatomic, assign, readonly) NSUInteger vmType;
@end

@interface AWEIMSkylightBizViewModel : AWEIMOnlineContactAvatarViewModel
@end

@interface AWEIMSkylightCellViewModel : NSObject
@property (nonatomic, strong, readonly) AWEIMOnlineContactAvatarViewModel *model;
@end

@interface AWEIMSkylightCommonCell : UICollectionViewCell
- (void)renderWithViewModel:(AWEIMSkylightCellViewModel *)viewModel;
@end

// 头像行视图组件：所有数据写入最终都经 applySnapshot:animatingDifferences:completion:。
@interface AWEIMSkylightViewComponent : NSObject
@property (nonatomic, strong, readonly) RxCollectionViewDiffableDataSource *dataSource;
@property (nonatomic, strong, readonly) UICollectionView *collectionView;
- (void)applySnapshot:(RxDiffableDataSourceSnapshot *)snapshot animatingDifferences:(BOOL)animating completion:(id)completion;
@end

// 头像行数据组件：shouldHidden 为真时整行收起（列表视图经代理写 hidden 并重排表头）。
@interface AWEIMSkylightDataComponent : NSObject
- (BOOL)shouldHidden;
@end

@interface AWEIMSkylightListView : UIView
@property (nonatomic, strong, readonly) AWEIMSkylightViewComponent *skylightInterface;
- (void)refreshWithIgnoreFrequency:(BOOL)ignoreFrequency;
- (void)performShouldHiddenDelegate;
- (void)viewWillAppear;
@end

// 消息列表会话；互动消息为 AWEIMOfficialChatModel，type 1003、sessionId "-1003"。
@interface AWEIMChatModel : NSObject
@property (nonatomic, assign, readonly) NSInteger type;
@property (nonatomic, copy, readonly) NSString *sessionId;
@end

@interface AWEIMChatCellViewModel : NSObject
@property (nonatomic, strong, readonly) AWEIMChatModel *chat;
@end

@interface AWEIMChatListCommonCell : UITableViewCell
@property (nonatomic, strong, readonly) AWEIMChatCellViewModel *cellViewModel;
- (void)renderWithHolder:(id)holder;
@end

// 官方会话数据源。p_canShowOfficialChat: 为假时，upsert 里已在列表的会话转为删除。
@interface IESIMOfficialChatDataSource : NSObject
- (BOOL)p_canShowOfficialChat:(AWEIMChatModel *)chat;
- (void)p_updateChatListWithUpsert:(NSArray *)upsert remove:(NSArray *)remove;
- (AWEIMChatModel *)chatWithSession:(NSString *)sessionId;
@end

#pragma mark - 聊天输入功能组用到的类

// 输入页的组件体系：输入控制器持有一个组件管理器，组件通过 context 拿到宿主聊天页。
@interface AWEIMComponentContext : NSObject
@property (nonatomic, weak) UIViewController *hostViewController;
@end

@interface AWEIMComponentManager : NSObject
@property (nonatomic, strong) NSArray *components;
@end

@interface AWEIMComponentBase : NSObject
@property (nonatomic, weak) AWEIMComponentContext *context;
@property (nonatomic, weak) AWEIMComponentManager *belongingManager;
@end

// 聊天页控制器，输入控制器是它的子控制器。
@interface AWEIMMessageBaseViewController : UIViewController
@property (nonatomic, strong) UIViewController *messageListVC;
@end

// 消息列表控制器：view 是裁剪列表的容器，消息表格在 tableView。
@interface AWEIMMessageListViewController : UIViewController
@property (nonatomic, strong) UITableView *tableView;
@end

// 群聊顶部群功能栏：展开状态存在 Swift viewModel 里，hostVC_viewDidLoad 内按群身份与功能项红点同步算出，
// 切换只在原生允许时生效（40.8.0 反汇编）。
@interface AWEIMGroupZoneConversationComponent : AWEIMComponentBase
- (BOOL)isGroupZoneExpanded;
- (void)toggleGroupZoneExpanded:(BOOL)animated;
@end

// 消息页布局组件：主布局从当前几何计算快照，页面配置负责重排输入区、浮动条与消息列表。
@interface AWEIMMessageListLayoutComponent : AWEIMComponentBase
- (void)updatePageLayout:(id)layoutInfo;
- (void)p_layoutWithAnimation:(BOOL)animated coordinate:(id)coordinate;
@end

// 消息列表右上角的未读提示（⬆ N 条消息）：提示条挂在聊天页 view 上，纵坐标取 __bubbleYOrigin，
// 即列表视图上沿下方 32pt，有顶部浮条时为浮条高 + 16（40.8.0 反汇编）。
@interface AWEIMTopAnchorComponent : AWEIMComponentBase
- (double)__bubbleYOrigin;
@end

// 消息列表底部的「回到最新」圆钮（40×40）与「N 条新消息」胶囊：AWEIMBottomAnchorComponent 的同一个容器，
// 挂在列表视图上。纵坐标按列表视图高度写（出现 = 高 − 56，收起 = 高），换文案时只改宽度与横向居中（40.8.0 反汇编）。
@interface AWEIMBottomNewMessageTipsImageView : UIView
@end

// 普通聊天输入控制器。公司会话、POI 会话、作品详情与图文详情内的输入页复用同一套组件，
// 由下面四个只读标志区分，功能只接管四者都为假的那一种。
@interface IESIMInputViewController : UIViewController
@property (nonatomic, readonly) BOOL isCompanyChat;
@property (nonatomic, readonly) BOOL isShowingInPOIIMConversationViewController;
@property (nonatomic, readonly) BOOL isShowingInFeedDetailViewController;
@property (nonatomic, readonly) BOOL isShowingInImageVideoDisplayViewController;
// 当前输入形态：0 收起、1 系统键盘、2 表情面板、3 语音、5 加号面板（40.8.0 实测）。
@property (nonatomic, readonly) long long currentInputType;
@end

// 输入框：内部文字视图的 frame 由 contentInset 推出（layoutSubviews 与高度变化都按它写），
// 原生只经 setContentInsetPurely: 写这个值。
@interface IESIMGrowingTextView : UIView
@property (nonatomic) UIEdgeInsets contentInset;
- (void)setContentInsetPurely:(UIEdgeInsets)insets;
@end

// 输入行布局组件：左右按钮、文字视图、语音视图、面板容器都由它排布。
@interface IESIMInputLayoutComponent : AWEIMComponentBase
- (void)refreshLayout;
- (void)p_layoutInputViewsAfterAdjustButtons;
- (void)pp_layoutSubviewsWithAnimated:(BOOL)animated context:(id)context;
- (void)refreshBackgroundWithBackGroundImage:(BOOL)hasImage;
// 收起 / 语音态的输入页 frame：y = 父视图高 − 行高 − 底部安全区让位（40.8.0 反汇编）；
// 输入控制器、最近照片与菜单组件取折叠位置都经它。
- (CGRect)inputVCFoldedFrame:(CGFloat)height;
@end

// 左右按钮的供给策略，返回本轮参与布局的按钮数组。
@interface IESIMInputLeftComponentPolicy : AWEIMComponentBase
- (NSArray *)leftButtonsForShow;
@end

@interface IESIMInputRightComponentPolicy : AWEIMComponentBase
- (NSArray *)rightButtonsForShow;
@end

@interface IESIMInputPlayEntryComponent : AWEIMComponentBase
@end

@interface IESIMInputAudioComponent : AWEIMComponentBase
- (void)refreshBackgroundWithBackGroundImage:(BOOL)hasImage;
@end

@interface IESIMInputPlusComponent : AWEIMComponentBase
- (void)refreshBackgroundWithBackGroundImage:(BOOL)hasImage;
@end

// 输入框上方的表情快捷提示条（早上好 / 比心 …）。展示判定与高度管理都在这个交互器上；
// barMaker 是配置对象，只有普通单聊群聊用 AWEIMInputActionBarMaker_NormalGroupOrPrivate。
@interface AWEIMInputActionBarInteractor : AWEIMComponentBase
@property (nonatomic, readonly) id barMaker;
- (void)p_layoutActionBarShowAnimated:(BOOL)animated;
- (void)p_layoutActionBarDismissAnimated:(BOOL)animated;
- (BOOL)p_shouldShowActionBarAfterTypeResolved;
- (BOOL)p_shouldShowInputActionBarWithInputType:(NSInteger)type;
- (void)hideActionBarIfNeeded;
- (void)showActionBarIfPossible;
@end

// 提示条的浮动容器（与最近照片共用），高度由提示条自己写。
@interface AWEIMFloatingContainerView : UIView
@end

@interface AWEIMInputActionBarEntryView : UIView
@end

// 提示条里的一个表情芯片，芯片自带一层 85×30 的原生模糊；refreshStyle 会重写底色与模糊。
@interface AWEIMInputActionBarEntryItemCollectionViewCell : UICollectionViewCell
- (void)refreshStyle;
@end

// 加号面板打开时浮动容器里的最近照片条，照片在 _collectionView 里横向排列。
@interface AWEIMQuickPhotoPickerView : UIView
- (void)refreshBackgroundColorWhileHasBackground:(BOOL)hasBackground;
@end

// 最近照片条里的单张照片格与「添加更多可访问照片」入口格。
@interface AWEIMAssetListCollectionViewCell : UICollectionViewCell
@end

@interface AWEIMPhotoAddMoreCollectionViewCell : UICollectionViewCell
- (void)addBlurView;
@end

// 最近照片条的分发方：输入形态切换时由浮动条分发询问能否展示，40.8.0 只在加号面板（类型 5）返回 YES。
@interface AWEIMQuickSelectPhotoInteractor : AWEIMComponentBase
- (BOOL)canShowBarWhenInputTypeChangedTo:(long long)type;
@end

// 聊天页的小火人挂件：键盘、表情与加号面板时吸附到输入区，Lynx 容器在 _containerView。
@interface AWEIMStreakPendantView : UIView
@property (nonatomic, readonly) BOOL isInputAttached;
- (void)updateInputAttachedState:(BOOL)attached;
@end

// 加号面板与它的格子；格子里的图标方块自带原生模糊。
@interface AWEIMPlusPanelView : UIView
@end

// 宫格格子：模糊层在 configWithModel: 返回之后才由 addBlurView 建出。
@interface AWEIMChatPanelCollectionViewCell : UICollectionViewCell
- (void)configWithModel:(id)model;
- (void)addBlurView;
@end

// 表情面板顶部页签格子：userSelected 为选中态，__refreshSelectedUI 按它给 contentView 铺白底。
@interface AWEIMEmoticonTabCollectionViewCell : UICollectionViewCell
@property (nonatomic, readonly) BOOL userSelected;
- (void)__refreshSelectedUI;
@end

// 表情面板的横向翻页区（每页一个表情网格）。
@interface AWEIMEmoticonThemesCollectionView : UICollectionView
@end

@interface AWEIMEmoticonPanelBoxView : UIView
- (void)iesim_themeReload:(id)theme;
@end

// 页签行的两种原生形态按聊天有无背景图切换（40.8.0 反汇编）：居中时页签集合视图 contentInset.bottom 为 0、
// 固定入口图标在入口内居中、分隔线隐藏；否则底部留 8pt、图标距顶 6pt、分隔线显示。
@interface AWEIMEmoticonPanelBoxComponent : AWEIMComponentBase
- (void)verticalAlignmentCenter:(BOOL)center boxView:(UIView *)boxView;
@end

// 页签行左侧的固定入口（搜索）：entryView 为入口，iconView 为其中的图标。
@interface AWEIMEmoticonFixedTab : NSObject
@property (nonatomic, strong) UIView *entryView;
- (void)verticalAlignmentCenter:(BOOL)center;
@end

// 语音态「按住说话」的触摸视图，自带一层模糊与长按手势。
@interface AWEIMOptimizeAudioInputTouchView : UIView
- (void)refreshColor;
@end

@class AWENavigationBar;

// 聊天导航的 provider 聚合器，原生负责排列左右控件与标题组件。
@interface AWEIMMessageListNaviBarComponent : AWEIMComponentBase
@property (nonatomic, weak) AWENavigationBar *naviBar;
@property (nonatomic, weak) id naviBarTitleService;
- (void)setNeedsUpdateNaviBar;
@end

@interface AWEIMMessageListNaviBarTitleComponent : AWEIMComponentBase
- (void)setNeedsUpdateNaviBarTitle;
@end

@interface AWEIMNavigationUnreadView : UIView
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UIView *unreadCountView;
@property (nonatomic, strong) CAShapeLayer *dotLayer;
@property (nonatomic, strong) UILabel *dotLabel;
- (void)updateWithCount:(long long)count;
@end

// 标题：头像栈与标题容器；容器内主标题行（名称、人数、火花 AWEIMStreakFlameView）与副标题行（在线状态）。
// 头像、名称、火花、在线的点击都由标题视图自己的点击手势处理（p_didClickSelfWithGesture:）。
@interface AWEIMMessageListNaviBarTitleView : UIStackView
@property (nonatomic, strong) UIStackView *avatarStackView;
@property (nonatomic, strong) UIStackView *titleContainerStackView;
@property (nonatomic, strong) UIStackView *mainTitleStackView;
@property (nonatomic, strong) UIStackView *subtitleStackView;
@end
// 标题头像：p_updateDots 显示在线圆点时给头像内容 contentView 挂 notchLayer 缺口遮罩（为圆点留出外圈），隐藏圆点时摘掉。
@interface AWEIMMessageListNaviBarTitleAvatarComponent : AWEIMComponentBase
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) CAShapeLayer *notchLayer;
@property (nonatomic, strong) UIView *onlineDotView;
- (void)p_updateDots;
@end
// 顶部浮条（群公告、置顶消息等）的容器组件，容器懒创建。
@interface AWEIMMessageListTopFloatingComponent : AWEIMComponentBase
@property (nonatomic, strong) UIView *topFloatingContainer;
@end
@interface AWEIMMessageVoipEntranceView : UIView
@property (nonatomic, strong) UIButton *audioBtn;
@property (nonatomic, strong) UIButton *videoBtn;
@end

#pragma mark - 个人主页功能组用到的类

@interface AWEUserProfileUGCContributionGuideEmptyCollectionViewCell : UICollectionViewCell
@property (nonatomic, strong) UIView *bodyView;
+ (double)viewHeight;
@end

// 个人主页的页面 context（顶栏条目、头像扩展、编辑主页格持有）；isCurrentUser 为真即自己的主页。
@interface AWEProfileContext : NSObject
- (BOOL)isCurrentUser;
@end

// 个人主页头部的 context（头部各分区、昵称区组件持有）。
@interface AWEProfileHeaderContext : NSObject
- (BOOL)isCurrentUser;
@end

// 顶栏条目控制器：canShow 为真才进入左右数据源，navigationItemView 是放进顶栏容器的视图。
// 添加好友 / 侧栏 / 搜索 / 访客分别是下面四个类，navigationType 依次为 4 / 6 / 7 / 8。
@interface AWEProfileNaviAddFriendItemController : NSObject
- (BOOL)canShow;
- (UIView *)navigationItemView;
- (AWEProfileContext *)profileContext;
- (id)delegate;
@end

@interface AWEProfileNavMoreFuncItemController : NSObject
- (BOOL)canShow;
- (UIView *)navigationItemView;
- (AWEProfileContext *)profileContext;
- (id)delegate;
@end

@interface AWEProfileNavSearchItemController : NSObject
- (BOOL)canShow;
- (UIView *)navigationItemView;
- (AWEProfileContext *)profileContext;
- (id)delegate;
@end

@interface AWEProfileNavVisitorItemController : NSObject
- (BOOL)canShow;
- (UIView *)navigationItemView;
- (AWEProfileContext *)profileContext;
- (id)delegate;
@end

// 顶栏组件：reloadData 重新取左右数据源（逐个询问 canShow）并重排。
@interface AWEProfileNavigationBaseComponent : NSObject
- (void)reloadData;
- (AWEProfileContext *)profileContext;
@end

@interface AWEProfileNavigationContainerView : UIView
@end

// 头部分区来源：reloadSections 与 updateSections: 都从 sectionViewModelArray 取分区 VM。
@interface AWEProfileHeaderSectionProviderManager : NSObject
- (NSArray *)sectionViewModelArray;
- (AWEProfileHeaderContext *)context;
@end

// 头部列表 VM（AWEBaseListViewModel 子类）；reloadSections 替换分区后重算头部高度并刷新分页栏位置。
@interface AWEProfileHeaderViewModel : NSObject
- (void)reloadSections;
- (BOOL)isCurrentUser;
@end

@interface AWEProfileHeaderSocialStatisticCollectionViewCellV2 : UICollectionViewCell
- (BOOL)isCurrentUser;
@end

@interface AWEProfileHeaderHomeShortcutCell : UICollectionViewCell
- (AWEProfileContext *)profileContext;
@end

// 「记录下幸福瞬间」等发布引导横幅所在分区的 cell，内容是 Compose 视图。
@interface AWEUserProfileUGCHeaderContributionGuideBannerSectionCell : UICollectionViewCell
- (AWEProfileHeaderContext *)context;
@end

// 头像扩展 avatar_story_publish：头像右下角加号。canShow 决定是否显示并参与点击分派；
// p_shouldAddHollowMasks 为真时在头像上给加号挖出镂空。
@interface AWEProfileAvatarStoryPublishController : NSObject
- (BOOL)canShow;
- (BOOL)p_shouldAddHollowMasks;
- (void)updateUIWithContainerView:(UIView *)containerView anchorView:(UIView *)anchorView;
- (UIButton *)story25PublishButton;
- (AWEProfileContext *)profileContext;
@end

@interface AWEProfileAvatarSectionControllerV2 : NSObject
- (void)configCell:(id)cell index:(NSInteger)index model:(id)model;
- (void)reloadAvatarExtension;
- (AWEProfileContext *)profileContext;
@end

// 昵称一行：昵称、切换账号箭头（switchAccountButton）与多账号未读点
// （noticeUnreadDotView、multiAccountNoticeUnreadDotView）。
@interface AWEProfileHeaderNameLabelContainerView : UIView
- (AWEProfileHeaderContext *)context;
@end

@interface AWEProfileHeaderNameAreaSectionCell_New : UICollectionViewCell
- (AWEProfileHeaderContext *)context;
@end

// AWERL 组件的虚拟视图；mount 后 renderedView 是挂上去的真实视图。
@interface AWERLVirtualView : NSObject
- (UIView *)renderedView;
@end

// 抖音号下方的胶囊行（创建 AI 形象、原创角色及运营胶囊）。buildVirtualView: 返回 nil 时整行不参与排布。
@interface AWEProfileHeaderGenericOperationComponent : NSObject
- (id)buildVirtualView:(id)data;
- (AWERLVirtualView *)containerNode;
- (AWEProfileHeaderContext *)context;
- (void)setNeedsUpdate;
@end

// 分页模型：profileTabType 作品 0 / 喜欢 2 / 收藏 16 / 日常 38 / 足迹 46。
@interface AWEUserProfileTabModel : NSObject
@property (nonatomic, assign) NSInteger profileTabType;
@end

// 分页数据：tabArray 懒构建并缓存（同时写 _numOfTab），tabTitles 由 tabArray 生成；
// updateUser:shouldRefreshTab:YES 清空缓存。
@interface AWEUserProfileTabHelper : NSObject
- (NSArray<AWEUserProfileTabModel *> *)tabArray;
- (BOOL)p_isCurrentUser;
- (id)user;
- (void)updateUser:(id)user shouldRefreshTab:(BOOL)shouldRefreshTab;
@end

// 个人主页的分页编排：p_updateTabView 比较分页是否变化，变化时按 landingTabType 重载分页。
@interface AWEUIOrchestrationHomeComponent : NSObject
- (AWEUserProfileTabHelper *)tabHelper;
- (void)p_updateTabView;
@end

// 个人主页功能区（观看历史 … 全部功能）的卡片模型；cardType 120 为「全部功能」。
@interface AWEProfileExtensionAreaCardModel : NSObject
@property (nonatomic, assign) unsigned long long cardType;
@property (nonatomic, copy) NSString *title;
@end

@interface AWEProfileExtensionAreaContext : NSObject
- (id)userModel;
- (AWEProfileHeaderContext *)profileHeaderContext;
- (id)dataSource;
@end

// 功能区数据源：refreshUserModel: 生成卡片列表（setCardList:），按列表建卡片控制器与视图，再通知视图持有者刷新。
@interface AWEProfileEAVajraDataSource : NSObject
- (void)refreshUserModel:(id)userModel;
- (AWEProfileExtensionAreaContext *)context;
@end

// 功能区视图持有者：setCardList: 后 computeLayout 按卡片标题算宽度与间距；cell 里的卡片视图按下标向数据源取。
@interface AWEProfileEAVajraViewHolder : NSObject
- (NSArray *)cardList;
- (UIView *)cardViewWithCardModel:(AWEProfileExtensionAreaCardModel *)cardModel;
- (AWEProfileExtensionAreaContext *)context;
@end

@interface AWEProfileExtensionAreaCell : UICollectionViewCell
- (void)addCardView:(UIView *)cardView;
@end

// 功能区卡片视图：图标 imageView（按卡片模型里的亮 / 暗色图标地址加载）在上，标题 titleLabel 在下。
@interface AWEProfileExtensionAreaVajraStyleCardView : UIView
- (AWEProfileExtensionAreaCardModel *)cardModel;
- (void)configWithCardModel:(AWEProfileExtensionAreaCardModel *)cardModel;
- (UIImageView *)imageView;
- (UILabel *)titleLabel;
@end

// 个人主页的 SVG 图标集（与设置页图标同名，如 ic_gearsimplify_outlined_20）。
@interface UIImage (AWEProfileSVG)
+ (UIImage *)svg_userProfileImageWithName:(NSString *)name size:(CGSize)size color:(UIColor *)color;
@end

#pragma mark - 媒体保存功能组用到的类

// 作品长按面板的一项；actionType 121 为原生「保存至相册」（AWELongPressPanelDownloadViewModel）。
@interface AWELongPressPanelBaseViewModel : NSObject
@property (nonatomic, strong) AWEAwemeModel *awemeModel;
@property (nonatomic, assign) unsigned long long actionType;
@property (nonatomic, strong) NSString *duxIconName;
@property (nonatomic, strong) NSString *describeString;
@property (nonatomic, copy) id action;
// 以下为长按菜单精简用到的字段：原生项的语义标识（如 speed、dislike），插件项为 nil。
- (NSString *)panelBizVMIdentifier;
@property (nonatomic, strong) UIView *subView;            // 行右侧附件：开关、状态文字、箭头、缩略图
@property (nonatomic, strong) UIView *totalView;          // 整行自绘控件，如倍速分段
@property (nonatomic, strong) UIImage *iconImage;
@property (nonatomic, assign) BOOL disableInteraction;
@property (nonatomic, copy) id willAppearBlock;
@property (nonatomic, copy) NSString *referString;
- (void)trackCellShow;
- (void)configVM;
- (void)configVMIfNeeded;              // hasConfig 为假时调一次 configVM
@end

@interface AWELongPressPanelViewGroupModel : NSObject                 // 长按面板的一组
@property (nonatomic, assign) unsigned long long groupType;
@property (nonatomic, strong) NSArray *groupArr;
@property (nonatomic, assign) long long numberOfRowsInSection;
@property (nonatomic, assign) long long cellHeight;
@property (nonatomic, assign) BOOL hasMore;
@property (nonatomic, assign) BOOL isModern;
@end

@interface AWELongPressPanelManager : NSObject
+ (instancetype)shareInstance;
- (void)dismissWithAnimation:(BOOL)animated completion:(id)completion;
// 长按作品后是否弹出面板：各长按入口与 iPad「更多」按钮共用；两参数版本转调此方法。
- (BOOL)shouldShowPanelWhenUserDidLongPressWithModel:(id)model referString:(id)referString scene:(id)scene;
@end

@interface AWELongPressPanelTableViewController : UIViewController   // 推荐页视频与图文共用
- (NSArray *)dataArray;
- (void)setDataArray:(NSArray *)dataArray;
- (UITableView *)tableView;
// 行点击的原生入口：执行 action 并埋点。
- (void)executeActionForViewModel:(id)viewModel;
// 按行在分组里的位置画卡片底与分割线；非 AWELongPressPanelSettingCell 的 cell 走通用卡片底。
- (void)setSectionCornreRadiusAndLines:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)updateFirstScreenVisibleStatusForVMAtIndexPath:(NSIndexPath *)indexPath groupModel:(id)groupModel;
@end

// 作品长按菜单的普通行。
@interface AWELongPressPanelSettingCell : UITableViewCell
- (void)setLongPressPanelVM:(id)viewModel;
- (UIView *)sectionBackgroundView;
- (UIView *)sectionSeparatorView;
- (UIView *)rightSubView;
- (UIColor *)sectionBackgroundColorForHighlighted:(BOOL)highlighted;   // 卡片底色（sectionBackgroundView）
@end

@interface AWEModernLongPressPanelUIConfig : NSObject
+ (UIColor *)cellHighlightedColor;
+ (UIColor *)itemTitleColor;
@end

// 抖音列表框架：列表 VM 持有分区 VM，分区 VM 持有本分区的数据模型；评论长按面板基于它。
@interface AWEBaseListViewModel : NSObject
- (void)replaceBySectionViewModels:(NSArray *)sectionViewModels sync:(BOOL)sync;
@end

@interface AWEBaseListSectionViewModel : NSObject
- (NSArray *)modelsArray;
- (void)replaceByModels:(NSArray *)models animated:(BOOL)animated sync:(BOOL)sync;
@end

// 作品长按菜单的内容控制器，挂在 DUXContentSheet 的导航里，表格控制器是它的子控制器。
@interface AWEVideoLongPressPanelViewController : UIViewController
@end

@interface AWEDanmakuSettingsPanelConfig : NSObject
@property(nonatomic, assign) unsigned long long themeColorType;
@end

@interface AWEDanmakuSettingsPanelView : UIView
- (instancetype)initWithDanmakuScene:(unsigned long long)scene config:(AWEDanmakuSettingsPanelConfig *)config delegate:(id)delegate;
- (void)setSectionCornerRadiusAndLines:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath;
@end

@interface AWEDanmakuSettingsPanelViewController : UIViewController
@end

// 抖音的视图级主题偏好：设了偏好的视图及其子树按指定的深 / 浅主题取色，取消后跟随全局主题。
@interface UIView (AWEThemePreference)
- (void)awe_preferDarkTheme;
- (void)awe_cancelPreferredTheme;
- (BOOL)awe_hasPreferredTheme;
@end

// 抖音现代长按面板的格子：图标在上、文字在下，updateUI: 按菜单项配置。
@interface AWEModernLongPressHorizontalSettingItemCell : UICollectionViewCell
- (void)updateUI:(id)viewModel;
- (UIImageView *)buttonIcon;
- (UILabel *)buttonLabel;
- (void)setSeparatorHidden:(BOOL)hidden;
@end

@interface AWEModernLongPressPanelTableViewController : UIViewController
- (NSArray *)dataArray;
@end

@interface AWECommentImageModel : NSObject                            // 评论图片：download_url 为水印模板
- (id)originUrl;
- (id)downloadUrl;
@end

@interface AWECommentMediaDownloadConfigLivePhoto : NSObject          // 原生评论实况下载配置
- (BOOL)needClientWaterMark;
- (BOOL)needClientEndWaterMark;
- (id)watermarkConfig;
@end

@interface AWEIMCustomMenuModel : NSObject                            // 私信长按菜单项，点击走 willPerform block
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *imageName;
@property (nonatomic, copy) NSString *lightImageURL;
@property (nonatomic, copy) NSString *darkImageURL;
@property (nonatomic, assign) unsigned long long type;
@property (nonatomic, copy) NSString *trackerName;
@property (nonatomic, copy) id willPerformMenuActionSelectorBlock;
@end

@interface AWEIMCustomMenuComponentContext : NSObject
@property (nonatomic, copy) NSArray *menuItemList;
@property (nonatomic, strong) UITableViewCell *cell;
@end

@interface AWEIMCustomMenuComponent : NSObject
- (void)p_showMenuWithContext:(AWEIMCustomMenuComponentContext *)context;
- (void)msg_dismissMenu;
@end

// 表情面板长按预览：按钮行在 container 底部，各操作按钮叠放、按需显示。
@interface AWEIMEmoticonPreviewV2 : UIView
@property (nonatomic, strong) UIView *container;
@property (nonatomic, strong) UIView *content;
@property (nonatomic, strong) UIView *verticalSeparateLineView;
@property (nonatomic, strong) UIButton *checkSeriesButton;
@property (nonatomic, strong) UIButton *addToCustomButton;
@property (nonatomic, strong) UIButton *deleteFromCustomButton;
@property (nonatomic, strong) UIButton *deleteDoubleCheckButton;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) id model;
- (BOOL)shouldShowOptionButtons;
- (void)p_setupOptionButtonsIfNeededWithModel:(id)model;
- (void)resetButtonsAndColor;
- (void)p_hidePreview;
@end

// 相似表情页头部（单击评论表情、私信表情消息后出现）：buttonStackView 为等宽按钮行。
@interface AWEIMSimilarEmojiDisplayView : UIView
@property (nonatomic, strong) UIStackView *buttonStackView;
- (void)renderWithDisplayModel:(id)model context:(id)context;
- (void)p_configButtonsWithButtonViewModels:(id)models;
- (id)p_createButton;
@end

#pragma mark - 抖音设置系统（注入设置菜单用）

@interface AWESettingItemModel : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, strong) UIColor *titleColor;       // 非空时 updateSubviewsColor 按它给标题着色
@property (nonatomic, assign) NSInteger type;
@property (nonatomic, copy) NSString *svgIconImageName;
@property (nonatomic, assign) NSInteger cellType;
@property (nonatomic, assign) NSInteger colorStyle;
@property (nonatomic, assign) BOOL isEnable;
@property (nonatomic, assign) BOOL isSwitchOn;
@property (nonatomic, copy) void (^cellTappedBlock)(void);
@property (nonatomic, copy) void (^switchChangedBlock)(void);
- (void)refreshCell;                 // 按当前属性重配所在 cell
@end

// 设置页分区页脚；说明文字的高度按比文字实际宽度更宽的宽度估算，长一些的文字会被截掉末行。
@interface AWESettingsTableSectionFooterView : UITableViewHeaderFooterView
- (UILabel *)footerNoticeLabel;
@end

@interface AWESettingSectionModel : NSObject
@property (nonatomic, assign) NSInteger type;
@property (nonatomic, assign) CGFloat sectionHeaderHeight;
@property (nonatomic, copy) NSString *sectionHeaderTitle;
@property (nonatomic, strong) NSArray *itemArray;
@property (nonatomic, copy) NSString *sectionFooterTitle;
@property (nonatomic, assign) BOOL useNewFooterLayout;   // 页脚按多行说明文字排版
@end

@interface AWESettingBaseViewModel : NSObject
@end

@interface AWESettingsViewModel : AWESettingBaseViewModel
@property (nonatomic, assign) NSInteger colorStyle;
@property (nonatomic, strong) NSArray *sectionDataArray;
@property (nonatomic, weak) id controllerDelegate;
@end

@interface AWESettingBaseViewController : UIViewController
@property (nonatomic, assign) NSInteger colorStyle;
@property (nonatomic, assign) BOOL useCardUIStyle;       // viewDidLoad 里据此切圆角卡片样式
@property (nonatomic, strong, readonly) UITableView *tableView;
- (AWESettingBaseViewModel *)viewModel;
@end

// 设置页的行。卡片样式下标题、开关等都在 containerView（即 realContentView）里，
// 项不可用时抖音调暗的是这一层。
@interface AWESettingsTableViewCell : UITableViewCell
@property (nonatomic, strong) UIView *lineView;
@property (nonatomic, strong, readonly) AWESettingItemModel *itemModel;
@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, strong, readonly) UIImageView *iconImageView;
- (void)updateSubviewsAfterLayout;
- (void)updateSubviewsColor;         // 按 item 与深浅色重配标题、图标、开关颜色
@end

@interface AWENavigationBar : UIView
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIView *bottomLineView;
@property (nonatomic, strong) UIView *leftBtnsContainerView;
@property (nonatomic, strong) UIView *rightBtnsContainerView;
@property (nonatomic) BOOL shouldTouchPenetrate;
@property (nonatomic, strong) UILabel *titleLabel;
@end

#pragma mark - 发布时间与地区用到的类

// 作品的发布字段：createTime 为秒级时间戳（JSON create_time），cityCode 为城市代码（JSON city），
// region 为国家地区码，ipAttribution 为原生属地文字（JSON ip_attribution）。
@interface AWEAwemeModel (DKPublishInfo)
@property (nonatomic, strong) NSNumber *createTime;
@property (nonatomic, copy) NSString *cityCode;
@property (nonatomic, copy) NSString *region;
@property (nonatomic, copy) NSString *ipAttribution;
@end

// 左侧栈的时间元素（AWEPlayInteractionLeftElement 子类）：原生只在部分页面显示「完整日期  IP属地：…」一行。
// shouldActiveWithData:（data 为作品，context 为元素上下文）按页面判定是否加入左侧栈；
// 换作品时先 setModel:，再由 layoutElementView 重写 timestampLabel 文字。
@interface AWEPlayInteractionTimestampElement : NSObject
@property (nonatomic, strong) AWEAwemeModel *model;
@property (nonatomic, strong) UILabel *timestampLabel;
@property (nonatomic, assign) BOOL appear;
+ (BOOL)shouldActiveWithData:(id)data context:(id)context;
+ (NSString *)formattedDateForFullTimestamp:(double)timestamp;
- (id)context;
- (void)layoutElementView;
@end

#pragma mark - 长按复制昵称与文案用到的类

@interface AWEUserModel : NSObject
@property (nonatomic, copy) NSString *nickname;
@end

// 作品的作者与完整文案：descriptionString 为正文加话题标签（itemTitle + caption），不受播放页折叠影响。
@interface AWEAwemeModel (DKInfoCopy)
@property (nonatomic, strong) AWEUserModel *author;
@property (nonatomic, copy) NSString *descriptionString;
@end

// 播放交互层元素基类（AWEBaseElement 子类），model 为当前作品；左侧昵称、文案元素都继承它。
@interface AWEPlayInteractionBaseElement : NSObject
@property (nonatomic, strong) AWEAwemeModel *model;
@end

#endif /* DouyinHeaders_h */
