//
//  DKPlaybackCleanRules.m
//  DYKiller
//
//  识别口径（40.7.0 实机，见 docs/playback-clean.md）：
//   - 整行项按元素类判定；锚点、模板底栏、抖音精选、私信回复栏再按元素自带的标识区分。
//   - 标签元素的三个子视图取元素自己的属性；好友推荐是关系标签里只剩好友推荐视图可见的形态。
//   - 昵称右侧标签取作者元素标签管理器的已激活组件及其 tagView。
//

#import "DKPlaybackCleanRules.h"
#import "DKKeys.h"

static id DKCleanValue(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *DKCleanString(id object, NSString *key) {
    id value = DKCleanValue(object, key);
    if (![value isKindOfClass:NSString.class]) return nil;
    return [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static UIView *DKCleanViewValue(id object, NSString *key) {
    id value = DKCleanValue(object, key);
    return [value isKindOfClass:UIView.class] ? value : nil;
}

static BOOL DKCleanIsKind(id object, NSString *className) {
    Class cls = NSClassFromString(className);
    return cls && [object isKindOfClass:cls];
}

static UIView *DKCleanFindView(UIView *root, Class cls, NSUInteger depth) {
    if (!root || !cls) return nil;
    if ([root isKindOfClass:cls]) return root;
    if (depth == 0) return nil;
    for (UIView *subview in root.subviews) {
        UIView *found = DKCleanFindView(subview, cls, depth - 1);
        if (found) return found;
    }
    return nil;
}

id DKCleanRowElement(UIView *row) {
    if (!DKCleanIsKind(row, @"AWEBaseElementView")) return nil;
    return DKCleanValue(row, @"element");
}

UIView *DKCleanRowForView(UIView *view) {
    Class rowClass = NSClassFromString(@"AWEBaseElementView");
    UIView *candidate = view.superview;
    for (NSUInteger depth = 0; candidate && rowClass && depth < 8; depth++) {
        if ([candidate isKindOfClass:rowClass]) return candidate;
        candidate = candidate.superview;
    }
    return nil;
}

// 锚点：templateAnchorInfo.name，拍同款的名字末尾带空格，比对前去空白。
static NSString *DKCleanAnchorKey(UIView *row) {
    static NSDictionary<NSString *, NSString *> *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"music_star":  DKKeyPlaybackMusicAnchorMode,
            @"poi_poi":     DKKeyPlaybackLocationMode,
            @"prop_effect": DKKeyPlaybackPropEffectMode,
            @"game_pad":    DKKeyPlaybackGameTagMode,
        };
    });
    UIView *anchorView = DKCleanFindView(row, NSClassFromString(@"AWEFeedTemplateAnchorViewV2"), 4);
    id info = DKCleanValue(anchorView, @"templateAnchorInfo");
    NSString *name = DKCleanString(info, @"name");
    if ([name isEqualToString:@"openplatform_anchor"]) {
        NSString *extra = DKCleanString(info, @"extra");
        NSData *data = [extra dataUsingEncoding:NSUTF8StringEncoding];
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        id base = [json isKindOfClass:NSDictionary.class] ? json[@"base"] : nil;
        if ([base isKindOfClass:NSDictionary.class]
            && [base[@"client_key"] isEqual:@"aw7c4z4ej0o3efzd"]) return DKKeyPlaybackJianyingMode;
    }
    return name ? map[name] : nil;
}

// 底部模板栏：元素 identifier。
static NSString *DKCleanTemplateBarKey(id element) {
    static NSDictionary<NSString *, NSString *> *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"related_search_anchor": DKKeyPlaybackRelatedSearchMode,
            @"playlet_bar":           DKKeyPlaybackVideoCollectionMode,
            @"trending_page":         DKKeyPlaybackHotspotMode,
        };
    });
    NSString *identifier = DKCleanString(element, @"identifier");
    return identifier ? map[identifier] : nil;
}

NSString *DKCleanKeyForRow(UIView *row) {
    id element = DKCleanRowElement(row);
    if (!element) return nil;
    if (DKCleanIsKind(element, @"AWEPlayInteractionDanmakuElement")) return DKKeyPlaybackDanmakuMode;
    if (DKCleanIsKind(element, @"AWEPlayInteractionRiskNoticeElement")) return DKKeyPlaybackRiskNoticeMode;
    if (DKCleanIsKind(element, @"AWEPlayInteractionECommerceEntryElement")) return DKKeyPlaybackStoreMode;
    if (DKCleanIsKind(element, @"AWEPlayInteractionMusicInfoAiRefactorElement")
        || DKCleanIsKind(element, @"AWEPlayInteractionMusicInfoElement")) return DKKeyPlaybackMusicInfoMode;
    if (DKCleanIsKind(element, @"AWEPlayInteractionNewDiversionBarBottomElement")) return DKKeyPlaybackAppDownloadMode;
    if (DKCleanIsKind(element, @"AWEPlayInteractionAnchorElement")) return DKCleanAnchorKey(row);
    if (DKCleanIsKind(element, @"AWETemplateNewBottomElement")) return DKCleanTemplateBarKey(element);
    if (DKCleanIsKind(element, @"AWEPlayInteractionTagsElementV2")) {
        return [DKCleanString(element, @"businessID") isEqualToString:@"daily_recommend"] ? DKKeyPlaybackSelectedMode : nil;
    }
    if (DKCleanIsKind(element, @"AWEPlayInteractionBottomButtonElement")) {
        return [DKCleanString(element, @"identifier") isEqualToString:@"unread_video_im"] ? DKKeyPlaybackQuickReplyMode : nil;
    }
    return nil;
}

BOOL DKCleanIsTagsElement(id element) {
    return DKCleanIsKind(element, @"AWEPlayInteractionTagsElement");
}

// 好友推荐时关系标签里只有 AFDFriendRecommendTagView 可见，其余子视图全部隐藏。
static BOOL DKCleanRelationShowsFriendRecommend(UIView *relation) {
    Class friendClass = NSClassFromString(@"AFDFriendRecommendTagView");
    if (!friendClass) return NO;
    BOOL friendShown = NO;
    for (UIView *subview in relation.subviews) {
        if ([subview isKindOfClass:friendClass]) {
            if (!subview.hidden) friendShown = YES;
        } else if (!subview.hidden) {
            return NO;
        }
    }
    return friendShown;
}

void DKCleanEnumerateTagsElementViews(id element, void (^block)(UIView *view, NSString *key)) {
    if (!block || !DKCleanIsTagsElement(element)) return;
    UIView *entrance = DKCleanViewValue(element, @"recommendEntranceLabel");
    if (entrance) block(entrance, DKKeyPlaybackOtherUserRecommendMode);
    UIView *relation = DKCleanViewValue(element, @"dynamicLabel");
    if (relation && DKCleanRelationShowsFriendRecommend(relation)) block(relation, DKKeyPlaybackFriendRecommendMode);
    UIView *shared = DKCleanViewValue(element, @"imUnreadSharedVideoTagView");
    if (shared) block(shared, DKKeyPlaybackFriendShareMode);
}

static NSString *DKCleanTagComponentKey(id component) {
    if (DKCleanIsKind(component, @"AWEChapterTagComponent")) return DKKeyPlaybackChapterHighlightsMode;
    if (DKCleanIsKind(component, @"AWECoCreatorTagComponent")) return DKKeyPlaybackCoCreatorMode;
    if (DKCleanIsKind(component, @"AWESlidesTagComponent")
        || DKCleanIsKind(component, @"AWERichAwemeTagComponent")) return DKKeyPlaybackSlidesTagMode;
    return nil;
}

void DKCleanEnumerateManagerTags(id manager, void (^block)(UIView *tagView, NSString *key)) {
    if (!block || !manager) return;
    id components = DKCleanValue(manager, @"activedComponents");
    if (![components isKindOfClass:NSArray.class]) return;
    for (id component in (NSArray *)components) {
        NSString *key = DKCleanTagComponentKey(component);
        if (!key) continue;
        UIView *tagView = DKCleanViewValue(component, @"tagView");
        if (tagView) block(tagView, key);
    }
}

void DKCleanEnumerateAuthorTags(id element, void (^block)(UIView *tagView, NSString *key)) {
    if (!element || ![element respondsToSelector:NSSelectorFromString(@"tagsManager")]) return;
    DKCleanEnumerateManagerTags(DKCleanValue(element, @"tagsManager"), block);
}
