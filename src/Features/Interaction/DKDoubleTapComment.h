// 双击评论的入口、运行时校验与页面内去重。
#ifndef DKDoubleTapComment_h
#define DKDoubleTapComment_h

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSUInteger, DKDoubleTapCommentEntry) {
    DKDoubleTapCommentFeedPlayer,
    DKDoubleTapCommentFeedInteraction,
    DKDoubleTapCommentStory,
    DKDoubleTapCommentRelatedPlayer,
    DKDoubleTapCommentRelatedInteraction,
    DKDoubleTapCommentListenFeed,
    DKDoubleTapCommentEntryCount
};

// types 为返回值及显式参数的类型首字符，如 v@@ 表示 void(id, id)。
BOOL DKDoubleTapCommentMethod(Class cls, SEL selector, const char *types);
BOOL DKDoubleTapCommentOwnMethod(Class cls, SEL selector);
id DKDoubleTapCommentObject(id object, SEL selector);
BOOL DKDoubleTapCommentBool(id object, SEL selector);
id DKDoubleTapCommentModel(id object);
BOOL DKDoubleTapCommentModelsMatch(id first, id second);
void DKDoubleTapCommentInstalled(DKDoubleTapCommentEntry entry);
void DKDoubleTapCommentMissing(void);
void DKDoubleTapCommentStale(void);
void DKDoubleTapCommentDuplicate(void);

// handler 返回 NO 时透传原方法；所有页面判定与原生评论调用均在主线程。
void DKDoubleTapCommentDispatch(DKDoubleTapCommentEntry entry, id source,
                               dispatch_block_t original, BOOL (^handler)(void));
BOOL DKDoubleTapCommentOpen(UIViewController *owner, id model, dispatch_block_t action);
NSString *DKDoubleTapCommentDiagnostics(void);

#endif
