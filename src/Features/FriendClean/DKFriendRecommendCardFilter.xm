//
//  DKFriendRecommendCardFilter.xm
//  DYKiller
//
//  朋友页精简 —— 移除朋友页内容流里的「看看朋友推荐的作品」卡片。
//
//  实现：
//   - 朋友页内容流响应（AWEFamiliarFeedResponseModel，预加载为 AWEFamiliarFeedPreloadResponse）的 cardList 是
//     AWEConcernCardModel 数组，数据控制器经 cardList 读取并转换成作品列表。卡片条目 type 为 8，其 aweme 带 friendRecommendCard。
//   - 开关打开时 cardList 按当前条目生成去掉卡片条目的可变数组，保留原数组；
//     卡片不进入内容流，前后作品直接相连。从下一次加载或刷新起生效，已加载的列表不动。
//

#import "DouyinHeaders.h"
#import "DKFriendClean.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import <stdatomic.h>

static const NSInteger kDKFriendRecommendCardType = 8;
static atomic_uint_fast64_t gDKRemovedRecommendCards;

static BOOL DKIsFriendRecommendCard(id card) {
    if (![card isKindOfClass:%c(AWEConcernCardModel)] || ![card respondsToSelector:@selector(type)]) return NO;
    if ([(AWEConcernCardModel *)card type] != kDKFriendRecommendCardType) return NO;
    AWEAwemeModel *aweme = [card respondsToSelector:@selector(aweme)] ? [(AWEConcernCardModel *)card aweme] : nil;
    return [aweme respondsToSelector:@selector(friendRecommendCard)] && [aweme friendRecommendCard] != nil;
}

static NSArray *DKFilterCardList(NSArray *list) {
    if (!DKPrefBool(DKKeyFriendRemoveRecommendCard) || ![list isKindOfClass:NSArray.class] || list.count == 0) return list;

    NSIndexSet *drop = [list indexesOfObjectsPassingTest:^BOOL(id card, __unused NSUInteger index, __unused BOOL *stop) {
        return DKIsFriendRecommendCard(card);
    }];
    NSArray *result = list;
    if (drop.count) {
        NSMutableArray *filtered = [list mutableCopy];
        [filtered removeObjectsAtIndexes:drop];
        result = filtered;
        atomic_fetch_add(&gDKRemovedRecommendCards, drop.count);
    }
    return result;
}

NSString *DKFriendRecommendCardStatus(void) {
    return [NSString stringWithFormat:@"移除看看朋友推荐的作品=%d 累计过滤条目（含重复读取）=%llu\n", DKPrefBool(DKKeyFriendRemoveRecommendCard),
        (unsigned long long)atomic_load(&gDKRemovedRecommendCards)];
}

%hook AWEFamiliarFeedResponseModel

- (NSArray *)cardList {
    return DKFilterCardList(%orig);
}

%end

%hook AWEFamiliarFeedPreloadResponse

- (NSArray *)cardList {
    return DKFilterCardList(%orig);
}

%end
