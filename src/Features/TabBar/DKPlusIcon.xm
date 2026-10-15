//
//  DKPlusIcon.xm
//  拍摄按钮的自定义图片：设置页选图 → 圆形裁剪 → 存成 PNG。「拍摄按钮」选「自定义图片」时
//  悬浮玻璃圆键与原生拍摄按钮都显示它（见 DKGlassTabBar.xm、DKTabBarAppearance.xm）。
//
//  全程不改抖音自己的拍摄图标，原生按钮只是在它上面盖一层；清除或换回其他选项即回到原样。
//

#import "DKPlusIcon.h"
#import "DKIconCropper.h"
#import "DKGlassTabBar.h"
#import "DKTabBarAppearance.h"
#import "DKUtils.h"
#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"

#import <PhotosUI/PhotosUI.h>
#import <objc/runtime.h>

static char kDKPickerRelayKey;

// 备份恢复时接受的图标：与 DKIconCropper 的输出一致，正方形 PNG，边长 128–512。
static const NSUInteger kDKPlusIconMinSide = 128;
static const NSUInteger kDKPlusIconMaxSide = 512;
static const NSUInteger kDKPlusIconMaxBytes = 4 * 1024 * 1024;

// 弹窗里缩略图/占位文案的高度。
static const CGFloat kDKPreviewSide = 88.0;
static const CGFloat kDKPreviewPadding = 8.0;
static const CGFloat kDKPreviewWidth = 250.0;

#pragma mark - 存储

// 文件是这个功能唯一的状态来源，不另存一个 bool 偏好——两份状态迟早会打架。
// DKKeyPlusIcon 只当设置项的 identifier 用，供液态玻璃守卫在低系统上灰显这一行。
static NSString *DKPlusIconPath(void) {
    static NSString *path = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *support = [NSSearchPathForDirectoriesInDomains(
            NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
        NSString *directory = [support stringByAppendingPathComponent:@"DYKiller"];
        [NSFileManager.defaultManager createDirectoryAtPath:directory
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:NULL];
        path = [directory stringByAppendingPathComponent:@"plus-icon.png"];
    });
    return path;
}

static UIImage *gCustomIcon = nil;
static BOOL gCustomIconLoaded = NO;

UIImage *DKPlusIconCustom(void) {
    if (!gCustomIconLoaded) {
        gCustomIconLoaded = YES;
        gCustomIcon = [UIImage imageWithContentsOfFile:DKPlusIconPath()];
    }
    return gCustomIcon;
}

// 写盘失败时内存也不改：界面显示的与磁盘上的必须是同一件事。
static void DKPlusIconStore(UIImage *icon) {
    NSString *path = DKPlusIconPath();
    if (!icon) {
        [NSFileManager.defaultManager removeItemAtPath:path error:NULL];
        gCustomIconLoaded = YES;
        gCustomIcon = nil;
        return;
    }
    NSData *data = UIImagePNGRepresentation(icon);
    if (!data || ![data writeToFile:path atomically:YES]) return;
    gCustomIconLoaded = YES;
    gCustomIcon = icon;
}

// 文件被备份恢复替换或删除后，丢掉内存里的旧图，下次取图重新读盘。
static void DKPlusIconReload(void) {
    gCustomIconLoaded = NO;
    gCustomIcon = nil;
    DKTabBarAppearanceRefresh();
}

static NSString *DKPlusIconDetail(void) {
    return DKPlusIconCustom() ? @"已自定义" : @"抖音默认";
}

// detail 一律按落地后的真实状态重取，不按「打算设成什么」写。
// 清除图片时若「拍摄按钮」正选着自定义图片，一并改回默认：这是交互动作，不放进 onChange，
// 免得备份恢复依次调 onChange 时改写刚恢复的值。
static void DKPlusIconDidChange(AWESettingItemModel *item) {
    DKTabBarAppearanceRefresh();
    if (item) item.detail = DKPlusIconDetail();
    DKSettingsReloadCurrentPage();
}

static void DKPlusIconApply(UIImage *icon, AWESettingItemModel *item) {
    DKPlusIconStore(icon);
    if (!icon && DKPrefInteger(DKKeyPlusStyle) == DKPlusStyleCustom) {
        [NSUserDefaults.standardUserDefaults setInteger:DKPlusStyleDefault forKey:DKKeyPlusStyle];
    }
    DKPlusIconDidChange(item);
}

#pragma mark - 裁剪

// completion 只在写盘成功后以 YES 调用；取消裁剪、写盘失败都以 NO 调用。
static void DKPlusIconPresentCropper(UIViewController *presenter, UIImage *image, void (^completion)(BOOL picked)) {
    if (!presenter || !image) {
        if (completion) completion(NO);
        return;
    }
    DKIconCropper *cropper = [[DKIconCropper alloc] initWithImage:image completion:^(UIImage *cropped) {
        BOOL stored = NO;
        if (cropped) {
            DKPlusIconStore(cropped);
            stored = DKPlusIconCustom() == cropped;
        }
        if (completion) completion(stored);
    }];
    if (cropper) [presenter presentViewController:cropper animated:YES completion:nil];
    else if (completion) completion(NO);
}

#pragma mark - 相册

@interface DKPlusIconPickerRelay : NSObject <PHPickerViewControllerDelegate>
@property (nonatomic, weak) UIViewController *presenter;
@property (nonatomic, copy) void (^completion)(BOOL picked);
@end

@implementation DKPlusIconPickerRelay

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    NSItemProvider *provider = results.firstObject.itemProvider;
    // 只捕获目标对象，不捕获 self：relay 挂在 picker 上，picker 一消失它就走了，
    // 而取图是异步的，回来时 self 早已为 nil。
    __weak UIViewController *presenter = self.presenter;
    void (^completion)(BOOL) = self.completion;

    // 裁剪页要等相册收完再开：present 不能压在别人的 dismiss 动画上。
    [picker dismissViewControllerAnimated:YES completion:^{
        if (![provider canLoadObjectOfClass:UIImage.class]) {
            if (completion) completion(NO);
            return;
        }
        [provider loadObjectOfClass:UIImage.class
                  completionHandler:^(UIImage *image, __unused NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (![image isKindOfClass:UIImage.class]) {
                    if (completion) completion(NO);
                    return;
                }
                DKPlusIconPresentCropper(presenter, image, completion);
            });
        }];
    }];
}

@end

// 不建 PHPhotoLibrary，走进程外选取：不申请相册权限，也就不弹权限请求。
void DKPlusIconPick(UIViewController *presenter, void (^completion)(BOOL picked)) {
    if (!presenter) {
        if (completion) completion(NO);
        return;
    }

    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.filter = PHPickerFilter.imagesFilter;
    configuration.selectionLimit = 1;

    PHPickerViewController *picker =
        [[PHPickerViewController alloc] initWithConfiguration:configuration];
    DKPlusIconPickerRelay *relay = [[DKPlusIconPickerRelay alloc] init];
    relay.presenter = presenter;
    relay.completion = completion;
    picker.delegate = relay;
    // delegate 是弱引用，relay 得跟着 picker 一起活着。
    objc_setAssociatedObject(picker, &kDKPickerRelayKey, relay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [presenter presentViewController:picker animated:YES completion:nil];
}

#pragma mark - 弹窗

// 居中必须用约束，不能用 frame + autoresizing：box.view 建出来时是整屏宽，
// 之后被 alert 压到自己的内容宽度，autoresizing 按【建立时】的左右余量等比分配，
// 于是内容会偏向余量小的一侧——实测缩略图明显偏左。
static UIViewController *DKPlusIconPreviewBox(UIImage *icon) {
    UIViewController *box = [[UIViewController alloc] init];
    box.preferredContentSize = CGSizeMake(kDKPreviewWidth, kDKPreviewSide + kDKPreviewPadding * 2.0);

    UIView *content = nil;
    if (icon) {
        UIImageView *thumbnail = [[UIImageView alloc] initWithImage:icon];
        thumbnail.contentMode = UIViewContentModeScaleAspectFit;
        content = thumbnail;
    } else {
        UILabel *label = [[UILabel alloc] init];
        label.text = @"选择图标";
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont systemFontOfSize:15.0];
        label.textColor = UIColor.secondaryLabelColor;
        content = label;
    }

    content.translatesAutoresizingMaskIntoConstraints = NO;
    [box.view addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.centerXAnchor constraintEqualToAnchor:box.view.centerXAnchor],
        [content.topAnchor constraintEqualToAnchor:box.view.topAnchor constant:kDKPreviewPadding],
        [content.widthAnchor constraintEqualToConstant:kDKPreviewSide],
        [content.heightAnchor constraintEqualToConstant:kDKPreviewSide]
    ]];
    return box;
}

static void DKPlusIconShowDialog(AWESettingItemModel *item, UIViewController *presenter) {
    UIImage *icon = DKPlusIconCustom();
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"更换拍摄图标"
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert setValue:DKPlusIconPreviewBox(icon) forKey:@"contentViewController"];

    __weak AWESettingItemModel *weakItem = item;
    __weak UIViewController *weakPresenter = presenter;

    UIAlertAction *clear = [UIAlertAction actionWithTitle:@"清除"
                                                    style:UIAlertActionStyleDestructive
                                                  handler:^(__unused UIAlertAction *action) {
        DKPlusIconApply(nil, weakItem);
    }];
    clear.enabled = icon != nil;
    [alert addAction:clear];

    [alert addAction:[UIAlertAction actionWithTitle:@"选择"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        // 退一拍再开相册：直接 present 会压在 alert 自己的消失动画上。
        dispatch_async(dispatch_get_main_queue(), ^{
            DKPlusIconPick(weakPresenter, ^(BOOL picked) {
                if (picked) DKPlusIconDidChange(weakItem);
            });
        });
    }]];

    // Alert 点外部不消失，没有这一项就没有退出路径。
    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 设置项注册

%ctor {
    DKSettingsRegister(DKKeyPlusIcon, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeAction(DKKeyPlusIcon, @"更换拍摄图标", DKPlusIconDetail(),
                                                 ^(AWESettingItemModel *it, UIViewController *presenter) {
            DKPlusIconShowDialog(it, presenter);
        });
        DKSettingsValue *icon = [DKSettingsValue imageWithName:DKKeyPlusIcon path:DKPlusIconPath() types:@[ @"public.png" ]
                                                      maxBytes:kDKPlusIconMaxBytes minSide:kDKPlusIconMinSide
                                                       maxSide:kDKPlusIconMaxSide square:YES];
        DKSettingsWithValues(item, @[ icon ], ^NSString *(NSArray *values, __unused BOOL brief) {
            return values[0] == NSNull.null ? @"抖音默认" : @"已自定义";
        });
        DKSettingsOnChange(item, ^{ DKPlusIconReload(); });
        return DKSettingsWithInfo(item,
            @"从相册选一张图片裁成圆形，作为拍摄按钮的图标；需在「拍摄按钮」中选择「自定义图片」。"
            @"悬浮玻璃底栏与抖音原生底栏都生效；点「清除」删除图片并把「拍摄按钮」改回默认。");
    });
}
