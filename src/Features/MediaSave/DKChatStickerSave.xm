// 私信表情消息长按菜单：在「添加」后并列「保存表情包」，点击走菜单项的 willPerform block。
#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import "DKMediaResolver.h"
#import "DKMediaSaveDiagnostics.h"
#import "DKMediaSaveRuntime.h"
#import "DKMediaSaveTask.h"
#import "DKMediaSelect.h"

static NSString *const kDKChatSaveTracker = @"dk_save_sticker";
// 原生菜单 type：添加 4、分享 3。插件项用原生未使用的值。
static const unsigned long long kDKChatAddType = 4;
static const unsigned long long kDKChatShareType = 3;
static const unsigned long long kDKChatSaveType = 7790;

// 菜单图标：系统下载符号渲染成明暗两张 PNG，按文件地址交给菜单。
static NSString *DKChatIconURL(BOOL dark) {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"DYKillerMediaSave"];
    NSString *path = [dir stringByAppendingPathComponent:dark ? @"menu-save-dark.png" : @"menu-save-light.png"];
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
        UIImage *symbol = [[UIImage systemImageNamed:@"square.and.arrow.down" withConfiguration:config]
                           imageWithTintColor:dark ? UIColor.whiteColor : UIColor.blackColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
        format.scale = 3;
        CGSize size = CGSizeMake(28, 28);
        UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
            CGSize s = symbol.size;
            [symbol drawInRect:CGRectMake((size.width - s.width) / 2, (size.height - s.height) / 2, s.width, s.height)];
        }];
        [UIImagePNGRepresentation(image) writeToFile:path atomically:YES];
    }
    return [NSURL fileURLWithPath:path].absoluteString;
}

static unsigned long long DKMenuType(id item) {
    id value = DKMediaValue(item, @"type");
    return [value respondsToSelector:@selector(unsignedLongLongValue)] ? [value unsignedLongLongValue] : 0;
}

// 返回插入「保存表情包」后的菜单数组；不适用时返回 nil。
static NSArray *DKChatMenuWithSave(AWEIMCustomMenuComponent *component, NSArray *items, id cell) {
    id message = DKMediaValue(DKMediaValue(cell, @"currentContext"), @"message");
    Class giphy = NSClassFromString(@"AWEIMGiphyMessage"), menuClass = NSClassFromString(@"AWEIMCustomMenuModel");
    if (!giphy || !menuClass || ![message isKindOfClass:giphy] || ![items isKindOfClass:NSArray.class]) return nil;
    if (!DKResolveStickerURLGroups(message).count) return nil;
    NSUInteger at = items.count, addIndex = NSNotFound;
    for (NSUInteger i = 0; i < items.count; i++) {
        if ([DKMediaValue(items[i], @"trackerName") isEqual:kDKChatSaveTracker]) return nil;
        unsigned long long type = DKMenuType(items[i]);
        if (type == kDKChatAddType && addIndex == NSNotFound) addIndex = i;
        if (type == kDKChatShareType && at == items.count) at = i;
    }
    if (addIndex != NSNotFound) at = addIndex + 1;
    AWEIMCustomMenuModel *reference = addIndex != NSNotFound ? items[addIndex] : items.firstObject;

    AWEIMCustomMenuModel *save = [menuClass new];
    save.title = @"保存表情包";
    save.trackerName = kDKChatSaveTracker;
    save.type = kDKChatSaveType;
    save.imageName = DKMediaValue(reference, @"imageName");
    save.lightImageURL = DKChatIconURL(NO);
    save.darkImageURL = DKChatIconURL(YES);
    __weak AWEIMCustomMenuComponent *weakComponent = component;
    __weak id weakMessage = message;
    __weak UIResponder *weakCell = [cell isKindOfClass:UIResponder.class] ? cell : nil;
    save.willPerformMenuActionSelectorBlock = ^{
        UIWindowScene *scene = DKPromptSceneForResponder(weakCell);
        AWEIMCustomMenuComponent *strongComponent = weakComponent;
        if ([strongComponent respondsToSelector:@selector(msg_dismissMenu)]) [strongComponent msg_dismissMenu];
        DKMediaSaveItem *item = DKSelectStickerItem(DKResolveStickerURLGroups(weakMessage));
        DKMediaSaveRun(item ? @[item] : @[], @"私信表情菜单", scene);
    };
    NSMutableArray *extended = [items mutableCopy];
    [extended insertObject:save atIndex:MIN(at, extended.count)];
    DKMediaSaveHit(DKMediaSaveEntryChatMenu);
    return extended;
}

%group DKChatMenuHooks
%hook AWEIMCustomMenuComponent
- (void)p_showMenuWithContext:(AWEIMCustomMenuComponentContext *)context {
    if (DKPrefBool(DKKeyMediaSaveChatSticker)) {
        NSArray *extended = DKChatMenuWithSave(self, context.menuItemList, context.cell);
        if (extended) context.menuItemList = extended;
    }
    %orig;
}
%end
%end

// p_showMenuWithContext: 缺失时改挂两个公开入口，在菜单数组参数上插入。
%group DKChatMenuFallbackHooks
%hook AWEIMCustomMenuComponent
- (void)msg_showMenuForBubbleFrameInScreen:(CGRect)bubble tapLocationInScreen:(CGPoint)tap menuItemList:(NSArray *)items
                          menuPanelOptions:(unsigned long long)options moreEmoticon:(BOOL)more onCell:(id)cell extra:(id)extra {
    NSArray *extended = DKPrefBool(DKKeyMediaSaveChatSticker) ? DKChatMenuWithSave(self, items, cell) : nil;
    %orig(bubble, tap, extended ?: items, options, more, cell, extra);
}

- (void)msg_showMenuForBubbleFrameInScreen:(CGRect)bubble highLocationInScreen:(CGPoint)high lowLocationInScreen:(CGPoint)low
                      tryHighLocationFirst:(BOOL)tryHigh menuItemList:(NSArray *)items menuPanelOptions:(unsigned long long)options
                                    onCell:(id)cell extra:(id)extra {
    NSArray *extended = DKPrefBool(DKKeyMediaSaveChatSticker) ? DKChatMenuWithSave(self, items, cell) : nil;
    %orig(bubble, high, low, tryHigh, extended ?: items, options, cell, extra);
}
%end
%end

%ctor {
    DKSettingsRegister(DKKeyMediaSaveChatSticker, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyMediaSaveChatSticker, @"保存聊天与表情面板表情包",
                            @"私信表情消息的长按菜单、单击表情消息后的表情页、表情面板长按预览里增加「保存表情包」。动图存为 GIF。");
    });
    Class component = NSClassFromString(@"AWEIMCustomMenuComponent");
    Class context = NSClassFromString(@"AWEIMCustomMenuComponentContext");
    BOOL ok = DKMediaMethod(component, @selector(p_showMenuWithContext:), "v@")
        && DKMediaMethod(context, @selector(setMenuItemList:), "v@") && DKMediaMethod(context, @selector(cell), "@");
    SEL tapSel = @selector(msg_showMenuForBubbleFrameInScreen:tapLocationInScreen:menuItemList:menuPanelOptions:moreEmoticon:onCell:extra:);
    SEL highSel = @selector(msg_showMenuForBubbleFrameInScreen:highLocationInScreen:lowLocationInScreen:tryHighLocationFirst:menuItemList:menuPanelOptions:onCell:extra:);
    if (ok) {
        %init(DKChatMenuHooks);
    } else if (DKMediaMethod(component, tapSel, "v{{@QB@@") && DKMediaMethod(component, highSel, "v{{{B@Q@@")) {
        %init(DKChatMenuFallbackHooks);
        ok = YES;
    }
    DKMediaSaveInstalled(DKMediaSaveEntryChatMenu, ok);
}
