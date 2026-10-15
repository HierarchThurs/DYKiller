// 媒体保存诊断：各入口的安装与命中计数，以及最近几次保存的明细。
#ifndef DKMediaSaveDiagnostics_h
#define DKMediaSaveDiagnostics_h

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, DKMediaSaveEntry) {
    DKMediaSaveEntryFeedPanel,
    DKMediaSaveEntryFeedPanelModern,
    DKMediaSaveEntryCommentElement,
    DKMediaSaveEntryCommentImageNoWatermark,
    DKMediaSaveEntryCommentLiveNoWatermark,
    DKMediaSaveEntryStickerMenu,
    DKMediaSaveEntryStickerCell,
    DKMediaSaveEntrySimilarSheet,
    DKMediaSaveEntryChatMenu,
    DKMediaSaveEntryPreview,
    DKMediaSaveEntryCount
};

#ifdef __cplusplus
extern "C" {
#endif

void DKMediaSaveInstalled(DKMediaSaveEntry entry, BOOL installed);
void DKMediaSaveHit(DKMediaSaveEntry entry);
void DKMediaSaveNote(NSString *line);
NSString *DKMediaSaveDiagnostics(void);

#ifdef __cplusplus
}
#endif

#endif
