// 下载结果的格式判定与转换：按文件头识别，相册不可用的编码在这里拒收。
#ifndef DKMediaFormat_h
#define DKMediaFormat_h

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, DKMediaFileType) {
    DKMediaFileUnknown,
    DKMediaFileJPEG,
    DKMediaFilePNG,
    DKMediaFileGIF,
    DKMediaFileWebP,
    DKMediaFileHEIF,
    DKMediaFileVVIC,     // 字节自研图片编码，系统不可解码
    DKMediaFileVideo,
};

#ifdef __cplusplus
extern "C" {
#endif

DKMediaFileType DKMediaSniff(NSURL *file);
NSString *DKMediaFileTypeName(DKMediaFileType type);
BOOL DKMediaIsImageType(DKMediaFileType type);
// 按文件头给出扩展名（AVFoundation 与相册按扩展名识别本地文件容器）；无法判定时返回 nil。
NSString *DKMediaFileExtension(NSURL *file);
// 视频轨编码为 avc1 / hvc1 / hev1 时可写入相册；codec 返回四字符编码。
BOOL DKMediaVideoPlayable(NSURL *file, NSString **codec);
BOOL DKMediaVideoHasAudio(NSURL *file);
NSUInteger DKMediaFrameCount(NSURL *file);
// 验证真实 GIF 类型、完整解码状态及每帧的可解码性。
BOOL DKMediaGIFValid(NSURL *file);
// 多帧图转 GIF（保留逐帧时长和循环次数）；缺帧或编码失败返回 nil。
NSData *DKMediaGIFData(NSURL *file);
// 首帧编码为 PNG（保留透明）。
NSData *DKMediaPNGData(NSURL *file);
// 图片类文件写入相册时用的数据与类型标识：GIF / 多帧转 GIF，WebP 转 PNG，其余原样。
NSData *DKMediaPhotoData(NSURL *file, DKMediaFileType type, NSString **uti);

#ifdef __cplusplus
}
#endif

#endif
