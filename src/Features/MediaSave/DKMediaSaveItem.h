// 媒体保存单元：一次保存里的一项内容及其候选下载地址。
#ifndef DKMediaSaveItem_h
#define DKMediaSaveItem_h

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, DKMediaKind) {
    DKMediaKindVideo,
    DKMediaKindImage,
    DKMediaKindLivePhoto,
    DKMediaKindAnimated,
    DKMediaKindAudio,
};

// 一个候选：同一份内容的若干镜像地址，按顺序重试。tag 描述编码或模板，供诊断显示。
@interface DKMediaCandidate : NSObject
@property (nonatomic, copy) NSArray<NSString *> *urls;
@property (nonatomic, copy) NSString *tag;
+ (instancetype)candidateWithURLs:(NSArray<NSString *> *)urls tag:(NSString *)tag;
@end

@interface DKMediaSaveItem : NSObject
@property (nonatomic, assign) DKMediaKind kind;
// 视频、图片、动图、音频的地址；实况的照片地址。按优先级排列。
@property (nonatomic, copy) NSArray<DKMediaCandidate *> *primary;
// 实况的视频地址。
@property (nonatomic, copy) NSArray<DKMediaCandidate *> *paired;
// 视频缺音轨时补用的背景音乐地址。
@property (nonatomic, copy) NSArray<DKMediaCandidate *> *music;
+ (instancetype)itemWithKind:(DKMediaKind)kind primary:(NSArray<DKMediaCandidate *> *)primary;
@end

#ifdef __cplusplus
extern "C" {
#endif

NSString *DKMediaKindName(DKMediaKind kind);

#ifdef __cplusplus
}
#endif

#endif
