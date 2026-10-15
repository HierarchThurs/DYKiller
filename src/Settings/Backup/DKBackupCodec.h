//
//  DKBackupCodec.h
//  备份文件的编解码：UTF-8 JSON，顶层依次为 format、version、createdAt、source、settings、sets、files。
//  图片以 Base64 放在最后一节，附字节数与 sha256。只依赖 Foundation、ImageIO 与 CommonCrypto。
//

#ifndef DKBackupCodec_h
#define DKBackupCodec_h

#import "DKBackupModel.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DKBackupErrorCode) {
    DKBackupErrorUnreadable = 1,   // 无法读取文件
    DKBackupErrorTooLarge,         // 文件超过上限
    DKBackupErrorNotBackup,        // 不是 DYKiller 备份文件
    DKBackupErrorCorrupted,        // 备份文件已损坏
    DKBackupErrorNewerVersion,     // 来自更新版本的格式
    DKBackupErrorWriteFailed,      // 写入失败
};

#ifdef __cplusplus
extern "C" {
#endif

/// 错误的 localizedDescription 即给用户看的原因。
extern NSString *const DKBackupErrorDomain;
/// 备份文件的大小上限。
extern const unsigned long long DKBackupMaxFileBytes;

NSError *DKBackupMakeError(DKBackupErrorCode code, NSString *_Nullable detail);

/// 导出文件名：DYKiller_Backup_yyyyMMdd_HHmmss.dykbackup。
NSString *DKBackupFileName(NSDate *date);

/// 把各项的当前存值编码成备份。source 为 plugin / app / system；glassAvailable 为 NO 时不写受玻璃守卫的项。
NSData *_Nullable DKBackupEncode(NSArray<DKBackupEntry *> *entries, id<DKSettingsStore> store,
                                 NSDictionary<NSString *, NSString *> *source, NSDate *date,
                                 BOOL glassAvailable, NSError **error);

/// 解析备份：校验格式、版本与各节结构，核对图片的字节数与 sha256；值的规范化在算计划时进行。
DKBackupDocument *_Nullable DKBackupDecode(NSData *data, NSError **error);

/// 先查大小再读入文件。
NSData *_Nullable DKBackupReadFile(NSString *path, NSError **error);

/// 恢复默认用的文档：各项的值全部为「未设置」。
DKBackupDocument *DKBackupDefaultsDocument(NSArray<DKBackupEntry *> *entries);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END

#endif /* DKBackupCodec_h */
