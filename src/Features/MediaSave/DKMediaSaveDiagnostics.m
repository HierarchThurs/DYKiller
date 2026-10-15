#import "DKMediaSaveDiagnostics.h"
#import "DKKeys.h"
#import "DKUtils.h"
#import <os/lock.h>

static os_unfair_lock gDKMediaLock = OS_UNFAIR_LOCK_INIT;
static BOOL gDKMediaInstalled[DKMediaSaveEntryCount];
static BOOL gDKMediaChecked[DKMediaSaveEntryCount];
static NSUInteger gDKMediaHits[DKMediaSaveEntryCount];
static NSMutableArray<NSString *> *gDKMediaNotes;

void DKMediaSaveInstalled(DKMediaSaveEntry entry, BOOL installed) {
    if (entry >= DKMediaSaveEntryCount) return;
    os_unfair_lock_lock(&gDKMediaLock);
    gDKMediaChecked[entry] = YES;
    gDKMediaInstalled[entry] = installed;
    os_unfair_lock_unlock(&gDKMediaLock);
}

void DKMediaSaveHit(DKMediaSaveEntry entry) {
    if (entry >= DKMediaSaveEntryCount) return;
    os_unfair_lock_lock(&gDKMediaLock);
    gDKMediaHits[entry]++;
    os_unfair_lock_unlock(&gDKMediaLock);
}

void DKMediaSaveNote(NSString *line) {
    if (!line.length) return;
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"HH:mm:ss";
    NSString *stamped = [NSString stringWithFormat:@"%@ %@", [formatter stringFromDate:NSDate.date], line];
    os_unfair_lock_lock(&gDKMediaLock);
    if (!gDKMediaNotes) gDKMediaNotes = [NSMutableArray array];
    [gDKMediaNotes addObject:stamped];
    if (gDKMediaNotes.count > 40) [gDKMediaNotes removeObjectsInRange:NSMakeRange(0, gDKMediaNotes.count - 40)];
    os_unfair_lock_unlock(&gDKMediaLock);
}

NSString *DKMediaSaveDiagnostics(void) {
    NSArray *names = @[@"推荐页长按面板", @"推荐页长按面板（Modern）", @"评论长按保存元素", @"原生评论图片去水印",
                       @"原生评论实况去水印", @"评论表情长按菜单", @"评论表情响应者", @"相似表情页按钮",
                       @"私信表情菜单", @"表情预览按钮"];
    NSArray *keys = @[DKKeyMediaSaveVideo, DKKeyMediaSaveCurrentImage, DKKeyMediaSaveAllImages, DKKeyMediaSaveCover,
                      DKKeyMediaSaveMusic, DKKeyMediaSaveComment, DKKeyMediaSaveCommentSticker, DKKeyCommentImageNoWatermark,
                      DKKeyCommentLivePhotoNoWatermark, DKKeyMediaSaveChatSticker, DKKeyMediaSaveHaptic,
                      DKKeyMediaSaveGlass, DKKeyMediaSaveGlassClear];
    NSMutableString *out = [NSMutableString string];
    for (NSString *key in keys) [out appendFormat:@"%@=%@\n", key, DKPrefBool(key) ? @"开启" : @"关闭"];
    os_unfair_lock_lock(&gDKMediaLock);
    for (NSUInteger i = 0; i < DKMediaSaveEntryCount; i++) {
        NSString *state = !gDKMediaChecked[i] ? @"未检查" : (gDKMediaInstalled[i] ? @"已安装" : @"类或签名不兼容");
        [out appendFormat:@"%@：Hook=%@ 命中=%lu\n", names[i], state, (unsigned long)gDKMediaHits[i]];
    }
    NSArray *notes = [gDKMediaNotes copy];
    os_unfair_lock_unlock(&gDKMediaLock);
    [out appendString:@"最近保存：\n"];
    if (!notes.count) [out appendString:@"(无)\n"];
    for (NSString *note in notes) [out appendFormat:@"  %@\n", note];
    return out;
}
