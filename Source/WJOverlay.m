#import "WJOverlay.h"
#import "WJBlocker.h"
#import <objc/runtime.h>

static const CGFloat kBallSize = 46;
static const CGFloat kPanelWidth = 230;
static const CGFloat kPanelHeight = 150;
static const CGFloat kEdgeMargin = 8;

#pragma mark - 穿透容器：空白区域让触摸穿过，只有子视图响应

@interface WJPassthroughView : UIView
@end
@implementation WJPassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

#pragma mark - 置顶窗口：平时不当 keyWindow，避免抢走目标 App 的键盘/输入

@interface WJOverlayWindow : UIWindow
@end
@implementation WJOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

#pragma mark - Overlay 控制器

@interface WJOverlay : NSObject
@property (nonatomic, strong) WJOverlayWindow *window;
@property (nonatomic, strong) UIView *ball;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UISwitch *toggle;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, assign) BOOL panelVisible;
@end

@implementation WJOverlay

+ (instancetype)shared {
    static WJOverlay *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (void)buildIfNeeded {
    if (self.window) return;

    CGRect screen = [UIScreen mainScreen].bounds;
    WJOverlayWindow *win = [[WJOverlayWindow alloc] initWithFrame:screen];
    win.windowLevel = UIWindowLevelAlert + 10;
    win.backgroundColor = [UIColor clearColor];
    win.rootViewController = [[UIViewController alloc] init];

    WJPassthroughView *root = [[WJPassthroughView alloc] initWithFrame:screen];
    [win.rootViewController.view addSubview:root];

    // 悬浮球：淡蓝半透明，可拖动，点击展开/收起面板
    UIView *ball = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kBallSize, kBallSize)];
    ball.backgroundColor = [[UIColor colorWithRed:0.30 green:0.58 blue:1.00 alpha:1] colorWithAlphaComponent:0.22];
    ball.layer.cornerRadius = kBallSize / 2;
    ball.layer.borderWidth = 1;
    ball.layer.borderColor = [[UIColor colorWithRed:0.30 green:0.58 blue:1.00 alpha:1] colorWithAlphaComponent:0.5].CGColor;
    ball.center = CGPointMake(screen.size.width - kEdgeMargin - kBallSize / 2,
                              screen.size.height * 0.32);

    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectInset(ball.bounds, 13, 13)];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];
    icon.image = [UIImage systemImageNamed:@"hand.raised.slash.fill" withConfiguration:cfg];
    if (!icon.image) icon.image = [UIImage systemImageNamed:@"nosign" withConfiguration:cfg];
    if (!icon.image) icon.image = [UIImage systemImageNamed:@"xmark.circle.fill" withConfiguration:cfg];
    icon.tintColor = [[UIColor colorWithRed:0.30 green:0.58 blue:1.00 alpha:1] colorWithAlphaComponent:0.95];
    [ball addSubview:icon];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(ballTapped)];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(ballDragged:)];
    [ball addGestureRecognizer:tap];
    [ball addGestureRecognizer:pan];
    [root addSubview:ball];
    self.ball = ball;

    // 面板
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kPanelWidth, kPanelHeight)];
    panel.backgroundColor = [UIColor colorWithRed:0.10 green:0.11 blue:0.14 alpha:0.96];
    panel.layer.cornerRadius = 14;
    panel.hidden = YES;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 14, kPanelWidth - 32, 24)];
    title.text = @"拦截跳转微信";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [panel addSubview:title];

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(16, 40, kPanelWidth - 32, 34)];
    subtitle.text = @"开启后，QQ音乐分享到微信不会真的跳转，仍提示成功";
    subtitle.textColor = [UIColor colorWithWhite:0.7 alpha:1];
    subtitle.font = [UIFont systemFontOfSize:11];
    subtitle.numberOfLines = 2;
    [panel addSubview:subtitle];

    UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectMake(16, 92, 51, 31)];
    [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:toggle];
    self.toggle = toggle;

    UILabel *statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(76, 92, kPanelWidth - 92, 31)];
    statusLabel.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    statusLabel.font = [UIFont systemFontOfSize:12];
    statusLabel.numberOfLines = 2;
    [panel addSubview:statusLabel];
    self.statusLabel = statusLabel;

    [root addSubview:panel];
    self.panel = panel;

    win.hidden = NO;
    self.window = win;

    [self refreshState];
}

- (void)refreshState {
    BOOL on = WJBlockerEnabled();
    [self.toggle setOn:on animated:NO];
    self.statusLabel.text = on ? @"已开启 · 不会跳微信" : @"已关闭 · 正常跳转";
    self.statusLabel.textColor = on ? [UIColor colorWithRed:0.3 green:0.9 blue:0.5 alpha:1]
                                    : [UIColor colorWithWhite:0.85 alpha:1];
    self.ball.layer.borderColor = on ? [[UIColor colorWithRed:0.2 green:0.8 blue:0.45 alpha:1] colorWithAlphaComponent:0.9].CGColor
                                     : [[UIColor colorWithRed:0.30 green:0.58 blue:1.00 alpha:1] colorWithAlphaComponent:0.5].CGColor;
}

- (void)toggleChanged:(UISwitch *)sender {
    WJBlockerSetEnabled(sender.on);
    [self refreshState];
}

- (void)ballTapped {
    self.panelVisible = !self.panelVisible;
    self.panel.hidden = !self.panelVisible;
    if (self.panelVisible) {
        CGPoint c = self.ball.center;
        CGFloat px = MIN(MAX(c.x - kPanelWidth / 2, kEdgeMargin),
                         self.window.bounds.size.width - kPanelWidth - kEdgeMargin);
        CGFloat py = c.y + kBallSize / 2 + 10;
        if (py + kPanelHeight > self.window.bounds.size.height - kEdgeMargin) {
            py = c.y - kBallSize / 2 - 10 - kPanelHeight;
        }
        self.panel.frame = CGRectMake(px, py, kPanelWidth, kPanelHeight);
        [self refreshState];
    }
}

- (void)ballDragged:(UIPanGestureRecognizer *)gesture {
    CGPoint delta = [gesture translationInView:self.window];
    CGPoint c = self.ball.center;
    c.x += delta.x;
    c.y += delta.y;
    self.ball.center = c;
    [gesture setTranslation:CGPointZero inView:self.window];

    if (gesture.state == UIGestureRecognizerStateEnded) {
        // 贴边吸附
        CGRect area = self.window.bounds;
        CGFloat x = MIN(MAX(c.x, kEdgeMargin + kBallSize / 2), area.size.width - kEdgeMargin - kBallSize / 2);
        CGFloat y = MIN(MAX(c.y, kEdgeMargin + kBallSize / 2), area.size.height - kEdgeMargin - kBallSize / 2);
        [UIView animateWithDuration:0.2 animations:^{ self.ball.center = CGPointMake(x, y); }];
    }
}

@end

void WJOverlayPresent(void) {
    // App 启动后 window 才就绪，延迟附着
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[WJOverlay shared] buildIfNeeded];
    });
}
