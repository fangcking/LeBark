#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 拦截开关是否打开（默认关闭；状态持久化到目标 App 的 NSUserDefaults）
BOOL WJBlockerEnabled(void);
void WJBlockerSetEnabled(BOOL enabled);

// 安装 hook（在 constructor 中调用，只执行一次）
void WJBlockerInstall(void);

NS_ASSUME_NONNULL_END
