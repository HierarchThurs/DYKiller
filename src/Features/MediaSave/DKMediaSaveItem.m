#import "DKMediaSaveItem.h"

@implementation DKMediaCandidate
+ (instancetype)candidateWithURLs:(NSArray<NSString *> *)urls tag:(NSString *)tag {
    DKMediaCandidate *candidate = [self new];
    candidate.urls = urls ?: @[];
    candidate.tag = tag ?: @"";
    return candidate;
}
@end

@implementation DKMediaSaveItem
+ (instancetype)itemWithKind:(DKMediaKind)kind primary:(NSArray<DKMediaCandidate *> *)primary {
    DKMediaSaveItem *item = [self new];
    item.kind = kind;
    item.primary = primary ?: @[];
    item.paired = @[];
    item.music = @[];
    return item;
}
@end

NSString *DKMediaKindName(DKMediaKind kind) {
    switch (kind) {
        case DKMediaKindVideo: return @"视频";
        case DKMediaKindImage: return @"图片";
        case DKMediaKindLivePhoto: return @"实况";
        case DKMediaKindAnimated: return @"表情";
        case DKMediaKindAudio: return @"音乐";
    }
    return @"未知";
}
