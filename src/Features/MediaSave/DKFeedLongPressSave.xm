// 作品长按面板：按开关加入无水印保存项；与原生「保存至相册」重叠时移除原生项，插件项放在原生项的位置。
#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import "DKMediaResolver.h"
#import "DKMediaSaveDiagnostics.h"
#import "DKMediaSaveRuntime.h"
#import "DKMediaSaveTask.h"
#import "DKMediaSelect.h"
#import <objc/runtime.h>

// 原生「保存至相册」与「倍速」的 actionType；插件项用 7701 起的专用段。
static const unsigned long long DKNativeSaveAction = 121;
static const unsigned long long DKNativeSpeedAction = 31;
static const unsigned long long DKFeedActionBase = 7701;

typedef NS_ENUM(NSUInteger, DKFeedSaveKind) {
    DKFeedSaveMain,
    DKFeedSaveCurrent,
    DKFeedSaveAll,
    DKFeedSaveCover,
    DKFeedSaveMusic,
};

static NSArray<DKMediaSaveItem *> *DKFeedItems(id aweme, DKFeedSaveKind kind) {
    NSDictionary *dict = DKResolveAweme(aweme);
    DKMediaSaveItem *item = nil;
    switch (kind) {
        case DKFeedSaveCurrent: return DKSelectAlbumItems(dict, NO);
        case DKFeedSaveAll: return DKSelectAlbumItems(dict, YES);
        case DKFeedSaveMain: item = DKSelectAwemeMain(dict); break;
        case DKFeedSaveCover: item = DKSelectAwemeCover(dict); break;
        case DKFeedSaveMusic: item = DKSelectAwemeMusic(dict); break;
    }
    return item ? @[item] : @[];
}

// 先收起面板再开始保存；收起回调缺失时延时兜底，只执行一次。
static void DKFeedRun(id aweme, DKFeedSaveKind kind, NSString *source, UIWindowScene *scene) {
    __block BOOL started = NO;
    void (^run)(void) = ^{
        if (started) return;
        started = YES;
        DKMediaSaveRun(DKFeedItems(aweme, kind), source, scene);
    };
    Class managerClass = NSClassFromString(@"AWELongPressPanelManager");
    AWELongPressPanelManager *manager = [managerClass respondsToSelector:@selector(shareInstance)] ? [managerClass shareInstance] : nil;
    if ([manager respondsToSelector:@selector(dismissWithAnimation:completion:)]) {
        [manager dismissWithAnimation:YES completion:^{ dispatch_async(dispatch_get_main_queue(), run); }];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), run);
}

static AWELongPressPanelBaseViewModel *DKFeedViewModel(id aweme, NSString *title, unsigned long long action, DKFeedSaveKind kind, UIViewController *panel) {
    Class cls = NSClassFromString(@"AWELongPressPanelBaseViewModel");
    if (!cls) return nil;
    AWELongPressPanelBaseViewModel *model = [cls new];
    model.awemeModel = aweme;
    model.actionType = action;
    model.duxIconName = @"ic_boxarrowdownhigh_outlined";
    model.describeString = title;
    NSString *source = [@"长按面板·" stringByAppendingString:title];
    __weak UIViewController *weakPanel = panel;
    model.action = ^{ DKFeedRun(aweme, kind, source, DKPromptSceneForResponder(weakPanel)); };
    return model;
}

static AWELongPressPanelViewGroupModel *DKFeedGroup(id source, NSArray *items) {
    Class cls = NSClassFromString(@"AWELongPressPanelViewGroupModel");
    if (!cls) return nil;
    AWELongPressPanelViewGroupModel *group = [cls new];
    if ([source isKindOfClass:cls]) {
        AWELongPressPanelViewGroupModel *original = source;
        group.groupType = original.groupType;
        group.isModern = original.isModern;
        group.cellHeight = original.cellHeight;
        group.hasMore = original.hasMore;
        // 原生行数跟随条目数时同步新条目数，否则保持原值。
        long long rows = original.numberOfRowsInSection;
        group.numberOfRowsInSection = rows == (long long)original.groupArr.count ? (long long)items.count : rows;
    }
    group.groupArr = items;
    return group;
}

static unsigned long long DKFeedActionType(id item) {
    id value = DKMediaValue(item, @"actionType");
    return [value respondsToSelector:@selector(unsignedLongLongValue)] ? [value unsignedLongLongValue] : 0;
}

static NSArray *DKFeedMerge(NSArray *groups, NSArray *added, BOOL removeNative) {
    NSInteger nativeGroup = -1, nativeIndex = -1, speedGroup = -1;
    for (NSUInteger g = 0; g < groups.count; g++) {
        NSArray *items = DKMediaValue(groups[g], @"groupArr");
        if (![items isKindOfClass:NSArray.class]) continue;
        for (NSUInteger i = 0; i < items.count; i++) {
            unsigned long long type = DKFeedActionType(items[i]);
            if (type == DKNativeSaveAction && nativeGroup < 0) { nativeGroup = g; nativeIndex = i; }
            if (type == DKNativeSpeedAction && speedGroup < 0) speedGroup = g;
        }
    }
    NSMutableArray *out = [groups mutableCopy];
    if (nativeGroup >= 0) {
        NSMutableArray *items = [DKMediaValue(groups[nativeGroup], @"groupArr") mutableCopy];
        if (removeNative) [items removeObjectAtIndex:nativeIndex];
        NSUInteger at = removeNative ? nativeIndex : nativeIndex + 1;
        [items insertObjects:added atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(at, added.count)]];
        id group = DKFeedGroup(groups[nativeGroup], items);
        if (group) out[nativeGroup] = group;
    } else if (speedGroup >= 0) {
        NSMutableArray *items = [DKMediaValue(groups[speedGroup], @"groupArr") mutableCopy];
        [items addObjectsFromArray:added];
        id group = DKFeedGroup(groups[speedGroup], items);
        if (group) out[speedGroup] = group;
    } else {
        id last = groups.lastObject;
        NSArray *lastItems = DKMediaValue(last, @"groupArr");
        id group = DKFeedGroup(last, added);
        // 末组是空分组（作品长按菜单的原生项全部移除后留下的）时填入这一组，否则另起一组。
        if (group && [lastItems isKindOfClass:NSArray.class] && lastItems.count == 0) out[out.count - 1] = group;
        else if (group) [out addObject:group];
    }
    return out;
}

static char kDKFeedPanelCacheKey;

static NSArray *DKFeedPanelData(UIViewController *panel, NSArray *original, DKMediaSaveEntry entry) {
    BOOL video = DKPrefBool(DKKeyMediaSaveVideo), current = DKPrefBool(DKKeyMediaSaveCurrentImage);
    BOOL all = DKPrefBool(DKKeyMediaSaveAllImages), cover = DKPrefBool(DKKeyMediaSaveCover), music = DKPrefBool(DKKeyMediaSaveMusic);
    if (!(video || current || all || cover || music) || ![original isKindOfClass:NSArray.class]) return original;
    id aweme = DKMediaValue(panel, @"awemeModel");
    if (![aweme isKindOfClass:NSClassFromString(@"AWEAwemeModel")]) return original;

    // 同一面板、同一作品、同一组开关与当前项时复用已建的插件项。
    NSUInteger mask = video | current << 1 | all << 2 | cover << 3 | music << 4;
    NSString *signature = [NSString stringWithFormat:@"%p|%lu|%@", aweme, (unsigned long)mask, DKMediaValue(aweme, @"currentImageIndex")];
    NSDictionary *cache = objc_getAssociatedObject(panel, &kDKFeedPanelCacheKey);
    if ([cache[@"signature"] isEqualToString:signature]) {
        NSArray *cached = cache[@"added"];
        return cached.count ? DKFeedMerge(original, cached, [cache[@"remove"] boolValue]) : original;
    }
    DKMediaSaveHit(entry);

    NSDictionary *dict = DKResolveAweme(aweme);
    BOOL album = DKSelectAwemeIsAlbum(dict);
    NSMutableArray *added = [NSMutableArray array];
    BOOL removeNative = NO;
    void (^add)(NSString *, NSUInteger, DKFeedSaveKind) = ^(NSString *title, NSUInteger offset, DKFeedSaveKind kind) {
        AWELongPressPanelBaseViewModel *model = DKFeedViewModel(aweme, title, DKFeedActionBase + offset, kind, panel);
        if (model) [added addObject:model];
    };
    if (!album && video && DKSelectAwemeMain(dict)) { add(DKSelectMainTitle(dict), 0, DKFeedSaveMain); removeNative = YES; }
    if (album && current && DKSelectAlbumItems(dict, NO).count) { add(DKSelectAlbumCurrentTitle(dict), 1, DKFeedSaveCurrent); removeNative = YES; }
    if (album && all && [dict[@"images"] count] > 1) add(DKSelectAlbumAllTitle(dict), 2, DKFeedSaveAll);
    if (!album && cover && DKSelectAwemeCover(dict)) add(@"保存封面", 3, DKFeedSaveCover);
    if (music && DKSelectAwemeMusic(dict)) add(@"保存音乐", 4, DKFeedSaveMusic);
    objc_setAssociatedObject(panel, &kDKFeedPanelCacheKey, @{@"signature": signature, @"added": [added copy], @"remove": @(removeNative)},
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return added.count ? DKFeedMerge(original, added, removeNative) : original;
}

%group DKFeedPanelHooks
%hook AWELongPressPanelTableViewController
- (NSArray *)dataArray {
    NSArray *original = %orig;
    return DKFeedPanelData(self, original, DKMediaSaveEntryFeedPanel);
}
%end
%end

%group DKFeedModernPanelHooks
%hook AWEModernLongPressPanelTableViewController
- (NSArray *)dataArray {
    NSArray *original = %orig;
    return DKFeedPanelData(self, original, DKMediaSaveEntryFeedPanelModern);
}
%end
%end

%ctor {
    DKSettingsRegister(DKKeyMediaSaveVideo, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyMediaSaveVideo, @"保存视频",
                            @"长按视频出现「保存视频」，保存无水印的高清播放源（HEVC 或 H.264）；视频形式的实况存为实况。开启后移除原生「保存至相册」，作者禁止下载的作品同样可保存。");
    });
    DKSettingsRegister(DKKeyMediaSaveCurrentImage, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyMediaSaveCurrentImage, @"保存当前图片",
                            @"长按图文出现「保存当前图片」，保存正在看的这一项：图片存原图，实况存为实况，混排视频存为视频，均无水印。开启后移除原生「保存至相册」。");
    });
    DKSettingsRegister(DKKeyMediaSaveAllImages, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyMediaSaveAllImages, @"保存全部图片", @"长按多图图文出现「保存全部」，按顺序保存全部图片、实况与视频。");
    });
    DKSettingsRegister(DKKeyMediaSaveCover, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyMediaSaveCover, @"保存封面", @"长按视频出现「保存封面」，保存视频封面图。");
    });
    DKSettingsRegister(DKKeyMediaSaveMusic, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyMediaSaveMusic, @"保存音乐", @"长按作品出现「保存音乐」，下载背景音乐后用系统分享面板存到文件或发送。");
    });

    Class panel = NSClassFromString(@"AWELongPressPanelTableViewController");
    BOOL installed = DKMediaMethod(panel, @selector(dataArray), "@") && NSClassFromString(@"AWELongPressPanelBaseViewModel");
    if (installed) %init(DKFeedPanelHooks);
    DKMediaSaveInstalled(DKMediaSaveEntryFeedPanel, installed);
    Class modern = NSClassFromString(@"AWEModernLongPressPanelTableViewController");
    BOOL modernInstalled = DKMediaMethod(modern, @selector(dataArray), "@") && ![modern isSubclassOfClass:panel];
    if (modernInstalled) %init(DKFeedModernPanelHooks);
    DKMediaSaveInstalled(DKMediaSaveEntryFeedPanelModern, modernInstalled);
}
