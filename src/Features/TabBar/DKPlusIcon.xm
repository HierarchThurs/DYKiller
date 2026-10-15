//
//  DKPlusIcon.xm
//  拍摄圆键的自定义图标：设置页选图 → 圆形裁剪 → 存成 PNG，圆键取图时优先用它。
//
//  全程不碰抖音自己的拍摄图标 image view，只改 DYKiller 圆键的取图来源，
//  所以「不覆盖原生图标」是结构性成立的——清除后取图自然回落到镜像抖音那条老路径。
//

#import "DKPlusIcon.h"
#import "DKIconCropper.h"
#import "DKGlassTabBar.h"
#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"

#import <PhotosUI/PhotosUI.h>
#import <objc/runtime.h>

static char kDKPickerRelayKey;

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

static NSString *DKPlusIconDetail(void) {
    return DKPlusIconCustom() ? @"已自定义" : @"抖音默认";
}

// detail 一律按落地后的真实状态重取，不按「打算设成什么」写。
static void DKPlusIconApply(UIImage *icon, AWESettingItemModel *item) {
    DKPlusIconStore(icon);
    DKGlassTabBarRefresh();
    if (item) item.detail = DKPlusIconDetail();
    DKSettingsReloadCurrentPage();
}

#pragma mark - 裁剪

static void DKPlusIconPresentCropper(UIViewController *presenter, UIImage *image,
                                     AWESettingItemModel *item) {
    if (!presenter || !image) return;
    __weak AWESettingItemModel *weakItem = item;
    DKIconCropper *cropper = [[DKIconCropper alloc] initWithImage:image
                                                       completion:^(UIImage *cropped) {
        if (cropped) DKPlusIconApply(cropped, weakItem);
    }];
    if (cropper) [presenter presentViewController:cropper animated:YES completion:nil];
}

#pragma mark - 相册

@interface DKPlusIconPickerRelay : NSObject <PHPickerViewControllerDelegate>
@property (nonatomic, weak) UIViewController *presenter;
@property (nonatomic, weak) AWESettingItemModel *item;
@end

@implementation DKPlusIconPickerRelay

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    NSItemProvider *provider = results.firstObject.itemProvider;
    // 只捕获目标对象，不捕获 self：relay 挂在 picker 上，picker 一消失它就走了，
    // 而取图是异步的，回来时 self 早已为 nil。
    __weak UIViewController *presenter = self.presenter;
    __weak AWESettingItemModel *item = self.item;

    // 裁剪页要等相册收完再开：present 不能压在别人的 dismiss 动画上。
    [picker dismissViewControllerAnimated:YES completion:^{
        if (![provider canLoadObjectOfClass:UIImage.class]) return;
        [provider loadObjectOfClass:UIImage.class
                  completionHandler:^(UIImage *image, __unused NSError *error) {
            if (![image isKindOfClass:UIImage.class]) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                DKPlusIconPresentCropper(presenter, image, item);
            });
        }];
    }];
}

@end

// 不建 PHPhotoLibrary，走进程外选取：不申请相册权限，也就不弹权限请求。
static void DKPlusIconPresentPicker(UIViewController *presenter, AWESettingItemModel *item) {
    if (!presenter) return;

    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.filter = PHPickerFilter.imagesFilter;
    configuration.selectionLimit = 1;

    PHPickerViewController *picker =
        [[PHPickerViewController alloc] initWithConfiguration:configuration];
    DKPlusIconPickerRelay *relay = [[DKPlusIconPickerRelay alloc] init];
    relay.presenter = presenter;
    relay.item = item;
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
            DKPlusIconPresentPicker(weakPresenter, weakItem);
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
        return DKSettingsWithInfo(item,
            @"从相册选一张图片裁成圆形，替换悬浮玻璃底栏中间的拍摄按钮图标；点「清除」恢复抖音默认图标。");
    });
}
