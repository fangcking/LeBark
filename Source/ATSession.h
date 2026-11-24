// The recorded steps, the timing settings, and the runner that plays them back
// through TouchSynth. Main thread only.
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ATActionType) {
    ATActionTypeTap = 0,
    ATActionTypeSwipe = 1,
};

// One step. Points are in screen coordinates, the space TouchSynth expects.
@interface ATAction : NSObject
@property (nonatomic) ATActionType type;
@property (nonatomic) CGPoint start;
@property (nonatomic) CGPoint end; // swipes only
// 该步执行后的延时，单位毫秒（10 ~ 60000），默认 500。独立于其它步骤。
@property (nonatomic) NSInteger delayMs;
+ (instancetype)tapAt:(CGPoint)point;
+ (instancetype)swipeFrom:(CGPoint)start to:(CGPoint)end;
@end

@interface ATSession : NSObject

@property (class, nonatomic, readonly) ATSession *shared;

@property (nonatomic, readonly) NSArray<ATAction *> *actions;
@property (nonatomic) NSTimeInterval swipeDuration; // finger travel time（滑动动作本身的时长）
@property (nonatomic) NSInteger loopCount;          // 0 repeats forever
@property (nonatomic) BOOL showTouches;
@property (nonatomic) CGPoint bubbleCenter;         // CGPointZero until placed

@property (nonatomic, readonly, getter=isRunning) BOOL running;
@property (nonatomic, readonly) NSInteger currentIndex;
@property (nonatomic, readonly) NSInteger currentLoop;

// Steps or settings changed.
@property (nonatomic, copy, nullable) void (^onChange)(void);
// Running started or stopped.
@property (nonatomic, copy, nullable) void (^onRunStateChange)(void);
// A step is about to play.
@property (nonatomic, copy, nullable) void (^onStepStart)(NSInteger index, ATAction *action);
// A step finished. reachedTarget is NO when nothing was under the point.
@property (nonatomic, copy, nullable) void (^onStepFinish)(NSInteger index, ATAction *action, BOOL reachedTarget);

- (void)addAction:(ATAction *)action;
- (void)removeActionAtIndex:(NSInteger)index;
- (void)removeLastAction;
- (void)removeAllActions;
// 把某一步上移/下移，用于调整执行顺序与点位位置。返回是否真的移动了。
- (BOOL)moveActionAtIndex:(NSInteger)index byOffset:(NSInteger)offset;
// Call after moving an action's points in place (e.g. while dragging a marker).
- (void)actionsDidChange;

- (void)start;
- (void)stop;
- (void)save;

@end

NS_ASSUME_NONNULL_END
