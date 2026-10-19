#import "DKInteractionIconDraw.h"
#import "DouyinHeaders.h"

static DKInteractionIconSlot DKIconSettingsSlot(AWESettingItemModel *item) {
    NSString *key = item.identifier;
    if (![key hasPrefix:@"DYKillerInteraction"]) return DKInteractionIconUnknown;
    for (NSInteger index = 0; index < DKInteractionIconSlotCount; index++) {
        DKInteractionIconSlot slot = (DKInteractionIconSlot)index;
        if ([key isEqualToString:DKInteractionIconAssetKey(slot)] || [key isEqualToString:DKInteractionIconStyleKey(slot)]) return slot;
    }
    return DKInteractionIconUnknown;
}

static UIImage *DKIconSettingsImage(DKInteractionIconSlot slot, CGSize size, CGFloat scale) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; cache.countLimit = 64; });
    NSString *key = [NSString stringWithFormat:@"%ld/%g/%g/%g", (long)slot, size.width, size.height, scale];
    UIImage *image = [cache objectForKey:key];
    if (image) return image;
    UIGraphicsImageRendererFormat *format = UIGraphicsImageRendererFormat.preferredFormat;
    format.opaque = NO;
    format.scale = scale;
    image = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGFloat side = MIN(size.width, size.height);
        DKInteractionIconDraw(context.CGContext, slot, 1, CGRectMake((size.width - side) / 2, (size.height - side) / 2, side, side));
    }];
    image = [image imageWithRenderingMode:DKInteractionIconIsActive(slot) ? UIImageRenderingModeAlwaysOriginal : UIImageRenderingModeAlwaysTemplate];
    if (image) [cache setObject:image forKey:key];
    return image;
}

static void DKIconSettingsCellApply(AWESettingsTableViewCell *cell) {
    DKInteractionIconSlot slot = DKIconSettingsSlot(cell.itemModel);
    if (slot == DKInteractionIconUnknown) return;
    UIImageView *view = cell.iconImageView;
    CGSize size = view.bounds.size;
    if (size.width <= 0 || size.height <= 0) return;
    view.tintColor = cell.titleLabel.textColor;
    UIImage *image = DKIconSettingsImage(slot, size, cell.window.screen.scale ?: UIScreen.mainScreen.scale);
    if (view.image != image) view.image = image;
    // 分隔线延伸至卡片两边，保留原生首尾行的显隐与线高。
    UIView *line = cell.lineView;
    if (line.superview) {
        CGRect frame = line.frame;
        frame.origin.x = 0;
        frame.size.width = line.superview.bounds.size.width;
        if (!CGRectEqualToRect(line.frame, frame)) line.frame = frame;
    }
}

%hook AWESettingsTableViewCell
- (void)setItemModel:(id)model { %orig; DKIconSettingsCellApply(self); }
- (void)updateSubviewsColor { %orig; DKIconSettingsCellApply(self); }
- (void)updateSubviewsAfterLayout { %orig; DKIconSettingsCellApply(self); }
%end
