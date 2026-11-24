# WeChatJumpBlocker（巨魔环境 QQ音乐拦截跳微信插件）

一个注入到 QQ音乐的 iOS dylib 插件。打开悬浮开关后，QQ音乐里"分享到微信 / 跳转微信"**不会真的打开微信**，但 QQ音乐仍会认为跳转成功（不弹失败、不卡在分享中）。

## 原理

微信分享的跳转链路：`QQ音乐 → 微信SDK sendReq → UIApplication openURL(weixin://) → 微信 → 回调 onResp(errCode=0) → 显示"分享成功"`。

本插件用 Objective-C runtime 方法交换（不依赖 CydiaSubstrate）hook 三个点：

1. `-[UIApplication canOpenURL:]`：对微信 URL 返回 `YES`，让 SDK 认为"微信已安装"。
2. `-[UIApplication openURL:]` 与 `-[UIApplication openURL:options:completionHandler:]`：对微信 URL 返回 `YES` 但不调用原实现——SDK 认为"跳转已发起成功"，微信却不会被打开。
3. 伪造回调：拦截后延迟构造一个 `SendMessageToWXResp`（`errCode=0`，即 `WXSuccess`）喂给 AppDelegate 的 `onResp:`，让 QQ音乐显示"分享成功"。

> 拦截范围：`weixin://` / `wechat://` / `wxopen://` / `weixinulapi://` / `applink.qq.com` / `help.wechat.com`。开关关闭时全部放行，行为与未注入一致。

## 悬浮窗

- 淡蓝色小圆球，可拖动、贴边吸附，显示在所有内容最上层。
- 点击展开面板，里面有开关（默认关闭）。状态持久化在 QQ音乐沙盒内。
- 空白处触摸穿透，不影响 QQ音乐正常操作。

## 用法

1. 用 TrollFools 把 `WeChatJumpBlocker.dylib`（或 `.deb`）注入 QQ音乐。
2. 重启 QQ音乐，屏幕右侧出现淡蓝色小圆球。
3. 点圆球，打开"拦截跳转微信"开关。
4. 之后在 QQ音乐里点分享到微信，不会跳到微信，但会提示分享成功。

## 编译（Mac + Theos）

```bash
make package FINALPACKAGE=1
```

产物：`packages/com.wechatjumpblocker.tweak_1.0.0_iphoneos-arm64.deb`，内含 `WeChatJumpBlocker.dylib`（arm64 + arm64e）。
