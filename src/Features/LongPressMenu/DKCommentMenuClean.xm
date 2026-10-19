//
//  DKCommentMenuClean.xm
//  长按菜单：评论长按菜单 —— 收录原生菜单项，按勾选移除。
//
//  实现：
//   - 面板列表（AWEBaseList 框架）先设好分区，各分区在绑定时经 replaceByModels:animated:sync: 填入菜单项；
//     普通分区的菜单项在这里收录与过滤，菜单项以 elementType 数字识别，文案取 elementContent。
//   - 顶部「分享评论给」好友行是单独的分区，在列表设分区（replaceBySectionViewModels:sync:）时整段去掉。
//   - 分区内全部移除时，该分区不留下方的分隔间距。
//   - 勾选在下一次打开菜单时生效。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKLongPressMenu.h"
#import "DKUtils.h"
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const kDKCommentListVMClass = @"AWECommentLongPressPanelSwiftImpl.AWECommentLongPressPanelListViewModel";
static NSString *const kDKCommentNormalSectionVMClass = @"AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelNormalSectionViewModel";
static NSString *const kDKCommentShareSectionVMClass = @"AWEIMShareImpl.ShareCommentHorizontalSectionViewModel";
static NSString *const kDKCommentNormalSectionClass = @"AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelNormalSectionController";
static NSString *const kDKCommentShareItemID = @"share";

// 评论长按面板的菜单项（AWECommentLongPressPanelElementViewModelProtocol）。
@interface DKCommentMenuElement : NSObject
- (unsigned long long)elementType;
- (id)elementContent;
@end

@interface DKCommentNormalSection : NSObject
- (NSInteger)numberOfItems;
- (CGSize)sizeForFooterWithCollectionViewSize:(CGSize)size;
@end

static Class DKCommentClass(NSString *name) {
    return name.length ? NSClassFromString(name) : Nil;
}

static NSString *DKCommentMenuItemID(id element) {
    if (![element respondsToSelector:@selector(elementType)]) return nil;
    unsigned long long type = ((unsigned long long (*)(id, SEL))objc_msgSend)(element, @selector(elementType));
    return [NSString stringWithFormat:@"%llu", type];
}

static NSString *DKCommentMenuItemTitle(id element) {
    id content = [element respondsToSelector:@selector(elementContent)]
        ? ((id (*)(id, SEL))objc_msgSend)(element, @selector(elementContent)) : nil;
    if ([content isKindOfClass:NSAttributedString.class]) content = [(NSAttributedString *)content string];
    return [content isKindOfClass:NSString.class] && [content length] ? content : nil;
}

static NSArray *DKCommentFilterModels(NSArray *models) {
    if (![models isKindOfClass:NSArray.class] || models.count == 0) return models;
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:models.count];
    NSMutableArray<NSString *> *removed = [NSMutableArray array];
    for (id element in models) {
        NSString *itemID = DKCommentMenuItemID(element);
        if (!itemID) {
            [kept addObject:element];
            continue;
        }
        NSString *title = DKCommentMenuItemTitle(element) ?: itemID;
        [entries addObject:@{ DKLongPressMenuFieldID: itemID, DKLongPressMenuFieldTitle: title }];
        if (DKLongPressMenuHidden(DKLongPressMenuComment, itemID)) [removed addObject:title];
        else [kept addObject:element];
    }
    DKLongPressMenuRecord(DKLongPressMenuComment, entries);
    if (removed.count == 0) return models;
    DKLongPressMenuNote(DKLongPressMenuComment, [NSString stringWithFormat:@"分区 %lu 项，移除 %@",
                                                 (unsigned long)models.count, [removed componentsJoinedByString:@"、"]]);
    return kept;
}

static NSArray *DKCommentFilterSections(NSArray *sections) {
    if (![sections isKindOfClass:NSArray.class]) return sections;
    Class shareClass = DKCommentClass(kDKCommentShareSectionVMClass);
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:sections.count];
    BOOL found = NO;
    for (id section in sections) {
        if (shareClass && [section isKindOfClass:shareClass]) {
            found = YES;
            if (DKLongPressMenuHidden(DKLongPressMenuComment, kDKCommentShareItemID)) continue;
        }
        [kept addObject:section];
    }
    if (found) {
        DKLongPressMenuRecord(DKLongPressMenuComment, @[ @{ DKLongPressMenuFieldID: kDKCommentShareItemID,
                                                            DKLongPressMenuFieldTitle: @"分享评论给" } ]);
    }
    DKLongPressMenuNote(DKLongPressMenuComment, [NSString stringWithFormat:@"%lu 个分区%@", (unsigned long)sections.count,
                                                 kept.count < sections.count ? @"，去掉「分享评论给」" : @""]);
    return kept.count == sections.count ? sections : kept;
}

%group DKCommentMenuCleanHooks

%hook AWEBaseListViewModel

- (void)replaceBySectionViewModels:(NSArray *)sections sync:(BOOL)sync {
    Class list = DKCommentClass(kDKCommentListVMClass);
    if (list && [self isKindOfClass:list]) {
        %orig(DKCommentFilterSections(sections), sync);
        return;
    }
    %orig;
}

%end

%hook AWEBaseListSectionViewModel

- (void)replaceByModels:(NSArray *)models animated:(BOOL)animated sync:(BOOL)sync {
    Class normal = DKCommentClass(kDKCommentNormalSectionVMClass);
    if (normal && [self isKindOfClass:normal]) {
        %orig(DKCommentFilterModels(models), animated, sync);
        return;
    }
    %orig;
}

%end

// 菜单项全部移除的普通分区不留分隔间距。
%hook DKCommentNormalSection

- (CGSize)sizeForFooterWithCollectionViewSize:(CGSize)size {
    if ([self numberOfItems] == 0) return CGSizeZero;
    return %orig;
}

%end

%end

%ctor {
    Class section = DKCommentClass(kDKCommentNormalSectionClass);
    BOOL ready = DKCommentClass(kDKCommentListVMClass) && DKCommentClass(kDKCommentNormalSectionVMClass)
        && NSClassFromString(@"AWEBaseListViewModel") && NSClassFromString(@"AWEBaseListSectionViewModel")
        && class_getInstanceMethod(section, @selector(sizeForFooterWithCollectionViewSize:));
    if (ready) %init(DKCommentMenuCleanHooks, DKCommentNormalSection = section);
}
