// 特殊卡类别的业务判据、设置文案与偏好键。
#import "DKContentFilter.h"
#import "DKKeys.h"

static NSArray<NSDictionary *> *DKCardDefinitions(void) {
    static NSArray *definitions;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        definitions = @[
            @{ @"name": @"热点", @"key": DKKeyFilterRecommendedHotspot, @"title": @"推荐过滤热点",
               @"info": @"过滤首页推荐中的「抖音热点」卡片（如 24 小时精选热点）；普通视频保留。", @"families": @[@"hotspot"], @"exact": @[] },
            @{ @"name": @"创作引导", @"key": DKKeyFilterRecommendedCreation, @"title": @"推荐过滤创作引导",
               @"info": @"过滤作品里程碑、发布周年、往日回忆、主题日常、拍同款、道具与配乐推荐、挑战与话题等发布引导卡片。", @"families": @[@"creation"], @"exact": @[] },
            @{ @"name": @"电商", @"key": DKKeyFilterRecommendedEcommerce, @"title": @"推荐过滤电商卡片",
               @"info": @"过滤店铺动态、商品搜索等购物卡片；普通带货视频保留。", @"families": @[], @"exact": @[@"shop_moment", @"video_query"] },
            @{ @"name": @"游戏", @"key": DKKeyFilterRecommendedGame, @"title": @"推荐过滤游戏卡片",
               @"info": @"过滤小游戏与云游戏卡片（含即点即玩）；普通游戏视频保留。", @"families": @[@"minigame", @"cloud_game"], @"exact": @[] },
            @{ @"name": @"社交推荐", @"key": DKKeyFilterRecommendedSocial, @"title": @"推荐过滤社交推荐",
               @"info": @"过滤推荐搭子、推荐群聊等社交卡片。", @"families": @[@"recommend_mate", @"recommend_im_group"], @"exact": @[] },
            @{ @"name": @"兴趣选择", @"key": DKKeyFilterRecommendedInterest, @"title": @"推荐过滤兴趣推荐卡",
               @"info": @"过滤首页推荐中「你可能感兴趣」的整屏兴趣推荐卡；普通视频与图文保留。从后续新载入批次生效。", @"families": @[], @"exact": @[@"interest_recommend"] },
            @{ @"name": @"小程序", @"key": DKKeyFilterRecommendedMicroApp, @"title": @"推荐过滤小程序卡片",
               @"info": @"过滤小程序推荐与小程序兴趣卡片。", @"families": @[@"microapp"], @"exact": @[@"interest_card"] },
            @{ @"name": @"其他", @"key": @"", @"title": @"",
               @"info": @"", @"families": @[], @"exact": @[] },
        ];
        NSCAssert(definitions.count == DKFilterCardKindCount, @"特殊卡类别表与枚举数量须一致");
    });
    return definitions;
}

NSString *DKFilterCardKindName(DKFilterCardKind kind) { return DKCardDefinitions()[kind][@"name"]; }
NSString *DKFilterCardKindKey(DKFilterCardKind kind) {
    NSString *key = DKCardDefinitions()[kind][@"key"];
    return key.length ? key : nil;
}
NSString *DKFilterCardKindTitle(DKFilterCardKind kind) { return DKCardDefinitions()[kind][@"title"]; }
NSString *DKFilterCardKindInfo(DKFilterCardKind kind) { return DKCardDefinitions()[kind][@"info"]; }

DKFilterCardKind DKFilterCardKindForBusiness(id businessID) {
    if (![businessID isKindOfClass:NSString.class]) return DKFilterCardOther;
    for (NSUInteger kind = 0; kind < DKFilterCardOther; kind++) {
        NSDictionary *definition = DKCardDefinitions()[kind];
        if ([definition[@"exact"] containsObject:businessID]) return (DKFilterCardKind)kind;
        for (NSString *family in definition[@"families"]) {
            if (((kind == DKFilterCardHotspot || kind == DKFilterCardCreation) && [businessID hasPrefix:family]) ||
                [businessID isEqualToString:family] || [businessID hasPrefix:[family stringByAppendingString:@"_"]])
                return (DKFilterCardKind)kind;
        }
    }
    return DKFilterCardOther;
}
