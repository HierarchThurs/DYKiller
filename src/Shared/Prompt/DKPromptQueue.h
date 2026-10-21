// 只负责会话顺序与可见时间，不持有 UIKit 视图或业务回调。时间由主线程驱动器提供。
#ifndef DKPromptQueue_h
#define DKPromptQueue_h
#import <Foundation/Foundation.h>

@interface DKPromptQueue : NSObject
@property (nonatomic, readonly, copy) NSArray<NSString *> *identifiers;
@property (nonatomic, readonly, copy) NSString *currentIdentifier;
@property (nonatomic, readonly) NSTimeInterval nextDelay; // 无需计时为 INFINITY。
- (void)enqueueIdentifier:(NSString *)identifier resultDuration:(NSTimeInterval)duration atTime:(NSTimeInterval)time;
- (void)finishIdentifier:(NSString *)identifier duration:(NSTimeInterval)duration atTime:(NSTimeInterval)time;
- (void)withdrawIdentifier:(NSString *)identifier atTime:(NSTimeInterval)time;
- (void)advanceTo:(NSTimeInterval)time;
- (void)setActive:(BOOL)active atTime:(NSTimeInterval)time;
- (void)setInteracting:(BOOL)interacting atTime:(NSTimeInterval)time;
- (NSArray<NSString *> *)takeExpiredIdentifiers;
@end
#endif
