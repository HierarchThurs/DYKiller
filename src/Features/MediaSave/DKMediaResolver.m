#import "DKMediaResolver.h"

id DKMediaValue(id object, NSString *key) {
    if (!object || !key.length) return nil;
    @try {
        id value = [object valueForKey:key];
        return value == NSNull.null ? nil : value;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSArray<NSString *> *DKStrings(id value) {
    if (![value isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (id item in value) if ([item isKindOfClass:NSString.class] && [item length]) [out addObject:item];
    return out;
}

static NSDictionary *DKURLModel(id model) {
    if (!model) return nil;
    NSArray<NSString *> *urls = DKStrings(DKMediaValue(model, @"originURLList"));
    if (!urls.count) return nil;
    NSMutableDictionary *dict = [@{@"urls": urls} mutableCopy];
    id key = DKMediaValue(model, @"URLKey");
    if ([key isKindOfClass:NSString.class]) dict[@"key"] = key;
    id width = DKMediaValue(model, @"imageWidth"), height = DKMediaValue(model, @"imageHeight");
    if ([width isKindOfClass:NSNumber.class]) dict[@"w"] = width;
    if ([height isKindOfClass:NSNumber.class]) dict[@"h"] = height;
    return dict;
}

static NSDictionary *DKVideo(id video) {
    if (!video) return nil;
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    NSMutableArray *gears = [NSMutableArray array];
    id models = DKMediaValue(video, @"bitrateModels");
    for (id model in [models isKindOfClass:NSArray.class] ? models : @[]) {
        NSDictionary *addr = DKURLModel(DKMediaValue(model, @"playAddr"));
        if (!addr) continue;
        NSMutableDictionary *gear = [@{@"addr": addr} mutableCopy];
        id codec = DKMediaValue(model, @"isH265"), bitrate = DKMediaValue(model, @"bitrate"), name = DKMediaValue(model, @"gearName");
        if (codec) gear[@"codec"] = codec;
        if (bitrate) gear[@"bitrate"] = bitrate;
        if ([name isKindOfClass:NSString.class]) gear[@"gear"] = name;
        [gears addObject:gear];
    }
    dict[@"bitrates"] = gears;
    NSDictionary *h264 = DKURLModel(DKMediaValue(video, @"h264URL"));
    NSDictionary *play = DKURLModel(DKMediaValue(video, @"playURL"));
    NSDictionary *cover = DKURLModel(DKMediaValue(video, @"coverURL"));
    if (h264) dict[@"h264"] = h264;
    if (play) dict[@"play"] = play;
    if (cover) dict[@"cover"] = cover;
    return dict;
}

NSDictionary *DKResolveAweme(id aweme) {
    if (!aweme) return @{};
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    id type = DKMediaValue(aweme, @"awemeType"), index = DKMediaValue(aweme, @"currentImageIndex");
    if (type) dict[@"type"] = type;
    if (index) dict[@"currentIndex"] = index;
    dict[@"animated"] = @(DKMediaValue(aweme, @"animatedImageVideoInfo") != nil);
    NSDictionary *video = DKVideo(DKMediaValue(aweme, @"video"));
    if (video) dict[@"video"] = video;
    NSDictionary *music = DKURLModel(DKMediaValue(DKMediaValue(aweme, @"music"), @"playURL"));
    if (music) dict[@"music"] = music;
    NSMutableArray *images = [NSMutableArray array];
    id album = DKMediaValue(aweme, @"albumImages");
    for (id image in [album isKindOfClass:NSArray.class] ? album : @[]) {
        NSMutableDictionary *entry = [@{@"urls": DKStrings(DKMediaValue(image, @"urlList")),
                                        @"free": DKStrings(DKMediaValue(image, @"watermarkFreeUrlList"))} mutableCopy];
        id clipType = DKMediaValue(image, @"type"), liveType = DKMediaValue(image, @"livePhotoType");
        if (clipType) entry[@"clipType"] = clipType;
        if (liveType) entry[@"livePhotoType"] = liveType;
        NSDictionary *clip = DKVideo(DKMediaValue(image, @"clipVideo"));
        if (clip) entry[@"clip"] = clip;
        [images addObject:entry];
    }
    dict[@"images"] = images;
    return dict;
}

NSDictionary *DKResolveComment(id comment) {
    if (!comment) return @{};
    NSMutableArray *images = [NSMutableArray array];
    id list = DKMediaValue(comment, @"imageList");
    for (id image in [list isKindOfClass:NSArray.class] ? list : @[]) {
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        NSDictionary *origin = DKURLModel(DKMediaValue(image, @"originUrl"));
        NSDictionary *medium = DKURLModel(DKMediaValue(image, @"mediumUrl"));
        if (origin) entry[@"origin"] = origin;
        if (medium) entry[@"medium"] = medium;
        entry[@"live"] = DKStrings(DKMediaValue(DKMediaValue(image, @"livePhotoModel"), @"videoUrl"));
        [images addObject:entry];
    }
    NSMutableArray *videos = [NSMutableArray array];
    id replies = DKMediaValue(comment, @"commentVideoReplyStruct");
    for (id reply in [replies isKindOfClass:NSArray.class] ? replies : @[]) {
        id aweme = DKMediaValue(reply, @"awemeModel");
        if (aweme) [videos addObject:DKResolveAweme(aweme)];
    }
    id replyVideo = DKMediaValue(comment, @"replyVideoModel");
    if (replyVideo && !videos.count) [videos addObject:DKResolveAweme(replyVideo)];
    NSMutableDictionary *dict = [@{@"images": images, @"videos": videos} mutableCopy];
    id sticker = DKMediaValue(comment, @"sticker");
    if (sticker) {
        NSMutableDictionary *s = [NSMutableDictionary dictionary];
        NSDictionary *animate = DKURLModel(DKMediaValue(sticker, @"animateURLModel"));
        NSDictionary *still = DKURLModel(DKMediaValue(sticker, @"staticURLModel"));
        if (animate) s[@"animate"] = animate;
        if (still) s[@"static"] = still;
        if (s.count) dict[@"sticker"] = s;
    }
    return dict;
}

static void DKAppendGroup(NSMutableArray<NSArray *> *groups, NSArray<NSString *> *urls) {
    if (urls.count && ![groups containsObject:urls]) [groups addObject:urls];
}

static void DKAppendString(NSMutableArray<NSArray *> *groups, id value) {
    if ([value isKindOfClass:NSString.class] && [value length]) DKAppendGroup(groups, @[value]);
}

static void DKCollectStickerURLs(id model, NSMutableArray *animated, NSMutableArray *still, NSHashTable *visited) {
    if (!model || [visited containsObject:model]) return;
    [visited addObject:model];
    for (NSString *key in @[@"animationURL", @"animateURL", @"animate_url"]) DKAppendString(animated, DKMediaValue(model, key));
    for (NSString *key in @[@"giphyURL", @"animateURLModel"]) {
        DKAppendGroup(animated, DKStrings(DKMediaValue(DKMediaValue(model, key), @"originURLList")));
    }
    for (NSString *key in @[@"staticURL", @"static_url", @"displayIconURL"]) DKAppendString(still, DKMediaValue(model, key));
    DKAppendGroup(still, DKStrings(DKMediaValue(DKMediaValue(model, @"staticURLModel"), @"originURLList")));
    for (NSString *key in @[@"emoticonModel", @"giphyMessage"]) {
        DKCollectStickerURLs(DKMediaValue(model, key), animated, still, visited);
    }
}

NSArray<NSArray *> *DKResolveStickerURLGroups(id model) {
    NSMutableArray *animated = [NSMutableArray array], *still = [NSMutableArray array];
    NSHashTable *visited = [NSHashTable hashTableWithOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality];
    DKCollectStickerURLs(model, animated, still, visited);
    // 动画地址存在时保留动画来源，下载失败由任务报告。
    return animated.count ? animated : still;
}
