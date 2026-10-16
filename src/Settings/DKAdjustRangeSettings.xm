//
//  DKAdjustRangeSettings.xm
//  DYKiller
//
//  插件工具 —— 扩展所有缩放与位移。
//
//  实现：
//   - 开启前弹风险确认，清单由 DKAdjustRange 登记表生成：按「种类 + 常规范围」合并成行，行内列出各项设置标题。
//   - 开关变化后逐项执行登记项的 onChange，各功能按新的生效范围重新应用；关闭不改写存值，取值处钳到常规范围。
//   - 风险开关须本人确认，不进备份，恢复与恢复默认都不改它；各项数值本身照常备份。
//

#import "DKAdjustRange.h"
#import "DKKeys.h"
#import "DKSettingsInternal.h"

// 一行清单：「互动按钮缩放、头像缩放：50%–100% → 0%–200%」。先列缩放、再列位移，同类按登记顺序。
static NSArray<NSString *> *DKAdjustConfirmLines(void) {
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (NSNumber *kind in @[ @(DKAdjustKindScale), @(DKAdjustKindOffset) ]) {
        for (NSString *key in DKAdjustKeys()) {
            if (DKAdjustKindForKey(key) == kind.integerValue) [keys addObject:key];
        }
    }
    NSMutableArray<NSString *> *ranges = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *titles = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        DKAdjustKind kind = DKAdjustKindForKey(key);
        DKAdjustBounds extended = DKAdjustExtendedBounds(key);
        NSString *range = [NSString stringWithFormat:@"%@ → %@%@",
                           DKAdjustBoundsText(kind, DKAdjustNormalBounds(key)), DKAdjustBoundsText(kind, extended),
                           kind == DKAdjustKindOffset && extended.minimum < 0 ? @"（负值为下移）" : @""];
        NSString *title = DKSettingsBuildItem(key).title ?: key;
        if (!titles[range]) {
            titles[range] = [NSMutableArray array];
            [ranges addObject:range];
        }
        [titles[range] addObject:title];
    }
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *range in ranges) {
        [lines addObject:[NSString stringWithFormat:@"· %@：%@", [titles[range] componentsJoinedByString:@"、"], range]];
    }
    return lines;
}

static NSAttributedString *DKAdjustConfirmMessage(void) {
    NSString *text = [NSString stringWithFormat:
        @"各项缩放与位移的常规范围，是按抖音界面的最佳显示效果设定的。开启后，以下设置可超出常规范围调整：\n\n"
        @"%@\n\n"
        @"超出常规范围的数值会按现有计算规则直接生效，本插件不保证其显示效果。过于激进的调整可能导致元素重叠、遮挡、"
        @"超出屏幕或无法点击，甚至影响抖音的正常使用。开启即表示您已了解上述风险，并自行承担由此产生的一切后果。\n\n"
        @"关闭本开关后，所有数值立即回到常规范围内生效；已保存的数值会保留，重新开启后恢复。",
        [DKAdjustConfirmLines() componentsJoinedByString:@"\n"]];
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentLeft;
    style.paragraphSpacing = 2.0;
    return [[NSAttributedString alloc] initWithString:text attributes:@{
        NSParagraphStyleAttributeName: style,
        NSFontAttributeName: [UIFont systemFontOfSize:13.0],
        NSForegroundColorAttributeName: UIColor.labelColor,
    }];
}

static void DKAdjustConfirm(UIViewController *presenter, dispatch_block_t commit) {
    NSAttributedString *message = DKAdjustConfirmMessage();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"开启扩展调整范围？" message:message.string
                                                            preferredStyle:UIAlertControllerStyleAlert];
    // 清单与风险说明较长，左对齐便于阅读；系统不支持时保留居中的普通文字。
    @try {
        [alert setValue:message forKey:@"attributedMessage"];
    } @catch (__unused NSException *exception) {
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"我已了解，开启" style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *action) { commit(); }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

// 生效范围变了，让每个登记项按新范围重新应用。
static void DKAdjustRefreshAll(void) {
    for (NSString *key in DKAdjustKeys()) {
        dispatch_block_t onChange = DKSettingsItemOnChange(DKSettingsBuildItem(key));
        if (onChange) onChange();
    }
}

%ctor {
    DKSettingsRegister(DKKeyAdjustRangeExtended, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitchConfirmingOn(DKKeyAdjustRangeExtended, @"扩展所有缩放与位移",
            @"放宽各项缩放与位移设置的可调范围，超出常规范围的显示效果不作保证。开启前会列出各项的扩展范围并需确认风险；"
            @"关闭后所有数值立即回到常规范围内生效，已保存的数值保留。",
            ^(UIViewController *presenter, dispatch_block_t commit) { DKAdjustConfirm(presenter, commit); });
        DKSettingsOnChange(item, ^{ DKAdjustRefreshAll(); });
        return DKSettingsWithoutBackup(item);
    });
}
