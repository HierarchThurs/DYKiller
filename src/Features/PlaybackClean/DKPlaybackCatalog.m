// 播放页类型目录：稳定身份、首次原文、用户改名与独立档位。
// 标题解析顺序固定为「用户改名 → 旧设置语义名 → 首次原文」，三者都取不到的身份不登记。
#import "DKPlaybackCatalog.h"
#import "DKPlaybackCleanRules.h"
#import "DKElementRowHiding.h"
#import "DouyinHeaders.h"
#import "DKKeys.h"
#import <objc/runtime.h>

@interface DKPlaybackRowType : NSObject
@property (nonatomic, weak) id element;
@property (nonatomic, weak) id data;
@property (nonatomic) DKPlaybackCatalogKind kind;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *legacy;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *rawTitle;
@property (nonatomic) NSUInteger group;
@property (nonatomic) BOOL recorded;
@end
@implementation DKPlaybackRowType
@end

// 栈级分类缓存：记住判定过的控制器，容器身份变化时重算。
@interface DKPlaybackStackKind : NSObject
@property (nonatomic, weak) UIViewController *controller;
@property (nonatomic) BOOL bottom;
@end
@implementation DKPlaybackStackKind
@end

static char kDKPlaybackRowTypeKey;
static char kDKPlaybackRowKindKey;
static char kDKPlaybackStackKindKey;

static const NSUInteger kDKPlaybackCatalogLimit = 512;
static const NSUInteger kDKPlaybackTitleMaxLength = 24;
static const NSUInteger kDKPlaybackRejectedLimit = 32;

static NSMutableArray<NSDictionary *> *gCatalogs[2];
static NSMutableDictionary<NSString *, NSDictionary *> *gIndexes[2];
static NSMutableDictionary<NSString *, NSDictionary *> *gLegacyIndexes[2];
static NSMutableArray<NSDictionary *> *gRejected[2];

static void DKCatalogLoad(DKPlaybackCatalogKind kind);

static id DKCatalogValue(id object, NSString *key) {
    if (!object) return nil;
    @try { return [object valueForKey:key]; }
    @catch (__unused NSException *exception) { return nil; }
}

static NSString *DKCatalogString(id object, NSString *key) {
    id value = DKCatalogValue(object, key);
    return [value isKindOfClass:NSString.class]
        ? [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
}

// 模板底栏的业务名分散在 name / title.text / mainContent.text 三处，需按顺序尝试。
static NSString *DKCatalogDeepString(id object, NSArray<NSString *> *path) {
    id current = object;
    for (NSString *key in path) {
        current = DKCatalogValue(current, key);
        if (!current) return nil;
    }
    return [current isKindOfClass:NSString.class]
        ? [current stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
}

#pragma mark - 键

NSString *DKPlaybackCatalogMasterKey(DKPlaybackCatalogKind kind) {
    return kind == DKPlaybackCatalogAnchors ? DKKeyPlaybackAllAnchorsMode : DKKeyPlaybackAllBottomBarsMode;
}

NSString *DKPlaybackCatalogPageKey(DKPlaybackCatalogKind kind) {
    return kind == DKPlaybackCatalogAnchors ? DKKeyPlaybackAnchorsPage : DKKeyPlaybackBottomBarsPage;
}

NSString *DKPlaybackCatalogRenamePageKey(DKPlaybackCatalogKind kind) {
    return kind == DKPlaybackCatalogAnchors ? DKKeyPlaybackAnchorRenamePage : DKKeyPlaybackBottomBarRenamePage;
}

NSString *DKPlaybackCatalogModePrefix(DKPlaybackCatalogKind kind) {
    return kind == DKPlaybackCatalogAnchors ? DKKeyPlaybackAnchorModePrefix : DKKeyPlaybackBottomBarModePrefix;
}

NSString *DKPlaybackCatalogNamePrefix(DKPlaybackCatalogKind kind) {
    return kind == DKPlaybackCatalogAnchors ? DKKeyPlaybackAnchorNamePrefix : DKKeyPlaybackBottomBarNamePrefix;
}

NSString *DKPlaybackCatalogStorageKey(DKPlaybackCatalogKind kind) {
    return kind == DKPlaybackCatalogAnchors ? DKKeyPlaybackAnchorCatalog : DKKeyPlaybackBottomBarCatalog;
}

static NSString *DKCatalogEncodedID(NSString *identifier) {
    static NSCharacterSet *allowed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        allowed = [NSCharacterSet characterSetWithCharactersInString:
            @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"];
    });
    return [identifier stringByAddingPercentEncodingWithAllowedCharacters:allowed];
}

NSString *DKPlaybackCatalogModeKey(DKPlaybackCatalogKind kind, NSString *identifier) {
    if (!identifier.length) return nil;
    DKCatalogLoad(kind);
    NSString *legacy = gIndexes[kind][identifier][@"legacy"];
    if (legacy.length) return legacy;
    return [DKPlaybackCatalogModePrefix(kind) stringByAppendingString:DKCatalogEncodedID(identifier) ?: @""];
}

NSArray<NSString *> *DKPlaybackCatalogLegacyKeys(DKPlaybackCatalogKind kind) {
    if (kind == DKPlaybackCatalogAnchors) return @[
        DKKeyPlaybackGameTagMode, DKKeyPlaybackMusicAnchorMode, DKKeyPlaybackPropEffectMode,
        DKKeyPlaybackJianyingMode, DKKeyPlaybackPaidContentMode, DKKeyPlaybackLocationMode,
    ];
    return @[ DKKeyPlaybackRelatedSearchMode, DKKeyPlaybackRelatedVideoMode,
        DKKeyPlaybackVideoCollectionMode, DKKeyPlaybackHotspotMode, DKKeyPlaybackAppDownloadMode ];
}

NSString *DKPlaybackCatalogLegacyTitle(NSString *key) {
    static NSDictionary *titles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        titles = @{ DKKeyPlaybackGameTagMode: @"游戏标签", DKKeyPlaybackMusicAnchorMode: @"汽水音乐",
            DKKeyPlaybackPropEffectMode: @"拍同款", DKKeyPlaybackJianyingMode: @"剪映标签",
            DKKeyPlaybackPaidContentMode: @"付费内容", DKKeyPlaybackLocationMode: @"地理定位",
            DKKeyPlaybackRelatedSearchMode: @"相关搜索", DKKeyPlaybackRelatedVideoMode: @"相关视频",
            DKKeyPlaybackVideoCollectionMode: @"视频合集", DKKeyPlaybackHotspotMode: @"热点",
            DKKeyPlaybackAppDownloadMode: @"应用下载引导" };
    });
    return key ? titles[key] : nil;
}

#pragma mark - 分组

NSArray<NSDictionary *> *DKPlaybackCatalogGroups(DKPlaybackCatalogKind kind) {
    static NSArray *anchors, *bottom;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        anchors = @[
            @{ @"group": @(DKPlaybackCatalogGroupLabel), @"title": @"抖音标签", @"icon": @"ic_tag_outlined_20" },
            @{ @"group": @(DKPlaybackCatalogGroupCard), @"title": @"广告卡片", @"icon": @"ic_ad_outlined_20" },
        ];
        bottom = @[ @{ @"group": @0, @"title": @"", @"icon": @"ic_collection_outlined_20" } ];
    });
    return kind == DKPlaybackCatalogAnchors ? anchors : bottom;
}

NSUInteger DKPlaybackCatalogGroupOf(NSDictionary *entry) {
    id group = [entry isKindOfClass:NSDictionary.class] ? entry[@"group"] : nil;
    return [group isKindOfClass:NSNumber.class] ? [group unsignedIntegerValue] : 0;
}

static NSUInteger DKCatalogValidGroup(DKPlaybackCatalogKind kind, NSUInteger group) {
    return group < DKPlaybackCatalogGroups(kind).count ? group : 0;
}

// 昵称上方的非锚点卡片：按元素类识别，身份用类名、名称用固定语义名。
static NSDictionary *DKCatalogCardTypeForElement(id element) {
    static NSArray<NSDictionary *> *types;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        types = @[ @{ @"class": @"AWEPlayInteractionLearnMoreLynxTopElement", @"name": @"推广卡片" } ];
    });
    for (NSDictionary *type in types) {
        Class cls = NSClassFromString(type[@"class"]);
        if (cls && [element isKindOfClass:cls]) return type;
    }
    return nil;
}

#pragma mark - 目录

static NSString *DKCatalogStringField(id entry, NSString *field) {
    id value = [entry isKindOfClass:NSDictionary.class] ? entry[field] : nil;
    return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}

static void DKCatalogLoad(DKPlaybackCatalogKind kind) {
    if (gCatalogs[kind]) return;
    gCatalogs[kind] = [NSMutableArray array];
    gIndexes[kind] = [NSMutableDictionary dictionary];
    gLegacyIndexes[kind] = [NSMutableDictionary dictionary];
    gRejected[kind] = [NSMutableArray array];
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:DKPlaybackCatalogStorageKey(kind)];
    if (![stored isKindOfClass:NSArray.class]) return;
    NSArray *legacyKeys = DKPlaybackCatalogLegacyKeys(kind);
    for (id entry in stored) {
        if (gCatalogs[kind].count >= kDKPlaybackCatalogLimit) break;
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        NSString *identifier = DKCatalogStringField(entry, @"id");
        NSString *raw = DKCatalogStringField(entry, @"raw") ?: DKCatalogStringField(entry, @"title");
        NSString *legacy = DKCatalogStringField(entry, @"legacy");
        if (!identifier.length || DKCatalogEncodedID(identifier).length > 128) continue;
        if (!raw.length && !legacy.length) continue;
        if (gIndexes[kind][identifier]) continue;
        NSUInteger group = DKCatalogValidGroup(kind, [entry[@"group"] unsignedIntegerValue]);
        NSMutableDictionary *clean = [@{ @"id": identifier, @"group": @(group) } mutableCopy];
        if (raw.length) clean[@"raw"] = raw;
        if ([legacyKeys containsObject:legacy]) {
            clean[@"legacy"] = legacy;
            if (!gLegacyIndexes[kind][legacy]) gLegacyIndexes[kind][legacy] = clean;
        }
        [gCatalogs[kind] addObject:clean];
        gIndexes[kind][identifier] = clean;
    }
}

NSArray<NSDictionary *> *DKPlaybackCatalogEntries(DKPlaybackCatalogKind kind) {
    DKCatalogLoad(kind);
    return [gCatalogs[kind] copy];
}

static void DKCatalogStore(DKPlaybackCatalogKind kind) {
    [NSUserDefaults.standardUserDefaults setObject:[gCatalogs[kind] copy] forKey:DKPlaybackCatalogStorageKey(kind)];
}

// 未登记原因只留最近的若干条，避免诊断无限增长。
static void DKCatalogReject(DKPlaybackCatalogKind kind, NSString *identifier, NSString *reason) {
    DKCatalogLoad(kind);
    for (NSDictionary *entry in gRejected[kind]) {
        if ([entry[@"id"] isEqual:identifier]) return;
    }
    if (gRejected[kind].count >= kDKPlaybackRejectedLimit) [gRejected[kind] removeObjectAtIndex:0];
    [gRejected[kind] addObject:@{ @"id": identifier ?: @"?", @"reason": reason ?: @"?" }];
}

#pragma mark - 名称

NSString *DKPlaybackCatalogNameKey(DKPlaybackCatalogKind kind, NSString *identifier) {
    if (!identifier.length) return nil;
    return [DKPlaybackCatalogNamePrefix(kind) stringByAppendingString:DKCatalogEncodedID(identifier) ?: @""];
}

NSString *DKPlaybackCatalogCustomName(DKPlaybackCatalogKind kind, NSString *identifier) {
    NSString *key = DKPlaybackCatalogNameKey(kind, identifier);
    if (!key.length) return nil;
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *text = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return text.length ? text : nil;
}

void DKPlaybackCatalogSetCustomName(DKPlaybackCatalogKind kind, NSString *identifier, NSString *name) {
    NSString *key = DKPlaybackCatalogNameKey(kind, identifier);
    if (!key.length) return;
    NSString *text = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!text.length) [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
    else [NSUserDefaults.standardUserDefaults setObject:text forKey:key];
}

NSString *DKPlaybackCatalogTitle(DKPlaybackCatalogKind kind, NSDictionary *entry) {
    NSString *identifier = DKCatalogStringField(entry, @"id");
    if (!identifier.length) return nil;
    NSString *custom = DKPlaybackCatalogCustomName(kind, identifier);
    if (custom.length) return custom;
    NSString *legacy = DKPlaybackCatalogLegacyTitle(DKCatalogStringField(entry, @"legacy"));
    if (legacy.length) return legacy;
    return DKCatalogStringField(entry, @"raw");
}

/// 首次原文：标题为空或只是泛化类型词、以及与他人重名时补上描述文案，截断到不会撑破设置行。
static NSString *DKCatalogComposeRaw(NSString *title, NSString *desc, NSString *identifier, DKPlaybackCatalogKind kind) {
    static NSSet<NSString *> *generic;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        generic = [NSSet setWithArray:@[ @"视频", @"图文", @"直播", @"文章", @"长文章", @"音频", @"合集",
            @"热点", @"相关搜索", @"相关视频" ]];
    });
    DKCatalogLoad(kind);
    BOOL duplicated = NO;
    for (NSDictionary *entry in gCatalogs[kind]) {
        if ([entry[@"id"] isEqual:identifier]) continue;
        if ([DKCatalogStringField(entry, @"raw") isEqual:title]) duplicated = YES;
    }
    NSString *text = title;
    if (!text.length) text = desc;
    else if ((duplicated || [generic containsObject:text]) && desc.length && ![desc isEqualToString:text]) {
        text = [text stringByAppendingFormat:@"｜%@", desc];
    }
    if (text.length > kDKPlaybackTitleMaxLength) {
        text = [[text substringToIndex:kDKPlaybackTitleMaxLength] stringByAppendingString:@"…"];
    }
    return text.length ? text : nil;
}

#pragma mark - 行身份

static UIView *DKCatalogAnchorIn(UIView *view, NSUInteger depth) {
    if ([view isKindOfClass:NSClassFromString(@"AWEFeedTemplateAnchorViewV2")]) return view;
    if (!depth) return nil;
    for (UIView *child in view.subviews) {
        UIView *found = DKCatalogAnchorIn(child, depth - 1);
        if (found) return found;
    }
    return nil;
}

// 栈级缓存：命中正向时只比对容器身份，命中负向时只确认控制器仍拥有该栈，都不再沿响应链找控制器。
BOOL DKPlaybackCatalogStackIsBottom(UIView *stack) {
    if (![stack isKindOfClass:NSClassFromString(@"AWEElementStackView")]) return NO;
    DKPlaybackStackKind *cached = objc_getAssociatedObject(stack, &kDKPlaybackStackKindKey);
    AWEPlayInteractionViewController *controller = (id)cached.controller;
    if (cached && controller) {
        if (cached.bottom) {
            if (controller.bottomContainerView == stack) return YES;
        } else if ([stack isDescendantOfView:controller.viewIfLoaded]) {
            return NO;
        }
    }
    controller = (id)DKPlayInteractionControllerForView(stack);
    DKPlaybackStackKind *kind = [DKPlaybackStackKind new];
    kind.controller = controller;
    kind.bottom = controller && controller.bottomContainerView == stack;
    objc_setAssociatedObject(stack, &kDKPlaybackStackKindKey, kind, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return kind.bottom;
}

static BOOL DKCatalogKindForRow(UIView *row, DKPlaybackCatalogKind *kind) {
    if (!DKCleanRowElement(row)) return NO;
    NSNumber *cached = objc_getAssociatedObject(row, &kDKPlaybackRowKindKey);
    if (cached) {
        *kind = (DKPlaybackCatalogKind)(cached.unsignedIntegerValue - 1);
        return YES;
    }
    DKPlaybackCatalogKind found;
    if (DKCleanIsAnchorRow(row) || DKCatalogCardTypeForElement(DKCleanRowElement(row))) {
        found = DKPlaybackCatalogAnchors;
    } else if (DKPlaybackCatalogStackIsBottom(row.superview)) {
        found = DKPlaybackCatalogBottomBars;
    } else {
        return NO;
    }
    objc_setAssociatedObject(row, &kDKPlaybackRowKindKey, @(found + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    *kind = found;
    return YES;
}

static NSString *DKCatalogBottomIdentifier(id element) {
    NSString *identifier = DKCatalogString(element, @"identifier");
    if (identifier.length) return identifier;
    return element ? NSStringFromClass([element class]) : nil;
}

static NSString *DKCatalogAnchorRawTitle(id info, NSString *identifier) {
    NSString *title = DKCatalogDeepString(info, @[ @"titleModel", @"content" ]);
    NSString *desc = DKCatalogDeepString(info, @[ @"descModel", @"content" ]);
    return DKCatalogComposeRaw(title, desc, identifier, DKPlaybackCatalogAnchors);
}

static NSString *DKCatalogBottomRawTitle(id element, NSString *identifier) {
    if (![element isKindOfClass:NSClassFromString(@"AWETemplateNewBottomElement")]) return nil;
    id manager = DKCatalogValue(element, @"providerManager");
    id provider = DKCatalogValue(manager, @"currentProvider");
    id bar = DKCatalogValue(provider, @"barModel");
    NSString *title = DKCatalogString(bar, @"name");
    if (!title.length) title = DKCatalogDeepString(bar, @[ @"title", @"text" ]);
    NSString *desc = DKCatalogDeepString(bar, @[ @"mainContent", @"text" ]);
    return DKCatalogComposeRaw(title, desc, identifier, DKPlaybackCatalogBottomBars);
}

// 行随作品复用；数据对象改变或内容更新 Hook 到达时重建一次身份信息。
static DKPlaybackRowType *DKCatalogTypeForRow(UIView *row, DKPlaybackCatalogKind kind) {
    id element = DKCleanRowElement(row);
    id data = DKCatalogValue(element, @"data");
    DKPlaybackRowType *cached = objc_getAssociatedObject(row, &kDKPlaybackRowTypeKey);
    if (cached && cached.kind == kind && cached.element == element && cached.data == data) return cached;

    NSString *identifier = nil, *rawTitle = nil;
    NSUInteger group = DKPlaybackCatalogGroupLabel;
    if (kind == DKPlaybackCatalogAnchors) {
        NSDictionary *card = DKCatalogCardTypeForElement(element);
        if (card) {
            identifier = NSStringFromClass([element class]);
            rawTitle = DKCatalogComposeRaw(card[@"name"], nil, identifier, kind);
            group = DKPlaybackCatalogGroupCard;
        }
    }
    if (kind == DKPlaybackCatalogAnchors && !identifier.length) {
        id info = DKCatalogValue(DKCatalogAnchorIn(row, 4), @"templateAnchorInfo");
        NSString *name = DKCatalogString(info, @"name");
        if (!name.length) return nil;
        identifier = name;
        rawTitle = DKCatalogAnchorRawTitle(info, identifier);
        if ([name isEqualToString:@"openplatform_anchor"]) {
            NSData *bytes = [DKCatalogString(info, @"extra") dataUsingEncoding:NSUTF8StringEncoding];
            id extra = bytes ? [NSJSONSerialization JSONObjectWithData:bytes options:0 error:NULL] : nil;
            id base = [extra isKindOfClass:NSDictionary.class] ? extra[@"base"] : nil;
            NSString *client = DKCatalogString(base, @"client_key");
            if (!client.length) {
                DKCatalogReject(kind, name, @"开放平台锚点缺少 client_key");
                return nil;
            }
            identifier = [name stringByAppendingFormat:@":%@", client];
            NSString *app = DKCatalogString(base, @"app_name");
            rawTitle = app.length ? DKCatalogComposeRaw(app, nil, identifier, kind)
                                  : DKCatalogAnchorRawTitle(info, identifier);
        }
    } else if (kind == DKPlaybackCatalogBottomBars) {
        identifier = DKCatalogBottomIdentifier(element);
        rawTitle = DKCatalogBottomRawTitle(element, identifier);
    }
    if (!identifier.length || DKCatalogEncodedID(identifier).length > 128) return nil;

    NSString *legacy = DKCleanKeyForRow(row);
    DKPlaybackRowType *type = [DKPlaybackRowType new];
    type.element = element;
    type.data = data;
    type.kind = kind;
    type.identifier = identifier;
    type.legacy = legacy;
    type.key = legacy.length ? legacy : [DKPlaybackCatalogModePrefix(kind) stringByAppendingString:DKCatalogEncodedID(identifier)];
    type.rawTitle = rawTitle;
    type.group = DKCatalogValidGroup(kind, group);
    objc_setAssociatedObject(row, &kDKPlaybackRowTypeKey, type, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return type;
}

#pragma mark - 档位

DKDisplayMode DKPlaybackCatalogItemMode(DKPlaybackCatalogKind kind, NSString *identifier) {
    return DKPrefDisplayMode(DKPlaybackCatalogModeKey(kind, identifier));
}

BOOL DKPlaybackCatalogRowMode(UIView *row, DKDisplayMode *mode) {
    DKPlaybackCatalogKind kind;
    if (!DKCatalogKindForRow(row, &kind)) return NO;
    *mode = DKPrefDisplayMode(DKPlaybackCatalogMasterKey(kind));
    if (*mode != DKDisplayModeShow) return YES;
    DKPlaybackRowType *type = DKCatalogTypeForRow(row, kind);
    *mode = type ? DKPrefDisplayMode(type.key) : DKDisplayModeShow;
    return YES;
}

#pragma mark - 登记

void DKPlaybackCatalogRecordRow(UIView *row) {
    DKPlaybackCatalogKind kind;
    if (!row.window || !DKCatalogKindForRow(row, &kind)
        || DKPrefDisplayMode(DKPlaybackCatalogMasterKey(kind)) != DKDisplayModeShow) return;
    DKPlaybackRowType *type = DKCatalogTypeForRow(row, kind);
    if (!type || type.recorded) return;
    DKCatalogLoad(kind);
    if (gIndexes[kind][type.identifier]) { type.recorded = YES; return; }
    // 同一旧设置键只列一项：拍同款、视频合集这类合并类型不重复登记。
    if (type.legacy.length && gLegacyIndexes[kind][type.legacy]) {
        gIndexes[kind][type.identifier] = gLegacyIndexes[kind][type.legacy];
        type.recorded = YES;
        return;
    }
    if (!type.rawTitle.length && !DKPlaybackCatalogLegacyTitle(type.legacy)) {
        DKCatalogReject(kind, type.identifier, @"没有可用名称");
        type.recorded = YES;
        return;
    }
    AWEPlayInteractionViewController *controller = (id)DKPlayInteractionControllerForView(row);
    if (!controller.isDisplaying || controller.isPreload || DKElementRowHostHidden(row)) return;
    UIView *root = controller.viewIfLoaded;
    if (root.hidden || root.alpha < 0.01
        || !CGRectIntersectsRect([root convertRect:root.bounds toView:row.window], row.window.bounds)) return;
    if (gCatalogs[kind].count >= kDKPlaybackCatalogLimit) return;

    NSMutableDictionary *entry = [@{ @"id": type.identifier, @"group": @(type.group) } mutableCopy];
    if (type.rawTitle.length) entry[@"raw"] = type.rawTitle;
    if (type.legacy.length) {
        entry[@"legacy"] = type.legacy;
        if (!gLegacyIndexes[kind][type.legacy]) gLegacyIndexes[kind][type.legacy] = entry;
    }
    [gCatalogs[kind] addObject:entry];
    gIndexes[kind][type.identifier] = entry;
    type.recorded = YES;
    DKCatalogStore(kind);
}

void DKPlaybackCatalogRecordController(UIViewController *controller) {
    for (NSString *name in @[ @"leftContainerView", @"bottomContainerView" ]) {
        id stack = DKCatalogValue(controller, name);
        if (![stack isKindOfClass:UIStackView.class]) continue;
        for (UIView *row in ((UIStackView *)stack).arrangedSubviews) DKPlaybackCatalogRecordRow(row);
    }
}

#pragma mark - 诊断

NSString *DKPlaybackCatalogStatus(void) {
    NSMutableString *text = [NSMutableString string];
    for (NSUInteger kind = 0; kind < 2; kind++) {
        DKCatalogLoad((DKPlaybackCatalogKind)kind);
        [text appendFormat:@"%@：统一档位=%ld 目录=%lu\n", kind == DKPlaybackCatalogAnchors ? @"昵称上方标签" : @"底部相关栏目",
            (long)DKPrefDisplayMode(DKPlaybackCatalogMasterKey((DKPlaybackCatalogKind)kind)), (unsigned long)gCatalogs[kind].count];
        NSArray<NSDictionary *> *groups = DKPlaybackCatalogGroups((DKPlaybackCatalogKind)kind);
        for (NSDictionary *entry in gCatalogs[kind]) {
            NSString *identifier = entry[@"id"];
            NSUInteger group = DKPlaybackCatalogGroupOf(entry);
            NSString *groupTitle = group < groups.count ? groups[group][@"title"] : @"";
            if (![groupTitle isKindOfClass:NSString.class] || !groupTitle.length) groupTitle = @"未分组";
            [text appendFormat:@"  [%@] %@ %@ 档位=%ld%@\n", groupTitle, identifier,
                DKPlaybackCatalogTitle((DKPlaybackCatalogKind)kind, entry) ?: @"（无名称）",
                (long)DKPrefDisplayMode(DKPlaybackCatalogModeKey((DKPlaybackCatalogKind)kind, identifier)),
                DKPlaybackCatalogCustomName((DKPlaybackCatalogKind)kind, identifier) ? @" 已改名" : @""];
        }
        for (NSDictionary *entry in gRejected[kind]) {
            [text appendFormat:@"  未入列 %@：%@\n", entry[@"id"], entry[@"reason"]];
        }
    }
    return text;
}
