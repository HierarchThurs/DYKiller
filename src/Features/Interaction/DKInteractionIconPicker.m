#import "DKInteractionIconPicker.h"
#import "DKInteractionIconAssets.h"
#import "DKInteractionIcons.h"
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>

static char kDKIconPickerRelay;
static BOOL gDKIconPickerBusy;

static void DKIconShowError(UIViewController *presenter, NSString *message) {
    if (!presenter.view.window) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法设置图标" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

@interface DKInteractionIconPickerRelay : NSObject <PHPickerViewControllerDelegate, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate>
@property (nonatomic, weak) UIViewController *presenter;
@property (nonatomic) DKInteractionIconSlot slot;
@property (nonatomic, copy) void (^didChange)(BOOL hasImage);
@end

@implementation DKInteractionIconPickerRelay
- (void)importURL:(NSURL *)url album:(BOOL)album {
    // NSItemProvider 的 URL 只在回调期间有效，必须在返回前把数据读入自己的内存。
    BOOL access = [url startAccessingSecurityScopedResource];
    NSNumber *length = nil;
    [url getResourceValue:&length forKey:NSURLFileSizeKey error:NULL];
    NSData *data = url && length && length.unsignedLongLongValue <= 16 * 1024 * 1024
        ? [NSData dataWithContentsOfURL:url options:0 error:NULL] : nil;
    if (access) [url stopAccessingSecurityScopedResource];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *reason = nil;
        NSData *normalized = DKInteractionIconNormalize(data, album, &reason);
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *writeReason = reason;
            BOOL stored = normalized && DKInteractionIconStore(self.slot, normalized, &writeReason);
            gDKIconPickerBusy = NO;
            if (!stored) { DKIconShowError(self.presenter, writeReason ?: @"无法读取图片文件"); return; }
            DKInteractionIconsRefresh();
            if (self.didChange) self.didChange(YES);
        });
    });
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    NSItemProvider *provider = results.firstObject.itemProvider;
    [picker dismissViewControllerAnimated:YES completion:^{
        if (!provider) { gDKIconPickerBusy = NO; return; }
        [provider loadFileRepresentationForTypeIdentifier:UTTypeImage.identifier completionHandler:^(NSURL *url, NSError *error) {
            [self importURL:url album:YES];
        }];
    }];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    [controller dismissViewControllerAnimated:YES completion:^{
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ [self importURL:url album:NO]; });
    }];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    gDKIconPickerBusy = NO;
}
- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    gDKIconPickerBusy = NO;
}
@end

static void DKIconPresentSource(DKInteractionIconSlot slot, UIViewController *presenter, BOOL album, void (^didChange)(BOOL)) {
    if (!presenter.view.window || presenter.presentedViewController || gDKIconPickerBusy) return;
    gDKIconPickerBusy = YES;
    UIViewController *picker;
    DKInteractionIconPickerRelay *relay = [[DKInteractionIconPickerRelay alloc] init];
    relay.presenter = presenter;
    relay.slot = slot;
    relay.didChange = didChange;
    if (album) {
        PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
        configuration.filter = PHPickerFilter.imagesFilter;
        configuration.selectionLimit = 1;
        PHPickerViewController *photos = [[PHPickerViewController alloc] initWithConfiguration:configuration];
        photos.delegate = relay;
        picker = photos;
    } else {
        UIDocumentPickerViewController *files = [[UIDocumentPickerViewController alloc]
            initForOpeningContentTypes:@[ UTTypePNG, UTTypeSVG ] asCopy:YES];
        files.delegate = relay;
        picker = files;
    }
    objc_setAssociatedObject(picker, &kDKIconPickerRelay, relay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [presenter presentViewController:picker animated:YES completion:nil];
    picker.presentationController.delegate = relay;
}

static UIViewController *DKIconPreview(DKInteractionIconSlot slot) {
    UIViewController *box = [[UIViewController alloc] init];
    box.preferredContentSize = CGSizeMake(250, 120);
    UIImageView *thumbnail = [[UIImageView alloc] initWithImage:DKInteractionIconCustom(slot, CGSizeMake(88, 88), UIScreen.mainScreen.scale)];
    thumbnail.contentMode = UIViewContentModeScaleAspectFit;
    thumbnail.backgroundColor = [UIColor colorWithWhite:.16 alpha:1];
    thumbnail.layer.cornerRadius = 12;
    thumbnail.clipsToBounds = YES;
    UILabel *detail = [[UILabel alloc] init];
    NSString *text = DKInteractionIconDataDetail(DKInteractionIconData(slot));
    detail.text = [text isEqualToString:@"未设置"] ? text : [@"当前：" stringByAppendingString:text];
    detail.font = [UIFont systemFontOfSize:13];
    detail.textColor = UIColor.secondaryLabelColor;
    detail.textAlignment = NSTextAlignmentCenter;
    for (UIView *view in @[ thumbnail, detail ]) { view.translatesAutoresizingMaskIntoConstraints = NO; [box.view addSubview:view]; }
    [NSLayoutConstraint activateConstraints:@[
        [thumbnail.centerXAnchor constraintEqualToAnchor:box.view.centerXAnchor],
        [thumbnail.topAnchor constraintEqualToAnchor:box.view.topAnchor constant:4],
        [thumbnail.widthAnchor constraintEqualToConstant:88], [thumbnail.heightAnchor constraintEqualToConstant:88],
        [detail.topAnchor constraintEqualToAnchor:thumbnail.bottomAnchor constant:8],
        [detail.centerXAnchor constraintEqualToAnchor:box.view.centerXAnchor],
        [detail.widthAnchor constraintLessThanOrEqualToAnchor:box.view.widthAnchor constant:-16],
    ]];
    return box;
}

void DKInteractionIconShowPicker(DKInteractionIconSlot slot, UIViewController *presenter, void (^didChange)(BOOL)) {
    if (!presenter || gDKIconPickerBusy) return;
    UIViewController *presented = presenter.presentedViewController;
    if ([presented isKindOfClass:UIAlertController.class]) {
        [presented dismissViewControllerAnimated:YES completion:^{ DKInteractionIconShowPicker(slot, presenter, didChange); }];
        return;
    }
    if (presented) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[DKInteractionIconTitle(slot) stringByAppendingString:@"图标"]
        message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert setValue:DKIconPreview(slot) forKey:@"contentViewController"];
    __weak UIAlertController *weakAlert = alert;
    for (NSNumber *source in @[ @YES, @NO ]) {
        [alert addAction:[UIAlertAction actionWithTitle:source.boolValue ? @"从相册选择" : @"从文件选择"
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                // 等预览弹窗完成退出后再打开系统选择器。
                [weakAlert dismissViewControllerAnimated:YES completion:^{ DKIconPresentSource(slot, presenter, source.boolValue, didChange); }];
            }]];
    }
    UIAlertAction *clear = [UIAlertAction actionWithTitle:@"清除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSString *reason = nil;
        if (!DKInteractionIconStore(slot, nil, &reason)) {
            dispatch_async(dispatch_get_main_queue(), ^{ DKIconShowError(presenter, reason); });
            return;
        }
        DKInteractionIconsRefresh();
        if (didChange) didChange(NO);
    }];
    clear.enabled = DKInteractionIconData(slot) != nil;
    [alert addAction:clear];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}
