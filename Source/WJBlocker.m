#import "WJBlocker.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString *const kWJEnabledKey = @"com.wechatjumpblocker.enabled";

BOOL WJBlockerEnabled(void) {
    // 默认关闭：不注入时不影响任何行为，用户需手动打开悬浮开关。
    return [[NSUserDefaults standardUserDefaults] boolForKey:kWJEnabledKey];
}

void WJBlockerSetEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kWJEnabledKey];
}

// 判断一个 URL 是不是"跳微信"相关。
// 微信 SDK 跳转 scheme：weixin:// / wechat:// / wxopen://
// Universal Link：https://applink.qq.com / https://help.wechat.com
static BOOL WJIsWeChatURL(NSURL *url) {
    if (!url) return NO;
    NSString *s = [[url absoluteString] lowercaseString];
    if ([s hasPrefix:@"weixin://"]) return YES;
    if ([s hasPrefix:@"wechat://"]) return YES;
    if ([s hasPrefix:@"wxopen://"]) return YES;
    if ([s hasPrefix:@"weixinulapi://"]) return YES;
    if ([s containsString:@"applink.qq.com"]) return YES;
    if ([s containsString:@"help.wechat.com"]) return YES;
    return NO;
}

// 构造一个"分享成功"的回调喂给目标 App 的 WXApiDelegate。
// 微信官方约定：errCode == 0 (WXSuccess) 表示成功。
// 用 runtime 动态创建 SendMessageToWXResp，避免编译期依赖微信 SDK 头文件。
static void WJFakeWeChatSuccess(void) {
    id<UIApplicationDelegate> appDelegate = [[UIApplication sharedApplication] delegate];
    if (!appDelegate) return;
    if (![appDelegate respondsToSelector:@selector(onResp:)]) return;

    Class respClass = NSClassFromString(@"SendMessageToWXResp");
    if (!respClass) {
        // 退而求其次：某些 SDK 版本回调基类名不同，尝试 BaseResp
        respClass = NSClassFromString(@"BaseResp");
    }
    if (!respClass) return;

    id resp = [[respClass alloc] init];
    // errCode 为 int 属性，用 KVC 设置；同时带一个空的 errStr 更接近真实回调。
    @try {
        [resp setValue:@(0) forKey:@"errCode"];
        [resp setValue:@"" forKey:@"errStr"];
    } @catch (__unused NSException *e) {
        return;
    }

    // 稍作延迟，模拟微信"处理完"再回调的时序，避免与 SDK 内部状态冲突。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (WJBlockerEnabled()) {
            [appDelegate performSelector:@selector(onResp:) withObject:resp];
        }
    });
}

#pragma mark - Swizzled methods on UIApplication

@interface UIApplication (WJBlocker)
- (BOOL)wj_openURL:(NSURL *)url;
- (BOOL)wj_openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options completionHandler:(nullable void (^)(BOOL success))completionHandler;
- (BOOL)wj_canOpenURL:(NSURL *)url;
@end

@implementation UIApplication (WJBlocker)

// iOS 10 之前的跳转入口
- (BOOL)wj_openURL:(NSURL *)url {
    if (WJBlockerEnabled() && WJIsWeChatURL(url)) {
        WJFakeWeChatSuccess();
        // 关键：返回 YES 让调用方认为"跳转已成功发起"，但不调用原实现 -> 微信不会被打开
        return YES;
    }
    return [self wj_openURL:url];
}

// iOS 10+ 主流跳转入口
- (BOOL)wj_openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options completionHandler:(void (^)(BOOL))completionHandler {
    if (WJBlockerEnabled() && WJIsWeChatURL(url)) {
        WJFakeWeChatSuccess();
        if (completionHandler) completionHandler(YES);
        return YES;
    }
    return [self wj_openURL:url options:options completionHandler:completionHandler];
}

// 让微信 SDK 认为"微信已安装"，这样它才会走后续 sendReq 流程并拿到成功回调
- (BOOL)wj_canOpenURL:(NSURL *)url {
    if (WJBlockerEnabled() && WJIsWeChatURL(url)) {
        return YES;
    }
    return [self wj_canOpenURL:url];
}

@end

#pragma mark - Install

static void wj_exchange(Class cls, SEL original, SEL swizzled) {
    Method origMethod = class_getInstanceMethod(cls, original);
    Method swizMethod = class_getInstanceMethod(cls, swizzled);
    if (!origMethod || !swizMethod) return;
    method_exchangeImplementations(origMethod, swizMethod);
}

void WJBlockerInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class app = [UIApplication class];
        wj_exchange(app, @selector(openURL:), @selector(wj_openURL:));
        wj_exchange(app, @selector(openURL:options:completionHandler:),
                    @selector(wj_openURL:options:completionHandler:));
        wj_exchange(app, @selector(canOpenURL:), @selector(wj_canOpenURL:));
    });
}
