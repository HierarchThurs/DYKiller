//
//  DKCommentSurvey.xm
//  功能：移除评论列表中「你对该视频下的评论氛围是否满意？」评价卡片。
//
//  实现：
//   - 卡片由 Swift 分区控制器 AWECommentPanelListSwiftImpl.CommentSurveySectionController（ListKit 分区）提供，
//     类名带点，按名字取类后挂到占位 %hook 上。
//   - 开关开时分区条目数返回 0，卡片不再创建，下方评论由列表原生上移。numberOfItems 由父类
//     AWEBaseListSectionController 实现，Logos 会把 hook 加到这个子类上，%orig 走父类实现。
//

#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import <objc/runtime.h>

static NSString *const kDKCommentSurveySectionClass = @"AWECommentPanelListSwiftImpl.CommentSurveySectionController";

@interface DKCommentSurveySection : NSObject
- (NSInteger)numberOfItems;
@end

%group DKCommentSurveyHooks
%hook DKCommentSurveySection

- (NSInteger)numberOfItems {
    if (DKPrefBool(DKKeyRemoveCommentSurvey)) return 0;
    return %orig;
}

%end
%end

%ctor {
    DKSettingsRegister(DKKeyRemoveCommentSurvey, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyRemoveCommentSurvey, @"移除评论区氛围评价",
                            @"移除评论列表中「你对该视频下的评论氛围是否满意？」评价卡片，下方评论随之上移");
    });

    Class section = NSClassFromString(kDKCommentSurveySectionClass);
    if (section && class_getInstanceMethod(section, @selector(numberOfItems))) {
        %init(DKCommentSurveyHooks, DKCommentSurveySection = section);
    }
}
