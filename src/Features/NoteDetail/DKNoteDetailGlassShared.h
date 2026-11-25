#pragma once

#import <UIKit/UIKit.h>

@interface DKNoteGlassHit : NSObject
+ (instancetype)hitWithRect:(CGRect)rect target:(UIView *)target;
@end

#ifdef __cplusplus
extern "C" {
#endif

extern const CGFloat kDKNoteTopHeight;
extern const CGFloat kDKNoteEdge;
extern const CGFloat kDKNoteClusterGap;
// 小于返回、头像与昵称之间的 4pt 间距，静止时玻璃保持独立。
extern const CGFloat kDKNoteGlassMergeSpacing;
extern const CGFloat kDKNoteNamePadding;

BOOL DKNoteGlassEnabled(void);
void DKNoteSetGlassHits(UIView *bar, NSArray<DKNoteGlassHit *> *hits);
UIView *DKNoteGlassTargetAtPoint(UIView *bar, CGPoint point);
UIScrollView *DKNoteScrollerForBar(UIView *bar);
void DKNoteSetContentOverflow(UIView *bar, BOOL overflow);
void DKNoteRefreshNativeTopBars(void);
void DKNoteSetSegmentedOverflow(UIView *bar, BOOL enabled);
void DKNoteInstallSegmentedOverflowHooks(void);

#ifdef __cplusplus
}
#endif
