// 评论区保存：长按面板的「保存到相册」改由插件保存图片 / 实况 / 视频评论；原生评论下载去水印。
#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import "DKMediaResolver.h"
#import "DKMediaSaveDiagnostics.h"
#import "DKMediaSaveRuntime.h"
#import "DKMediaSaveTask.h"
#import "DKMediaSelect.h"
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const kDKCommentSaveElementClass = @"AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelSaveImageElement";
static NSString *const kDKCommentPanelSheetClass = @"AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelSheet";
static NSString *const kDKCommentMediaFeedClass = @"AWECommentMediaFeedViewController";
static NSString *const kDKCommentMediaCellClass = @"AWECommentMediaFeedSwfitImpl.CommentMediaFeedCellViewController";

@interface DKCommentSaveElement : NSObject
- (BOOL)elementShouldShow;
- (void)elementTapped;
- (id)commentPageContext;
@end

static id DKElementParams(id element) {
    return DKMediaValue(DKMediaValue(element, @"commentPageContext"), @"params");
}

static id DKElementComment(id element) {
    id comment = DKMediaValue(DKElementParams(element), @"selectdComment");
    return [comment isKindOfClass:NSClassFromString(@"AWECommentModel")] ? comment : nil;
}

// 列表长按 is_pic_inflow = 0，大图页长按为 1。
static BOOL DKElementInflow(id element) {
    NSDictionary *extra = DKMediaValue(DKElementParams(element), @"extraParams");
    return [extra isKindOfClass:NSDictionary.class] && [extra[@"is_pic_inflow"] integerValue] == 1;
}

static void DKCollectCells(UIViewController *controller, Class cellClass, NSMutableArray *out, NSUInteger depth) {
    if (!controller || depth > 8) return;
    if ([controller isKindOfClass:cellClass]) [out addObject:controller];
    for (UIViewController *child in controller.childViewControllers) DKCollectCells(child, cellClass, out, depth + 1);
}

// 大图页当前张：取覆盖窗口中心的 cell 控制器，读 Swift ivar currentIndexInMultiImageList（从 0 开始）。
static NSInteger DKBigPageIndex(NSUInteger count, UIWindowScene *scene) {
    UIViewController *feed = DKMediaFindControllerInScene(kDKCommentMediaFeedClass, scene);
    Class cellClass = NSClassFromString(kDKCommentMediaCellClass);
    Ivar ivar = cellClass ? class_getInstanceVariable(cellClass, "currentIndexInMultiImageList") : NULL;
    UIWindow *window = feed.viewIfLoaded.window;
    if (!ivar || !window) return -1;
    CGPoint center = CGPointMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds));
    NSMutableArray *cells = [NSMutableArray array];
    DKCollectCells(feed, cellClass, cells, 0);
    for (UIViewController *cell in cells) {
        UIView *view = cell.viewIfLoaded;
        if (view.window != window || ![view convertRect:view.bounds toView:nil].size.width) continue;
        if (!CGRectContainsPoint([view convertRect:view.bounds toView:nil], center)) continue;
        NSInteger index = *(NSInteger *)((uint8_t *)(__bridge void *)cell + ivar_getOffset(ivar));
        return index >= 0 && (NSUInteger)index < count ? index : -1;
    }
    return -1;
}

// 菜单元素按对象身份匹配所在列表，避免多个前台场景取到另一个窗口的面板。
static UIWindowScene *DKCommentSourceScene(id element) {
    UIWindowScene *single = nil;
    NSUInteger foregroundCount = 0;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if (![candidate isKindOfClass:UIWindowScene.class]
            || candidate.activationState != UISceneActivationStateForegroundActive) continue;
        UIWindowScene *scene = (UIWindowScene *)candidate;
        if (!DKPromptWindowForScene(scene)) continue;
        foregroundCount++;
        single = scene;
        UIViewController *list = DKMediaFindControllerInScene(
            @"AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelCollectionViewController", scene);
        NSArray *sections = DKMediaValue(DKMediaValue(list, @"viewModel"), @"sectionViewModelsArray");
        if (![sections isKindOfClass:NSArray.class]) continue;
        for (id section in sections) {
            NSArray *models = DKMediaValue(section, @"modelsArray");
            if ([models isKindOfClass:NSArray.class] && [models indexOfObjectIdenticalTo:element] != NSNotFound) return scene;
        }
    }
    return foregroundCount == 1 ? single : nil;
}

// 收起评论长按面板后再开始保存；收起入口缺失时延时兜底，只执行一次。
static void DKDismissCommentPanel(UIWindowScene *scene, dispatch_block_t then) {
    UIViewController *sheet = DKMediaFindControllerInScene(kDKCommentPanelSheetClass, scene);
    __block BOOL started = NO;
    dispatch_block_t run = ^{ if (!started) { started = YES; then(); } };
    if (sheet && DKMediaMethod(object_getClass(sheet), @selector(dismiss:withAnimated:), "v@B")) {
        ((void (*)(id, SEL, id, BOOL))objc_msgSend)(sheet, @selector(dismiss:withAnimated:), nil, YES);
    } else if (sheet) {
        [sheet dismissViewControllerAnimated:YES completion:run];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), run);
}

%group DKCommentElementHooks
%hook DKCommentSaveElement

- (BOOL)elementShouldShow {
    BOOL original = %orig;
    BOOL media = DKPrefBool(DKKeyMediaSaveComment), sticker = DKPrefBool(DKKeyMediaSaveCommentSticker);
    if (!media && !sticker) return original;
    id comment = DKElementComment(self);
    if (!comment) return original;
    NSDictionary *dict = DKResolveComment(comment);
    BOOL hasMedia = DKSelectCommentHasMedia(dict);
    if (media && hasMedia) return YES;
    if (sticker && !hasMedia && DKSelectCommentSticker(dict)) return YES;
    return original;
}

- (void)elementTapped {
    BOOL media = DKPrefBool(DKKeyMediaSaveComment), sticker = DKPrefBool(DKKeyMediaSaveCommentSticker);
    id comment = (media || sticker) ? DKElementComment(self) : nil;
    NSDictionary *dict = comment ? DKResolveComment(comment) : nil;
    BOOL hasMedia = DKSelectCommentHasMedia(dict);
    NSArray<DKMediaSaveItem *> *items = nil;
    NSString *source = nil;
    UIWindowScene *scene = (media || sticker) ? DKCommentSourceScene(self) : nil;
    if (!scene) { %orig; return; }
    if (media && hasMedia) {
        BOOL inflow = DKElementInflow(self);
        NSInteger index = inflow ? DKBigPageIndex([dict[@"images"] count], scene) : -1;
        items = DKSelectCommentItems(dict, index);
        source = !inflow ? @"评论长按·全部" : (index >= 0 ? [NSString stringWithFormat:@"评论大图页·第%ld张", (long)index + 1] : @"评论大图页·全部");
    } else if (sticker && !hasMedia) {
        DKMediaSaveItem *item = DKSelectCommentSticker(dict);
        if (item) { items = @[item]; source = @"评论长按·表情"; }
    }
    if (!items) {
        %orig;
        return;
    }
    DKMediaSaveHit(DKMediaSaveEntryCommentElement);
    DKDismissCommentPanel(scene, ^{ DKMediaSaveRun(items, source, scene); });
}

%end
%end

%group DKCommentImageNoWatermarkHooks
%hook AWECommentImageModel
- (id)downloadUrl {
    if (DKPrefBool(DKKeyCommentImageNoWatermark)) {
        id origin = [self originUrl];
        if (origin) { DKMediaSaveHit(DKMediaSaveEntryCommentImageNoWatermark); return origin; }
    }
    return %orig;
}
%end
%end

%group DKCommentLiveNoWatermarkHooks
%hook AWECommentMediaDownloadConfigLivePhoto
- (BOOL)needClientWaterMark {
    if (!DKPrefBool(DKKeyCommentLivePhotoNoWatermark)) return %orig;
    DKMediaSaveHit(DKMediaSaveEntryCommentLiveNoWatermark);
    return NO;
}
- (BOOL)needClientEndWaterMark {
    return DKPrefBool(DKKeyCommentLivePhotoNoWatermark) ? NO : %orig;
}
- (id)watermarkConfig {
    return DKPrefBool(DKKeyCommentLivePhotoNoWatermark) ? nil : %orig;
}
%end
%end

%ctor {
    DKSettingsRegister(DKKeyMediaSaveComment, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyMediaSaveComment, @"保存评论区图片与视频",
                            @"长按评论里的「保存到相册」改为无水印保存：评论列表里长按保存这条评论的全部图片、实况与视频，大图页长按保存当前这张。作者禁止下载的评论同样可保存。");
    });
    DKSettingsRegister(DKKeyCommentImageNoWatermark, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyCommentImageNoWatermark, @"原生保存评论图片去水印", @"抖音自带的评论图片保存改为保存原图，不带抖音号水印。");
    });
    DKSettingsRegister(DKKeyCommentLivePhotoNoWatermark, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyCommentLivePhotoNoWatermark, @"原生保存评论实况去水印", @"抖音自带的评论实况保存不再添加客户端水印。");
    });

    Class element = NSClassFromString(kDKCommentSaveElementClass);
    BOOL elementOK = DKMediaMethod(element, @selector(elementShouldShow), "B") && DKMediaMethod(element, @selector(elementTapped), "v")
        && DKMediaMethod(element, @selector(commentPageContext), "@");
    if (elementOK) %init(DKCommentElementHooks, DKCommentSaveElement = element);
    DKMediaSaveInstalled(DKMediaSaveEntryCommentElement, elementOK);

    Class image = NSClassFromString(@"AWECommentImageModel");
    BOOL imageOK = DKMediaMethod(image, @selector(downloadUrl), "@") && DKMediaMethod(image, @selector(originUrl), "@");
    if (imageOK) %init(DKCommentImageNoWatermarkHooks);
    DKMediaSaveInstalled(DKMediaSaveEntryCommentImageNoWatermark, imageOK);

    Class live = NSClassFromString(@"AWECommentMediaDownloadConfigLivePhoto");
    BOOL liveOK = DKMediaMethod(live, @selector(needClientWaterMark), "B") && DKMediaMethod(live, @selector(needClientEndWaterMark), "B")
        && DKMediaMethod(live, @selector(watermarkConfig), "@");
    if (liveOK) %init(DKCommentLiveNoWatermarkHooks);
    DKMediaSaveInstalled(DKMediaSaveEntryCommentLiveNoWatermark, liveOK);
}
