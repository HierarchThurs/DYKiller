#import "DKInteractionIconAssets.h"
#import "DKInteractionIconPicker.h"
#import "DKInteractionIcons.h"
#import "DKSettings.h"

static void DKIconSettingsRefreshDetails(UIViewController *presenter) {
    if (![presenter respondsToSelector:@selector(viewModel)]) return;
    AWESettingsViewModel *model = (AWESettingsViewModel *)[(AWESettingBaseViewController *)presenter viewModel];
    if (![model respondsToSelector:@selector(sectionDataArray)]) return;
    for (AWESettingSectionModel *section in model.sectionDataArray) {
        for (AWESettingItemModel *item in section.itemArray) {
            for (NSInteger index = 0; index < DKInteractionIconSlotCount; index++) {
                DKInteractionIconSlot slot = (DKInteractionIconSlot)index;
                if ([item.identifier isEqualToString:DKInteractionIconAssetKey(slot)]) item.detail = DKInteractionIconDetail(slot);
            }
        }
    }
    DKSettingsReloadCurrentPage();
}

static void DKRegisterInteractionStyle(DKInteractionIconSlot slot, NSString *title) {
    NSString *key = DKInteractionIconStyleKey(slot);
    DKSettingsRegister(key, ^{
        AWESettingItemModel *item = DKMakeChoiceConfirm(key, title, DKInteractionIconOptions(slot),
            ^(NSInteger index, UIViewController *presenter, dispatch_block_t commit) {
                BOOL hasImage = DKInteractionIconData(slot) != nil;
                if (slot == DKInteractionIconLikeBefore || slot == DKInteractionIconFavoriteBefore) {
                    hasImage |= DKInteractionIconData((DKInteractionIconSlot)(slot + 1)) != nil;
                }
                if (index != 3 || hasImage) { commit(); return; }
                id original = [NSUserDefaults.standardUserDefaults objectForKey:key];
                DKInteractionIconShowPicker(slot, presenter, ^(BOOL picked) {
                    id current = [NSUserDefaults.standardUserDefaults objectForKey:key];
                    if (picked && (current == original || [current isEqual:original])) commit();
                    DKIconSettingsRefreshDetails(presenter);
                });
            });
        DKSettingsOnChange(item, ^{ DKInteractionIconsRefresh(); });
        return item;
    });
}

%ctor {
    DKRegisterInteractionStyle(DKInteractionIconLikeBefore, @"点赞");
    DKRegisterInteractionStyle(DKInteractionIconComment, @"评论");
    DKRegisterInteractionStyle(DKInteractionIconFavoriteBefore, @"收藏");
    DKRegisterInteractionStyle(DKInteractionIconShare, @"分享");
    for (NSInteger index = 0; index < DKInteractionIconSlotCount; index++) {
        DKInteractionIconSlot slot = (DKInteractionIconSlot)index;
        NSString *key = DKInteractionIconAssetKey(slot);
        DKSettingsRegister(key, ^{
            AWESettingItemModel *item = DKMakeAction(key, DKInteractionIconTitle(slot), DKInteractionIconDetail(slot),
                ^(AWESettingItemModel *row, UIViewController *presenter) {
                    __weak AWESettingItemModel *weakRow = row;
                    DKInteractionIconShowPicker(slot, presenter, ^(BOOL hasImage) {
                        weakRow.detail = DKInteractionIconDetail(slot);
                        DKSettingsReloadCurrentPage();
                    });
                });
            DKSettingsWithValues(item, @[ DKInteractionIconValue(slot) ], ^NSString *(NSArray *values, BOOL brief) {
                return values.firstObject == NSNull.null ? @"未设置" : DKInteractionIconDataDetail(values.firstObject);
            });
            __weak AWESettingItemModel *weakItem = item;
            DKSettingsOnChange(item, ^{
                DKInteractionIconsRefresh();
                weakItem.detail = DKInteractionIconDetail(slot);
            });
            return item;
        });
    }
}
