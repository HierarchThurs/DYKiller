#import "DKMediaSelect.h"

static NSArray *DKArray(id value) { return [value isKindOfClass:NSArray.class] ? value : nil; }
static NSDictionary *DKDict(id value) { return [value isKindOfClass:NSDictionary.class] ? value : nil; }
static NSString *DKString(id value) { return [value isKindOfClass:NSString.class] ? value : nil; }
static long long DKInteger(id value) { return [value respondsToSelector:@selector(longLongValue)] ? [value longLongValue] : 0; }

#pragma mark - 地址

NSArray<NSString *> *DKSelectCleanURLs(NSArray *urls) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (id value in DKArray(urls)) {
        NSString *url = DKString(value);
        if (!url.length || [url containsString:@"watermark=1"] || [out containsObject:url]) continue;
        [out addObject:url];
    }
    return out;
}

NSString *DKSelectCodecOfKey(NSString *key) {
    for (NSString *codec in @[@"bytevc2", @"bytevc1", @"h264"]) {
        if ([key containsString:[NSString stringWithFormat:@"_%@_", codec]]) return codec;
    }
    return nil;
}

static NSString *DKPathOf(NSString *url) {
    NSString *path = [NSURL URLWithString:url].path ?: url;
    return path.lowercaseString;
}

// 图片模板：vvic 原图（.image）与服务端水印模板一律不用。
static BOOL DKImageURLUsable(NSString *url) {
    NSString *path = DKPathOf(url);
    if ([path hasSuffix:@".image"]) return NO;
    return ![url containsString:@"dy-water"] && ![url containsString:@"-download-webp"];
}

static NSInteger DKImageRank(NSString *url) {
    NSString *ext = DKPathOf(url).pathExtension;
    if ([ext isEqualToString:@"jpeg"] || [ext isEqualToString:@"jpg"]) return 0;
    if ([ext isEqualToString:@"heic"] || [ext isEqualToString:@"heif"] || [ext isEqualToString:@"png"]) return 1;
    if ([ext isEqualToString:@"webp"]) return 2;
    return 3;
}

static NSArray<NSString *> *DKSortedImageURLs(NSArray *urls) {
    NSMutableArray<NSString *> *usable = [NSMutableArray array];
    for (NSString *url in DKSelectCleanURLs(urls)) if (DKImageURLUsable(url)) [usable addObject:url];
    // 稳定排序：同一优先级内保持原有镜像顺序。
    NSMutableArray<NSString *> *sorted = [NSMutableArray array];
    for (NSInteger rank = 0; rank <= 3; rank++) {
        for (NSString *url in usable) if (DKImageRank(url) == rank) [sorted addObject:url];
    }
    return sorted;
}

NSArray<DKMediaCandidate *> *DKSelectImageCandidates(NSArray *urls, NSArray *free) {
    NSMutableArray<DKMediaCandidate *> *out = [NSMutableArray array];
    NSArray<NSString *> *freeURLs = DKSortedImageURLs(free);
    if (freeURLs.count) [out addObject:[DKMediaCandidate candidateWithURLs:freeURLs tag:@"watermark_free"]];
    NSArray<NSString *> *listURLs = DKSortedImageURLs(urls);
    if (listURLs.count) {
        NSString *tag = [NSString stringWithFormat:@"url_list.%@", DKPathOf(listURLs.firstObject).pathExtension];
        [out addObject:[DKMediaCandidate candidateWithURLs:listURLs tag:tag]];
    }
    return out;
}

NSArray<DKMediaCandidate *> *DKSelectPlainCandidates(NSArray *urls, NSString *tag) {
    NSArray<NSString *> *clean = DKSelectCleanURLs(urls);
    return clean.count ? @[[DKMediaCandidate candidateWithURLs:clean tag:tag]] : @[];
}

#pragma mark - 视频

static long long DKAddrArea(NSDictionary *addr, NSString *gear) {
    long long area = DKInteger(addr[@"w"]) * DKInteger(addr[@"h"]);
    if (area > 0) return area;
    long long side = DKInteger(gear);
    return side * side;
}

NSArray<DKMediaCandidate *> *DKSelectVideoCandidates(NSDictionary *video) {
    NSMutableArray<DKMediaCandidate *> *out = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    void (^add)(NSDictionary *, NSString *) = ^(NSDictionary *addr, NSString *tag) {
        NSArray<NSString *> *urls = DKSelectCleanURLs(addr[@"urls"]);
        if (!urls.count || [seen containsObject:urls.firstObject]) return;
        [seen addObject:urls.firstObject];
        [out addObject:[DKMediaCandidate candidateWithURLs:urls tag:tag]];
    };

    // is_h265：0 为 H.264，1 为 bytevc1（标准 HEVC），2 为 bytevc2（相册不可解码）。
    NSMutableArray<NSDictionary *> *gears = [NSMutableArray array];
    for (id value in DKArray(video[@"bitrates"])) {
        NSDictionary *gear = DKDict(value);
        NSDictionary *addr = DKDict(gear[@"addr"]);
        long long codec = DKInteger(gear[@"codec"]);
        if (!addr || codec < 0 || codec > 1) continue;
        if ([DKSelectCodecOfKey(DKString(addr[@"key"])) isEqualToString:@"bytevc2"]) continue;
        [gears addObject:gear];
    }
    [gears sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        long long areaA = DKAddrArea(a[@"addr"], a[@"gear"]), areaB = DKAddrArea(b[@"addr"], b[@"gear"]);
        if (areaA != areaB) return areaA > areaB ? NSOrderedAscending : NSOrderedDescending;
        long long rateA = DKInteger(a[@"bitrate"]), rateB = DKInteger(b[@"bitrate"]);
        if (rateA != rateB) return rateA > rateB ? NSOrderedAscending : NSOrderedDescending;
        return NSOrderedSame;
    }];
    for (NSDictionary *gear in gears) {
        NSDictionary *addr = gear[@"addr"];
        NSString *tag = [NSString stringWithFormat:@"%@ %lldx%lld %@", DKInteger(gear[@"codec"]) == 1 ? @"bytevc1" : @"h264",
                         DKInteger(addr[@"w"]), DKInteger(addr[@"h"]), DKString(gear[@"gear"]) ?: @""];
        add(addr, tag);
    }

    NSDictionary *h264 = DKDict(video[@"h264"]);
    if (h264) add(h264, [NSString stringWithFormat:@"play_addr_h264 %lldx%lld", DKInteger(h264[@"w"]), DKInteger(h264[@"h"])]);
    NSDictionary *play = DKDict(video[@"play"]);
    NSString *playCodec = DKSelectCodecOfKey(DKString(play[@"key"]));
    if (play && ![playCodec isEqualToString:@"bytevc2"]) {
        add(play, [NSString stringWithFormat:@"play_addr %@ %lldx%lld", playCodec ?: @"unknown", DKInteger(play[@"w"]), DKInteger(play[@"h"])]);
    }
    return out;
}

#pragma mark - 作品

BOOL DKSelectAwemeIsAlbum(NSDictionary *aweme) {
    return DKInteger(aweme[@"type"]) == 68 && DKArray(aweme[@"images"]).count > 0;
}

NSUInteger DKSelectAlbumCurrentIndex(NSDictionary *aweme) {
    NSUInteger count = DKArray(aweme[@"images"]).count;
    if (!count) return 0;
    long long current = DKInteger(aweme[@"currentIndex"]);
    // currentImageIndex 从 1 开始；未展示过的作品为 0。
    long long index = current > 0 ? current - 1 : 0;
    return (NSUInteger)MIN(MAX(index, 0LL), (long long)count - 1);
}

DKMediaSaveItem *DKSelectAlbumEntry(NSDictionary *entry) {
    NSArray<DKMediaCandidate *> *images = DKSelectImageCandidates(entry[@"urls"], entry[@"free"]);
    NSDictionary *clip = DKDict(entry[@"clip"]);
    NSArray<DKMediaCandidate *> *clipVideo = clip ? DKSelectVideoCandidates(clip) : @[];
    if (clipVideo.count && DKInteger(entry[@"clipType"]) == 4) {
        return [DKMediaSaveItem itemWithKind:DKMediaKindVideo primary:clipVideo];
    }
    if (clipVideo.count && images.count) {
        DKMediaSaveItem *item = [DKMediaSaveItem itemWithKind:DKMediaKindLivePhoto primary:images];
        item.paired = clipVideo;
        return item;
    }
    return images.count ? [DKMediaSaveItem itemWithKind:DKMediaKindImage primary:images] : nil;
}

NSArray<DKMediaSaveItem *> *DKSelectAlbumItems(NSDictionary *aweme, BOOL all) {
    NSArray *entries = DKArray(aweme[@"images"]);
    if (!DKSelectAwemeIsAlbum(aweme)) return @[];
    NSMutableArray<DKMediaSaveItem *> *out = [NSMutableArray array];
    if (all) {
        for (id entry in entries) {
            DKMediaSaveItem *item = DKSelectAlbumEntry(DKDict(entry));
            if (item) [out addObject:item];
        }
    } else {
        DKMediaSaveItem *item = DKSelectAlbumEntry(DKDict(entries[DKSelectAlbumCurrentIndex(aweme)]));
        if (item) [out addObject:item];
    }
    return out;
}

DKMediaSaveItem *DKSelectAwemeMain(NSDictionary *aweme) {
    if (DKSelectAwemeIsAlbum(aweme)) return nil;
    NSDictionary *video = DKDict(aweme[@"video"]);
    NSArray<DKMediaCandidate *> *videos = video ? DKSelectVideoCandidates(video) : @[];
    if (!videos.count) return nil;
    if ([aweme[@"animated"] boolValue]) {
        NSArray<DKMediaCandidate *> *cover = DKSelectImageCandidates(DKDict(video[@"cover"])[@"urls"], nil);
        if (cover.count) {
            DKMediaSaveItem *item = [DKMediaSaveItem itemWithKind:DKMediaKindLivePhoto primary:cover];
            item.paired = videos;
            return item;
        }
    }
    DKMediaSaveItem *item = [DKMediaSaveItem itemWithKind:DKMediaKindVideo primary:videos];
    item.music = DKSelectPlainCandidates(DKDict(aweme[@"music"])[@"urls"], @"music");
    return item;
}

DKMediaSaveItem *DKSelectAwemeCover(NSDictionary *aweme) {
    if (DKSelectAwemeIsAlbum(aweme)) return nil;
    NSArray<DKMediaCandidate *> *cover = DKSelectImageCandidates(DKDict(DKDict(aweme[@"video"])[@"cover"])[@"urls"], nil);
    return cover.count ? [DKMediaSaveItem itemWithKind:DKMediaKindImage primary:cover] : nil;
}

DKMediaSaveItem *DKSelectAwemeMusic(NSDictionary *aweme) {
    NSArray<DKMediaCandidate *> *music = DKSelectPlainCandidates(DKDict(aweme[@"music"])[@"urls"], @"music");
    return music.count ? [DKMediaSaveItem itemWithKind:DKMediaKindAudio primary:music] : nil;
}

#pragma mark - 评论

static DKMediaSaveItem *DKCommentImageItem(NSDictionary *image) {
    NSDictionary *origin = DKDict(image[@"origin"]), *medium = DKDict(image[@"medium"]);
    NSArray<DKMediaCandidate *> *photos = DKSelectImageCandidates(origin[@"urls"], nil);
    if (!photos.count) photos = DKSelectImageCandidates(medium[@"urls"], nil);
    if (!photos.count) return nil;
    NSArray<DKMediaCandidate *> *live = DKSelectPlainCandidates(image[@"live"], @"live_video");
    if (live.count) {
        DKMediaSaveItem *item = [DKMediaSaveItem itemWithKind:DKMediaKindLivePhoto primary:photos];
        item.paired = live;
        return item;
    }
    return [DKMediaSaveItem itemWithKind:DKMediaKindImage primary:photos];
}

NSArray<DKMediaSaveItem *> *DKSelectCommentItems(NSDictionary *comment, NSInteger index) {
    NSMutableArray<DKMediaSaveItem *> *out = [NSMutableArray array];
    NSArray *images = DKArray(comment[@"images"]);
    if (index >= 0 && (NSUInteger)index < images.count) {
        DKMediaSaveItem *item = DKCommentImageItem(DKDict(images[index]));
        if (item) [out addObject:item];
        return out;
    }
    for (id image in images) {
        DKMediaSaveItem *item = DKCommentImageItem(DKDict(image));
        if (item) [out addObject:item];
    }
    for (id aweme in DKArray(comment[@"videos"])) {
        DKMediaSaveItem *item = DKSelectAwemeMain(DKDict(aweme));
        if (item) [out addObject:item];
    }
    return out;
}

BOOL DKSelectCommentHasMedia(NSDictionary *comment) {
    return DKArray(comment[@"images"]).count > 0 || DKArray(comment[@"videos"]).count > 0;
}

DKMediaSaveItem *DKSelectStickerItem(NSArray<NSArray *> *urlGroups) {
    NSMutableArray<NSString *> *urls = [NSMutableArray array];
    for (id group in DKArray(urlGroups)) {
        for (NSString *url in DKSelectCleanURLs(DKArray(group))) if (![urls containsObject:url]) [urls addObject:url];
    }
    return urls.count ? [DKMediaSaveItem itemWithKind:DKMediaKindAnimated primary:@[[DKMediaCandidate candidateWithURLs:urls tag:@"sticker"]]] : nil;
}

DKMediaSaveItem *DKSelectCommentSticker(NSDictionary *comment) {
    NSDictionary *sticker = DKDict(comment[@"sticker"]);
    if (!sticker) return nil;
    NSArray *animated = DKSelectCleanURLs(DKDict(sticker[@"animate"])[@"urls"]);
    return DKSelectStickerItem(@[animated.count ? animated : (DKDict(sticker[@"static"])[@"urls"] ?: @[])]);
}

#pragma mark - 面板标题

NSString *DKSelectMainTitle(NSDictionary *aweme) {
    DKMediaSaveItem *item = DKSelectAwemeMain(aweme);
    return item.kind == DKMediaKindLivePhoto ? @"保存实况" : @"保存视频";
}

NSString *DKSelectAlbumCurrentTitle(NSDictionary *aweme) {
    NSArray<DKMediaSaveItem *> *items = DKSelectAlbumItems(aweme, NO);
    NSString *noun = @"图片";
    if (items.firstObject.kind == DKMediaKindLivePhoto) noun = @"实况";
    else if (items.firstObject.kind == DKMediaKindVideo) noun = @"视频";
    BOOL multiple = DKArray(aweme[@"images"]).count > 1;
    return [NSString stringWithFormat:@"保存%@%@", multiple ? @"当前" : @"", noun];
}

NSString *DKSelectAlbumAllTitle(NSDictionary *aweme) {
    BOOL live = NO, video = NO;
    for (DKMediaSaveItem *item in DKSelectAlbumItems(aweme, YES)) {
        live = live || item.kind == DKMediaKindLivePhoto;
        video = video || item.kind == DKMediaKindVideo;
    }
    if (video) return @"保存全部";
    return live ? @"保存全部实况" : @"保存全部图片";
}
