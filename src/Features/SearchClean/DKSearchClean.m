// 搜索中间页按抖音共用的区块配置过滤；所有改写只作用于本次返回的副本。
#import "DKSearchClean.h"
#import "DKKeys.h"
#import "DKUtils.h"

NSString *const DKSearchPageConfigKey = @"search_transfer_v2_page_conf";

static NSDictionary *DKSearchDictionary(id value) {
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

BOOL DKSearchTemplateMatches(NSString *url, NSString *bundle) {
    if (![url isKindOfClass:NSString.class]) return NO;
    NSURLComponents *parts = [NSURLComponents componentsWithString:url];
    NSString *path = [bundle stringByAppendingString:@"/template.js"];
    if ([[parts.path lastPathComponent] isEqualToString:@"template.js"] &&
        [[parts.path stringByDeletingLastPathComponent].lastPathComponent isEqualToString:bundle]) return YES;
    for (NSURLQueryItem *item in parts.queryItems) {
        if ([item.name isEqualToString:@"bundle"] && [item.value isEqualToString:path]) return YES;
    }
    return NO;
}

BOOL DKSearchIsMiddlePageProps(NSDictionary *props) {
    if (![props isKindOfClass:NSDictionary.class]) return NO;
    return DKSearchDictionary(props[@"abParams"])[DKSearchPageConfigKey] != nil ||
           DKSearchDictionary(props[@"settings"])[DKSearchPageConfigKey] != nil;
}

// 开关对应的区块标识，原生与各 Lynx 模板共用。
static NSSet<NSString *> *DKSearchHiddenComponents(void) {
    NSMutableSet *keys = [NSMutableSet set];
    if (DKPrefBool(DKKeySearchRemoveHistory)) [keys addObject:@"history"];
    if (DKPrefBool(DKKeySearchRemoveGuess)) [keys addObject:@"guessSearch"];
    if (DKPrefBool(DKKeySearchRemoveAllRanks)) [keys addObject:@"billboard"];
    return keys;
}

static NSDictionary *DKSearchHideComponents(NSDictionary *config, NSSet *hidden) {
    NSArray *components = config[@"pageComponents"];
    if (![components isKindOfClass:NSArray.class]) return config;
    NSMutableArray *rows = nil;
    for (NSUInteger i = 0; i < components.count; i++) {
        NSDictionary *row = DKSearchDictionary(components[i]);
        if (![hidden containsObject:row[@"key"]] || [row[@"show"] isEqual:@NO]) continue;
        NSMutableDictionary *copy = [row mutableCopy];
        copy[@"show"] = @NO;
        if (!rows) rows = [components mutableCopy];
        rows[i] = copy;
    }
    if (!rows) return config;
    NSMutableDictionary *result = [config mutableCopy];
    result[@"pageComponents"] = rows;
    return result;
}

static NSCharacterSet *DKSearchURIComponentCharacters(void) {
    static NSCharacterSet *characters;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        characters = [NSCharacterSet characterSetWithCharactersInString:
            @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"];
    });
    return characters;
}

// 字符串形态是 JSON；Lynx settings 中为 URL 编码的 JSON，改写后保持原编码。
static NSString *DKSearchHideComponentsInString(NSString *config, NSSet *hidden) {
    BOOL encoded = ![config hasPrefix:@"{"];
    NSData *data = [(encoded ? config.stringByRemovingPercentEncoding : config) dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *object = data ? DKSearchDictionary([NSJSONSerialization JSONObjectWithData:data options:0 error:nil]) : @{};
    NSDictionary *cleaned = DKSearchHideComponents(object, hidden);
    NSData *output = cleaned == object ? nil : [NSJSONSerialization dataWithJSONObject:cleaned options:0 error:nil];
    if (!output) return config;
    NSString *json = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
    return encoded ? [json stringByAddingPercentEncodingWithAllowedCharacters:DKSearchURIComponentCharacters()] : json;
}

static id DKSearchHideConfig(id config, NSSet *hidden) {
    if ([config isKindOfClass:NSDictionary.class]) return DKSearchHideComponents(config, hidden);
    if ([config isKindOfClass:NSString.class]) return DKSearchHideComponentsInString(config, hidden);
    return config;
}

id DKSearchCleanPageConfig(id config) {
    NSSet *hidden = DKSearchHiddenComponents();
    return hidden.count ? DKSearchHideConfig(config, hidden) : config;
}

NSDictionary *DKSearchCleanGlobalProps(NSDictionary *props, NSString *url) {
    if (![props isKindOfClass:NSDictionary.class]) return props;
    // 按配置内容识别各形态的中间页卡片；growth 模板路径判据并存。
    BOOL growth = DKSearchTemplateMatches(url, @"search_transfer_growth") ||
                  DKSearchTemplateMatches(props[@"originUrl"], @"search_transfer_growth") ||
                  DKSearchTemplateMatches(props[@"resolvedUrl"], @"search_transfer_growth");
    if (!growth && !DKSearchIsMiddlePageProps(props)) return props;
    NSSet *hidden = DKSearchHiddenComponents();
    if (!hidden.count) return props;

    NSMutableDictionary *result = [props mutableCopy];
    __block BOOL changed = NO;
    void (^update)(NSString *, NSString *, id) = ^(NSString *carrier, NSString *key, id value) {
        NSMutableDictionary *values = [DKSearchDictionary(result[carrier]) mutableCopy];
        values[key] = value;
        result[carrier] = values;
        changed = YES;
    };
    // abParams 来自 AB 全量数据，settings 来自搜索引擎自定义属性，模板按区块分别读取。
    for (NSString *carrier in @[ @"abParams", @"settings" ]) {
        id config = DKSearchDictionary(result[carrier])[DKSearchPageConfigKey];
        id cleaned = DKSearchHideConfig(config, hidden);
        if (cleaned != config) update(carrier, DKSearchPageConfigKey, cleaned);
    }
    // force_enable_recom_search=1 时模板跳过 guessSearch 配置直接显示。
    NSDictionary *experiments = DKSearchDictionary(DKSearchDictionary(result[@"abParams"])[@"search_transfer_experiments"]);
    id force = experiments[@"force_enable_recom_search"];
    if ([hidden containsObject:@"guessSearch"] && force && ![force isEqual:@0]) {
        NSMutableDictionary *copy = [experiments mutableCopy];
        copy[@"force_enable_recom_search"] = @0;
        update(@"abParams", @"search_transfer_experiments", copy);
    }
    return changed ? result : props;
}
