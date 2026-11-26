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

// 一套连点方案：一个自定义名字 + 一串步骤。方案之间互相独立。
@interface ATPlan : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, readonly) NSArray<ATAction *> *actions;
+ (instancetype)planWithName:(NSString *)name;
@end

@interface ATSession : NSObject

@property (class, nonatomic, readonly) ATSession *shared;

// 当前方案的步骤。切换方案后这个数组会变。
@property (nonatomic, readonly) NSArray<ATAction *> *actions;
// 所有方案，至少一套。
@property (nonatomic, readonly) NSArray<ATPlan *> *plans;
@property (nonatomic, readonly) ATPlan *activePlan;
@property (nonatomic, readonly) NSInteger activePlanIndex;
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

#pragma mark 方案

// 新建一套空方案并切换过去。名字为空时自动编号，重名会自动加后缀。
- (ATPlan *)createPlanNamed:(nullable NSString *)name;
// 改名。名字为空会被忽略。重名会自动加后缀。返回是否改了。
- (BOOL)renamePlanAtIndex:(NSInteger)index toName:(NSString *)name;
// 删除一套方案。只剩一套时拒绝删除。
- (BOOL)removePlanAtIndex:(NSInteger)index;
// 把某套方案设为当前方案（会先停止运行）。
- (void)selectPlanAtIndex:(NSInteger)index;

- (void)start;
- (void)stop;
- (void)save;

@end

NS_ASSUME_NONNULL_END
