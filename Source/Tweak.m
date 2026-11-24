#import <UIKit/UIKit.h>
#import "WJBlocker.h"
#import "WJOverlay.h"

// dylib 被加载时执行。不依赖 Substrate / Substitute，纯 runtime。
__attribute__((constructor)) static void WJEntry(void) {
    @autoreleasepool {
        // 安装 openURL / canOpenURL hook
        WJBlockerInstall();
        // 附着悬浮开关窗（延迟到 App window 就绪）
        WJOverlayPresent();
    }
}
