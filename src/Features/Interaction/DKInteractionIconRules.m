#import "DKInteractionIconRules.h"
#import "DKKeys.h"

static BOOL DKIconNameInFamily(NSString *name, NSString *family) {
    return [name isEqualToString:family] || [name hasPrefix:[family stringByAppendingString:@"_"]];
}

DKInteractionIconSlot DKInteractionIconSlotForName(NSString *name) {
    if (![name isKindOfClass:NSString.class]) return DKInteractionIconUnknown;
    NSArray *families = @[ @"icon_home_like_before", @"icon_home_like_after", @"icon_home_comment",
        @"icon_home_unfavorite_v2", @"icon_home_favorite_v2", @"iconHomeShareRight" ];
    for (NSInteger slot = 0; slot < (NSInteger)families.count; slot++) {
        if (DKIconNameInFamily(name, families[slot])) return (DKInteractionIconSlot)slot;
    }
    if (DKIconNameInFamily(name, @"icon_home_favorite_active")) return DKInteractionIconFavoriteAfter;
    if (DKIconNameInFamily(name, @"icon_home_share_v2")) return DKInteractionIconShare;
    return DKInteractionIconUnknown;
}

NSString *DKInteractionIconStyleKey(DKInteractionIconSlot slot) {
    switch (slot) {
        case DKInteractionIconLikeBefore: case DKInteractionIconLikeAfter: return DKKeyInteractionLikeStyle;
        case DKInteractionIconComment: return DKKeyInteractionCommentStyle;
        case DKInteractionIconFavoriteBefore: case DKInteractionIconFavoriteAfter: return DKKeyInteractionFavoriteStyle;
        case DKInteractionIconShare: return DKKeyInteractionShareStyle;
        default: return nil;
    }
}

NSString *DKInteractionIconAssetKey(DKInteractionIconSlot slot) {
    NSArray *keys = @[ DKKeyInteractionLikeBeforeIcon, DKKeyInteractionLikeAfterIcon, DKKeyInteractionCommentIcon,
        DKKeyInteractionFavoriteBeforeIcon, DKKeyInteractionFavoriteAfterIcon, DKKeyInteractionShareIcon ];
    return slot >= 0 && slot < (NSInteger)keys.count ? keys[slot] : nil;
}

NSString *DKInteractionIconTitle(DKInteractionIconSlot slot) {
    NSArray *titles = @[ @"未点赞", @"已点赞", @"评论", @"未收藏", @"已收藏", @"分享" ];
    return slot >= 0 && slot < (NSInteger)titles.count ? titles[slot] : nil;
}

NSArray<NSString *> *DKInteractionIconOptions(DKInteractionIconSlot slot) {
    switch (slot) {
        case DKInteractionIconLikeBefore: case DKInteractionIconLikeAfter: return @[ @"默认", @"小爱心", @"大拇指", @"自定义" ];
        case DKInteractionIconComment: return @[ @"默认", @"文字气泡", @"消息气泡", @"自定义" ];
        case DKInteractionIconFavoriteBefore: case DKInteractionIconFavoriteAfter: return @[ @"默认", @"星星", @"书签", @"自定义" ];
        case DKInteractionIconShare: return @[ @"默认", @"小箭头", @"纸飞机", @"自定义" ];
        default: return @[];
    }
}

BOOL DKInteractionIconIsActive(DKInteractionIconSlot slot) {
    return slot == DKInteractionIconLikeAfter || slot == DKInteractionIconFavoriteAfter;
}
