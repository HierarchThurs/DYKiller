// 选址规则：从普通字典描述的作品 / 评论 / 表情里挑出无水印、相册可用的下载地址。
// 只依赖 Foundation，输入由 DKMediaResolver 从抖音模型抽取，也可直接用取证数据构造。
//
// 字典约定：
//   地址字典   urls:[NSString] key:URLKey w/h:NSNumber
//   视频字典   bitrates:[{codec:is_h265, bitrate, gear, addr:地址字典}] h264/play/cover:地址字典
//   图集项字典 urls/free:[NSString] clipType/livePhotoType:NSNumber clip:视频字典
//   作品字典   type:aweme_type images:[图集项字典] video:视频字典 animated:BOOL currentIndex music:地址字典
//   评论字典   images:[{origin/medium:地址字典 live:[NSString]}] videos:[作品字典] sticker:{animate/static:地址字典}
#ifndef DKMediaSelect_h
#define DKMediaSelect_h

#import "DKMediaSaveItem.h"

#ifdef __cplusplus
extern "C" {
#endif

// 去空、去重，剔除带服务端水印参数的地址。
NSArray<NSString *> *DKSelectCleanURLs(NSArray *urls);
// URLKey 里的编码段：h264 / bytevc1 / bytevc2，识别不出返回 nil。
NSString *DKSelectCodecOfKey(NSString *key);

NSArray<DKMediaCandidate *> *DKSelectVideoCandidates(NSDictionary *video);
NSArray<DKMediaCandidate *> *DKSelectImageCandidates(NSArray *urls, NSArray *free);
NSArray<DKMediaCandidate *> *DKSelectPlainCandidates(NSArray *urls, NSString *tag);

BOOL DKSelectAwemeIsAlbum(NSDictionary *aweme);
NSUInteger DKSelectAlbumCurrentIndex(NSDictionary *aweme);
DKMediaSaveItem *DKSelectAlbumEntry(NSDictionary *entry);
NSArray<DKMediaSaveItem *> *DKSelectAlbumItems(NSDictionary *aweme, BOOL all);
// 非图集作品：视频，或视频形式的实况。
DKMediaSaveItem *DKSelectAwemeMain(NSDictionary *aweme);
DKMediaSaveItem *DKSelectAwemeCover(NSDictionary *aweme);
DKMediaSaveItem *DKSelectAwemeMusic(NSDictionary *aweme);

// index < 0 时返回评论里的全部图片、实况与视频。
NSArray<DKMediaSaveItem *> *DKSelectCommentItems(NSDictionary *comment, NSInteger index);
BOOL DKSelectCommentHasMedia(NSDictionary *comment);
DKMediaSaveItem *DKSelectCommentSticker(NSDictionary *comment);
// 表情：urlGroups 按优先级给出若干组地址。
DKMediaSaveItem *DKSelectStickerItem(NSArray<NSArray *> *urlGroups);

NSString *DKSelectMainTitle(NSDictionary *aweme);
NSString *DKSelectAlbumCurrentTitle(NSDictionary *aweme);
NSString *DKSelectAlbumAllTitle(NSDictionary *aweme);

#ifdef __cplusplus
}
#endif

#endif
