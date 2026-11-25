#pragma once

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

BOOL DKProfileEntryInServiceArea(void);
BOOL DKProfileEntryInTopBar(void);
NSString *DKProfileEntryTitle(void);
UIImage *DKProfileEntryGearImage(CGSize size);
void DKProfileEntryConfigureButton(UIButton *button);

void DKProfileComposeEntryRefresh(void);
void DKProfileTopEntryRefresh(void);
void DKProfileTopEntryLayout(UIView *container);
UIView *DKProfileTopEntryHit(UIView *container, CGPoint point, UIEvent *event);

#ifdef __cplusplus
}
#endif
