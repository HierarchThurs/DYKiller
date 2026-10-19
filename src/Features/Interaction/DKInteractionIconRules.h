#ifndef DKInteractionIconRules_h
#define DKInteractionIconRules_h
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, DKInteractionIconSlot) {
    DKInteractionIconUnknown = -1,
    DKInteractionIconLikeBefore,
    DKInteractionIconLikeAfter,
    DKInteractionIconComment,
    DKInteractionIconFavoriteBefore,
    DKInteractionIconFavoriteAfter,
    DKInteractionIconShare,
    DKInteractionIconSlotCount,
};

#ifdef __cplusplus
extern "C" {
#endif
DKInteractionIconSlot DKInteractionIconSlotForName(NSString *name);
NSString *DKInteractionIconStyleKey(DKInteractionIconSlot slot);
NSString *DKInteractionIconAssetKey(DKInteractionIconSlot slot);
NSString *DKInteractionIconTitle(DKInteractionIconSlot slot);
NSArray<NSString *> *DKInteractionIconOptions(DKInteractionIconSlot slot);
BOOL DKInteractionIconIsActive(DKInteractionIconSlot slot);
#ifdef __cplusplus
}
#endif
#endif
