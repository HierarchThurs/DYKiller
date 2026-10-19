//
//  DKSettingsColorEditors.h
//  颜色设置的两个编辑页：固定颜色的色谱 / RGB 选色页，十六进制与渐变的文字输入页。仅供 src/Settings 使用。
//  只有点保存才回调；回调值为规范值（#RRGGBB 或逗号分隔的渐变）。
//

#import "DKSettings.h"

@interface DKColorPickerController : UIViewController
- (instancetype)initWithTitle:(NSString *)title color:(NSString *)hex sample:(DKColorSample *)sample
                   completion:(void (^)(NSString *hex))completion;
@end

@interface DKColorTextController : UIViewController
- (instancetype)initWithTitle:(NSString *)title value:(NSString *)value gradient:(BOOL)gradient
                       sample:(DKColorSample *)sample completion:(void (^)(NSString *value))completion;
@end
