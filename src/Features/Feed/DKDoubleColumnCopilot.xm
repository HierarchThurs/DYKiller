//
//  DKDoubleColumnCopilot.xm
//  功能：播放页精简 —— 移除首页双列作品流右下角的 AI 按钮。
//
//  实现：抖音的 AI 入口由状态机驱动，copilotViewInvisible 为真时状态恒为 0（圆钮与输入条都隐藏）。
//  改值后调原生的 showCopilotView 按新判据重新走一次状态。
//

#import "DKDoubleColumnFeed.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import "DouyinHeaders.h"

static NSHashTable<AWEDCFeedCopilotController *> *gDKCopilotControllers;

NSString *DKDoubleColumnCopilotStatus(void) {
    NSMutableString *out = [NSMutableString stringWithFormat:@"移除AI按钮=%@\n", DKPrefBool(DKKeyDoubleColumnRemoveCopilot) ? @"开" : @"关"];
    NSArray<AWEDCFeedCopilotController *> *controllers = gDKCopilotControllers.allObjects;
    for (AWEDCFeedCopilotController *controller in controllers) {
        [out appendFormat:@"  控制器 %p invisible=%d state=%lu\n", controller,
            controller.copilotViewInvisible, (unsigned long)controller.copilotPresenter.state];
    }
    if (controllers.count == 0) [out appendString:@"  还没有见到 AI 入口\n"];
    return out;
}

%hook AWEDCFeedCopilotController

- (void)setupUI {
    if (!gDKCopilotControllers) gDKCopilotControllers = [NSHashTable weakObjectsHashTable];
    [gDKCopilotControllers addObject:self];
    %orig;
}

- (BOOL)copilotViewInvisible {
    return DKPrefBool(DKKeyDoubleColumnRemoveCopilot) || %orig;
}

%end

%ctor {
    DKSettingsRegister(DKKeyDoubleColumnRemoveCopilot, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(DKKeyDoubleColumnRemoveCopilot, @"移除AI按钮",
            @"点击首页后的双列作品流右下角的 AI 按钮。开启后不显示、不响应点击，关闭后立即恢复。");
        return DKSettingsOnChange(item, ^{
            for (AWEDCFeedCopilotController *controller in gDKCopilotControllers.allObjects) {
                [controller showCopilotView];
            }
        });
    });
}
