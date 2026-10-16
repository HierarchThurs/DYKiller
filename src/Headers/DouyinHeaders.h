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
@property (nonatomic, readonly, strong) UIImageView *buttonImageView;
@property (nonatomic, strong) UIImageView *aweImageView;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UILabel *buttonLabel;
@property (nonatomic, strong) UIView *containerView;
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
@property (nonatomic, assign) BOOL hasInlandscape;                  // 横屏视频判据（横屏排除全屏）
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

@interface AWEIMFeedVideoQuickReplayInputViewController : UIViewController  // 底部快捷回复栏控制器
@end

@interface AWEPlayInteractionViewController : UIViewController      // HUD 控制器；评论态其 view 顶部会被塞状态栏黑底，全屏时需压掉
@property (nonatomic, assign) BOOL hideMusicInfo;
@property (nonatomic, copy) NSString *referString;
- (void)performCommentAction;
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

// 抖音自绘底栏。它自身的 hidden/alpha 是抖音全部显隐逻辑的唯一汇聚点，可直接当镜像源。
@interface AWENormalModeTabBar : UITabBar
@end

// 底栏文字视图的配置（文字项为 TextViewUIConfig、首页为 FeedUIConfig，均继承此类）。抖音按选中状态与明暗进度
// 算好的文字色同步写进 textColor，文字视图再经绑定延后同步到 label。
@interface AWENormalModeTabBarInnerViewUIConfig : NSObject
@property (nonatomic, strong) UIColor *textColor;
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

// 弹幕渲染层。抖音开评论面板时就是把这一层的 alpha 压成 0（实测半屏 / 全屏都是），
// 容器与各条弹幕视图本身不动。
@interface DDanmakuPlayerView : UIView
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

// 第三行功能键。imageView 是 56×56 白圆+图标；smallImageView 导出里无图。
@interface AWESharePanelFunctionCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIImageView *smallImageView;
- (void)updateWithViewModel:(id)viewModel bigFontAdapter:(id)adapter;
- (void)updateImageViewWithViewModel:(id)viewModel;
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

#pragma mark - 个人主页功能组用到的类

@interface AWEUserProfileUGCContributionGuideEmptyCollectionViewCell : UICollectionViewCell
@property (nonatomic, strong) UIView *bodyView;
+ (double)viewHeight;
@end

#pragma mark - 媒体保存功能组用到的类

// 作品长按面板的一项；actionType 121 为原生「保存至相册」（AWELongPressPanelDownloadViewModel）。
@interface AWELongPressPanelBaseViewModel : NSObject
@property (nonatomic, strong) AWEAwemeModel *awemeModel;
@property (nonatomic, assign) unsigned long long actionType;
@property (nonatomic, strong) NSString *duxIconName;
@property (nonatomic, strong) NSString *describeString;
@property (nonatomic, copy) id action;
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
@end

@interface AWELongPressPanelTableViewController : UIViewController   // 推荐页视频与图文共用
- (NSArray *)dataArray;
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
@property (nonatomic, strong, readonly) AWESettingItemModel *itemModel;
@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, strong, readonly) UIImageView *iconImageView;
- (void)updateSubviewsAfterLayout;
- (void)updateSubviewsColor;         // 按 item 与深浅色重配标题、图标、开关颜色
@end

@interface AWENavigationBar : UIView
@property (nonatomic, strong) UILabel *titleLabel;
@end

#endif /* DouyinHeaders_h */
