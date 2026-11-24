#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// 悬浮窗入口，在 constructor 中调用一次。会自动附着到当前 App 的 window 上。
void WJOverlayPresent(void);

NS_ASSUME_NONNULL_END
