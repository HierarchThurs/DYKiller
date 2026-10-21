#import "DKPromptQueue.h"
#import <math.h>

static const NSTimeInterval kDKPromptSlice = 5.0;

@interface DKPromptQueueItem : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic) NSUInteger sequence;
@property (nonatomic) NSTimeInterval duration; // 0 表示业务仍在运行。
@end
@implementation DKPromptQueueItem
@end

@implementation DKPromptQueue {
    NSMutableArray<DKPromptQueueItem *> *_items;
    NSMutableArray<NSString *> *_expired;
    DKPromptQueueItem *_current;
    NSUInteger _sequence, _mainSequence, _guestSequence;
    NSTimeInterval _lastTime, _elapsed;
    BOOL _hasTime, _active, _interacting;
}

- (instancetype)init {
    if ((self = [super init])) {
        _items = [NSMutableArray array];
        _expired = [NSMutableArray array];
        _active = YES;
    }
    return self;
}

- (NSArray<NSString *> *)identifiers { return [_items valueForKey:@"identifier"]; }
- (NSString *)currentIdentifier { return _current.identifier; }

- (DKPromptQueueItem *)itemForIdentifier:(NSString *)identifier {
    for (DKPromptQueueItem *item in _items) if ([item.identifier isEqual:identifier]) return item;
    return nil;
}

- (void)accountTo:(NSTimeInterval)time {
    if (!isfinite(time)) return;
    if (_hasTime && _active && !_interacting && _current) _elapsed += MAX(0.0, time - _lastTime);
    _lastTime = _hasTime ? MAX(_lastTime, time) : time;
    _hasTime = YES;
}

- (void)display:(DKPromptQueueItem *)item {
    if (_current == item) return;
    _current = item;
    _elapsed = 0.0;
}

- (void)selectCurrent {
    DKPromptQueueItem *main = _items.firstObject;
    if (!main) {
        [self display:nil];
        _mainSequence = _guestSequence = 0;
        return;
    }
    if (_mainSequence != main.sequence) {
        _mainSequence = main.sequence;
        _guestSequence = (_current && _current != main) ? _current.sequence : main.sequence;
    }
    if (!_active || _interacting) return;
    if (!_current) { [self display:main]; return; }

    if (_current.duration > 0.0) {
        if (_elapsed < _current.duration) return;
        [_expired addObject:_current.identifier];
        [_items removeObjectIdenticalTo:_current];
        [self display:nil];
        [self selectCurrent];
        return;
    }
    if (_elapsed < kDKPromptSlice) return;
    if (_current != main) {
        [self display:main];
        return;
    }
    // 没有访客就保持在屏；访客游标只在实际让位时移动。
    DKPromptQueueItem *guest = nil;
    for (DKPromptQueueItem *item in _items) {
        if (item != main && item.sequence > _guestSequence) { guest = item; break; }
    }
    if (!guest && _items.count > 1) guest = _items[1];
    if (guest) {
        _guestSequence = guest.sequence;
        [self display:guest];
    }
}

- (void)enqueueIdentifier:(NSString *)identifier resultDuration:(NSTimeInterval)duration atTime:(NSTimeInterval)time {
    [self accountTo:time];
    if ([self itemForIdentifier:identifier]) return;
    DKPromptQueueItem *item = [DKPromptQueueItem new];
    item.identifier = identifier;
    item.sequence = ++_sequence;
    item.duration = MAX(0.0, duration);
    [_items addObject:item];
    [self selectCurrent];
}

- (void)finishIdentifier:(NSString *)identifier duration:(NSTimeInterval)duration atTime:(NSTimeInterval)time {
    [self accountTo:time];
    DKPromptQueueItem *item = [self itemForIdentifier:identifier];
    if (!item || item.duration > 0.0) return;
    item.duration = MAX(0.001, duration);
    if (item == _current) _elapsed = 0.0;
    [self selectCurrent];
}

- (void)withdrawIdentifier:(NSString *)identifier atTime:(NSTimeInterval)time {
    [self accountTo:time];
    DKPromptQueueItem *item = [self itemForIdentifier:identifier];
    if (!item) return;
    [_items removeObjectIdenticalTo:item];
    if (_current == item) [self display:nil];
    [self selectCurrent];
}

- (void)advanceTo:(NSTimeInterval)time {
    [self accountTo:time];
    [self selectCurrent];
}

- (void)setActive:(BOOL)active atTime:(NSTimeInterval)time {
    [self accountTo:time];
    _active = active;
    [self selectCurrent];
}

- (void)setInteracting:(BOOL)interacting atTime:(NSTimeInterval)time {
    [self accountTo:time];
    _interacting = interacting;
    [self selectCurrent];
}

- (NSTimeInterval)nextDelay {
    if (!_current || !_active || _interacting) return INFINITY;
    if (_current.duration > 0.0) return MAX(0.0, _current.duration - _elapsed);
    if (_current != _items.firstObject || _items.count > 1) return MAX(0.0, kDKPromptSlice - _elapsed);
    return INFINITY;
}

- (NSArray<NSString *> *)takeExpiredIdentifiers {
    NSArray *expired = [_expired copy];
    [_expired removeAllObjects];
    return expired;
}
@end
