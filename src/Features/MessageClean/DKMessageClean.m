//
//  DKMessageClean.m
//  DYKiller
//
//  消息页精简的刷新入口与诊断：汇总顶栏与列表顶部两部分。
//

#import "DKMessageClean.h"
#import "DKKeys.h"
#import "DKUtils.h"

void DKMessageCleanRefresh(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKMessageCleanRefresh(); });
        return;
    }
    DKMessageCleanTopBarRefresh();
    DKMessageCleanListRefresh();
}

static NSString *DKMessageCleanModeText(DKDisplayMode mode) {
    switch (mode) {
        case DKDisplayModeHide: return @"隐藏";
        case DKDisplayModeRemove: return @"移除";
        default: return @"显示";
    }
}

NSString *DKMessageCleanStatus(void) {
    NSArray<NSArray<NSString *> *> *items = @[
        @[ DKKeyMessageSideBarMode, @"左侧栏" ],
        @[ DKKeyMessageSlotMode, @"装扮商店" ],
        @[ DKKeyMessageSearchMode, @"搜索图标" ],
        @[ DKKeyMessagePlusMode, @"加号" ],
        @[ DKKeyMessageDailyMode, @"限时日常" ],
        @[ DKKeyMessageFriendAvatarMode, @"好友大头像" ],
        @[ DKKeyMessageInteractionMode, @"互动消息" ],
    ];
    NSMutableArray<NSString *> *modes = [NSMutableArray array];
    for (NSArray<NSString *> *item in items) {
        [modes addObject:[NSString stringWithFormat:@"%@=%@", item[1], DKMessageCleanModeText(DKPrefDisplayMode(item[0]))]];
    }
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"档位：%@\n", [modes componentsJoinedByString:@" "]];
    [out appendString:DKMessageCleanTopBarStatus()];
    [out appendString:DKMessageCleanListStatus()];
    return out;
}
