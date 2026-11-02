//
//  DKSettingsColorEditors.h
//  颜色编辑入口：系统颜色选择器（带不透明度）、单行十六进制输入页、渐变颜色页。仅供 src/Settings 使用。
//  只有确认后才回调；回调值为规范值（#AARRGGBB 或逗号分隔的 #AARRGGBB 渐变）。
//

#import "DKSettings.h"

/// 以系统 UIColorPickerViewController 选色，关闭时回调；allowsAlpha 为 NO 时不提供不透明度。
void DKSettingsPresentSystemColorPicker(UIViewController *presenter, NSString *title, NSString *storedHex,
                                        BOOL allowsAlpha, void (^completion)(NSString *hex));

@interface DKColorTextController : UIViewController
- (instancetype)initWithTitle:(NSString *)title value:(NSString *)value sample:(DKColorSample *)sample
                   completion:(void (^)(NSString *value))completion;
@end

/// 渐变颜色设置子页面：预览、逐色系统选择器/十六进制、拖动排序、删除、添加、整条不透明度。
@interface DKGradientColorController : UIViewController
- (instancetype)initWithTitle:(NSString *)title value:(NSString *)gradient sample:(DKColorSample *)sample
                   completion:(void (^)(NSString *value))completion;
@end
