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
    DKFilterStageAll = DKFilterStageAds | DKFilterStageLive | DKFilterStageLikes
};

typedef NS_OPTIONS(NSUInteger, DKFilterAdReason) {
    DKFilterAdNone = 0,
    DKFilterAdModelFlag = 1 << 0,
    DKFilterAdRawFlag = 1 << 1,
    DKFilterAdPayload = 1 << 2,
    DKFilterAdEmbedded = 1 << 3
};

typedef struct {
    NSUInteger input, output, ads, live, likes, unknownLikes, unknownSource;
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
NSString *DKContentFilterDiagnostics(void);

#ifdef __cplusplus
}
#endif
#endif
