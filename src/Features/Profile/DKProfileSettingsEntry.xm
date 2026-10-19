//
//  DKProfileSettingsEntry.xm
//  DYKiller
//
//  个人主页功能区（观看历史、稍后再看 … 全部功能）末尾的 DYKiller 设置入口，只作用于自己的主页。
//
//  实现：
//   - 功能区数据源 AWEProfileEAVajraDataSource 按服务端顺序生成卡片列表，「全部功能」（cardType 120）追加在末尾，
//     再按列表建卡片控制器与卡片视图；视图持有者 AWEProfileEAVajraViewHolder 拿到列表后按标题算宽度与间距，
//     cell 里的卡片视图按下标向数据源取。
//   - 入口只追加在视图持有者的列表末尾，排布由抖音按五张卡片重算。数据源的列表、卡片控制器与视图都不含入口，
//     抖音的曝光、点击上报与长按编辑不经过它：入口的 cell 用原生复用标识与原生卡片视图（cardViewWithCardModel:）自建，
//     willDisplay 不交给抖音，点击直接打开 DYKiller 设置；可见下标、曝光、加载与点击回调都跳过入口的下标。
//   - 功能区最多五张：数据源生成列表时，若加上入口会超过五张，从「全部功能」之前的最后一个入口开始去掉，
//     被去掉的卡片不再生成控制器与视图，其余卡片在两份列表里的下标保持一致。
//   - 图标取个人主页 SVG 图标集里的齿轮（ic_gearsimplify_outlined_20），模板渲染，按标题文字色着色；
//     卡片视图按主题重新取图标时改挂齿轮。
//   - 设置改动：对已见的功能区以当前用户模型调用数据源的 refreshUserModel:，走抖音自己的重建与重排。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKProfileClean.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import <objc/runtime.h>

static const unsigned long long kDKEntryCardType = 990001;   // 不与抖音卡片类型重合，只作诊断标识
static const unsigned long long kDKFindMoreCardType = 120;
static const NSUInteger kDKEntryMaxCards = 5;
static NSString *const kDKEntryReuseIdentifier = @"kAWEProfileExtensionAreaCard";
static NSString *const kDKEntryIconName = @"ic_gearsimplify_outlined_20";

static char kDKEntryModelKey;
static char kDKEntryCardViewKey;
// 弱表（自己主页的功能区视图持有者），只在主线程读写。
static NSHashTable *gDKEntryHolders;
static NSString *gDKEntryLastTrim;

static BOOL DKEntryMine(id owner) {
    AWEProfileExtensionAreaContext *context = [owner respondsToSelector:@selector(context)] ? (AWEProfileExtensionAreaContext *)[owner context] : nil;
    AWEProfileHeaderContext *header = [context respondsToSelector:@selector(profileHeaderContext)] ? [context profileHeaderContext] : nil;
    return [header respondsToSelector:@selector(isCurrentUser)] && [header isCurrentUser];
}

static BOOL DKEntryWanted(id owner) {
    return DKPrefBool(DKKeyProfileSettingsEntry) && !DKPrefBool(DKKeyProfileRemoveServiceArea) && DKEntryMine(owner);
}

static NSString *DKEntryTitle(void) {
    return DKPrefInteger(DKKeyProfileSettingsEntryName) == 1 ? @"插件设置" : @"DYKiller";
}

static BOOL DKEntryIsModel(id card) {
    return card && objc_getAssociatedObject(card, &kDKEntryModelKey) != nil;
}

static BOOL DKEntryIsFindMore(id card) {
    return [card respondsToSelector:@selector(cardType)] && [(AWEProfileExtensionAreaCardModel *)card cardType] == kDKFindMoreCardType;
}

static AWEProfileExtensionAreaCardModel *DKEntryMakeModel(void) {
    AWEProfileExtensionAreaCardModel *model = [[%c(AWEProfileExtensionAreaCardModel) alloc] init];
    if (![model respondsToSelector:@selector(setTitle:)] || ![model respondsToSelector:@selector(setCardType:)]) return nil;
    model.cardType = kDKEntryCardType;
    model.title = DKEntryTitle();
    objc_setAssociatedObject(model, &kDKEntryModelKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return model;
}

// 数据源列表给入口留一位：总数（含「全部功能」与入口）不超过五张，多出的从「全部功能」之前的最后一个入口去掉。
static NSArray *DKEntryTrimSourceCards(NSArray *cards) {
    NSMutableArray *kept = [cards mutableCopy];
    NSMutableArray<NSString *> *dropped = [NSMutableArray array];
    while (kept.count + 1 > kDKEntryMaxCards) {
        NSInteger index = (NSInteger)kept.count - 1;
        while (index >= 0 && DKEntryIsFindMore(kept[index])) index--;
        if (index < 0) break;
        id card = kept[index];
        [dropped addObject:[card respondsToSelector:@selector(title)] ? ([(AWEProfileExtensionAreaCardModel *)card title] ?: @"?") : @"?"];
        [kept removeObjectAtIndex:index];
    }
    if (NSThread.isMainThread) {
        gDKEntryLastTrim = dropped.count ? [NSString stringWithFormat:@"%lu 张，让位去掉 [%@]", (unsigned long)cards.count,
                                            [dropped componentsJoinedByString:@", "]] : nil;
    }
    return dropped.count ? [kept copy] : cards;
}

static NSArray *DKEntryAppend(NSArray *cards) {
    NSMutableArray *list = [NSMutableArray arrayWithCapacity:cards.count + 1];
    for (id card in cards) {
        if (!DKEntryIsModel(card)) [list addObject:card];
    }
    if (!list.count || list.count >= kDKEntryMaxCards) return list.count == cards.count ? cards : [list copy];
    AWEProfileExtensionAreaCardModel *model = DKEntryMakeModel();
    if (model) [list addObject:model];
    return [list copy];
}

static BOOL DKEntryAtIndexPath(AWEProfileEAVajraViewHolder *holder, NSIndexPath *indexPath) {
    NSArray *cards = [holder respondsToSelector:@selector(cardList)] ? [holder cardList] : nil;
    return indexPath.item >= 0 && indexPath.item < (NSInteger)cards.count && DKEntryIsModel(cards[indexPath.item]);
}

#pragma mark - 图标

static UIImage *DKEntryGearImage(CGSize size) {
    static UIImage *image;
    static CGSize imageSize;
    if (image && CGSizeEqualToSize(size, imageSize)) return image;
    UIImage *gear = nil;
    if ([UIImage respondsToSelector:@selector(svg_userProfileImageWithName:size:color:)]) {
        gear = [UIImage svg_userProfileImageWithName:kDKEntryIconName size:size color:UIColor.blackColor];
    }
    if (!gear) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:size.height * 0.8
                                                                                              weight:UIImageSymbolWeightRegular];
        gear = [UIImage systemImageNamed:@"gearshape" withConfiguration:config];
    }
    image = [gear imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    imageSize = size;
    return image;
}

static void DKEntryApplyIcon(UIView *cardView) {
    UIImageView *imageView = [cardView respondsToSelector:@selector(imageView)] ? [(AWEProfileExtensionAreaVajraStyleCardView *)cardView imageView] : nil;
    if (![imageView isKindOfClass:UIImageView.class]) return;
    CGSize size = imageView.bounds.size;
    if (size.width < 1.0 || size.height < 1.0) size = CGSizeMake(24.0, 24.0);
    UIImage *gear = DKEntryGearImage(size);
    if (gear && imageView.image != gear) imageView.image = gear;
    UILabel *label = [cardView respondsToSelector:@selector(titleLabel)] ? [(AWEProfileExtensionAreaVajraStyleCardView *)cardView titleLabel] : nil;
    if ([label isKindOfClass:UILabel.class] && label.textColor) imageView.tintColor = label.textColor;
}

// 卡片视图按主题刷新时，标题色可能在图标之后才写；下一轮主队列再着一次色。
static void DKEntryApplyIconNowAndLater(UIView *cardView) {
    DKEntryApplyIcon(cardView);
    __weak UIView *weakView = cardView;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *view = weakView;
        if (view && [view respondsToSelector:@selector(cardModel)] && DKEntryIsModel([(id)view cardModel])) DKEntryApplyIcon(view);
    });
}

static UIView *DKEntryCardView(AWEProfileEAVajraViewHolder *holder, AWEProfileExtensionAreaCardModel *model) {
    UIView *view = objc_getAssociatedObject(holder, &kDKEntryCardViewKey);
    if (![view isKindOfClass:UIView.class]) {
        view = [holder respondsToSelector:@selector(cardViewWithCardModel:)] ? [holder cardViewWithCardModel:model] : nil;
        if (![view isKindOfClass:UIView.class]) return nil;
        objc_setAssociatedObject(holder, &kDKEntryCardViewKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if ([view respondsToSelector:@selector(cardModel)] && [(id)view cardModel] != model &&
               [view respondsToSelector:@selector(configWithCardModel:)]) {
        [(AWEProfileExtensionAreaVajraStyleCardView *)view configWithCardModel:model];
    }
    DKEntryApplyIconNowAndLater(view);
    return view;
}

static UIViewController *DKEntryPresenter(UIView *view) {
    for (UIResponder *responder = view; responder; responder = responder.nextResponder) {
        if ([responder isKindOfClass:UIViewController.class] && ((UIViewController *)responder).navigationController) {
            return (UIViewController *)responder;
        }
    }
    return nil;
}

#pragma mark - 刷新与诊断

void DKProfileSettingsEntryRefresh(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKProfileSettingsEntryRefresh(); });
        return;
    }
    for (AWEProfileEAVajraViewHolder *holder in gDKEntryHolders.allObjects) {
        if (!DKEntryMine(holder)) continue;
        AWEProfileExtensionAreaContext *context = [holder respondsToSelector:@selector(context)] ? [holder context] : nil;
        id dataSource = [context respondsToSelector:@selector(dataSource)] ? [context dataSource] : nil;
        id user = [context respondsToSelector:@selector(userModel)] ? [context userModel] : nil;
        if (user && [dataSource respondsToSelector:@selector(refreshUserModel:)]) [dataSource refreshUserModel:user];
    }
}

NSString *DKProfileSettingsEntryStatus(void) {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"主页入口=%d 名称=%@ 功能区移除=%d 已见功能区=%lu 最近一次让位：%@\n", DKPrefBool(DKKeyProfileSettingsEntry),
        DKEntryTitle(), DKPrefBool(DKKeyProfileRemoveServiceArea), (unsigned long)gDKEntryHolders.allObjects.count,
        gDKEntryLastTrim ?: @"无"];
    for (AWEProfileEAVajraViewHolder *holder in gDKEntryHolders.allObjects) {
        NSMutableArray<NSString *> *titles = [NSMutableArray array];
        for (id card in [holder cardList]) {
            NSString *title = [card respondsToSelector:@selector(title)] ? [(AWEProfileExtensionAreaCardModel *)card title] : nil;
            [titles addObject:[NSString stringWithFormat:@"%@%@", title ?: @"?", DKEntryIsModel(card) ? @"(入口)" : @""]];
        }
        UIView *view = objc_getAssociatedObject(holder, &kDKEntryCardViewKey);
        [out appendFormat:@"  卡片=[%@] 入口视图在窗口=%d frame=%@\n", [titles componentsJoinedByString:@", "], view.window != nil,
            view ? NSStringFromCGRect([view convertRect:view.bounds toView:nil]) : @"-"];
    }
    return out;
}

#pragma mark - Hook

%hook AWEProfileEAVajraDataSource

- (void)setCardList:(NSArray *)cardList {
    if ([cardList isKindOfClass:NSArray.class] && cardList.count && DKEntryWanted(self)) {
        %orig(DKEntryTrimSourceCards(cardList));
        return;
    }
    %orig;
}

%end

%hook AWEProfileEAVajraViewHolder

- (void)setCardList:(NSArray *)cardList {
    if (NSThread.isMainThread && DKEntryMine(self)) {
        if (!gDKEntryHolders) gDKEntryHolders = [NSHashTable weakObjectsHashTable];
        [gDKEntryHolders addObject:self];
    }
    if ([cardList isKindOfClass:NSArray.class] && DKEntryWanted(self)) {
        %orig(DKEntryAppend(cardList));
        return;
    }
    %orig;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    if (!DKEntryAtIndexPath(self, indexPath)) return %orig;
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kDKEntryReuseIdentifier forIndexPath:indexPath];
    UIView *view = DKEntryCardView(self, [self cardList][indexPath.item]);
    if (view && [cell respondsToSelector:@selector(addCardView:)]) [(AWEProfileExtensionAreaCell *)cell addCardView:view];
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    if (DKEntryAtIndexPath(self, indexPath)) return;
    %orig;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (!DKEntryAtIndexPath(self, indexPath)) {
        %orig;
        return;
    }
    [collectionView deselectItemAtIndexPath:indexPath animated:NO];
    DKSettingsOpenMain(DKEntryPresenter(collectionView));
}

// 出现时的曝光补报按可见下标逐个走 cardWillDisplayAtIndexPath:，入口不在其中。
- (NSArray *)indexPathsForVisibleItems {
    NSArray *paths = %orig;
    if (![paths isKindOfClass:NSArray.class] || !paths.count) return paths;
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:paths.count];
    for (id path in paths) {
        if (!([path isKindOfClass:NSIndexPath.class] && DKEntryAtIndexPath(self, path))) [kept addObject:path];
    }
    return kept.count == paths.count ? paths : [kept copy];
}

- (void)cardWillDisplayAtIndexPath:(NSIndexPath *)indexPath {
    if (DKEntryAtIndexPath(self, indexPath)) return;
    %orig;
}

- (void)cardDidLoadAtIndexPath:(NSIndexPath *)indexPath {
    if (DKEntryAtIndexPath(self, indexPath)) return;
    %orig;
}

- (void)cardDidClickAtIndexPath:(NSIndexPath *)indexPath {
    if (DKEntryAtIndexPath(self, indexPath)) return;
    %orig;
}

%end

%hook AWEProfileExtensionAreaVajraStyleCardView

- (void)updateImageViewWithLightUrlArray:(id)lightUrls darkUrlArray:(id)darkUrls {
    %orig;
    if (DKEntryIsModel([self cardModel])) DKEntryApplyIconNowAndLater(self);
}

- (void)updateImageViewWithLightUrlArray:(id)lightUrls darkUrlArray:(id)darkUrls completion:(id)completion {
    %orig;
    if (DKEntryIsModel([self cardModel])) DKEntryApplyIconNowAndLater(self);
}

%end

#pragma mark - 设置

%ctor {
    DKSettingsRegister(DKKeyProfileSettingsEntry, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(DKKeyProfileSettingsEntry, @"个人主页添加DYKiller入口",
            @"在个人主页功能区（观看历史、全部功能那一行）的最后加一个 DYKiller 设置入口，点击直接打开插件设置。"
            @"功能区最多五个入口：已有四个入口加「全部功能」时，第四个入口让位给 DYKiller，关闭后恢复。只作用于自己的主页。");
        DKSettingsOnChange(item, ^{ DKProfileSettingsEntryRefresh(); });
        return item;
    });
    DKSettingsRegister(DKKeyProfileSettingsEntryName, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeChoice(DKKeyProfileSettingsEntryName, @"主页设置入口名称", @[ @"DYKiller", @"插件设置" ]);
        DKSettingsOnChange(item, ^{ DKProfileSettingsEntryRefresh(); });
        return DKSettingsWithInfo(item, @"个人主页 DYKiller 入口图标下方的文字。需先开启「个人主页添加DYKiller入口」。");
    });
}
