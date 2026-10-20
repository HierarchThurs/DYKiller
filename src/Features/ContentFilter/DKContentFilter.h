// 内容过滤的配置、纯规则与数据入口契约。
#ifndef DKContentFilter_h
#define DKContentFilter_h

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#ifdef __cplusplus
extern "C" {
#endif

// 特殊卡（作品带 hotSpotLynxCardModel）按业务号归类。Other 是登记表里未单独分类的业务与服务端新下发的业务，
// 只由「推荐过滤特殊卡片」总开关覆盖。
typedef NS_ENUM(NSUInteger, DKFilterCardKind) {
    DKFilterCardHotspot,
    DKFilterCardCreation,
    DKFilterCardEcommerce,
    DKFilterCardGame,
    DKFilterCardSocial,
    DKFilterCardInterest,
    DKFilterCardMicroApp,
    DKFilterCardOther,
    DKFilterCardKindCount
};

#define DKFilterCardBit(kind) ((NSUInteger)1 << (kind))
#define DKFilterCardAll (DKFilterCardBit(DKFilterCardKindCount) - 1)

typedef struct {
    BOOL lowLikes;
    BOOL removeLive;
    BOOL removeAds;
    BOOL removeMusic;
    BOOL removeArticles;
    BOOL removeMerchantNotes;
    NSUInteger removeCards;       // DKFilterCardBit 的组合；总开关开启时为 DKFilterCardAll
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
    DKFilterStageCards = 1 << 4,
    DKFilterStageArticle = 1 << 5,
    DKFilterStageMerchantNote = 1 << 6,
    DKFilterStageAll = DKFilterStageAds | DKFilterStageLive | DKFilterStageLikes | DKFilterStageMusic
        | DKFilterStageCards | DKFilterStageArticle | DKFilterStageMerchantNote
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
    NSUInteger input, output, ads, live, music, articles, merchantNotes, likes, unknownLikes, unknownSource;
    NSUInteger cards[DKFilterCardKindCount];
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
/// 业务号所属类别；不是字符串时返回 DKFilterCardOther。
DKFilterCardKind DKFilterCardKindForBusiness(id businessID);
/// 作品是否为特殊卡；是时经 kind 返回类别。业务号缺失或不是字符串的特殊卡归 Other。
BOOL DKFilterSpecialCard(id model, DKFilterCardKind *kind);
/// 类别的中文名，供诊断使用。
NSString *DKFilterCardKindName(DKFilterCardKind kind);
/// 类别自己的设置键；Other 没有单独开关，返回 nil。
NSString *DKFilterCardKindKey(DKFilterCardKind kind);
NSString *DKFilterCardKindTitle(DKFilterCardKind kind);
NSString *DKFilterCardKindInfo(DKFilterCardKind kind);
BOOL DKFilterIsArticle(id model);
/// 作品是否为商家笔记（图文作品上的 POI 富内容卡片：店铺动态、团购笔记等）。
BOOL DKFilterIsMerchantNote(id model);
DKFilterInsertDecision DKFilterSpecialCardInsert(id businessID, id model, DKFilterConfig config);
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
void DKFilterRecordInsert(DKFilterInsertDecision decision, DKFilterCardKind kind);
NSString *DKContentFilterDiagnostics(void);

#ifdef __cplusplus
}
#endif
#endif
