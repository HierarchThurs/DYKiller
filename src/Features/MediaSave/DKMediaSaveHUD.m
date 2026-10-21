#import "DKMediaSaveHUD.h"
#import "DKPrompt.h"

@implementation DKMediaSaveHUD {
    DKMediaHUDScene _scene;
    __weak UIWindowScene *_windowScene;
    dispatch_block_t _onCancel;
    DKPromptSession *_session;
    BOOL _finished;
}
- (instancetype)initWithScene:(DKMediaHUDScene)scene windowScene:(UIWindowScene *)windowScene onCancel:(dispatch_block_t)onCancel {
    if ((self = [super init])) {
        _scene = scene;
        _windowScene = windowScene;
        _onCancel = [onCancel copy];
    }
    return self;
}
- (UIImage *)glyphForState:(DKMediaHUDState)state {
    NSString *name;
    switch (state) {
        case DKMediaHUDStateSuccess: name = @"checkmark"; break;
        case DKMediaHUDStateCancelled: name = @"xmark"; break;
        case DKMediaHUDStateFailure: name = @"exclamationmark"; break;
        default: {
            NSArray *names = @[ @"arrow.down.to.line", @"photo", @"livephoto", @"photo.on.rectangle",
                                @"square.stack", @"face.smiling", @"music.note" ];
            name = names[_scene];
            break;
        }
    }
    return [UIImage systemImageNamed:name withConfiguration:
        [UIImageSymbolConfiguration configurationWithPointSize:13.0 weight:UIImageSymbolWeightSemibold]];
}
- (DKPromptContent *)contentForState:(DKMediaHUDState)state title:(NSString *)title subtitle:(NSString *)subtitle {
    DKPromptContent *content = [DKPromptContent new];
    content.icon = [self glyphForState:state];
    content.title = title;
    content.subtitle = subtitle;
    switch (state) {
        case DKMediaHUDStateSuccess: content.tone = DKPromptToneSuccess; break;
        case DKMediaHUDStateCancelled: content.tone = DKPromptToneCancelled; break;
        case DKMediaHUDStateFailure: content.tone = DKPromptToneFailure; break;
        default: content.tone = DKPromptToneProcessing; break;
    }
    return content;
}
- (void)showProgress:(NSString *)title fraction:(double)fraction {
    if (_finished) return;
    DKPromptContent *content = [self contentForState:DKMediaHUDStateProgress title:title subtitle:@"点击取消"];
    content.progressMode = DKPromptProgressDeterminate;
    content.progress = fraction;
    content.cardAction = _onCancel;
    _session = DKPromptSubmit(content, _windowScene, @"media_save");
}
- (void)updateProgress:(NSString *)title fraction:(double)fraction {
    if (_finished) return;
    DKPromptContent *content = [self contentForState:DKMediaHUDStateProgress title:title subtitle:@"点击取消"];
    content.progressMode = DKPromptProgressDeterminate;
    content.progress = fraction;
    content.cardAction = _onCancel;
    [_session update:content];
}
- (void)showResult:(DKMediaHUDState)state title:(NSString *)title subtitle:(NSString *)subtitle {
    if (_finished) return;
    _finished = YES;
    _onCancel = nil;
    DKPromptContent *content = [self contentForState:state title:title subtitle:subtitle];
    if (_session) [_session finish:content];
    else _session = DKPromptPostResult(content, _windowScene, @"media_save");
}
- (void)nudge { if (!_finished) [_session nudge]; }
@end
