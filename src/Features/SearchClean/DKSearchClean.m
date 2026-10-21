// 搜索卡片按原生业务标识过滤；显示配置只在本次渲染的副本上修改。
#import "DKSearchClean.h"
#import "DKKeys.h"
#import "DKUtils.h"

static NSDictionary *DKSearchDictionary(id value) {
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

static NSString *DKSearchString(id value) {
    return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}

static NSDictionary *DKSearchRankEntry(id value) {
    NSDictionary *entry = DKSearchDictionary(value);
    NSString *rankID = DKSearchString(entry[@"id"]);
    if (!rankID) return nil;
    NSString *title = [rankID isEqualToString:@"CITY"] ? @"同城榜" : DKSearchString(entry[@"title"]);
    return @{ @"id": rankID, @"title": title ?: rankID };
}

NSArray<NSDictionary *> *DKSearchRankCatalog(void) {
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:DKKeySearchRankCatalog];
    if (![stored isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *catalog = [NSMutableArray array];
    NSMutableSet *known = [NSMutableSet set];
    for (id value in stored) {
        NSDictionary *entry = DKSearchRankEntry(value);
        if (!entry || [known containsObject:entry[@"id"]]) continue;
        [known addObject:entry[@"id"]];
        [catalog addObject:entry];
    }
    return catalog;
}

void DKSearchRecordRanks(NSArray<NSDictionary *> *entries) {
    if (!entries.count) return;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    @synchronized (defaults) {
        NSArray *old = DKSearchRankCatalog();
        NSMutableArray *catalog = [old mutableCopy];
        NSMutableDictionary *indices = [NSMutableDictionary dictionary];
        [catalog enumerateObjectsUsingBlock:^(NSDictionary *entry, NSUInteger index, BOOL *stop) {
            indices[entry[@"id"]] = @(index);
        }];
        for (id value in entries) {
            NSDictionary *entry = DKSearchRankEntry(value);
            if (!entry) continue;
            NSNumber *index = indices[entry[@"id"]];
            if (index) catalog[index.unsignedIntegerValue] = entry;
            else {
                indices[entry[@"id"]] = @(catalog.count);
                [catalog addObject:entry];
            }
        }
        if (![old isEqualToArray:catalog]) [defaults setObject:catalog forKey:DKKeySearchRankCatalog];
    }
}

NSString *DKSearchRankHideKey(NSString *rankID) {
    return [DKKeySearchRankHidePrefix stringByAppendingString:rankID];
}

BOOL DKSearchRankHidden(NSString *rankID) {
    return rankID.length && DKPrefBool(DKSearchRankHideKey(rankID));
}

NSArray *DKSearchVisibleRanks(NSArray *tabs, NSString *(^identifier)(id)) {
    if (DKPrefBool(DKKeySearchRemoveAllRanks)) return @[];
    NSMutableArray *visible = [NSMutableArray arrayWithCapacity:tabs.count];
    for (id tab in tabs) if (!DKSearchRankHidden(identifier(tab))) [visible addObject:tab];
    return visible.count == tabs.count ? tabs : visible;
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

NSDictionary *DKSearchCleanGlobalProps(NSDictionary *props, NSString *url) {
    if (![props isKindOfClass:NSDictionary.class]) return props;
    if (!DKSearchTemplateMatches(url, @"search_transfer_growth") &&
        !DKSearchTemplateMatches(props[@"originUrl"], @"search_transfer_growth") &&
        !DKSearchTemplateMatches(props[@"resolvedUrl"], @"search_transfer_growth")) return props;
    BOOL removeHistory = DKPrefBool(DKKeySearchRemoveHistory);
    BOOL removeGuess = DKPrefBool(DKKeySearchRemoveGuess);
    if (!removeHistory && !removeGuess) return props;

    NSMutableDictionary *result = [props mutableCopy];
    NSMutableDictionary *ab = [DKSearchDictionary(props[@"abParams"]) mutableCopy];
    NSDictionary *page = DKSearchDictionary(ab[@"search_transfer_v2_page_conf"]);
    id components = page[@"pageComponents"];
    if ((removeHistory || removeGuess) && [components isKindOfClass:NSArray.class]) {
        NSMutableArray *rows = [NSMutableArray array];
        for (id value in components) {
            NSDictionary *row = DKSearchDictionary(value);
            BOOL remove = (removeHistory && [row[@"key"] isEqual:@"history"]) ||
                          (removeGuess && [row[@"key"] isEqual:@"guessSearch"]);
            if (remove) {
                NSMutableDictionary *copy = [row mutableCopy];
                copy[@"show"] = @NO;
                [rows addObject:copy];
            } else [rows addObject:value];
        }
        NSMutableDictionary *copy = [page mutableCopy];
        copy[@"pageComponents"] = rows;
        ab[@"search_transfer_v2_page_conf"] = copy;
    }
    if (removeGuess) {
        NSMutableDictionary *experiments = [DKSearchDictionary(ab[@"search_transfer_experiments"]) mutableCopy];
        experiments[@"force_enable_recom_search"] = @0;
        ab[@"search_transfer_experiments"] = experiments;
    }
    result[@"abParams"] = ab;
    return result;
}
