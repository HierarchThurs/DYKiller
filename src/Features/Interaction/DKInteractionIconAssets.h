#ifndef DKInteractionIconAssets_h
#define DKInteractionIconAssets_h
#import <UIKit/UIKit.h>
#import "DKInteractionIconRules.h"
#import "DKSettingsValue.h"
#import "DKInteractionIconFile.h"

#ifdef __cplusplus
extern "C" {
#endif
DKSettingsValue *DKInteractionIconValue(DKInteractionIconSlot slot);
NSData *DKInteractionIconData(DKInteractionIconSlot slot);
NSString *DKInteractionIconDetail(DKInteractionIconSlot slot);
BOOL DKInteractionIconStore(DKInteractionIconSlot slot, NSData *data, NSString **reason);
UIImage *DKInteractionIconCustom(DKInteractionIconSlot slot, CGSize size, CGFloat scale);
UIImage *DKInteractionIconImage(DKInteractionIconSlot slot, NSInteger style, CGSize size, CGFloat scale, BOOL light);
void DKInteractionIconAssetsReload(void);
#ifdef __cplusplus
}
#endif
#endif
