#import "ATSession.h"

#import "TouchSynth.h"

static NSString *const kDefaultsKey = @"com.trollautoclicker.v1";
static const NSTimeInterval kTapHoldTime = 0.05;
static const NSInteger kDefaultDelayMs = 500;
static NSString *const kFirstPlanName = @"方案 1";

#pragma mark - ATAction

@interface ATAction ()
- (NSDictionary *)dictionary;
+ (nullable instancetype)actionWithDictionary:(NSDictionary *)dictionary;
@end

@implementation ATAction

+ (instancetype)tapAt:(CGPoint)point {
    ATAction *action = [[self alloc] init];
    action.type = ATActionTypeTap;
    action.start = point;
    action.end = point;
    action.delayMs = kDefaultDelayMs;
    return action;
}

+ (instancetype)swipeFrom:(CGPoint)start to:(CGPoint)end {
    ATAction *action = [[self alloc] init];
    action.type = ATActionTypeSwipe;
    action.start = start;
    action.end = end;
    action.delayMs = kDefaultDelayMs;
    return action;
}

- (NSDictionary *)dictionary {
    return @{
        @"type": @(self.type),
        @"x1": @(self.start.x), @"y1": @(self.start.y),
        @"x2": @(self.end.x), @"y2": @(self.end.y),
        @"delayMs": @(self.delayMs),
    };
}

+ (nullable instancetype)actionWithDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    ATAction *action = [[self alloc] init];
    action.type = [dictionary[@"type"] integerValue] == ATActionTypeSwipe ? ATActionTypeSwipe : ATActionTypeTap;
    action.start = CGPointMake([dictionary[@"x1"] doubleValue], [dictionary[@"y1"] doubleValue]);
    action.end = CGPointMake([dictionary[@"x2"] doubleValue], [dictionary[@"y2"] doubleValue]);
    NSInteger delay = dictionary[@"delayMs"] ? [dictionary[@"delayMs"] integerValue] : kDefaultDelayMs;
    action.delayMs = MIN(MAX(delay, 10), 60000);
    return action;
}

@end

#pragma mark - ATPlan

@interface ATPlan ()
@property (nonatomic, strong) NSMutableArray<ATAction *> *mutableActions;
- (NSDictionary *)dictionary;
+ (nullable instancetype)planWithDictionary:(NSDictionary *)dictionary;
@end

@implementation ATPlan

+ (instancetype)planWithName:(NSString *)name {
    ATPlan *plan = [[self alloc] init];
    plan.name = name.length ? name : kFirstPlanName;
    plan.mutableActions = [NSMutableArray array];
    return plan;
}

- (NSArray<ATAction *> *)actions {
    return [self.mutableActions copy];
}

- (NSDictionary *)dictionary {
    NSMutableArray *actions = [NSMutableArray array];
    for (ATAction *action in self.mutableActions) {
        [actions addObject:[action dictionary]];
    }
    return @{
        @"name": self.name ?: kFirstPlanName,
        @"actions": actions,
    };
}

+ (nullable instancetype)planWithDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    ATPlan *plan = [[self alloc] init];
    NSString *name = [dictionary[@"name"] isKindOfClass:[NSString class]] ? dictionary[@"name"] : nil;
    plan.name = name.length ? name : kFirstPlanName;
    plan.mutableActions = [NSMutableArray array];
    for (NSDictionary *item in dictionary[@"actions"]) {
        ATAction *action = [ATAction actionWithDictionary:item];
        if (action) {
            [plan.mutableActions addObject:action];
        }
    }
    return plan;
}

@end

#pragma mark - ATSession

@implementation ATSession {
    NSMutableArray<ATPlan *> *_plans;
    NSInteger _activePlanIndex;
    NSUInteger _generation; // bumped on stop so pending steps see they are stale
    BOOL _idleTimerWasDisabled;
    BOOL _didCompleteLoops;
}

+ (ATSession *)shared {
    static ATSession *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[ATSession alloc] init];
    });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _plans = [NSMutableArray array];
        _activePlanIndex = 0;
        _swipeDuration = 0.25;
        _loopCount = 0;
        _showTouches = YES;
        _currentLoop = 1;
        _didCompleteLoops = NO;
        [self loadSaved];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillResignActive)
                                                     name:UIApplicationWillResignActiveNotification
                                                   object:nil];
    }
    return self;
}

#pragma mark 方案

- (NSArray<ATPlan *> *)plans {
    return [_plans copy];
}

- (ATPlan *)activePlan {
    if (_plans.count == 0) {
        [_plans addObject:[ATPlan planWithName:kFirstPlanName]];
        _activePlanIndex = 0;
    }
    NSInteger index = MIN(MAX(_activePlanIndex, 0), (NSInteger)_plans.count - 1);
    _activePlanIndex = index;
    return _plans[index];
}

- (NSInteger)activePlanIndex {
    // 通过 activePlan 走一遍，保证索引和数组一致。
    (void)[self activePlan];
    return _activePlanIndex;
}

- (NSArray<ATAction *> *)actions {
    return [self activePlan].actions;
}

// 当前方案的可变步骤数组。所有编辑都作用在它上面。
- (NSMutableArray<ATAction *> *)currentActions {
    return [self activePlan].mutableActions;
}

static NSString *ATTrimmedName(NSString *name) {
    if (![name isKindOfClass:[NSString class]]) {
        return @"";
    }
    return [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

// 重名时依次尝试 "名字 2"、"名字 3"……
- (NSString *)uniquePlanName:(NSString *)base excludingIndex:(NSInteger)exclude {
    NSString *candidate = base;
    NSInteger suffix = 2;
    while (YES) {
        BOOL taken = NO;
        for (NSInteger i = 0; i < (NSInteger)_plans.count; i++) {
            if (i == exclude) {
                continue;
            }
            if ([_plans[i].name isEqualToString:candidate]) {
                taken = YES;
                break;
            }
        }
        if (!taken) {
            return candidate;
        }
        candidate = [NSString stringWithFormat:@"%@ %ld", base, (long)suffix++];
    }
}

- (ATPlan *)createPlanNamed:(nullable NSString *)name {
    [self stop];
    NSString *trimmed = ATTrimmedName(name);
    if (!trimmed.length) {
        trimmed = [NSString stringWithFormat:@"方案 %ld", (long)_plans.count + 1];
    }
    ATPlan *plan = [ATPlan planWithName:[self uniquePlanName:trimmed excludingIndex:-1]];
    [_plans addObject:plan];
    _activePlanIndex = (NSInteger)_plans.count - 1;
    [self changed];
    return plan;
}

- (BOOL)renamePlanAtIndex:(NSInteger)index toName:(NSString *)name {
    if (index < 0 || index >= (NSInteger)_plans.count) {
        return NO;
    }
    NSString *trimmed = ATTrimmedName(name);
    if (!trimmed.length) {
        return NO;
    }
    _plans[index].name = [self uniquePlanName:trimmed excludingIndex:index];
    [self save];
    return YES;
}

- (BOOL)removePlanAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_plans.count || _plans.count <= 1) {
        return NO;
    }
    [self stop];
    [_plans removeObjectAtIndex:index];
    if (index < _activePlanIndex) {
        _activePlanIndex--;
    } else if (_activePlanIndex >= (NSInteger)_plans.count) {
        _activePlanIndex = (NSInteger)_plans.count - 1;
    }
    [self changed];
    return YES;
}

- (void)selectPlanAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_plans.count || index == _activePlanIndex) {
        return;
    }
    [self stop];
    _activePlanIndex = index;
    [self changed];
}

#pragma mark Persistence

- (void)loadSaved {
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kDefaultsKey];
    if (!saved) {
        return;
    }
    // 新格式：多套方案。
    NSArray *rawPlans = saved[@"plans"];
    if ([rawPlans isKindOfClass:[NSArray class]] && rawPlans.count > 0) {
        for (NSDictionary *item in rawPlans) {
            ATPlan *plan = [ATPlan planWithDictionary:item];
            if (plan) {
                [_plans addObject:plan];
            }
        }
        if (_plans.count > 0) {
            NSInteger index = [saved[@"activePlanIndex"] integerValue];
            _activePlanIndex = MIN(MAX(index, 0), (NSInteger)_plans.count - 1);
        }
    }
    // 老格式：只有一串步骤，迁移成一套「方案 1」。
    if (_plans.count == 0 && [saved[@"actions"] isKindOfClass:[NSArray class]]) {
        ATPlan *plan = [ATPlan planWithName:kFirstPlanName];
        for (NSDictionary *item in saved[@"actions"]) {
            ATAction *action = [ATAction actionWithDictionary:item];
            if (action) {
                [plan.mutableActions addObject:action];
            }
        }
        [_plans addObject:plan];
        _activePlanIndex = 0;
    }
    if (saved[@"swipeDuration"]) _swipeDuration = [saved[@"swipeDuration"] doubleValue];
    if (saved[@"loopCount"]) _loopCount = [saved[@"loopCount"] integerValue];
    if (saved[@"showTouches"]) _showTouches = [saved[@"showTouches"] boolValue];
    if (saved[@"bubbleX"]) _bubbleCenter = CGPointMake([saved[@"bubbleX"] doubleValue], [saved[@"bubbleY"] doubleValue]);
    (void)[self activePlan];
}

- (void)save {
    (void)[self activePlan]; // 至少保证有一套方案再落盘
    NSMutableArray *plans = [NSMutableArray array];
    for (ATPlan *plan in _plans) {
        [plans addObject:[plan dictionary]];
    }
    // 老版本读的是顶层 actions：同步写一份，降级安装时也不会丢点位。
    NSMutableArray *legacyActions = [NSMutableArray array];
    for (ATAction *action in [self activePlan].actions) {
        [legacyActions addObject:[action dictionary]];
    }
    [[NSUserDefaults standardUserDefaults] setObject:@{
        @"plans": plans,
        @"activePlanIndex": @(_activePlanIndex),
        @"actions": legacyActions,
        @"swipeDuration": @(_swipeDuration),
        @"loopCount": @(_loopCount),
        @"showTouches": @(_showTouches),
        @"bubbleX": @(_bubbleCenter.x),
        @"bubbleY": @(_bubbleCenter.y),
    } forKey:kDefaultsKey];
}

- (void)changed {
    _didCompleteLoops = NO; // 步骤变了，之前跑完的 100% 不再成立
    [self save];
    if (self.onChange) {
        self.onChange();
    }
}

#pragma mark Editing

- (void)setSwipeDuration:(NSTimeInterval)swipeDuration { _swipeDuration = swipeDuration; [self save]; }
- (void)setLoopCount:(NSInteger)loopCount { _loopCount = loopCount; [self save]; }
- (void)setShowTouches:(BOOL)showTouches { _showTouches = showTouches; [self save]; }
- (void)setBubbleCenter:(CGPoint)bubbleCenter { _bubbleCenter = bubbleCenter; [self save]; }

- (void)addAction:(ATAction *)action {
    [self stop];
    [[self currentActions] addObject:action];
    [self changed];
}

- (void)removeActionAtIndex:(NSInteger)index {
    NSMutableArray<ATAction *> *actions = [self currentActions];
    if (index < 0 || index >= (NSInteger)actions.count) {
        return;
    }
    [self stop];
    [actions removeObjectAtIndex:index];
    [self changed];
}

- (void)removeLastAction {
    [self removeActionAtIndex:(NSInteger)[self currentActions].count - 1];
}

- (BOOL)moveActionAtIndex:(NSInteger)index byOffset:(NSInteger)offset {
    NSMutableArray<ATAction *> *actions = [self currentActions];
    NSInteger target = index + offset;
    if (index < 0 || index >= (NSInteger)actions.count || target < 0 || target >= (NSInteger)actions.count) {
        return NO;
    }
    [self stop];
    ATAction *action = actions[index];
    [actions removeObjectAtIndex:index];
    [actions insertObject:action atIndex:target];
    [self changed];
    return YES;
}

- (void)removeAllActions {
    [self stop];
    [[self currentActions] removeAllObjects];
    [self changed];
}

- (void)actionsDidChange {
    [self changed];
}

#pragma mark Running

- (BOOL)didCompleteLoops {
    return _didCompleteLoops;
}

- (double)progress {
    if (_loopCount <= 0) {
        return -1; // 无限循环没有百分比
    }
    NSInteger count = (NSInteger)self.actions.count;
    NSInteger total = _loopCount * count;
    if (total <= 0) {
        return 0;
    }
    NSInteger done = _didCompleteLoops ? total : (_currentLoop - 1) * count + _currentIndex;
    double value = (double)done / (double)total;
    return MIN(MAX(value, 0), 1);
}

- (void)start {
    if (_running || self.actions.count == 0) {
        return;
    }
    _running = YES;
    _currentIndex = 0;
    _currentLoop = 1;
    _didCompleteLoops = NO;
    _idleTimerWasDisabled = [UIApplication sharedApplication].idleTimerDisabled;
    [UIApplication sharedApplication].idleTimerDisabled = YES; // long runs shouldn't lock the screen
    if (self.onRunStateChange) {
        self.onRunStateChange();
    }
    [self playStepForGeneration:_generation];
}

- (void)stop {
    if (!_running) {
        return;
    }
    _running = NO;
    _generation++;
    [TSTouchSynthesizer.sharedSynthesizer cancelAllTouches];
    [UIApplication sharedApplication].idleTimerDisabled = _idleTimerWasDisabled;
    if (self.onRunStateChange) {
        self.onRunStateChange();
    }
}

- (void)applicationWillResignActive {
    [self stop];
}

- (void)playStepForGeneration:(NSUInteger)generation {
    if (generation != _generation || !_running) {
        return;
    }
    NSArray<ATAction *> *actions = self.actions;
    if (_currentIndex >= (NSInteger)actions.count) {
        _currentIndex = 0;
        _currentLoop++;
        if (_loopCount > 0 && _currentLoop > _loopCount) {
            _didCompleteLoops = YES;
            [self stop];
            return;
        }
    }
    NSInteger index = _currentIndex;
    ATAction *action = actions[index];
    if (self.onStepStart) {
        self.onStepStart(index, action);
    }

    __weak ATSession *weakSelf = self;
    void (^finish)(BOOL) = ^(BOOL reachedTarget) {
        ATSession *strongSelf = weakSelf;
        if (!strongSelf || generation != strongSelf->_generation) {
            return;
        }
        if (strongSelf.onStepFinish) {
            strongSelf.onStepFinish(index, action, reachedTarget);
        }
        NSTimeInterval delay = action.delayMs / 1000.0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            ATSession *innerSelf = weakSelf;
            if (innerSelf && generation == innerSelf->_generation) {
                innerSelf->_currentIndex = index + 1;
                [innerSelf playStepForGeneration:generation];
            }
        });
    };

    TSTouchSynthesizer *synth = TSTouchSynthesizer.sharedSynthesizer;
    if (action.type == ATActionTypeSwipe) {
        [synth swipeFromPoint:action.start toPoint:action.end duration:self.swipeDuration completion:finish];
    } else {
        [synth tapAtPoint:action.start duration:kTapHoldTime completion:finish];
    }
}

@end
