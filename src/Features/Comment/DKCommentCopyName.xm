//
//  DKCommentCopyName.xm
//  功能：复制评论移除用户名 —— 评论长按菜单「复制该评论」只复制评论内容，不带开头的「@用户名: 」。
//
//  实现：
//   - 原生复制写进剪贴板的是「@昵称: 内容」（40.7.0 实测，冒号后一个空格）。原方法执行后，
//     剪贴板确有本次写入、且以「@」+ 评论作者昵称 + 冒号开头时，去掉这段前缀再写回。
//   - 昵称取 commentPageContext.params.selectdComment.author.nickname；昵称可能带空格，按全称比对。
//   - 未开启、取不到昵称、或剪贴板内容不是这个格式时，保持原生结果。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import <objc/runtime.h>

static NSString *const kDKCopyElementClass = @"AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelCopyElement";

@interface DKCommentCopyElement : NSObject
- (void)elementTapped;
@end

static id DKCopyValue(id object, NSString *key) {
    if (!object || ![object respondsToSelector:NSSelectorFromString(key)]) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *DKCopyAuthorName(id element) {
    id comment = DKCopyValue(DKCopyValue(DKCopyValue(element, @"commentPageContext"), @"params"), @"selectdComment");
    id name = DKCopyValue(DKCopyValue(comment, @"author"), @"nickname");
    return [name isKindOfClass:NSString.class] && [name length] ? name : nil;
}

// 「@昵称」后接半角或全角冒号与空白时返回其后的内容。
static NSString *DKCopyStripName(NSString *text, NSString *name) {
    NSString *prefix = [@"@" stringByAppendingString:name];
    if (![text isKindOfClass:NSString.class] || ![text hasPrefix:prefix]) return nil;
    NSString *rest = [text substringFromIndex:prefix.length];
    NSRange separator = [rest rangeOfString:@"^\\s*[:：]\\s*" options:NSRegularExpressionSearch];
    if (separator.location == NSNotFound) return nil;
    NSString *content = [rest substringFromIndex:NSMaxRange(separator)];
    return content.length ? content : nil;
}

static void DKCopyRewrite(NSString *name, NSInteger before) {
    UIPasteboard *board = UIPasteboard.generalPasteboard;
    if (board.changeCount == before) return;
    NSString *content = DKCopyStripName(board.string, name);
    if (content) board.string = content;
}

%group DKCommentCopyNameHooks
%hook DKCommentCopyElement

- (void)elementTapped {
    NSString *name = DKPrefBool(DKKeyCommentCopyWithoutName) ? DKCopyAuthorName(self) : nil;
    if (!name) {
        %orig;
        return;
    }
    NSInteger before = UIPasteboard.generalPasteboard.changeCount;
    %orig;
    if (UIPasteboard.generalPasteboard.changeCount != before) {
        DKCopyRewrite(name, before);
        return;
    }
    // 原生写剪贴板若排在下一轮主循环，再核对一次。
    dispatch_async(dispatch_get_main_queue(), ^{ DKCopyRewrite(name, before); });
}

%end
%end

%ctor {
    DKSettingsRegister(DKKeyCommentCopyWithoutName, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyCommentCopyWithoutName, @"复制评论移除用户名",
                            @"长按评论点「复制该评论」时只复制评论内容。抖音原生复制为「@用户名: 评论内容」，开启后为「评论内容」。");
    });
    Class element = NSClassFromString(kDKCopyElementClass);
    if (element && class_getInstanceMethod(element, @selector(elementTapped))) {
        %init(DKCommentCopyNameHooks, DKCommentCopyElement = element);
    }
}
