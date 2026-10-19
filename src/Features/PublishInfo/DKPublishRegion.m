#import "DKPublishRegion.h"

// 查询失败的地名 ID 隔这么久再试（网络或额度恢复后可以重新查到）。
static const NSTimeInterval kDKGeoNamesRetryInterval = 600;

static NSString *DKTrimmed(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *text = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return text.length ? text : nil;
}

static BOOL DKAsciiDigits(NSString *text) {
    static NSCharacterSet *nonDigits;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ nonDigits = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet; });
    return text.length > 0 && [text rangeOfCharacterFromSet:nonDigits].location == NSNotFound;
}

NSString *DKPublishRegionChinaName(NSString *code) {
    code = DKTrimmed(code);
    if (code.length != 6 || !DKAsciiDigits(code)) return nil;
    NSString *province = DKPublishRegionProvinces()[[code substringToIndex:2]];
    if (!province) return nil;
    NSString *city = DKPublishRegionCounties()[code] ?: DKPublishRegionPrefectures()[[code substringToIndex:4]];
    return city && ![city isEqualToString:province] ? [NSString stringWithFormat:@"%@ %@", province, city] : province;
}

NSString *DKPublishRegionCountryName(NSString *region) {
    region = DKTrimmed(region).uppercaseString;
    if (region.length != 2) return nil;
    NSString *special = @{ @"CN": @"中国", @"HK": @"中国香港", @"MO": @"中国澳门", @"TW": @"中国台湾" }[region];
    if (special) return special;
    NSString *name = [[NSLocale localeWithLocaleIdentifier:@"zh_Hans_CN"] localizedStringForCountryCode:region];
    return name.length && ![name isEqualToString:region] ? name : nil;
}

// 原生属地文字，去掉可能带的「IP属地：」前缀。
static NSString *DKAttributionText(NSString *ipAttribution) {
    NSString *text = DKTrimmed(ipAttribution);
    for (NSString *prefix in @[ @"IP属地：", @"IP属地:" ]) {
        if ([text hasPrefix:prefix]) text = DKTrimmed([text substringFromIndex:prefix.length]);
    }
    return text;
}

#pragma mark - GeoNames

static NSCache<NSString *, NSString *> *DKForeignNames(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 300; });
    return cache;
}

static NSMutableSet<NSString *> *DKInFlight(void) {
    static NSMutableSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ set = [NSMutableSet set]; });
    return set;
}

// 「用户名|地名 ID」→ 失败时间。
static NSMutableDictionary<NSString *, NSDate *> *DKFailures(void) {
    static NSMutableDictionary *failures;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ failures = [NSMutableDictionary dictionary]; });
    return failures;
}

static NSURLSession *DKGeoNamesSession(void) {
    static NSURLSession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.timeoutIntervalForRequest = 10;
        configuration.timeoutIntervalForResource = 15;
        session = [NSURLSession sessionWithConfiguration:configuration];
    });
    return session;
}

// 国家、一级行政区、地名依次拼接，去掉重复的层级。
static NSString *DKGeoNamesCompose(NSDictionary *json) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *field in @[ @"countryName", @"adminName1", @"name" ]) {
        NSString *value = DKTrimmed(json[field]);
        if (value && ![parts containsObject:value]) [parts addObject:value];
    }
    return parts.count ? [parts componentsJoinedByString:@" "] : nil;
}

static void DKGeoNamesFetch(NSString *geonameId, NSString *username, void (^resolved)(NSString *)) {
    NSURLComponents *components = [NSURLComponents componentsWithString:@"https://secure.geonames.org/getJSON"];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"geonameId" value:geonameId],
        [NSURLQueryItem queryItemWithName:@"lang" value:@"zh"],
        [NSURLQueryItem queryItemWithName:@"username" value:username],
    ];
    if (!components.URL) return;
    NSString *failureKey = [NSString stringWithFormat:@"%@|%@", username, geonameId];
    [DKInFlight() addObject:geonameId];
    void (^resolvedCopy)(NSString *) = [resolved copy];
    NSURLSessionDataTask *task = [DKGeoNamesSession() dataTaskWithURL:components.URL
                                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *name = nil;
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        if (!error && status == 200 && data.length) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            // 账号未启用、额度用尽等错误以 status 对象返回。
            if ([json isKindOfClass:NSDictionary.class] && !json[@"status"]) name = DKGeoNamesCompose(json);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [DKInFlight() removeObject:geonameId];
            if (!name) {
                DKFailures()[failureKey] = [NSDate date];
                return;
            }
            [DKFailures() removeObjectForKey:failureKey];
            [DKForeignNames() setObject:name forKey:geonameId];
            if (resolvedCopy) resolvedCopy(geonameId);
        });
    }];
    [task resume];
}

static BOOL DKShouldFetch(NSString *geonameId, NSString *username) {
    if ([DKInFlight() containsObject:geonameId]) return NO;
    NSDate *failed = DKFailures()[[NSString stringWithFormat:@"%@|%@", username, geonameId]];
    return !failed || -failed.timeIntervalSinceNow >= kDKGeoNamesRetryInterval;
}

#pragma mark - 显示地区

NSString *DKPublishRegionName(NSString *cityCode, NSString *region, NSString *ipAttribution, NSString *username,
                              void (^resolved)(NSString *geonameId)) {
    NSString *code = DKTrimmed(cityCode);
    NSString *country = DKTrimmed(region).uppercaseString;
    NSString *attribution = DKAttributionText(ipAttribution);
    BOOL domestic = !country || [@[ @"CN", @"HK", @"MO", @"TW" ] containsObject:country];
    if (domestic) return DKPublishRegionChinaName(code) ?: attribution ?: DKPublishRegionCountryName(country);

    if (DKAsciiDigits(code) && code.integerValue > 0) {
        NSString *cached = [DKForeignNames() objectForKey:code];
        if (cached) return cached;
        NSString *user = DKTrimmed(username);
        if (user && DKShouldFetch(code, user)) DKGeoNamesFetch(code, user, resolved);
    }
    return DKPublishRegionCountryName(country) ?: attribution;
}

NSString *DKPublishRegionStatus(void) {
    return [NSString stringWithFormat:@"国外地名：进行中=%lu 失败记录=%lu\n",
            (unsigned long)DKInFlight().count, (unsigned long)DKFailures().count];
}
