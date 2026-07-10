//
//  DKProfileCleaner.xm
//  DYKiller
//
//  移除个人主页中的干扰元素
//

#import <UIKit/UIKit.h>
#import <Logos/Logos.h>
#import "../../Shared/DKKeys.h"
#import "../../Shared/DKUtils.h"
#import "../../Headers/DouyinHeaders.h"
#import "../../Settings/DKSettings.h"

#pragma mark - Hook 1: 移除作品空态引导

%hook AWEUserProfileUGCContributionGuideEmptyCollectionViewCell

+ (double)viewHeight {
    if (DKPrefBool(DKKeyProfileHideUGCGuide)) {
        return 0.0;
    }
    return %orig;
}

- (void)configWithUserModel:(id)arg0 context:(id)arg1 {
    %orig;
    if (DKPrefBool(DKKeyProfileHideUGCGuide)) {
        self.bodyView.hidden = YES;
    } else {
        self.bodyView.hidden = NO;
    }
}

%end

#pragma mark - 注册设置

%ctor {
    DKSettingsRegisterItem(@"个人主页", ^{
        return DKMakeSwitch(DKKeyProfileHideUGCGuide, @"移除个人主页发作品区域", @"隐藏「作品」下方的去发布等引导元素");
    });
}
