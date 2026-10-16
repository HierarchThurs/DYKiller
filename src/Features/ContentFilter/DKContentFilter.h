// 内容过滤的配置、纯规则与数据入口契约。
#ifndef DKContentFilter_h
#define DKContentFilter_h

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    BOOL lowLikes;
    BOOL removeLive;
    BOOL removeAds;
    BOOL removeMusic;
    BOOL removeHotspot;
    long long minimumLikes;
    NSUInteger generation;
} DKFilterConfig;

typedef NS_ENUM(NSUInteger, DKFilterSource) {
    DKFilterSourceUnknown,
    DKFilterSourceRecommended,
    DKFilterSourceOther,
    DKFilterSourceConflict
};

typedef NS_OPTIONS(NSUInteger, DKFilterStage) {
    DKFilterStageAds = 1 << 0,
    DKFilterStageLive = 1 << 1,
    DKFilterStageLikes = 1 << 2,
    DKFilterStageMusic = 1 << 3,
    DKFilterStageHotspot = 1 << 4,
    DKFilterStageAll = DKFilterStageAds | DKFilterStageLive | DKFilterStageLikes | DKFilterStageMusic | DKFilterStageHotspot
};

typedef NS_OPTIONS(NSUInteger, DKFilterAdReason) {
    DKFilterAdNone = 0,
    DKFilterAdModelFlag = 1 << 0,
    DKFilterAdRawFlag = 1 << 1,
    DKFilterAdPayload = 1 << 2,
    DKFilterAdEmbedded = 1 << 3
};

// 特殊卡插入闸门的判定结果。
typedef NS_ENUM(NSUInteger, DKFilterInsertDecision) {
    DKFilterInsertKeep,
    DKFilterInsertCancel,
    DKFilterInsertUnknownSource
};

typedef struct {
    NSUInteger input, output, ads, live, music, hotspot, likes, unknownLikes, unknownSource;
    DKFilterAdReason adReasons;
} DKFilterCounts;

BOOL DKFilterMethod(Class cls, SEL selector, const char *returnType, NSArray<NSString *> *arguments);
BOOL DKFilterOwnMethod(Class cls, SEL selector);
id DKFilterObject(id object, SEL selector);
BOOL DKFilterBool(id object, SEL selector);
BOOL DKFilterIsClass(id object, NSString *className);
BOOL DKFilterParseInteger(NSString *text, long long *value);
BOOL DKFilterLikeCount(id raw, long long *value);
BOOL DKFilterIsLive(id model);
BOOL DKFilterIsHotspotBusiness(id businessID);
BOOL DKFilterIsHotspotCard(id model);
DKFilterInsertDecision DKFilterHotspotInsert(id businessID, id model, DKFilterConfig config);
DKFilterAdReason DKFilterAdModel(id model);
DKFilterAdReason DKFilterAdRaw(id raw);
id DKFilterApplyArray(id array, DKFilterConfig config, DKFilterSource source,
                     DKFilterStage stage, DKFilterCounts *counts);

DKFilterConfig DKFilterCurrentConfig(void);
void DKFilterPreferencesChanged(void);
id DKFilterWithBatch(id (^work)(void));
void DKFilterBindSource(id owner, id controller, NSString *source);
DKFilterSource DKFilterControllerSource(id controller);
id DKFilterArray(id array, id controller, DKFilterStage stage);
void DKFilterRegisterHook(NSString *name, BOOL installed, BOOL optional);
void DKFilterEntry(NSString *name, id object);
void DKFilterRecordAd(DKFilterAdReason reason);
void DKFilterRecordInsert(DKFilterInsertDecision decision);
NSString *DKContentFilterDiagnostics(void);

#ifdef __cplusplus
}
#endif
#endif
