//
//  DKProfileCleanTabs.xm
//  DYKiller
//
//  个人主页精简 —— 移除作品、日常、收藏、喜欢、足迹分页。
//
//  实现：
//   - AWEUserProfileTabHelper.tabArray 懒构建：按服务端顺序逐个类型生成分页模型，存进 _tabArray 并写 _numOfTab，
//     之后直接返回缓存；分页标题 tabTitles 由 tabArray 生成。
//     自己主页上，getter 在 %orig 之后按 profileTabType 去掉开启移除的分页，并把结果写回这两个 ivar，
//     其余读取（标题、下标与类型互查、分页数量）都看到同一份数组。全部分页都被移除时保留原数组。
//   - 设置改动：走抖音自己的刷新路径。updateUser:shouldRefreshTab:YES 把当前数组存为旧数组并清空缓存，
//     p_updateTabView 比较新旧数组，变化时按 landingTabType 定位默认分页并重载分页栏与页面。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKProfileClean.h"
#import "DKUtils.h"
#import <objc/runtime.h>

// 弱表（分页编排组件），只在主线程读写。
static NSHashTable *gDKProfileTabComponents;
static NSString *gDKProfileTabLastFilter;

static NSString *DKProfileTabKey(NSInteger type) {
    switch (type) {
        case 0: return DKKeyProfileRemovePostTab;
        case 38: return DKKeyProfileRemoveDailyTab;
        case 16: return DKKeyProfileRemoveFavoriteTab;
        case 2: return DKKeyProfileRemoveLikeTab;
        case 46: return DKKeyProfileRemoveFootprintTab;
        default: return nil;
    }
}

static BOOL DKProfileTabRemoved(id tab) {
    if (![tab respondsToSelector:@selector(profileTabType)]) return NO;
    NSString *key = DKProfileTabKey([(AWEUserProfileTabModel *)tab profileTabType]);
    return key && DKPrefBool(key);
}

static BOOL DKProfileTabHelperMine(AWEUserProfileTabHelper *helper) {
    return [helper respondsToSelector:@selector(p_isCurrentUser)] && [helper p_isCurrentUser];
}

static NSString *DKProfileTabTypes(NSArray *tabs) {
    NSMutableArray<NSString *> *types = [NSMutableArray arrayWithCapacity:tabs.count];
    for (id tab in tabs) {
        [types addObject:[tab respondsToSelector:@selector(profileTabType)]
            ? [NSString stringWithFormat:@"%ld", (long)[(AWEUserProfileTabModel *)tab profileTabType]] : @"?"];
    }
    return [types componentsJoinedByString:@","];
}

// 把过滤后的数组写回 _tabArray，分页数量写回 _numOfTab；ivar 不存在或类型不符时不写。
static void DKProfileTabStore(AWEUserProfileTabHelper *helper, NSArray *tabs) {
    Class cls = object_getClass(helper);
    Ivar array = class_getInstanceVariable(cls, "_tabArray");
    Ivar count = class_getInstanceVariable(cls, "_numOfTab");
    if (!array || !count) return;
    const char *arrayType = ivar_getTypeEncoding(array), *countType = ivar_getTypeEncoding(count);
    if (!arrayType || arrayType[0] != '@' || !countType || strcmp(countType, @encode(NSInteger)) != 0) return;
    object_setIvarWithStrongDefault(helper, array, tabs);
    *(NSInteger *)((uint8_t *)(__bridge void *)helper + ivar_getOffset(count)) = (NSInteger)tabs.count;
}

static NSArray *DKProfileTabFilter(AWEUserProfileTabHelper *helper, NSArray *tabs) {
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:tabs.count];
    for (id tab in tabs) {
        if (!DKProfileTabRemoved(tab)) [kept addObject:tab];
    }
    if (kept.count == tabs.count) return tabs;
    if (NSThread.isMainThread) {
        gDKProfileTabLastFilter = [NSString stringWithFormat:@"[%@] → [%@]%@", DKProfileTabTypes(tabs), DKProfileTabTypes(kept),
                                   kept.count ? @"" : @"（全部移除，保留原数组）"];
    }
    if (!kept.count) return tabs;
    NSArray *filtered = [kept copy];
    DKProfileTabStore(helper, filtered);
    return filtered;
}

void DKProfileCleanTabsRefresh(void) {
    for (AWEUIOrchestrationHomeComponent *component in gDKProfileTabComponents.allObjects) {
        AWEUserProfileTabHelper *helper = [component respondsToSelector:@selector(tabHelper)] ? [component tabHelper] : nil;
        if (!DKProfileTabHelperMine(helper) || ![helper respondsToSelector:@selector(user)] ||
            ![helper respondsToSelector:@selector(updateUser:shouldRefreshTab:)] ||
            ![component respondsToSelector:@selector(p_updateTabView)]) continue;
        id user = [helper user];
        if (!user) continue;
        [helper updateUser:user shouldRefreshTab:YES];
        [component p_updateTabView];
    }
}

NSString *DKProfileCleanTabsStatus(void) {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"已见分页编排=%lu 最近一次过滤：%@\n", (unsigned long)gDKProfileTabComponents.allObjects.count,
        gDKProfileTabLastFilter ?: @"未过滤"];
    for (AWEUIOrchestrationHomeComponent *component in gDKProfileTabComponents.allObjects) {
        AWEUserProfileTabHelper *helper = [component respondsToSelector:@selector(tabHelper)] ? [component tabHelper] : nil;
        NSArray *tabs = [helper respondsToSelector:@selector(tabArray)] ? [helper tabArray] : nil;
        [out appendFormat:@"  当前分页类型=[%@]\n", DKProfileTabTypes(tabs)];
    }
    return out;
}

%hook AWEUserProfileTabHelper

- (NSArray *)tabArray {
    NSArray *tabs = %orig;
    if (![tabs isKindOfClass:NSArray.class] || !tabs.count || !DKProfileTabHelperMine(self)) return tabs;
    return DKProfileTabFilter(self, tabs);
}

%end

%hook AWEUIOrchestrationHomeComponent

- (void)viewDidAppear {
    %orig;
    AWEUserProfileTabHelper *helper = [self respondsToSelector:@selector(tabHelper)] ? [self tabHelper] : nil;
    if (!DKProfileTabHelperMine(helper)) return;
    if (!gDKProfileTabComponents) gDKProfileTabComponents = [NSHashTable weakObjectsHashTable];
    [gDKProfileTabComponents addObject:self];
}

%end
