// 作品分享面板：在原生数据装入时统一收录与过滤功能按钮。
#import "DouyinHeaders.h"
#import "DKShareMenu.h"
#import <objc/runtime.h>

static char kDKShareMenuWorkContextKey;

%hook AWESharePanelFunctionsDataManager

- (void)fetchSharePanelFunctionConfigWithScene:(id)scene shareContext:(AWEShareContext *)context
                         customConfiguration:(id)configuration shareView:(id)shareView {
    BOOL work = [context respondsToSelector:@selector(aweme)] && context.aweme != nil;
    objc_setAssociatedObject(self, &kDKShareMenuWorkContextKey, @(work), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
}

- (void)setDataSource:(NSArray *)dataSource {
    if ([objc_getAssociatedObject(self, &kDKShareMenuWorkContextKey) boolValue]) {
        dataSource = DKShareMenuFilter(dataSource);
    }
    %orig(dataSource);
}

%end
