// 内容过滤诊断只保存计数、判据与类名。
#import "DKContentFilter.h"
#import <os/lock.h>

static os_unfair_lock gDKFilterStatsLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary *gDKFilterHooks, *gDKFilterEntries;
static DKFilterCounts gDKFilterCounts;
static NSUInteger gDKFilterEmpty, gDKFilterAdModels, gDKFilterUnknownBatches, gDKFilterConflicts;
static NSUInteger gDKFilterInsertCancels[DKFilterCardKindCount], gDKFilterInsertUnknown;
static DKFilterAdReason gDKFilterReasons;
static NSString *gDKFilterLastClass;

void DKFilterRegisterHook(NSString *name, BOOL installed, BOOL optional) {
    os_unfair_lock_lock(&gDKFilterStatsLock);
    if (!gDKFilterHooks) gDKFilterHooks = [NSMutableDictionary dictionary];
    gDKFilterHooks[name] = installed ? @"已安装" : (optional ? @"可选入口缺失" : @"类或签名不兼容");
    os_unfair_lock_unlock(&gDKFilterStatsLock);
}

void DKFilterEntry(NSString *name, id object) {
    NSString *className = object ? NSStringFromClass([object class]) : nil;
    os_unfair_lock_lock(&gDKFilterStatsLock);
    if (!gDKFilterEntries) gDKFilterEntries = [NSMutableDictionary dictionary];
    gDKFilterEntries[name] = @([gDKFilterEntries[name] unsignedIntegerValue] + 1);
    gDKFilterLastClass = className;
    os_unfair_lock_unlock(&gDKFilterStatsLock);
}

void DKFilterRecordAd(DKFilterAdReason reason) {
    os_unfair_lock_lock(&gDKFilterStatsLock);
    gDKFilterAdModels++;
    gDKFilterReasons |= reason;
    os_unfair_lock_unlock(&gDKFilterStatsLock);
}

void DKFilterRecordInsert(DKFilterInsertDecision decision, DKFilterCardKind kind) {
    if (kind >= DKFilterCardKindCount) kind = DKFilterCardOther;
    os_unfair_lock_lock(&gDKFilterStatsLock);
    if (decision == DKFilterInsertCancel) gDKFilterInsertCancels[kind]++;
    if (decision == DKFilterInsertUnknownSource) gDKFilterInsertUnknown++;
    os_unfair_lock_unlock(&gDKFilterStatsLock);
}

id DKFilterArray(id array, id controller, DKFilterStage stage) {
    DKFilterConfig config = DKFilterCurrentConfig();
    DKFilterSource source = DKFilterControllerSource(controller);
    DKFilterCounts counts;
    id filtered = DKFilterApplyArray(array, config, source, stage, &counts);
    os_unfair_lock_lock(&gDKFilterStatsLock);
    gDKFilterCounts.input += counts.input;
    gDKFilterCounts.output += counts.output;
    gDKFilterCounts.ads += counts.ads;
    gDKFilterCounts.live += counts.live;
    gDKFilterCounts.music += counts.music;
    gDKFilterCounts.articles += counts.articles;
    gDKFilterCounts.merchantNotes += counts.merchantNotes;
    gDKFilterCounts.likes += counts.likes;
    gDKFilterCounts.unknownLikes += counts.unknownLikes;
    gDKFilterCounts.unknownSource += counts.unknownSource;
    for (NSUInteger kind = 0; kind < DKFilterCardKindCount; kind++) gDKFilterCounts.cards[kind] += counts.cards[kind];
    gDKFilterReasons |= counts.adReasons;
    if (counts.input && !counts.output) gDKFilterEmpty++;
    if (stage & ~DKFilterStageAds) {
        if (source == DKFilterSourceUnknown) gDKFilterUnknownBatches++;
        if (source == DKFilterSourceConflict) gDKFilterConflicts++;
    }
    os_unfair_lock_unlock(&gDKFilterStatsLock);
    return filtered;
}

static NSString *DKFilterOnOff(BOOL on) {
    return on ? @"开启" : @"关闭";
}

// 「热点=1 创作引导=0 …」；按类别固定顺序列出。
static NSString *DKFilterCardCounts(const NSUInteger counts[DKFilterCardKindCount]) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSUInteger kind = 0; kind < DKFilterCardKindCount; kind++) {
        [parts addObject:[NSString stringWithFormat:@"%@=%lu", DKFilterCardKindName((DKFilterCardKind)kind),
            (unsigned long)counts[kind]]];
    }
    return [parts componentsJoinedByString:@" "];
}

// 生效中的特殊卡类别；全部类别时写「全部」。
static NSString *DKFilterCardSwitches(NSUInteger cards) {
    if (cards == DKFilterCardAll) return @"全部";
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSUInteger kind = 0; kind < DKFilterCardKindCount; kind++) {
        if (cards & DKFilterCardBit(kind)) [names addObject:DKFilterCardKindName((DKFilterCardKind)kind)];
    }
    return names.count ? [names componentsJoinedByString:@"、"] : @"无";
}

NSString *DKContentFilterDiagnostics(void) {
    DKFilterConfig config = DKFilterCurrentConfig();
    os_unfair_lock_lock(&gDKFilterStatsLock);
    NSDictionary *hooks = [gDKFilterHooks copy], *entries = [gDKFilterEntries copy];
    DKFilterCounts counts = gDKFilterCounts;
    NSUInteger empty = gDKFilterEmpty, adModels = gDKFilterAdModels;
    NSUInteger unknown = gDKFilterUnknownBatches, conflicts = gDKFilterConflicts;
    NSUInteger insertCancels[DKFilterCardKindCount];
    memcpy(insertCancels, gDKFilterInsertCancels, sizeof(insertCancels));
    NSUInteger insertUnknown = gDKFilterInsertUnknown;
    DKFilterAdReason reasons = gDKFilterReasons;
    NSString *last = gDKFilterLastClass;
    os_unfair_lock_unlock(&gDKFilterStatsLock);
    NSMutableString *out = [NSMutableString stringWithFormat:
        @"低赞=%@ 最低点赞=%lld 推荐直播移除=%@ 推荐音乐过滤=%@ 推荐文章过滤=%@ 商家笔记过滤=%@ 广告过滤=%@ 配置代际=%lu\n"
        @"特殊卡片过滤类别=%@\n",
        DKFilterOnOff(config.lowLikes), config.minimumLikes, DKFilterOnOff(config.removeLive),
        DKFilterOnOff(config.removeMusic), DKFilterOnOff(config.removeArticles),
        DKFilterOnOff(config.removeMerchantNotes), DKFilterOnOff(config.removeAds),
        (unsigned long)config.generation, DKFilterCardSwitches(config.removeCards)];
    for (NSString *name in [hooks.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [out appendFormat:@"%@：%@ 命中=%lu\n", name, hooks[name], (unsigned long)[entries[name] unsignedIntegerValue]];
    }
    [out appendFormat:@"各处理阶段累计输入=%lu 输出=%lu 移除低赞=%lu 直播=%lu 音乐=%lu 文章=%lu 商家笔记=%lu 广告=%lu\n"
        @"移除特殊卡片：%@\n"
        @"未知点赞保留=%lu 未知来源条目保留=%lu 来源未知批次=%lu 来源冲突批次=%lu 全空阶段=%lu\n"
        @"广告模型／显示阻断=%lu 判据位=%lu 最近入口类=%@\n",
        (unsigned long)counts.input, (unsigned long)counts.output, (unsigned long)counts.likes,
        (unsigned long)counts.live, (unsigned long)counts.music, (unsigned long)counts.articles,
        (unsigned long)counts.merchantNotes, (unsigned long)counts.ads, DKFilterCardCounts(counts.cards),
        (unsigned long)counts.unknownLikes,
        (unsigned long)counts.unknownSource, (unsigned long)unknown, (unsigned long)conflicts,
        (unsigned long)empty, (unsigned long)adModels, (unsigned long)reasons, last ?: @"(无)"];
    [out appendFormat:@"特殊卡插卡闸门取消：%@ 来源未确认保留=%lu\n",
        DKFilterCardCounts(insertCancels), (unsigned long)insertUnknown];
    [out appendString:@"判据位：1=作品标志 2=原始标志 4=广告载荷 8=内嵌广告\n"];
    return out;
}
