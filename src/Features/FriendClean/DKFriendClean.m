//
//  DKFriendClean.m
//  DYKiller
//
//  朋友页精简的刷新入口与诊断：顶栏、私信图标、作品行与标签，以及朋友推荐卡片过滤。
//

#import "DKFriendClean.h"
#import "DKKeys.h"
#import "DKPlaybackClean.h"
#import "DKUtils.h"

void DKFriendCleanRefresh(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKFriendCleanRefresh(); });
        return;
    }
    DKFriendCleanTopBarRefresh();
    DKFriendCleanSendMessageRefresh();
    DKPlaybackCleanRefresh();
}

static NSString *DKFriendCleanModeText(DKDisplayMode mode) {
    switch (mode) {
        case DKDisplayModeHide: return @"隐藏";
        case DKDisplayModeRemove: return @"移除";
        default: return @"显示";
    }
}

NSString *DKFriendCleanStatus(void) {
    NSArray<NSArray<NSString *> *> *items = @[
        @[ DKKeyFriendAvatarEntryMode, @"头像和加号" ],
        @[ DKKeyFriendDailyMode, @"限时日常" ],
        @[ DKKeyFriendButtonMode, @"朋友按钮" ],
        @[ DKKeyFriendRelationTagMode, @"朋友标记" ],
        @[ DKKeyFriendStoryTagMode, @"日常标签" ],
        @[ DKKeyFriendFollowTagMode, @"关注标签" ],
        @[ DKKeyFriendFastReplyMode, @"私信面板" ],
        @[ DKKeyFriendSendMessageMode, @"私信图标" ],
    ];
    NSMutableArray<NSString *> *modes = [NSMutableArray array];
    for (NSArray<NSString *> *item in items) {
        [modes addObject:[NSString stringWithFormat:@"%@=%@", item[1], DKFriendCleanModeText(DKPrefDisplayMode(item[0]))]];
    }
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"档位：%@\n", [modes componentsJoinedByString:@" "]];
    [out appendString:DKFriendCleanTopBarStatus()];
    [out appendString:DKFriendCleanSendMessageStatus()];
    [out appendString:DKFriendRecommendCardStatus()];
    [out appendString:@"朋友标记、关注标签、私信面板与日常标签的状态见「播放页精简」节。\n"];
    return out;
}
