// 广告判据只读取明确标志与具名载荷。
#import "DKContentFilter.h"

static BOOL DKFilterAdFlag(id value) {
    if ([value isKindOfClass:NSNumber.class]) {
        double number = [value doubleValue];
        return number == 1.0;
    }
    if (![value isKindOfClass:NSString.class]) return NO;
    NSString *text = [[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    return [text isEqualToString:@"1"] || [text isEqualToString:@"true"] || [text isEqualToString:@"yes"];
}

static BOOL DKFilterMeaningfulPayload(id value) {
    if ([value isKindOfClass:NSString.class]) {
        NSString *text = [[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
        return text.length && ![@[@"{}", @"[]", @"null"] containsObject:text];
    }
    if ([value isKindOfClass:NSDictionary.class] || [value isKindOfClass:NSArray.class]) return [value count] > 0;
    if ([value isKindOfClass:NSData.class]) return [value length] > 0;
    return DKFilterAdFlag(value);
}

static DKFilterAdReason DKFilterAdDictionary(id raw, NSUInteger depth) {
    if (depth > 8 || ![raw isKindOfClass:NSDictionary.class]) return DKFilterAdNone;
    NSDictionary *dictionary = raw;
    DKFilterAdReason reason = DKFilterAdNone;
    for (NSString *key in @[@"is_ads", @"is_ad"]) {
        if (DKFilterAdFlag(dictionary[key])) reason |= DKFilterAdRawFlag;
    }
    for (NSString *key in @[@"aweme_raw_ad", @"raw_ad_data"]) {
        if (DKFilterMeaningfulPayload(dictionary[key])) reason |= DKFilterAdPayload;
    }
    for (NSString *key in @[@"aweme", @"aweme_info", @"item", @"common_dynamic_patch_model"]) {
        reason |= DKFilterAdDictionary(dictionary[key], depth + 1);
    }
    return reason;
}

DKFilterAdReason DKFilterAdRaw(id raw) {
    return DKFilterAdDictionary(raw, 0);
}

static DKFilterAdReason DKFilterAwemeAd(id model) {
    if (!DKFilterIsClass(model, @"AWEAwemeModel")) return DKFilterAdNone;
    for (NSString *name in @[@"checkIsAd", @"isHardAdModel", @"isHardAd", @"isAds"]) {
        if (DKFilterBool(model, NSSelectorFromString(name))) return DKFilterAdModelFlag;
    }
    return DKFilterAdNone;
}

DKFilterAdReason DKFilterAdModel(id model) {
    DKFilterAdReason reason = DKFilterAwemeAd(model);
    if (reason || !DKFilterIsClass(model, @"AWEGeneralSearchModel")) return reason;
    id patch = DKFilterObject(model, @selector(commonDynamicPatchModel));
    if (DKFilterBool(patch, NSSelectorFromString(@"is_ad"))) reason |= DKFilterAdRawFlag;
    for (NSString *name in @[@"aweme", @"awemeInVideoFeed"]) {
        if (DKFilterAwemeAd(DKFilterObject(model, NSSelectorFromString(name)))) reason |= DKFilterAdEmbedded;
    }
    return reason;
}
