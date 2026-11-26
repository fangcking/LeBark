#import "ATViews.h"

#import <math.h>

NSString *const ATOverlayKeyboardWillShowNotification = @"ATOverlayKeyboardWillShowNotification";
NSString *const ATOverlayKeyboardDidHideNotification = @"ATOverlayKeyboardDidHideNotification";

static const CGFloat kBubbleSize = 44;
static const CGFloat kEdgeMargin = 10;
static const CGFloat kStepRowHeight = 78;
static const CGFloat kVisibleStepRows = 3.2;
static const CGFloat kPlanRowHeight = 44;
static const CGFloat kVisiblePlanRows = 3;

// Slider position 0...1 maps exponentially onto seconds, for fine control at the low end.
static const NSTimeInterval kMinSwipeTime = 0.05, kMaxSwipeTime = 3;

UIColor *ATTapColor(void) { return [UIColor colorWithRed:0.30 green:0.58 blue:1.00 alpha:1]; }
UIColor *ATSwipeColor(void) { return [UIColor colorWithRed:1.00 green:0.62 blue:0.22 alpha:1]; }
UIColor *ATGoColor(void) { return [UIColor colorWithRed:0.20 green:0.80 blue:0.45 alpha:1]; }
UIColor *ATStopColor(void) { return [UIColor colorWithRed:1.00 green:0.32 blue:0.32 alpha:1]; }
UIColor *ATTextColor(void) { return [UIColor whiteColor]; }
UIColor *ATSecondaryTextColor(void) { return [UIColor colorWithRed:0.80 green:0.82 blue:0.86 alpha:1]; }
UIColor *ATMutedTextColor(void) { return [UIColor colorWithRed:0.58 green:0.60 blue:0.65 alpha:1]; }
UIColor *ATSurfaceColor(void) { return [UIColor colorWithRed:0.09 green:0.10 blue:0.12 alpha:0.97]; }
UIColor *ATCardColor(void) { return [UIColor colorWithRed:0.17 green:0.18 blue:0.21 alpha:1]; }

static UIImage *ATSymbol(NSString *name, CGFloat size, UIFontWeight weight) {
    UIImageSymbolWeight symbolWeight = weight >= UIFontWeightBold ? UIImageSymbolWeightBold : UIImageSymbolWeightSemibold;
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:size weight:symbolWeight];
    return [UIImage systemImageNamed:name withConfiguration:config];
}

static float ATSliderValue(NSTimeInterval seconds, NSTimeInterval min, NSTimeInterval max) {
    return (float)(log(MAX(seconds, min) / min) / log(max / min));
}

static NSTimeInterval ATSeconds(float value, NSTimeInterval min, NSTimeInterval max) {
    NSTimeInterval seconds = min * pow(max / min, value);
    return seconds < 1 ? round(seconds * 100) / 100 : round(seconds * 10) / 10;
}

static NSString *ATFormatSeconds(NSTimeInterval seconds) {
    if (seconds < 1) {
        return [NSString stringWithFormat:@"%.0f ms", seconds * 1000];
    }
    return [NSString stringWithFormat:@"%.1f s", seconds];
}

#pragma mark - Passthrough

@implementation ATPassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

#pragma mark - Bubble

@implementation ATBubbleView {
    UIView *_tint;
    UIImageView *_icon;
    CAShapeLayer *_ring;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:CGRectMake(0, 0, kBubbleSize, kBubbleSize)])) {
        // 极淡阴影：只提供一点轮廓感，不遮挡底色
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.08;
        self.layer.shadowRadius = 4;
        self.layer.shadowOffset = CGSizeMake(0, 1);

        // 真正半透明的淡色圆。绝不使用磨砂(UIVisualEffectView)——磨砂是不透明的，
        // 会把底下内容糊成深色，那就成了"深蓝球"而不是"透出底下的一点蓝"。
        _tint = [[UIView alloc] initWithFrame:self.bounds];
        _tint.layer.cornerRadius = kBubbleSize / 2;
        _tint.userInteractionEnabled = NO;
        _tint.layer.borderWidth = 1;
        [self addSubview:_tint];

        _icon = [[UIImageView alloc] initWithFrame:CGRectInset(self.bounds, 12, 12)];
        _icon.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_icon];

        _ring = [CAShapeLayer layer];
        _ring.frame = self.bounds;
        _ring.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(self.bounds, 2, 2)].CGPath;
        _ring.fillColor = [UIColor clearColor].CGColor;
        _ring.lineWidth = 2;
        _ring.lineCap = kCALineCapRound;
        _ring.strokeEnd = 0.28;
        [self.layer addSublayer:_ring];

        [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
        [self addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragged:)]];
        [self applyRunning:NO];
    }
    return self;
}

- (void)setRunning:(BOOL)running {
    if (_running != running) {
        _running = running;
        [self applyRunning:running];
    }
}

- (void)applyRunning:(BOOL)running {
    _icon.image = ATSymbol(running ? @"stop.fill" : @"hand.tap.fill", 16, UIFontWeightBold);
    UIColor *base = running ? ATStopColor() : ATTapColor();
    // 真正透出底下的淡色：平时淡蓝 alpha 0.16、运行淡红 alpha 0.24。
    // 不用磨砂底，所以底下内容能看穿；图标用实色，浅色背景上也看得清。
    _tint.backgroundColor = [base colorWithAlphaComponent:running ? 0.24 : 0.16];
    _tint.layer.borderColor = [base colorWithAlphaComponent:0.45].CGColor;
    _icon.tintColor = [base colorWithAlphaComponent:0.95];
    _ring.strokeColor = ATGoColor().CGColor;
    _ring.hidden = !running;
    [_ring removeAllAnimations];
    if (running) {
        CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        spin.fromValue = @0;
        spin.toValue = @(2 * M_PI);
        spin.duration = 1.0;
        spin.repeatCount = HUGE_VALF;
        [_ring addAnimation:spin forKey:@"spin"];
    }
}

- (void)tapped {
    [UIView animateWithDuration:0.08 animations:^{
        self.transform = CGAffineTransformMakeScale(0.88, 0.88);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:0 options:0 animations:^{
            self.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];
    if (self.onTap) {
        self.onTap();
    }
}

- (void)dragged:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self.superview];
    self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:self.superview];
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        CGPoint target = [self snappedCenter];
        [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0 options:0 animations:^{
            self.center = target;
        } completion:nil];
        if (self.onMoved) {
            self.onMoved(target);
        }
    }
}

- (CGPoint)snappedCenter {
    CGRect area = UIEdgeInsetsInsetRect(self.superview.bounds, self.superview.safeAreaInsets);
    CGFloat half = kBubbleSize / 2 + kEdgeMargin;
    CGFloat x = self.center.x < CGRectGetMidX(area) ? CGRectGetMinX(area) + half : CGRectGetMaxX(area) - half;
    CGFloat y = MIN(MAX(self.center.y, CGRectGetMinY(area) + half), CGRectGetMaxY(area) - half);
    return CGPointMake(x, y);
}

@end

#pragma mark - Marker

@implementation ATMarkerView {
    UIColor *_color;
}

- (instancetype)initWithNumber:(NSInteger)number color:(UIColor *)color diameter:(CGFloat)diameter {
    if ((self = [super initWithFrame:CGRectMake(0, 0, diameter, diameter)])) {
        _color = color;
        self.layer.cornerRadius = diameter / 2;
        self.layer.borderWidth = 2.5;
        self.layer.borderColor = color.CGColor;
        self.backgroundColor = [color colorWithAlphaComponent:0.55];
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.4;
        self.layer.shadowRadius = 4;
        self.layer.shadowOffset = CGSizeZero;

        if (number > 0) {
            UILabel *label = [[UILabel alloc] initWithFrame:self.bounds];
            label.text = [NSString stringWithFormat:@"%ld", (long)number];
            label.textAlignment = NSTextAlignmentCenter;
            label.textColor = [UIColor whiteColor];
            label.font = [UIFont systemFontOfSize:diameter * 0.38 weight:UIFontWeightHeavy];
            label.shadowColor = [UIColor colorWithWhite:0 alpha:0.6];
            label.shadowOffset = CGSizeMake(0, 1);
            [self addSubview:label];
        } else {
            self.backgroundColor = [color colorWithAlphaComponent:0.55];
        }
        [self addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragged:)]];
    }
    return self;
}

- (void)dragged:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self.superview];
    CGRect bounds = self.superview.bounds;
    self.center = CGPointMake(MIN(MAX(self.center.x + translation.x, 0), CGRectGetMaxX(bounds)),
                              MIN(MAX(self.center.y + translation.y, 0), CGRectGetMaxY(bounds)));
    [pan setTranslation:CGPointZero inView:self.superview];
    BOOL finished = pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled;
    if (pan.state == UIGestureRecognizerStateBegan) {
        self.transform = CGAffineTransformMakeScale(1.2, 1.2);
    } else if (finished) {
        self.transform = CGAffineTransformIdentity;
    }
    if (self.onDrag) {
        self.onDrag(self, finished);
    }
}

- (void)setActive:(BOOL)active {
    _active = active;
    [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        self.transform = active ? CGAffineTransformMakeScale(1.25, 1.25) : CGAffineTransformIdentity;
        self.backgroundColor = [self->_color colorWithAlphaComponent:active ? 0.9 : 0.55];
    } completion:nil];
}

@end

#pragma mark - Gradient button

@interface ATGradientButton : UIButton
@property (nonatomic, readonly) CAGradientLayer *gradient;
@end

@implementation ATGradientButton
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _gradient = [CAGradientLayer layer];
        _gradient.startPoint = CGPointMake(0, 0);
        _gradient.endPoint = CGPointMake(1, 1);
        [self.layer insertSublayer:_gradient atIndex:0];
        self.layer.cornerRadius = 16;
        self.clipsToBounds = YES;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _gradient.frame = self.bounds;
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.75 : 1;
}
@end

#pragma mark - Panel

@implementation ATPanelView {
    ATSession *_session;
    UIStackView *_stack;
    UILabel *_stepsCount;
    UIScrollView *_stepsScroll;
    UIStackView *_stepsStack;
    NSLayoutConstraint *_stepsHeight;
    UILabel *_emptyLabel;
    NSMutableArray<UIView *> *_rows;
    NSMutableArray<UITextField *> *_delayFields; // 每一步的延时输入框
    NSInteger _highlighted;
    UITextField *_loopCountField;            // 循环次数输入框，0/留空 = 无限循环
    UISlider *_swipeTimeSlider;
    UILabel *_swipeTimeValue;
    UISwitch *_touchesSwitch;
    ATGradientButton *_runButton;
    UILabel *_statusLabel;

    // 方案
    UILabel *_planCount;
    UIScrollView *_planScroll;
    UIStackView *_planStack;
    NSLayoutConstraint *_planHeight;
    NSMutableArray<UIView *> *_planRows;
    NSInteger _renamingPlanIndex;   // -1 = 没有在改名
    NSInteger _pendingDeletePlanIndex; // 第一次点垃圾桶时进入待确认
    UITextField *_planNameField;    // 改名输入框，用来抢焦点
}

- (instancetype)initWithSession:(ATSession *)session {
    if ((self = [super initWithFrame:CGRectZero])) {
        _session = session;
        _rows = [NSMutableArray array];
        _delayFields = [NSMutableArray array];
        _planRows = [NSMutableArray array];
        _highlighted = -1;
        _renamingPlanIndex = -1;
        _pendingDeletePlanIndex = -1;
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.45;
        self.layer.shadowRadius = 24;
        self.layer.shadowOffset = CGSizeMake(0, 10);
        [self buildViews];
        [self reloadSteps];
        [self updateRunState];
    }
    return self;
}

- (void)buildViews {
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    blur.translatesAutoresizingMaskIntoConstraints = NO;
    blur.layer.cornerRadius = 26;
    blur.layer.cornerCurve = kCACornerCurveContinuous;
    blur.clipsToBounds = YES;
    blur.layer.borderWidth = 1;
    blur.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.16].CGColor;
    blur.contentView.backgroundColor = ATSurfaceColor(); // solid, so text reads over any app
    [self addSubview:blur];

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.showsVerticalScrollIndicator = NO;
    scroll.alwaysBounceVertical = NO;
    [blur.contentView addSubview:scroll];

    _stack = [[UIStackView alloc] init];
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.spacing = 14;
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:_stack];

    NSLayoutConstraint *fitContent = [self.heightAnchor constraintEqualToAnchor:_stack.heightAnchor constant:36];
    fitContent.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [blur.topAnchor constraintEqualToAnchor:self.topAnchor],
        [blur.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [blur.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [blur.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:blur.contentView.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:blur.contentView.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:blur.contentView.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:blur.contentView.trailingAnchor],
        [_stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:18],
        [_stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-18],
        [_stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:18],
        [_stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-18],
        fitContent,
    ]];

    [_stack addArrangedSubview:[self headerView]];
    [_stack addArrangedSubview:[self planSection]];
    [_stack addArrangedSubview:[self stepsSection]];
    [_stack addArrangedSubview:[self editButtons]];
    [_stack addArrangedSubview:[self timingSection]];
    [_stack addArrangedSubview:[self runSection]];
}

#pragma mark Sections

- (UIView *)headerView {
    UIView *iconBox = [[UIView alloc] init];
    iconBox.backgroundColor = ATTapColor();
    iconBox.layer.cornerRadius = 10;
    iconBox.layer.cornerCurve = kCACornerCurveContinuous;
    UIImageView *icon = [[UIImageView alloc] initWithImage:ATSymbol(@"hand.tap.fill", 17, UIFontWeightBold)];
    icon.tintColor = [UIColor whiteColor];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [iconBox addSubview:icon];
    iconBox.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [iconBox.widthAnchor constraintEqualToConstant:36],
        [iconBox.heightAnchor constraintEqualToConstant:36],
        [icon.centerXAnchor constraintEqualToAnchor:iconBox.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:iconBox.centerYAnchor],
    ]];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"连点器";
    title.font = [UIFont systemFontOfSize:21 weight:UIFontWeightBold];
    title.textColor = ATTextColor();
    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.text = @"TrollStore / TrollFools 注入版";
    subtitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    subtitle.textColor = ATSecondaryTextColor();
    UIStackView *titles = [[UIStackView alloc] initWithArrangedSubviews:@[title, subtitle]];
    titles.axis = UILayoutConstraintAxisVertical;
    titles.spacing = 1;

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setImage:ATSymbol(@"xmark.circle.fill", 24, UIFontWeightSemibold) forState:UIControlStateNormal];
    close.tintColor = ATMutedTextColor();
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [close setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[iconBox, titles, [UIView new], close]];
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12;
    return row;
}

- (UILabel *)sectionLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.attributedText = [[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightBold],
        NSForegroundColorAttributeName: ATSecondaryTextColor(),
        NSKernAttributeName: @1.2,
    }];
    return label;
}

#pragma mark 方案

- (UIView *)planSection {
    _planCount = [[UILabel alloc] init];
    _planCount.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
    _planCount.textColor = ATSecondaryTextColor();
    [_planCount setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIButton *add = [UIButton buttonWithType:UIButtonTypeSystem];
    [add setImage:ATSymbol(@"plus.circle.fill", 21, UIFontWeightSemibold) forState:UIControlStateNormal];
    add.tintColor = ATGoColor();
    [add addTarget:self action:@selector(addPlanTapped) forControlEvents:UIControlEventTouchUpInside];
    [add.widthAnchor constraintEqualToConstant:26].active = YES;
    [add.heightAnchor constraintEqualToConstant:26].active = YES;

    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[[self sectionLabel:@"方案"], [UIView new], _planCount, add]];
    header.alignment = UIStackViewAlignmentCenter;
    header.spacing = 6;

    UIView *box = [[UIView alloc] init];
    box.backgroundColor = ATCardColor();
    box.layer.cornerRadius = 16;
    box.layer.cornerCurve = kCACornerCurveContinuous;
    box.clipsToBounds = YES;
    box.translatesAutoresizingMaskIntoConstraints = NO;

    _planScroll = [[UIScrollView alloc] init];
    _planScroll.translatesAutoresizingMaskIntoConstraints = NO;
    _planScroll.showsVerticalScrollIndicator = NO;
    [box addSubview:_planScroll];

    _planStack = [[UIStackView alloc] init];
    _planStack.axis = UILayoutConstraintAxisVertical;
    _planStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_planScroll addSubview:_planStack];

    _planHeight = [box.heightAnchor constraintEqualToConstant:kPlanRowHeight];
    [NSLayoutConstraint activateConstraints:@[
        _planHeight,
        [_planScroll.topAnchor constraintEqualToAnchor:box.topAnchor],
        [_planScroll.bottomAnchor constraintEqualToAnchor:box.bottomAnchor],
        [_planScroll.leadingAnchor constraintEqualToAnchor:box.leadingAnchor],
        [_planScroll.trailingAnchor constraintEqualToAnchor:box.trailingAnchor],
        [_planStack.topAnchor constraintEqualToAnchor:_planScroll.contentLayoutGuide.topAnchor],
        [_planStack.bottomAnchor constraintEqualToAnchor:_planScroll.contentLayoutGuide.bottomAnchor],
        [_planStack.leadingAnchor constraintEqualToAnchor:_planScroll.frameLayoutGuide.leadingAnchor],
        [_planStack.trailingAnchor constraintEqualToAnchor:_planScroll.frameLayoutGuide.trailingAnchor],
    ]];

    UIStackView *section = [[UIStackView alloc] initWithArrangedSubviews:@[header, box]];
    section.axis = UILayoutConstraintAxisVertical;
    section.spacing = 8;
    return section;
}

- (void)reloadPlans {
    for (UIView *row in _planRows) {
        [row removeFromSuperview];
    }
    [_planRows removeAllObjects];
    _planNameField = nil;

    NSArray<ATPlan *> *plans = _session.plans;
    for (NSInteger i = 0; i < (NSInteger)plans.count; i++) {
        UIView *row = [self rowForPlan:plans[i] index:i];
        [_planStack addArrangedSubview:row];
        [_planRows addObject:row];
    }
    _planCount.text = [NSString stringWithFormat:@"%ld 套", (long)plans.count];
    _planHeight.constant = MIN(MAX((CGFloat)plans.count, 1), kVisiblePlanRows) * kPlanRowHeight;

    if (_renamingPlanIndex >= 0 && _planNameField) {
        UITextField *field = _planNameField;
        dispatch_async(dispatch_get_main_queue(), ^{
            [field becomeFirstResponder];
        });
    }
}

- (UIView *)rowForPlan:(ATPlan *)plan index:(NSInteger)index {
    UIView *row = [[UIView alloc] init];
    [row.heightAnchor constraintEqualToConstant:kPlanRowHeight].active = YES;

    // 改名状态：名字变成输入框，右侧给一个确认按钮。
    if (index == _renamingPlanIndex) {
        UITextField *field = [[UITextField alloc] init];
        field.text = plan.name;
        field.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        field.textColor = ATTextColor();
        field.tintColor = ATTapColor();
        field.borderStyle = UITextBorderStyleNone;
        field.returnKeyType = UIReturnKeyDone;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.delegate = self;
        field.tag = 9000 + index;
        _planNameField = field;

        UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
        [done setImage:ATSymbol(@"checkmark.circle.fill", 20, UIFontWeightSemibold) forState:UIControlStateNormal];
        done.tintColor = ATGoColor();
        done.tag = 9000 + index;
        [done addTarget:self action:@selector(planRenameDone:) forControlEvents:UIControlEventTouchUpInside];
        [done.widthAnchor constraintEqualToConstant:26].active = YES;

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[field, done]];
        stack.alignment = UIStackViewAlignmentCenter;
        stack.spacing = 6;
        stack.layoutMargins = UIEdgeInsetsMake(0, 12, 0, 10);
        stack.layoutMarginsRelativeArrangement = YES;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:row.topAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
            [stack.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        ]];
        return row;
    }

    BOOL active = index == _session.activePlanIndex;

    UIButton *select = [UIButton buttonWithType:UIButtonTypeSystem];
    [select setImage:ATSymbol(active ? @"checkmark.circle.fill" : @"circle", 19, UIFontWeightSemibold)
            forState:UIControlStateNormal];
    select.tintColor = active ? ATTapColor() : ATMutedTextColor();
    select.tag = index;
    [select addTarget:self action:@selector(selectPlanTapped:) forControlEvents:UIControlEventTouchUpInside];
    [select.widthAnchor constraintEqualToConstant:24].active = YES;

    UIButton *name = [UIButton buttonWithType:UIButtonTypeSystem];
    [name setTitle:plan.name forState:UIControlStateNormal];
    name.titleLabel.font = [UIFont systemFontOfSize:15 weight:(active ? UIFontWeightSemibold : UIFontWeightMedium)];
    [name setTitleColor:(active ? ATTextColor() : ATSecondaryTextColor()) forState:UIControlStateNormal];
    name.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    name.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    name.tag = index;
    [name addTarget:self action:@selector(selectPlanTapped:) forControlEvents:UIControlEventTouchUpInside];
    [name setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [name setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    UILabel *steps = [[UILabel alloc] init];
    steps.text = [NSString stringWithFormat:@"%ld 步", (long)plan.actions.count];
    steps.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    steps.textColor = ATMutedTextColor();
    [steps setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIButton *pencil = [UIButton buttonWithType:UIButtonTypeSystem];
    [pencil setImage:ATSymbol(@"pencil", 15, UIFontWeightSemibold) forState:UIControlStateNormal];
    pencil.tintColor = ATMutedTextColor();
    pencil.tag = index;
    [pencil addTarget:self action:@selector(renamePlanTapped:) forControlEvents:UIControlEventTouchUpInside];
    [pencil.widthAnchor constraintEqualToConstant:26].active = YES;

    // 第一次点垃圾桶变成「确认」，3 秒内不点自动撤回，避免误删。
    BOOL confirming = index == _pendingDeletePlanIndex;
    UIButton *trash = [UIButton buttonWithType:UIButtonTypeSystem];
    trash.tag = index;
    [trash addTarget:self action:@selector(removePlanTapped:) forControlEvents:UIControlEventTouchUpInside];
    [trash.widthAnchor constraintEqualToConstant:(confirming ? 40 : 26)].active = YES;
    if (confirming) {
        [trash setTitle:@"确认" forState:UIControlStateNormal];
        trash.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
        [trash setTitleColor:ATStopColor() forState:UIControlStateNormal];
    } else {
        [trash setImage:ATSymbol(@"trash", 16, UIFontWeightSemibold) forState:UIControlStateNormal];
        trash.tintColor = ATMutedTextColor();
    }

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[select, name, steps, pencil, trash]];
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 8;
    stack.layoutMargins = UIEdgeInsetsMake(0, 12, 0, 10);
    stack.layoutMarginsRelativeArrangement = YES;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:row.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
    ]];
    return row;
}

#pragma mark Steps

- (UIView *)stepsSection {
    _stepsCount = [[UILabel alloc] init];
    _stepsCount.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
    _stepsCount.textColor = ATSecondaryTextColor();
    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[[self sectionLabel:@"步骤"], [UIView new], _stepsCount]];

    UIView *box = [[UIView alloc] init];
    box.backgroundColor = ATCardColor();
    box.layer.cornerRadius = 16;
    box.layer.cornerCurve = kCACornerCurveContinuous;
    box.clipsToBounds = YES;
    box.translatesAutoresizingMaskIntoConstraints = NO;

    _stepsScroll = [[UIScrollView alloc] init];
    _stepsScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:_stepsScroll];

    _stepsStack = [[UIStackView alloc] init];
    _stepsStack.axis = UILayoutConstraintAxisVertical;
    _stepsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_stepsScroll addSubview:_stepsStack];

    _emptyLabel = [[UILabel alloc] init];
    _emptyLabel.text = @"还没有步骤。\n点「选点」，然后在屏幕上点按或拖动。";
    _emptyLabel.numberOfLines = 0;
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _emptyLabel.textColor = ATMutedTextColor();
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:_emptyLabel];

    _stepsHeight = [box.heightAnchor constraintEqualToConstant:70];
    [NSLayoutConstraint activateConstraints:@[
        _stepsHeight,
        [_stepsScroll.topAnchor constraintEqualToAnchor:box.topAnchor],
        [_stepsScroll.bottomAnchor constraintEqualToAnchor:box.bottomAnchor],
        [_stepsScroll.leadingAnchor constraintEqualToAnchor:box.leadingAnchor],
        [_stepsScroll.trailingAnchor constraintEqualToAnchor:box.trailingAnchor],
        [_stepsStack.topAnchor constraintEqualToAnchor:_stepsScroll.contentLayoutGuide.topAnchor],
        [_stepsStack.bottomAnchor constraintEqualToAnchor:_stepsScroll.contentLayoutGuide.bottomAnchor],
        [_stepsStack.leadingAnchor constraintEqualToAnchor:_stepsScroll.frameLayoutGuide.leadingAnchor],
        [_stepsStack.trailingAnchor constraintEqualToAnchor:_stepsScroll.frameLayoutGuide.trailingAnchor],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
        [_emptyLabel.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:12],
        [_emptyLabel.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-12],
    ]];

    UIStackView *section = [[UIStackView alloc] initWithArrangedSubviews:@[header, box]];
    section.axis = UILayoutConstraintAxisVertical;
    section.spacing = 8;
    return section;
}

- (UIButton *)pillWithTitle:(NSString *)title symbol:(NSString *)symbol tint:(UIColor *)tint action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:ATSymbol(symbol, 13, UIFontWeightBold) forState:UIControlStateNormal];
    [button setTitle:[@" " stringByAppendingString:title] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    button.tintColor = tint;
    [button setTitleColor:ATTextColor() forState:UIControlStateNormal];
    button.backgroundColor = ATCardColor();
    button.layer.cornerRadius = 12;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    [button.heightAnchor constraintEqualToConstant:40].active = YES;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIView *)editButtons {
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self pillWithTitle:@"选点" symbol:@"record.circle" tint:ATStopColor() action:@selector(recordTapped)],
        [self pillWithTitle:@"撤销" symbol:@"arrow.uturn.backward" tint:ATTextColor() action:@selector(undoTapped)],
        [self pillWithTitle:@"清空" symbol:@"trash" tint:ATTextColor() action:@selector(clearTapped)],
    ]];
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = 8;
    return row;
}

- (UIView *)sliderRowWithTitle:(NSString *)title
                        slider:(UISlider *__strong *)outSlider
                         value:(UILabel *__strong *)outValue
                          tint:(UIColor *)tint {
    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    label.textColor = ATTextColor();
    UILabel *value = [[UILabel alloc] init];
    value.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
    value.textColor = tint;
    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[label, [UIView new], value]];

    UISlider *slider = [[UISlider alloc] init];
    slider.minimumTrackTintColor = tint;
    slider.maximumTrackTintColor = [UIColor colorWithWhite:1 alpha:0.28];
    slider.thumbTintColor = [UIColor whiteColor];
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[top, slider]];
    row.axis = UILayoutConstraintAxisVertical;
    row.spacing = 4;
    *outSlider = slider;
    *outValue = value;
    return row;
}

// 循环次数输入框：直接输入数字，0 或留空表示无限循环。
- (UIView *)loopRow {
    UILabel *label = [[UILabel alloc] init];
    label.text = @"循环次数";
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    label.textColor = ATTextColor();

    UIView *box = [[UIView alloc] init];
    box.backgroundColor = ATCardColor();
    box.layer.cornerRadius = 10;
    box.layer.cornerCurve = kCACornerCurveContinuous;
    box.clipsToBounds = YES;

    UITextField *field = [[UITextField alloc] init];
    field.keyboardType = UIKeyboardTypeNumberPad;
    field.returnKeyType = UIReturnKeyDone;
    field.textAlignment = NSTextAlignmentRight;
    field.font = [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightSemibold];
    field.textColor = ATGoColor();
    field.borderStyle = UITextBorderStyleNone;
    field.placeholder = @"∞";
    field.delegate = self;
    field.text = _session.loopCount ? [NSString stringWithFormat:@"%ld", (long)_session.loopCount] : @"";
    [field addTarget:self action:@selector(loopChanged:) forControlEvents:UIControlEventEditingChanged];
    [field addTarget:self action:@selector(loopDone:) forControlEvents:UIControlEventEditingDidEndOnExit];
    [field addTarget:self action:@selector(loopDone:) forControlEvents:UIControlEventEditingDidEnd];
    [field.widthAnchor constraintEqualToConstant:56].active = YES;

    UILabel *unit = [[UILabel alloc] init];
    unit.text = @"次";
    unit.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    unit.textColor = ATSecondaryTextColor();

    UIStackView *input = [[UIStackView alloc] initWithArrangedSubviews:@[field, unit]];
    input.axis = UILayoutConstraintAxisHorizontal;
    input.alignment = UIStackViewAlignmentCenter;
    input.spacing = 4;
    input.layoutMargins = UIEdgeInsetsMake(0, 10, 0, 10);
    input.layoutMarginsRelativeArrangement = YES;
    input.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:input];
    [NSLayoutConstraint activateConstraints:@[
        [input.topAnchor constraintEqualToAnchor:box.topAnchor constant:6],
        [input.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-6],
        [input.leadingAnchor constraintEqualToAnchor:box.leadingAnchor],
        [input.trailingAnchor constraintEqualToAnchor:box.trailingAnchor],
    ]];
    _loopCountField = field;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[label, [UIView new], box]];
    row.alignment = UIStackViewAlignmentCenter;

    UILabel *hint = [[UILabel alloc] init];
    hint.text = @"留空或 0 = 无限循环";
    hint.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    hint.textColor = ATMutedTextColor();
    hint.textAlignment = NSTextAlignmentRight;

    UIStackView *wrap = [[UIStackView alloc] initWithArrangedSubviews:@[row, hint]];
    wrap.axis = UILayoutConstraintAxisVertical;
    wrap.spacing = 2;
    return wrap;
}

- (UIView *)timingSection {
    UIView *swipeTimeRow = [self sliderRowWithTitle:@"滑动时长" slider:&_swipeTimeSlider value:&_swipeTimeValue tint:ATSwipeColor()];
    _swipeTimeSlider.value = ATSliderValue(_session.swipeDuration, kMinSwipeTime, kMaxSwipeTime);

    UIView *loopRow = [self loopRow];

    UILabel *touchesLabel = [[UILabel alloc] init];
    touchesLabel.text = @"显示触摸";
    touchesLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    touchesLabel.textColor = ATTextColor();
    _touchesSwitch = [[UISwitch alloc] init];
    _touchesSwitch.onTintColor = ATGoColor();
    _touchesSwitch.on = _session.showTouches;
    [_touchesSwitch addTarget:self action:@selector(touchesChanged) forControlEvents:UIControlEventValueChanged];
    UIStackView *touchesRow = [[UIStackView alloc] initWithArrangedSubviews:@[touchesLabel, [UIView new], _touchesSwitch]];
    touchesRow.alignment = UIStackViewAlignmentCenter;

    [self refreshTimingLabels];
    UIStackView *section = [[UIStackView alloc] initWithArrangedSubviews:@[[self sectionLabel:@"时序"], swipeTimeRow, loopRow, touchesRow]];
    section.axis = UILayoutConstraintAxisVertical;
    section.spacing = 12;
    [section setCustomSpacing:6 afterView:section.arrangedSubviews.firstObject];
    return section;
}

- (UIView *)runSection {
    _runButton = [ATGradientButton buttonWithType:UIButtonTypeCustom];
    _runButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    _runButton.tintColor = [UIColor whiteColor];
    [_runButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_runButton.heightAnchor constraintEqualToConstant:54].active = YES;
    [_runButton addTarget:self action:@selector(runTapped) forControlEvents:UIControlEventTouchUpInside];

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
    _statusLabel.textColor = ATSecondaryTextColor();
    _statusLabel.textAlignment = NSTextAlignmentCenter;

    UIStackView *section = [[UIStackView alloc] initWithArrangedSubviews:@[_runButton, _statusLabel]];
    section.axis = UILayoutConstraintAxisVertical;
    section.spacing = 8;
    return section;
}

#pragma mark Steps

- (UIView *)rowForAction:(ATAction *)action index:(NSInteger)index {
    BOOL swipe = action.type == ATActionTypeSwipe;
    UIColor *color = swipe ? ATSwipeColor() : ATTapColor();

    UILabel *badge = [[UILabel alloc] init];
    badge.text = [NSString stringWithFormat:@"%ld", (long)index + 1];
    badge.textAlignment = NSTextAlignmentCenter;
    badge.font = [UIFont systemFontOfSize:13 weight:UIFontWeightHeavy];
    badge.textColor = [UIColor whiteColor];
    badge.backgroundColor = color;
    badge.layer.cornerRadius = 14;
    badge.clipsToBounds = YES;
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    [badge.widthAnchor constraintEqualToConstant:28].active = YES;
    [badge.heightAnchor constraintEqualToConstant:28].active = YES;

    UILabel *title = [[UILabel alloc] init];
    title.text = swipe ? @"滑动" : @"点击";
    title.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    title.textColor = ATTextColor();
    UILabel *detail = [[UILabel alloc] init];
    detail.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    detail.textColor = ATSecondaryTextColor();
    detail.text = swipe
        ? [NSString stringWithFormat:@"%.0f,%.0f → %.0f,%.0f", action.start.x, action.start.y, action.end.x, action.end.y]
        : [NSString stringWithFormat:@"x %.0f  y %.0f", action.start.x, action.start.y];
    UIStackView *texts = [[UIStackView alloc] initWithArrangedSubviews:@[title, detail]];
    texts.axis = UILayoutConstraintAxisVertical;

    // 上移 / 下移：调整步骤的执行顺序和点位位置
    UIButton *up = [UIButton buttonWithType:UIButtonTypeSystem];
    [up setImage:ATSymbol(@"chevron.up", 16, UIFontWeightBold) forState:UIControlStateNormal];
    up.tintColor = ATSecondaryTextColor();
    up.tag = index;
    up.enabled = index > 0;
    [up addTarget:self action:@selector(moveUpTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIButton *down = [UIButton buttonWithType:UIButtonTypeSystem];
    [down setImage:ATSymbol(@"chevron.down", 16, UIFontWeightBold) forState:UIControlStateNormal];
    down.tintColor = ATSecondaryTextColor();
    down.tag = index;
    down.enabled = index < (NSInteger)_session.actions.count - 1;
    [down addTarget:self action:@selector(moveDownTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIButton *remove = [UIButton buttonWithType:UIButtonTypeSystem];
    [remove setImage:ATSymbol(@"minus.circle.fill", 20, UIFontWeightSemibold) forState:UIControlStateNormal];
    remove.tintColor = ATMutedTextColor();
    remove.tag = index;
    [remove addTarget:self action:@selector(removeTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[badge, texts, [UIView new], up, down, remove]];
    top.alignment = UIStackViewAlignmentCenter;
    top.spacing = 8;

    // 本步骤独立延时输入框
    UILabel *delayLabel = [[UILabel alloc] init];
    delayLabel.text = @"此步后延时";
    delayLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    delayLabel.textColor = ATSecondaryTextColor();

    UIView *delayBox = [[UIView alloc] init];
    delayBox.backgroundColor = ATCardColor();
    delayBox.layer.cornerRadius = 8;
    delayBox.layer.cornerCurve = kCACornerCurveContinuous;
    delayBox.clipsToBounds = YES;

    UITextField *delayField = [[UITextField alloc] init];
    delayField.keyboardType = UIKeyboardTypeNumberPad;
    delayField.returnKeyType = UIReturnKeyDone;
    delayField.textAlignment = NSTextAlignmentRight;
    delayField.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
    delayField.textColor = color;
    delayField.borderStyle = UITextBorderStyleNone;
    delayField.text = [NSString stringWithFormat:@"%ld", (long)action.delayMs];
    delayField.delegate = self;
    delayField.tag = index;
    [delayField.widthAnchor constraintEqualToConstant:64].active = YES;
    [delayField addTarget:self action:@selector(stepDelayChanged:) forControlEvents:UIControlEventEditingChanged];
    [delayField addTarget:self action:@selector(stepDelayDone:) forControlEvents:UIControlEventEditingDidEndOnExit];
    [delayField addTarget:self action:@selector(stepDelayDone:) forControlEvents:UIControlEventEditingDidEnd];

    UILabel *unit = [[UILabel alloc] init];
    unit.text = @"ms";
    unit.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    unit.textColor = ATSecondaryTextColor();

    UIStackView *delayInput = [[UIStackView alloc] initWithArrangedSubviews:@[delayField, unit]];
    delayInput.axis = UILayoutConstraintAxisHorizontal;
    delayInput.alignment = UIStackViewAlignmentCenter;
    delayInput.spacing = 4;
    delayInput.layoutMargins = UIEdgeInsetsMake(0, 8, 0, 8);
    delayInput.layoutMarginsRelativeArrangement = YES;
    delayInput.translatesAutoresizingMaskIntoConstraints = NO;
    [delayBox addSubview:delayInput];
    [NSLayoutConstraint activateConstraints:@[
        [delayInput.topAnchor constraintEqualToAnchor:delayBox.topAnchor constant:3],
        [delayInput.bottomAnchor constraintEqualToAnchor:delayBox.bottomAnchor constant:-3],
        [delayInput.leadingAnchor constraintEqualToAnchor:delayBox.leadingAnchor],
        [delayInput.trailingAnchor constraintEqualToAnchor:delayBox.trailingAnchor],
    ]];
    [_delayFields addObject:delayField];

    UIStackView *bottom = [[UIStackView alloc] initWithArrangedSubviews:@[delayLabel, [UIView new], delayBox]];
    bottom.alignment = UIStackViewAlignmentCenter;
    bottom.spacing = 8;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[top, bottom]];
    row.axis = UILayoutConstraintAxisVertical;
    row.spacing = 6;
    row.layoutMargins = UIEdgeInsetsMake(8, 12, 8, 12);
    row.layoutMarginsRelativeArrangement = YES;
    [row.heightAnchor constraintEqualToConstant:kStepRowHeight].active = YES;
    return row;
}

- (void)reloadSteps {
    for (UIView *row in _rows) {
        [row removeFromSuperview];
    }
    [_rows removeAllObjects];
    [_delayFields removeAllObjects];
    [self reloadPlans];
    NSArray<ATAction *> *actions = _session.actions;
    NSInteger taps = 0;
    for (NSInteger i = 0; i < (NSInteger)actions.count; i++) {
        UIView *row = [self rowForAction:actions[i] index:i];
        [_stepsStack addArrangedSubview:row];
        [_rows addObject:row];
        taps += actions[i].type == ATActionTypeTap;
    }
    NSInteger swipes = (NSInteger)actions.count - taps;
    _stepsCount.text = actions.count ? [NSString stringWithFormat:@"%ld 点击 · %ld 滑动", (long)taps, (long)swipes] : @"";
    _emptyLabel.hidden = actions.count > 0;
    _stepsHeight.constant = actions.count ? MIN(actions.count, kVisibleStepRows) * kStepRowHeight : 70;
    _highlighted = -1;
    [self updateRunState];
}

- (void)highlightStep:(NSInteger)index {
    if (_highlighted >= 0 && _highlighted < (NSInteger)_rows.count) {
        _rows[_highlighted].backgroundColor = [UIColor clearColor];
    }
    _highlighted = index;
    if (index >= 0 && index < (NSInteger)_rows.count) {
        UIView *row = _rows[index];
        BOOL swipe = _session.actions[index].type == ATActionTypeSwipe;
        row.backgroundColor = [(swipe ? ATSwipeColor() : ATTapColor()) colorWithAlphaComponent:0.2];
        [_stepsScroll scrollRectToVisible:row.frame animated:YES];
    }
    [self updateStatus];
}

- (void)updateRunState {
    BOOL running = _session.running;
    [_runButton setImage:ATSymbol(running ? @"stop.fill" : @"play.fill", 16, UIFontWeightBold) forState:UIControlStateNormal];
    [_runButton setTitle:running ? @"  停止" : @"  开始" forState:UIControlStateNormal];
    UIColor *base = running ? ATStopColor() : ATGoColor();
    CGFloat h, s, b, a;
    [base getHue:&h saturation:&s brightness:&b alpha:&a];
    _runButton.gradient.colors = @[(id)base.CGColor, (id)[UIColor colorWithHue:h saturation:s brightness:b * 0.72 alpha:a].CGColor];
    if (!running) {
        [self highlightStep:-1];
    }
    [self updateStatus];
}

- (void)updateStatus {
    NSUInteger count = _session.actions.count;
    if (_session.running) {
        NSString *loops = _session.loopCount ? [NSString stringWithFormat:@"%ld/%ld", (long)_session.currentLoop, (long)_session.loopCount]
                                             : [NSString stringWithFormat:@"%ld", (long)_session.currentLoop];
        _statusLabel.text = [NSString stringWithFormat:@"第 %@ 轮  ·  第 %ld/%lu 步", loops, (long)_session.currentIndex + 1, (unsigned long)count];
    } else {
        _statusLabel.text = count ? @"点悬浮按钮可停止运行" : @"先选点，再点开始";
    }
}

- (void)showMessage:(NSString *)message {
    _statusLabel.text = message;
    _statusLabel.textColor = ATStopColor();
    CAKeyframeAnimation *shake = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    shake.values = @[@0, @-10, @10, @-6, @6, @0];
    shake.duration = 0.35;
    [self.layer addAnimation:shake forKey:@"shake"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self->_statusLabel.textColor = ATSecondaryTextColor();
        [self updateStatus];
    });
}

#pragma mark Controls

- (void)refreshTimingLabels {
    _swipeTimeValue.text = ATFormatSeconds(_session.swipeDuration);
    if (!_loopCountField.isEditing) {
        _loopCountField.text = _session.loopCount ? [NSString stringWithFormat:@"%ld", (long)_session.loopCount] : @"";
    }
    // 刷新每步延时显示（编辑中的那一个不覆盖，避免打断输入）
    NSArray<ATAction *> *actions = _session.actions;
    for (NSInteger i = 0; i < (NSInteger)_delayFields.count && i < (NSInteger)actions.count; i++) {
        UITextField *field = _delayFields[i];
        if (!field.isEditing) {
            field.text = [NSString stringWithFormat:@"%ld", (long)actions[i].delayMs];
        }
    }
}

// 每一步独立延时：就地改模型并保存，不重建整行（否则键盘会被收起）。
- (void)stepDelayChanged:(UITextField *)field {
    NSInteger index = field.tag;
    NSArray<ATAction *> *actions = _session.actions;
    if (index < 0 || index >= (NSInteger)actions.count) {
        return;
    }
    NSInteger value = [field.text integerValue];
    actions[index].delayMs = MIN(MAX(value, 10), 60000);
    [_session save];
}

- (void)stepDelayDone:(UITextField *)field {
    [field resignFirstResponder];
    [self refreshTimingLabels];
}

// 悬浮窗默认不是 keyWindow，直接 becomeFirstResponder 键盘不会弹。
// 在开始编辑前先通知外层把悬浮窗临时设为 keyWindow。
- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
    [[NSNotificationCenter defaultCenter] postNotificationName:ATOverlayKeyboardWillShowNotification object:self];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    // 方案改名框：失焦即保存，名字为空则保留原名。
    // 不管当前是不是改名状态都保存，避免切换/重排把这个框拆掉时丢掉刚输入的名字。
    if (textField.tag >= 9000) {
        NSInteger index = textField.tag - 9000;
        if (_renamingPlanIndex == index) {
            _renamingPlanIndex = -1;
        }
        [_session renamePlanAtIndex:index toName:textField.text];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reloadPlans];
        });
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:ATOverlayKeyboardDidHideNotification object:self];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)sliderChanged:(UISlider *)slider {
    _session.swipeDuration = ATSeconds(slider.value, kMinSwipeTime, kMaxSwipeTime);
    [self refreshTimingLabels];
}

- (void)loopChanged:(UITextField *)field {
    NSInteger value = [field.text integerValue]; // 空串 → 0 → 无限循环
    if (value < 0) value = 0;
    if (value > 99999) {
        value = 99999;
        field.text = @"99999";
    }
    _session.loopCount = value;
    [self updateStatus];
}

- (void)loopDone:(UITextField *)field {
    [field resignFirstResponder];
    [self refreshTimingLabels];
}

- (void)touchesChanged {
    _session.showTouches = _touchesSwitch.on;
    if (self.onTouchesChanged) {
        self.onTouchesChanged(_touchesSwitch.on);
    }
}

#pragma mark 方案操作

- (void)addPlanTapped {
    [_session createPlanNamed:nil];
    _pendingDeletePlanIndex = -1;
    // 新建后直接进入改名，省一次点击。
    _renamingPlanIndex = _session.activePlanIndex;
    [self reloadPlans];
    [_stepsScroll setContentOffset:CGPointZero animated:NO];
}

- (void)selectPlanTapped:(UIButton *)button {
    _pendingDeletePlanIndex = -1;
    _renamingPlanIndex = -1;
    [_session selectPlanAtIndex:button.tag];
    [self reloadPlans];
}

- (void)renamePlanTapped:(UIButton *)button {
    _pendingDeletePlanIndex = -1;
    _renamingPlanIndex = button.tag;
    [self reloadPlans];
}

- (void)removePlanTapped:(UIButton *)button {
    NSInteger index = button.tag;
    NSArray<ATPlan *> *plans = _session.plans;
    if (index < 0 || index >= (NSInteger)plans.count) {
        return;
    }
    if (plans.count <= 1) {
        [self showMessage:@"至少保留一套方案"];
        return;
    }
    if (_pendingDeletePlanIndex != index) {
        _pendingDeletePlanIndex = index;
        [self reloadPlans];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self->_pendingDeletePlanIndex == index) {
                self->_pendingDeletePlanIndex = -1;
                [self reloadPlans];
            }
        });
        return;
    }
    _pendingDeletePlanIndex = -1;
    [_session removePlanAtIndex:index];
    [self reloadPlans];
}

- (void)planRenameDone:(UIButton *)button {
    NSInteger index = button.tag - 9000;
    UITextField *field = _planNameField;
    _renamingPlanIndex = -1;
    if (field && index >= 0) {
        if (![_session renamePlanAtIndex:index toName:field.text]) {
            [self showMessage:@"方案名不能为空"];
        }
    }
    [field resignFirstResponder];
    [self reloadPlans];
}

- (void)recordTapped {
    if (self.onRecord) {
        self.onRecord();
    }
}

- (void)undoTapped {
    [_session removeLastAction];
}

- (void)clearTapped {
    [_session removeAllActions];
}

- (void)removeTapped:(UIButton *)button {
    [_session removeActionAtIndex:button.tag];
}

- (void)moveUpTapped:(UIButton *)button {
    [_session moveActionAtIndex:button.tag byOffset:-1];
}

- (void)moveDownTapped:(UIButton *)button {
    [_session moveActionAtIndex:button.tag byOffset:1];
}

- (void)closeTapped {
    if (self.onClose) {
        self.onClose();
    }
}

- (void)runTapped {
    if (self.onToggleRun) {
        self.onToggleRun();
    }
}

@end
