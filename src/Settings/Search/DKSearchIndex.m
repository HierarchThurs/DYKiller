//
//  DKSearchIndex.m
//

#import "DKSearchIndex.h"
#import "DKSettingsInternal.h"
#import "DKSettingsLayout.h"
#import <stdlib.h>

// 字段权重。
static const CGFloat kDKSearchWeightTitle = 1.0;
static const CGFloat kDKSearchWeightPage = 0.45;
static const CGFloat kDKSearchWeightSection = 0.35;
static const CGFloat kDKSearchWeightText = 0.30;
static const CGFloat kDKSearchWeightKey = 0.15;

@interface DKSearchField : NSObject
@property (nonatomic, copy) NSString *text;      // 已规范化
@property (nonatomic, assign) CGFloat weight;
@property (nonatomic, assign) BOOL isTitle;
@end

@implementation DKSearchField
@end

@interface DKSearchEntry ()
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *icon;
@property (nonatomic, copy) NSString *pageTitle;
@property (nonatomic, copy) NSString *sectionHeader;
@property (nonatomic, copy) NSString *lockReason;
@property (nonatomic, copy) NSArray<DKSettingsPage *> *pagePath;
@property (nonatomic, assign) BOOL isPageEntry;
@property (nonatomic, assign) BOOL onCurrentPage;
@property (nonatomic, assign) NSUInteger layoutOrder;
@property (nonatomic, strong) NSMutableArray<DKSearchField *> *fields;
@end

@implementation DKSearchEntry

- (instancetype)init {
    if ((self = [super init])) {
        _pagePath = @[];
        _fields = [NSMutableArray array];
    }
    return self;
}

@end

#pragma mark - 规范化

// 只留字母、数字与汉字：小写、全角转半角，去掉空白与常见标点。
static NSString *DKSearchNormalize(NSString *text) {
    if (![text isKindOfClass:NSString.class] || text.length == 0) return @"";
    NSString *half = [text stringByApplyingTransform:NSStringTransformFullwidthToHalfwidth reverse:NO] ?: text;
    NSString *lower = half.lowercaseString;
    NSMutableString *out = [NSMutableString stringWithCapacity:lower.length];
    for (NSUInteger index = 0; index < lower.length; index++) {
        unichar character = [lower characterAtIndex:index];
        if ((character >= 'a' && character <= 'z') || (character >= '0' && character <= '9')) {
            [out appendFormat:@"%C", character];
        } else if ((character >= 0x3040 && character <= 0x30FF) ||
                   (character >= 0x3400 && character <= 0x9FFF) ||
                   (character >= 0xF900 && character <= 0xFAFF)) {
            [out appendFormat:@"%C", character];   // 假名与汉字；CJK 标点（、。「」）当分隔符丢掉
        }
    }
    return out;
}

static NSArray<NSString *> *DKSearchTokens(NSString *query) {
    if (![query isKindOfClass:NSString.class] || query.length == 0) return @[];
    NSArray<NSString *> *parts = [query componentsSeparatedByCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray<NSString *> *tokens = [NSMutableArray arrayWithCapacity:parts.count];
    for (NSString *part in parts) {
        NSString *compact = DKSearchNormalize(part);
        if (compact.length) [tokens addObject:compact];
    }
    return tokens;
}

#pragma mark - 匹配

// query 的字符是否按顺序出现在 field 里。
static BOOL DKSearchSubsequence(NSString *query, NSString *field) {
    NSUInteger cursor = 0, length = field.length;
    for (NSUInteger index = 0; index < query.length; index++) {
        unichar target = [query characterAtIndex:index];
        BOOL found = NO;
        while (cursor < length) {
            if ([field characterAtIndex:cursor++] == target) { found = YES; break; }
        }
        if (!found) return NO;
    }
    return YES;
}

// query 的字符是否都出现在 field 里（不要求顺序），用于「图片评论」这类语序打乱的输入。
static BOOL DKSearchContainsAllChars(NSString *query, NSString *field) {
    NSUInteger queryLength = query.length, fieldLength = field.length;
    if (queryLength == 0 || fieldLength < queryLength) return NO;
    BOOL *used = calloc(fieldLength, sizeof(BOOL));
    if (!used) return NO;
    BOOL all = YES;
    for (NSUInteger q = 0; q < queryLength && all; q++) {
        unichar target = [query characterAtIndex:q];
        BOOL found = NO;
        for (NSUInteger f = 0; f < fieldLength; f++) {
            if (used[f]) continue;
            if ([field characterAtIndex:f] == target) {
                used[f] = YES;
                found = YES;
                break;
            }
        }
        if (!found) all = NO;
    }
    free(used);
    return all;
}

// 有界编辑距离，超过 limit 立即返回 limit + 1。
static NSUInteger DKSearchEditDistance(NSString *a, NSString *b, NSUInteger limit) {
    NSUInteger lengthA = a.length, lengthB = b.length;
    NSUInteger diff = lengthA > lengthB ? lengthA - lengthB : lengthB - lengthA;
    if (diff > limit) return limit + 1;
    NSUInteger *previous = calloc(lengthB + 1, sizeof(NSUInteger));
    NSUInteger *current = calloc(lengthB + 1, sizeof(NSUInteger));
    if (!previous || !current) {
        free(previous);
        free(current);
        return limit + 1;
    }
    for (NSUInteger column = 0; column <= lengthB; column++) previous[column] = column;
    NSUInteger distance = limit + 1;
    for (NSUInteger row = 1; row <= lengthA; row++) {
        current[0] = row;
        NSUInteger rowMin = current[0];
        unichar left = [a characterAtIndex:row - 1];
        for (NSUInteger column = 1; column <= lengthB; column++) {
            unichar right = [b characterAtIndex:column - 1];
            NSUInteger cost = (left == right) ? 0 : 1;
            NSUInteger value = MIN(MIN(previous[column] + 1, current[column - 1] + 1), previous[column - 1] + cost);
            current[column] = value;
            rowMin = MIN(rowMin, value);
        }
        if (rowMin > limit) {
            free(previous);
            free(current);
            return limit + 1;
        }
        NSUInteger *swap = previous;
        previous = current;
        current = swap;
    }
    distance = previous[lengthB];
    free(previous);
    free(current);
    return distance;
}

// 英数输入的容错：字段里任一与 query 等长的窗口差一个字符即算命中。
static BOOL DKSearchApproximate(NSString *query, NSString *field) {
    if (query.length < 4) return NO;
    if (![query canBeConvertedToEncoding:NSASCIIStringEncoding]) return NO;
    if (field.length + 1 < query.length) return NO;
    NSUInteger width = query.length;
    for (NSUInteger start = 0; start < field.length; start++) {
        NSUInteger length = MIN(width, field.length - start);
        if (length + 1 < width) break;
        NSString *window = [field substringWithRange:NSMakeRange(start, length)];
        if (DKSearchEditDistance(query, window, 1) <= 1) return YES;
    }
    return NO;
}

// 0–1 的匹配档位。长字段（如 ⓘ 说明）只认精确、前缀与连续子串，避免子序列在长句里乱命中。
static const NSUInteger kDKSearchLooseFieldLimit = 24;

static CGFloat DKSearchLevel(NSString *query, NSString *field) {
    if (query.length == 0 || field.length == 0) return 0;
    if ([field isEqualToString:query]) return 1.00;
    if ([field hasPrefix:query]) return 0.92;
    if ([field rangeOfString:query].location != NSNotFound) {
        CGFloat ratio = (CGFloat)query.length / (CGFloat)field.length;
        return 0.70 + 0.15 * MIN(1.0, ratio * 1.6);
    }
    if (field.length > kDKSearchLooseFieldLimit) return 0;
    if (DKSearchSubsequence(query, field)) {
        CGFloat coverage = (CGFloat)query.length / (CGFloat)field.length;
        return 0.42 + 0.18 * MIN(1.0, coverage * 2.0);
    }
    if (DKSearchContainsAllChars(query, field)) {
        CGFloat coverage = (CGFloat)query.length / (CGFloat)field.length;
        return 0.38 + 0.12 * MIN(1.0, coverage * 2.0);
    }
    if (DKSearchApproximate(query, field)) return 0.55;
    return 0;
}

static void DKAddField(DKSearchEntry *entry, NSString *text, CGFloat weight, BOOL isTitle) {
    NSString *compact = DKSearchNormalize(text);
    if (compact.length == 0) return;
    for (DKSearchField *existing in entry.fields) {
        if (existing.isTitle != isTitle) continue;
        if ([existing.text isEqualToString:compact]) return;
    }
    DKSearchField *field = [[DKSearchField alloc] init];
    field.text = compact;
    field.weight = weight;
    field.isTitle = isTitle;
    [entry.fields addObject:field];
}

static void DKResetFields(DKSearchEntry *entry, NSString *extraText, NSString *infoText, NSString *keyText) {
    [entry.fields removeAllObjects];
    DKAddField(entry, entry.title, kDKSearchWeightTitle, YES);
    DKAddField(entry, entry.pageTitle, kDKSearchWeightPage, NO);
    DKAddField(entry, entry.sectionHeader, kDKSearchWeightSection, NO);
    DKAddField(entry, extraText, kDKSearchWeightText, NO);
    DKAddField(entry, infoText, kDKSearchWeightText, NO);
    NSString *alias = [keyText hasPrefix:@"DYKiller"] ? [keyText substringFromIndex:8] : nil;
    DKAddField(entry, alias, kDKSearchWeightKey, NO);
}

static CGFloat DKSearchScoreEntry(DKSearchEntry *entry, NSArray<NSString *> *tokens) {
    if (tokens.count == 0 || entry.fields.count == 0) return 0;
    CGFloat total = 0.0;
    for (NSString *token in tokens) {
        CGFloat best = 0.0;
        for (DKSearchField *field in entry.fields) {
            if (field.weight == kDKSearchWeightKey && token.length < 3) continue;
            CGFloat level = DKSearchLevel(token, field.text);
            if (level <= 0.0) continue;
            CGFloat score = level * field.weight;
            if (field.isTitle) score += level * 0.06;      // 标题命中的加成
            best = MAX(best, score);
        }
        if (best <= 0.0) return 0.0;
        total += best;
    }
    CGFloat score = total / (CGFloat)tokens.count;
    NSString *compactTitle = DKSearchNormalize(entry.title);
    score += 0.04 * (1.0 - MIN(1.0, (CGFloat)compactTitle.length / 20.0));
    if (entry.isPageEntry) score -= 0.005;                 // 同分时设置行优于子页入口
    return score;
}

#pragma mark - 建索引

static void DKPrepareProbe(AWESettingItemModel *item) {
    DKSettingsPrepareItem(item, nil);
    AWESettingSectionModel *probe = DKSettingsMakeSection(nil, nil, @[ item ]);
    DKSettingsApplyLocks(@[ probe ]);
}

static NSString *DKItemLockReason(AWESettingItemModel *item) {
    return item.isEnable ? nil : DKSettingsLockReason(item);
}

static DKSearchEntry *DKMakeEntry(NSString *identifier, NSString *title, NSString *icon,
                                  NSString *pageTitle, NSString *sectionHeader,
                                  NSArray<DKSettingsPage *> *path, BOOL isPageEntry, NSUInteger order) {
    DKSearchEntry *entry = [[DKSearchEntry alloc] init];
    entry.identifier = identifier ?: @"";
    entry.title = title ?: @"";
    entry.icon = icon;
    entry.pageTitle = pageTitle;
    entry.sectionHeader = sectionHeader;
    entry.pagePath = path ?: @[];
    entry.isPageEntry = isPageEntry;
    entry.layoutOrder = order;
    DKResetFields(entry, nil, nil, isPageEntry ? nil : identifier);
    return entry;
}

// 布局表递归：产出设置行、动作行与子页入口。
static NSUInteger DKCollectSections(NSArray<DKSettingsSection *> *sections,
                                    NSArray<DKSettingsPage *> *ancestors,
                                    NSString *pageTitle,
                                    NSMutableArray<DKSearchEntry *> *out,
                                    NSMutableDictionary<NSString *, DKSearchEntry *> *byIdentifier,
                                    NSUInteger order) {
    for (DKSettingsSection *section in sections) {
        for (id row in section.rows) {
            if ([row isKindOfClass:DKSettingsRow.class]) {
                DKSettingsRow *spec = row;
                AWESettingItemModel *item = DKSettingsBuildItem(spec.key);
                if (!item) continue;
                DKPrepareProbe(item);
                DKSearchEntry *entry = DKMakeEntry(spec.key, item.title ?: spec.key,
                                                   item.svgIconImageName ?: spec.icon,
                                                   pageTitle, section.header, ancestors, NO, order++);
                DKResetFields(entry, item.detail, DKSettingsItemInfo(item), spec.key);
                entry.lockReason = DKItemLockReason(item);
                [out addObject:entry];
                if (spec.key.length) byIdentifier[spec.key] = entry;
            } else if ([row isKindOfClass:DKSettingsPage.class]) {
                DKSettingsPage *spec = row;
                NSArray<DKSettingsPage *> *path = [ancestors arrayByAddingObject:spec];
                DKSearchEntry *entry = DKMakeEntry(spec.identifier, spec.title, spec.icon,
                                                   pageTitle, section.header, path, YES, order++);
                entry.lockReason = DKSettingsKeyLockReason(spec.identifier);
                [out addObject:entry];
                if (spec.identifier.length) byIdentifier[spec.identifier] = entry;
                order = DKCollectSections(spec.sections, path, spec.title, out, byIdentifier, order);
            } else if ([row isKindOfClass:DKSettingsLink.class]) {
                DKSettingsLink *spec = row;
                DKSearchEntry *entry = DKMakeEntry(spec.title, spec.title, spec.icon,
                                                   pageTitle, section.header, ancestors, NO, order++);
                [out addObject:entry];
                if (spec.title.length) byIdentifier[spec.title] = entry;
            }
        }
    }
    return order;
}

// 当前页 live 项：覆盖运行时动态子页（移除底栏项目 / 移除顶部频道 / 恢复明细），并刷新静态项的最新文字。
static void DKMergeCurrentPage(UIViewController *page, NSArray<DKSettingsPage *> *pagePath, BOOL isMain,
                               NSMutableArray<DKSearchEntry *> *out,
                               NSMutableDictionary<NSString *, DKSearchEntry *> *byIdentifier) {
    NSString *pageTitle = pagePath.lastObject.title;
    for (AWESettingSectionModel *section in DKSettingsPageSections(page)) {
        for (AWESettingItemModel *item in section.itemArray) {
            NSString *identifier = item.identifier;
            if (!identifier.length) continue;
            DKSearchEntry *entry = byIdentifier[identifier];
            if (!entry) {
                entry = DKMakeEntry(identifier, item.title ?: identifier, item.svgIconImageName,
                                    pageTitle, section.sectionHeaderTitle, pagePath, NO, out.count);
                [out addObject:entry];
                byIdentifier[identifier] = entry;
            }
            if (!isMain) entry.onCurrentPage = YES;
            if (item.title.length) entry.title = item.title;
            if (item.svgIconImageName.length) entry.icon = item.svgIconImageName;
            DKResetFields(entry, item.detail, DKSettingsItemInfo(item), identifier);
            entry.lockReason = DKItemLockReason(item);
        }
    }
}

// 子页 identifier 序列逐级对应到布局表里的页面；任一级找不到返回 nil。
static NSArray<DKSettingsPage *> *DKResolvePagePath(NSArray<NSString *> *identifiers) {
    if (!identifiers) return nil;
    NSMutableArray<DKSettingsPage *> *path = [NSMutableArray arrayWithCapacity:identifiers.count];
    NSArray<DKSettingsSection *> *sections = DKSettingsLayoutMain();
    for (NSString *identifier in identifiers) {
        DKSettingsPage *found = nil;
        for (DKSettingsSection *section in sections) {
            for (id row in section.rows) {
                if (![row isKindOfClass:DKSettingsPage.class]) continue;
                if (![((DKSettingsPage *)row).identifier isEqualToString:identifier]) continue;
                found = row;
                break;
            }
            if (found) break;
        }
        if (!found) return nil;
        [path addObject:found];
        sections = found.sections;
    }
    return path;
}

@interface DKSearchIndex ()
@property (nonatomic, copy) NSArray<DKSearchEntry *> *entries;
@end

@implementation DKSearchIndex

+ (instancetype)indexForPage:(UIViewController *)page pagePath:(NSArray<NSString *> *)pagePath {
    DKSearchIndex *index = [[self alloc] init];
    NSArray<DKSettingsPage *> *specs = DKResolvePagePath(pagePath);
    // 只有布局表里的一级页（路径为空数组）才不区分本页；路径未知的运行时页面按子页处理。
    BOOL isMain = specs != nil && specs.count == 0;
    NSMutableArray<DKSearchEntry *> *entries = [NSMutableArray array];
    NSMutableDictionary<NSString *, DKSearchEntry *> *byIdentifier = [NSMutableDictionary dictionary];
    NSUInteger order = 0;
    for (DKSettingsSection *section in DKSettingsLayoutMain()) {
        order = DKCollectSections(@[ section ], @[], nil, entries, byIdentifier, order);
    }
    if (page) DKMergeCurrentPage(page, specs ?: @[], isMain, entries, byIdentifier);
    for (DKSearchEntry *entry in entries) {
        for (DKSettingsPage *ancestor in entry.pagePath) {
            if (!DKSettingsKeyIsLocked(ancestor.identifier)) continue;
            entry.lockReason = DKSettingsKeyLockReason(ancestor.identifier);
            break;
        }
    }
    index.entries = entries;
    return index;
}

- (NSArray<DKSearchEntry *> *)resultsForQuery:(NSString *)query {
    NSArray<NSString *> *tokens = DKSearchTokens(query);
    if (tokens.count == 0) return @[];
    NSMutableArray<DKSearchEntry *> *matched = [NSMutableArray array];
    NSMapTable<DKSearchEntry *, NSNumber *> *scores = [NSMapTable strongToStrongObjectsMapTable];   // 条目不可拷贝，不能当字典键
    for (DKSearchEntry *entry in self.entries) {
        CGFloat score = DKSearchScoreEntry(entry, tokens);
        if (score <= 0.0) continue;
        [scores setObject:@(score) forKey:entry];
        [matched addObject:entry];
    }
    [matched sortUsingComparator:^(DKSearchEntry *left, DKSearchEntry *right) {
        if (left.onCurrentPage != right.onCurrentPage) {
            return left.onCurrentPage ? NSOrderedAscending : NSOrderedDescending;
        }
        CGFloat leftScore = [scores objectForKey:left].doubleValue, rightScore = [scores objectForKey:right].doubleValue;
        if (fabs(leftScore - rightScore) > 0.001) {
            return leftScore > rightScore ? NSOrderedAscending : NSOrderedDescending;
        }
        if (left.layoutOrder != right.layoutOrder) {
            return left.layoutOrder < right.layoutOrder ? NSOrderedAscending : NSOrderedDescending;
        }
        return [left.title localizedStandardCompare:right.title];
    }];
    return matched;
}

@end
