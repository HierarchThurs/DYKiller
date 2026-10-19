// 分享面板：累计原生业务标识与显示文案，按开关过滤功能行。
#import "DKShareMenu.h"
#import "DKKeys.h"
#import "DKUtils.h"

@protocol DKShareMenuFunction <NSObject>
- (NSString *)shareType;
@end

@protocol DKShareMenuModel <NSObject>
- (id<DKShareMenuFunction>)function;
- (NSString *)title;
@end

@protocol DKShareMenuLocalizations <NSObject>
+ (instancetype)sharedInstance;
- (NSString *)translatedStringForString:(NSString *)string;
@end

static NSString *gLastFilter;

static BOOL DKShareMenuValidID(id itemID) {
    if (![itemID isKindOfClass:NSString.class] || ![itemID length] || [itemID length] > 128) return NO;
    static NSCharacterSet *invalid;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *characters = [NSCharacterSet.whitespaceAndNewlineCharacterSet mutableCopy];
        [characters formUnionWithCharacterSet:NSCharacterSet.controlCharacterSet];
        invalid = [characters copy];
    });
    return [itemID rangeOfCharacterFromSet:invalid].location == NSNotFound;
}

static NSString *DKShareMenuItemID(id<DKShareMenuModel> model) {
    if (![model respondsToSelector:@selector(function)]) return nil;
    id<DKShareMenuFunction> function = model.function;
    if (![function respondsToSelector:@selector(shareType)]) return nil;
    id itemID = function.shareType;
    return DKShareMenuValidID(itemID) ? itemID : nil;
}

NSArray<NSDictionary *> *DKShareMenuCatalog(void) {
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:DKKeyShareMenuCatalog];
    if (![stored isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *catalog = [NSMutableArray array];
    for (id entry in stored) {
        if ([entry isKindOfClass:NSDictionary.class] && DKShareMenuValidID(entry[@"id"])) {
            [catalog addObject:entry];
        }
    }
    return catalog;
}

NSString *DKShareMenuHideKey(NSString *itemID) {
    return [DKKeyShareMenuHidePrefix stringByAppendingString:itemID];
}

static void DKShareMenuRecord(NSArray<NSDictionary *> *entries) {
    if (!entries.count) return;
    NSArray *old = DKShareMenuCatalog();
    NSMutableArray *catalog = [old mutableCopy];
    NSMutableSet *known = [NSMutableSet set];
    for (NSDictionary *entry in old) [known addObject:entry[@"id"]];
    for (NSDictionary *entry in entries) {
        NSString *itemID = entry[@"id"];
        if ([known containsObject:itemID]) continue;
        [known addObject:itemID];
        [catalog addObject:entry];
    }
    if (catalog.count != old.count) {
        [NSUserDefaults.standardUserDefaults setObject:catalog forKey:DKKeyShareMenuCatalog];
    }
}

NSArray *DKShareMenuFilter(NSArray *lines) {
    if (![lines isKindOfClass:NSArray.class]) return lines;
    Class localizationClass = NSClassFromString(@"ALPLocalizationsManager");
    id<DKShareMenuLocalizations> localizations = [localizationClass respondsToSelector:@selector(sharedInstance)]
        ? [(id<DKShareMenuLocalizations>)localizationClass sharedInstance] : nil;
    NSMutableArray *entries = [NSMutableArray array];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:lines.count];
    NSUInteger removed = 0;
    BOOL changed = NO;
    for (id line in lines) {
        if (![line isKindOfClass:NSArray.class]) {
            [result addObject:line];
            continue;
        }
        NSMutableArray *kept = [NSMutableArray arrayWithCapacity:[line count]];
        for (id<DKShareMenuModel> model in line) {
            NSString *itemID = DKShareMenuItemID(model);
            if (itemID) {
                id title = [model respondsToSelector:@selector(title)] ? model.title : nil;
                if (![title isKindOfClass:NSString.class] || ![title length]) title = itemID;
                NSString *localized = [localizations respondsToSelector:@selector(translatedStringForString:)]
                    ? [localizations translatedStringForString:title] : nil;
                [entries addObject:@{ @"id": itemID, @"title": localized.length ? localized : title }];
            }
            if (itemID && DKPrefBool(DKShareMenuHideKey(itemID))) removed++;
            else [kept addObject:model];
        }
        if (kept.count == [line count]) {
            [result addObject:line];
        } else {
            changed = YES;
            if (kept.count) [result addObject:[kept copy]];
        }
    }
    DKShareMenuRecord(entries);
    gLastFilter = [NSString stringWithFormat:@"%lu 行，移除 %lu 项，剩 %lu 行",
                   (unsigned long)lines.count, (unsigned long)removed, (unsigned long)result.count];
    return changed ? [result copy] : lines;
}

NSString *DKShareMenuStatus(void) {
    NSArray *catalog = DKShareMenuCatalog();
    NSMutableString *out = [NSMutableString stringWithFormat:@"分享面板精简：目录 %lu 项\n",
                            (unsigned long)catalog.count];
    for (NSDictionary *entry in catalog) {
        [out appendFormat:@"  %@ %@  %@\n", DKPrefBool(DKShareMenuHideKey(entry[@"id"])) ? @"✕" : @"·",
         entry[@"id"], entry[@"title"]];
    }
    [out appendFormat:@"  最近一次：%@\n", gLastFilter ?: @"本次启动尚未打开作品分享面板"];
    return out;
}
