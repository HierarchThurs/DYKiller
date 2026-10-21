// 内容类型判据、精确点赞解析与保持数组契约的稳定筛选。
#import "DKContentFilter.h"
#import <CoreFoundation/CoreFoundation.h>
#import <limits.h>

BOOL DKFilterParseInteger(NSString *text, long long *value) {
    if (![text isKindOfClass:NSString.class]) return NO;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length) return NO;
    unsigned long long number = 0;
    for (NSUInteger i = 0; i < trimmed.length; i++) {
        unichar digit = [trimmed characterAtIndex:i];
        if (digit < '0' || digit > '9') return NO;
        unsigned int n = digit - '0';
        if (number > ((unsigned long long)LLONG_MAX - n) / 10) return NO;
        number = number * 10 + n;
    }
    if (value) *value = (long long)number;
    return YES;
}

BOOL DKFilterLikeCount(id raw, long long *value) {
    if ([raw isKindOfClass:NSString.class]) return DKFilterParseInteger(raw, value);
    if (![raw isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)raw) == CFBooleanGetTypeID()) return NO;
    @try {
        NSDecimal decimal = [raw decimalValue];
        if (NSDecimalIsNotANumber(&decimal)) return NO;
        NSDecimal zero = NSDecimalNumber.zero.decimalValue;
        NSDecimal maximum = [NSDecimalNumber decimalNumberWithString:@"9223372036854775807"].decimalValue;
        if (NSDecimalCompare(&decimal, &zero) == NSOrderedAscending
            || NSDecimalCompare(&decimal, &maximum) == NSOrderedDescending) return NO;
        NSDecimal rounded;
        NSDecimalRound(&rounded, &decimal, 0, NSRoundDown);
        if (NSDecimalCompare(&decimal, &rounded) != NSOrderedSame) return NO;
        if (value) *value = [[NSDecimalNumber decimalNumberWithDecimal:decimal] longLongValue];
        return YES;
    } @catch (__unused NSException *exception) { return NO; }
}

BOOL DKFilterIsLive(id model) {
    return DKFilterIsClass(model, @"AWEAwemeModel")
        && (DKFilterBool(model, @selector(isLive)) || DKFilterObject(model, @selector(cellRoom)) != nil);
}

BOOL DKFilterSpecialCard(id model, DKFilterCardKind *kind) {
    if (!DKFilterIsClass(model, @"AWEAwemeModel")) return NO;
    // 原生与 Lynx 特殊卡共用该卡模型，过滤按业务号分类。
    id card = DKFilterObject(model, @selector(hotSpotLynxCardModel));
    if (!card) return NO;
    if (kind) *kind = DKFilterCardKindForBusiness(DKFilterObject(card, @selector(businessID)));
    return YES;
}

BOOL DKFilterIsArticle(id model) {
    return DKFilterIsClass(model, @"AWEAwemeModel") && DKFilterObject(model, @selector(articleInfo)) != nil;
}

// 商家笔记由 POI 富内容的目标链接确认。
BOOL DKFilterIsMerchantNote(id model) {
    if (!DKFilterIsClass(model, @"AWEAwemeModel")) return NO;
    id rich = DKFilterObject(model, @selector(specialRichAwemeModel));
    if (!rich) return NO;
    id scheme = DKFilterObject(rich, @selector(detailScheme));
    BOOL poiScheme = [scheme isKindOfClass:NSString.class] && [scheme hasPrefix:@"aweme://poi/"];
    return poiScheme;
}

static BOOL DKFilterIsRecommended(id model, DKFilterSource source, DKFilterCounts *counts) {
    if (source == DKFilterSourceOther || source == DKFilterSourceConflict) return NO;
    id refer = DKFilterObject(model, @selector(referString));
    // 模型的明确非推荐来源优先，阻止主动插入的其他页面内容进入推荐规则。
    if ([refer isKindOfClass:NSString.class] && [refer length]) return [refer isEqualToString:@"homepage_hot"];
    if (source == DKFilterSourceRecommended) return YES;
    counts->unknownSource++;
    return NO;
}

// 客户端插入的特殊卡没有页面批次来源，只按模型来源确认首页推荐。按业务号所属类别的开关判定；
// 业务号不是字符串时交给宿主。
DKFilterInsertDecision DKFilterSpecialCardInsert(id businessID, id model, DKFilterConfig config) {
    if (![businessID isKindOfClass:NSString.class]) return DKFilterInsertKeep;
    if (!(config.removeCards & DKFilterCardBit(DKFilterCardKindForBusiness(businessID)))) return DKFilterInsertKeep;
    id refer = DKFilterObject(model, @selector(referString));
    if (![refer isKindOfClass:NSString.class] || ![refer length]) return DKFilterInsertUnknownSource;
    return [refer isEqualToString:@"homepage_hot"] ? DKFilterInsertCancel : DKFilterInsertKeep;
}

id DKFilterApplyArray(id array, DKFilterConfig config, DKFilterSource source,
                     DKFilterStage stage, DKFilterCounts *result) {
    DKFilterCounts counts = {0};
    if (![array isKindOfClass:NSArray.class]) { if (result) *result = counts; return array; }
    NSArray *original = array;
    counts.input = counts.output = original.count;
    BOOL ads = config.removeAds && (stage & DKFilterStageAds);
    BOOL live = config.removeLive && (stage & DKFilterStageLive);
    BOOL music = config.removeMusic && (stage & DKFilterStageMusic);
    NSUInteger cards = (stage & DKFilterStageCards) ? config.removeCards : 0;
    BOOL article = config.removeArticles && (stage & DKFilterStageArticle);
    BOOL notes = config.removeMerchantNotes && (stage & DKFilterStageMerchantNote);
    BOOL likes = config.lowLikes && config.minimumLikes > 0 && (stage & DKFilterStageLikes);
    BOOL recommended = live || music || cards || article || notes || likes;
    if (!ads && !recommended) { if (result) *result = counts; return array; }

    NSMutableIndexSet *removed = [NSMutableIndexSet indexSet];
    NSUInteger index = 0;
    DKFilterCardKind kind = DKFilterCardOther;
    for (id model in original) {
        DKFilterAdReason reason = DKFilterAdModel(model);
        if (reason && ads) {
            [removed addIndex:index]; counts.ads++; counts.adReasons |= reason;
        } else if (DKFilterIsClass(model, @"AWEAwemeModel") && recommended
                   && DKFilterIsRecommended(model, source, &counts)) {
            if (DKFilterIsLive(model)) {
                if (live) { [removed addIndex:index]; counts.live++; }
            } else if (music && DKFilterObject(model, @selector(musicCard))) {
                [removed addIndex:index]; counts.music++;
            } else if (cards && DKFilterSpecialCard(model, &kind) && (cards & DKFilterCardBit(kind))) {
                [removed addIndex:index]; counts.cards[kind]++;
            } else if (article && DKFilterIsArticle(model)) {
                [removed addIndex:index]; counts.articles++;
            } else if (notes && DKFilterIsMerchantNote(model)) {
                [removed addIndex:index]; counts.merchantNotes++;
            } else if (likes && !reason) {
                id statistics = DKFilterObject(model, @selector(statistics));
                long long count = 0;
                if (!DKFilterLikeCount(DKFilterObject(statistics, @selector(diggCount)), &count)) counts.unknownLikes++;
                else if (count < config.minimumLikes) { [removed addIndex:index]; counts.likes++; }
            }
        }
        index++;
    }
    counts.output -= removed.count;
    if (result) *result = counts;
    if (!removed.count) return array;
    NSMutableArray *filtered = [original mutableCopy];
    [filtered removeObjectsAtIndexes:removed];
    return [array isKindOfClass:NSMutableArray.class] ? filtered : [filtered copy];
}
