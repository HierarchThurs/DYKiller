// 配置快照按批次复用；数据处理留在宿主调用线程。
#import "DKContentFilter.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import <os/lock.h>
#import <pthread.h>

static os_unfair_lock gDKConfigLock = OS_UNFAIR_LOCK_INIT;
static DKFilterConfig gDKConfig;
static NSUInteger gDKGeneration = 1;
static pthread_key_t gDKBatchKey;

typedef struct { DKFilterConfig config; } DKFilterBatch;

void DKFilterPreferencesChanged(void) {
    os_unfair_lock_lock(&gDKConfigLock);
    gDKGeneration++;
    os_unfair_lock_unlock(&gDKConfigLock);
}

static void DKFilterInitializeConfig(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        pthread_key_create(&gDKBatchKey, NULL);
        [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification
            object:NSUserDefaults.standardUserDefaults queue:nil usingBlock:^(__unused NSNotification *note) {
            DKFilterPreferencesChanged();
        }];
    });
}

// 总开关覆盖全部类别；关闭时按各类别自己的开关组合。
static NSUInteger DKFilterReadCardSwitches(void) {
    if (DKPrefBool(DKKeyFilterRecommendedSpecialCard)) return DKFilterCardAll;
    NSUInteger cards = 0;
    for (NSUInteger kind = 0; kind < DKFilterCardKindCount; kind++) {
        NSString *key = DKFilterCardKindKey((DKFilterCardKind)kind);
        if (key && DKPrefBool(key)) cards |= DKFilterCardBit(kind);
    }
    return cards;
}

DKFilterConfig DKFilterCurrentConfig(void) {
    DKFilterInitializeConfig();
    DKFilterBatch *batch = pthread_getspecific(gDKBatchKey);
    if (batch) return batch->config;
    for (;;) {
        os_unfair_lock_lock(&gDKConfigLock);
        NSUInteger generation = gDKGeneration;
        DKFilterConfig current = gDKConfig;
        os_unfair_lock_unlock(&gDKConfigLock);
        if (current.generation == generation) return current;
        DKFilterConfig next = {0};
        next.lowLikes = DKPrefBool(DKKeyFilterLowLikes);
        next.removeLive = DKPrefBool(DKKeyRemoveRecommendedLive);
        next.removeAds = DKPrefBool(DKKeyFilterAds);
        next.removeMusic = DKPrefBool(DKKeyFilterRecommendedMusic);
        next.removeArticles = DKPrefBool(DKKeyFilterRecommendedArticle);
        next.removeMerchantNotes = DKPrefBool(DKKeyFilterRecommendedMerchantNote);
        next.removeCards = DKFilterReadCardSwitches();
        id raw = [NSUserDefaults.standardUserDefaults objectForKey:DKKeyMinimumLikes];
        DKFilterLikeCount(raw, &next.minimumLikes);
        next.generation = generation;
        os_unfair_lock_lock(&gDKConfigLock);
        BOOL valid = generation == gDKGeneration;
        if (valid) gDKConfig = next;
        os_unfair_lock_unlock(&gDKConfigLock);
        if (valid) return next;
    }
}

id DKFilterWithBatch(id (^work)(void)) {
    DKFilterConfig config = DKFilterCurrentConfig();
    DKFilterBatch batch = {config};
    void *previous = pthread_getspecific(gDKBatchKey);
    pthread_setspecific(gDKBatchKey, &batch);
    @try { return work(); }
    @finally { pthread_setspecific(gDKBatchKey, previous); }
}
