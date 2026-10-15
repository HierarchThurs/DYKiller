// 评论表情长按菜单：在「添加到表情」后并列「保存表情包」，由评论 cell 响应并按评论模型保存原表情。
#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import "DKMediaResolver.h"
#import "DKMediaSaveDiagnostics.h"
#import "DKMediaSaveRuntime.h"
#import "DKMediaSaveTask.h"
#import "DKMediaSelect.h"

static NSString *const kDKCommentCellClass = @"AWECommentPanelListSwiftImpl.CommentNewCell";
static NSString *const kDKCommentListController = @"AWECommentPanelListSwiftImpl.CommentViewController";

@interface DKCommentNewCell : UICollectionViewCell
@end

@interface DKCommentNewCell (DKMediaSave)
- (void)dk_saveCommentSticker:(id)sender;
@end

static BOOL DKMenuHasAction(NSArray *items, SEL action) {
    for (id item in items) {
        if ([item isKindOfClass:UIMenuItem.class] && ((UIMenuItem *)item).action == action) return YES;
    }
    return NO;
}

// cell → 列表 indexPath → CommentViewModel.sectionViewModelsArray[section].modelsArray[item]。
static id DKCommentForCell(UICollectionViewCell *cell) {
    UICollectionView *list = nil;
    for (UIView *view = cell.superview; view; view = view.superview) {
        if ([view isKindOfClass:UICollectionView.class]) { list = (UICollectionView *)view; break; }
    }
    NSIndexPath *path = [list indexPathForCell:cell];
    UIViewController *controller = DKMediaControllerForResponder(cell, kDKCommentListController);
    NSArray *sections = DKMediaValue(DKMediaValue(controller, @"viewModel"), @"sectionViewModelsArray");
    if (!path || ![sections isKindOfClass:NSArray.class] || (NSUInteger)path.section >= sections.count) return nil;
    NSArray *models = DKMediaValue(sections[path.section], @"modelsArray");
    if (![models isKindOfClass:NSArray.class] || (NSUInteger)path.item >= models.count) return nil;
    id comment = models[path.item];
    return [comment isKindOfClass:NSClassFromString(@"AWECommentModel")] ? comment : nil;
}

%group DKStickerMenuHooks
%hook UIMenuController
- (void)setMenuItems:(NSArray *)items {
    SEL save = @selector(dk_saveCommentSticker:);
    if (DKPrefBool(DKKeyMediaSaveCommentSticker) && DKMenuHasAction(items, NSSelectorFromString(@"addSticker")) && !DKMenuHasAction(items, save)) {
        NSMutableArray *extended = [items mutableCopy];
        [extended addObject:[[UIMenuItem alloc] initWithTitle:@"保存表情包" action:save]];
        DKMediaSaveHit(DKMediaSaveEntryStickerMenu);
        %orig(extended);
        return;
    }
    %orig;
}
%end
%end

%group DKStickerCellHooks
%hook DKCommentNewCell
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action == @selector(dk_saveCommentSticker:)) return DKPrefBool(DKKeyMediaSaveCommentSticker);
    return %orig;
}

%new
- (void)dk_saveCommentSticker:(id)sender {
    DKMediaSaveHit(DKMediaSaveEntryStickerCell);
    id comment = DKCommentForCell(self);
    DKMediaSaveItem *item = comment ? DKSelectCommentSticker(DKResolveComment(comment)) : nil;
    DKMediaSaveRun(item ? @[item] : @[], @"评论表情长按");
}
%end
%end

%ctor {
    DKSettingsRegister(DKKeyMediaSaveCommentSticker, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyMediaSaveCommentSticker, @"保存评论区表情包",
                            @"长按评论表情的菜单、单击评论表情后的表情页里增加「保存表情包」；也可长按评论用「保存到相册」保存。动图存为 GIF。");
    });
    Class cell = NSClassFromString(kDKCommentCellClass);
    BOOL cellOK = DKMediaMethod(cell, @selector(canPerformAction:withSender:), "B:@");
    BOOL menuOK = cellOK && DKMediaMethod(UIMenuController.class, @selector(setMenuItems:), "v@");
    if (cellOK) %init(DKStickerCellHooks, DKCommentNewCell = cell);
    if (menuOK) %init(DKStickerMenuHooks);
    DKMediaSaveInstalled(DKMediaSaveEntryStickerCell, cellOK);
    DKMediaSaveInstalled(DKMediaSaveEntryStickerMenu, menuOK);
}
