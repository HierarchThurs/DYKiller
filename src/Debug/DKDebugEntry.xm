//
//  DKDebugEntry.xm
//  DYKiller
//
//  注册调试开关，并在前台窗口变化时同步全局调试浮层。
//

#import "DKDebugInspector.h"
#import "DKAudioProbe.h"
#import "DKKeys.h"
#import "DKSettings.h"

static BOOL DKEntryIsDebugWindow(UIWindow *window) {
    return [NSStringFromClass(window.class) hasPrefix:@"DKDebug"];
}

static AWESettingItemModel *DKMakeDebugSwitch(void) {
    AWESettingItemModel *item = DKMakeSwitch(DKKeyDebugInspectorEnabled, @"调试工具", @"开启后显示全局扳手入口");
    void (^origBlock)(void) = [item.switchChangedBlock copy];
    item.switchChangedBlock = ^{
        if (origBlock) origBlock();
        DKAudioProbePreferenceDidChange();
        DKDebugInspectorRefreshOverlay();
    };
    return item;
}

%hook UIWindow

- (void)becomeKeyWindow {
    %orig;
    if (!DKEntryIsDebugWindow(self)) DKDebugInspectorRefreshOverlay();
}

- (void)makeKeyAndVisible {
    %orig;
    if (!DKEntryIsDebugWindow(self)) DKDebugInspectorRefreshOverlay();
}

- (void)setHidden:(BOOL)hidden {
    %orig(hidden);
    if (!hidden && !DKEntryIsDebugWindow(self)) DKDebugInspectorRefreshOverlay();
}

%end

%ctor {
    DKAudioProbeInstallIfEnabled(YES);
    // 调试入口按设备临时开关，不进备份，恢复与恢复默认都不改它。
    DKSettingsRegister(DKKeyDebugInspectorEnabled, ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeDebugSwitch());
    });
    DKDebugInspectorInstall();
}
