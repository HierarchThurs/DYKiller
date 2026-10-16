//
//  DKSettingsMigration.m
//  已改为三档单选的旧开关：旧键为开且新键未写过时，新键记为「移除」（2），随后删掉旧键。
//

#import <Foundation/Foundation.h>
#import "DKKeys.h"

static const NSInteger kDKMigratedRemoveMode = 2;

static void DKMigrateSwitchesToModes(void) {
    NSDictionary<NSString *, NSString *> *map = @{
        @"DYKillerHideMusicInfo":         DKKeyPlaybackMusicInfoMode,
        @"DYKillerHideCommentBottomBar":  DKKeyCommentReplyBottomBarMode,
        @"DYKillerHideFollowButton":      DKKeyFollowButtonDisplay,
    };
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    BOOL changed = NO;
    for (NSString *oldKey in map) {
        id oldValue = [defaults objectForKey:oldKey];
        if (!oldValue) continue;
        NSString *newKey = map[oldKey];
        if ([oldValue respondsToSelector:@selector(boolValue)] && [oldValue boolValue] && ![defaults objectForKey:newKey]) {
            [defaults setInteger:kDKMigratedRemoveMode forKey:newKey];
        }
        [defaults removeObjectForKey:oldKey];
        changed = YES;
    }
    if (changed) [defaults synchronize];
}

__attribute__((constructor))
static void DKSettingsMigrationCtor(void) {
    DKMigrateSwitchesToModes();
}
