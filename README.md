# 乐币BARK · iOS 结账账本（TrollStore 版）

一个用 SwiftUI 写的 iPhone App：**不接管 BARK 的通知，而是直接读取本机 BARK 里已有的历史消息**，把 7 台服务器的推送汇总成一个可搜索、可标记结账、可按周截图的账本。

全程复用 `SmsRemote`（短信转发）那套交付形式：源码 + GitHub 云编译 + 巨魔安装，无需 Mac、无需开发者账号、无需公网服务器。

## 它解决什么

你现在的流程：7 台服务器每天 12:00 各自推一条「今日汇总」到 BARK → 消息散在 BARK 里，不好统计、不好复制、没法标记谁结了账。

这个 App：

- **免手动复制**：用巨魔权限直接读 BARK 的历史消息，**只拉「乐币」分组**（分组名可改），自动解析成结账名单存进本 App
- **一键复制名字**：名单里点一下名字就复制，直接拿去搜人
- **标记已结账**：点圆圈或左滑标记，实时看到谁没结
- **按周截图**：干净的白色名单视图，可直接截屏发群；也能复制成文字
- **本地存储**：所有数据只存你这台 iPhone，不上传任何地方

## 数据从哪来（三条路）

1. **从 BARK 拉取（推荐，免手动）**：首页绿色按钮「从 BARK 拉取」或「设置 → 拉取」，读取 App Group `group.bark` 下的 `recent_messages_snapshot.json`，**只保留 group 等于设定分组名（默认「乐币」）的消息**，解析后存进本 App。分组名在设置页可改，读取失败时会列出 BARK 里现有的分组名供你选择。
   - 拉取后数据存在本 App，会一直累积，不受 BARK 快照只保留 100 条的限制；建议每天拉一次
2. **局域网直连（可选）**：若 7 台服务器和手机同内网，让它们 POST 到 App 显示的地址，名单自动入库
3. **粘贴导入（兜底）**：从 BARK 长按复制历史消息，粘贴进来，支持一次多条自动切分

## 推送格式（解析器认这个）

```
[202]今日汇总
金币:203/12684,账号:2/44
[21][929]:82unicorn:金 90,[22.5]
[44][932]:353揪揪 n:金 113,[28.25]
异常信息:
[25][0495 常 A10][超出个人每周限制]
```

字段含义：
- `[202]` 服务器编号
- `金币:成功/总数,账号:成功/总数` 汇总数字
- `[序号][时间毫秒]:名字:金 N,[金额]` 结账人（名字就是要复制去搜人的字段）
- `[序号][名字][原因]` 异常记录，单独归类不计入结账名单

金额缺失时按金币 ÷ 4 自动推算。重复导入不会生成重复名单。

## 界面

- **今日**：各服务器汇总卡片、待结账/已结账统计、异常信息
- **结账名单**：按日期分组，搜索名字，标记结账，批量操作，一键复制全部名字
- **按周**：按自然周切换，截图专用视图（白底名单）。每天一个完整日期标题（如「2026年11月19日 周四」），明细只显示「名字 / 金币 / 需结账金额」三项，不出现序号和毫秒；顶部有周范围与合计，右上角可复制同样格式的文字版，底部可开启紧凑模式（只留名字，一屏更多）
- **设置**：BARK 读取、粘贴导入、局域网接收地址、服务器编号管理、端口、清空数据

## 为什么能读 BARK 的数据（原理）

BARK 官方源码（Finb/Bark）里，历史消息存两处：

- 主 App 沙盒 `Documents/bark.realm`（Realm 数据库）
- App Group `group.bark` 容器下 `recent_messages_snapshot.json`（最近 100 条消息快照，字段 title/body/group/createDate）

巨魔（TrollStore）允许 App 自带任意 entitlements。本 App 声明了：
- `com.apple.security.application-groups = group.bark` → 可读共享容器里的快照 JSON
- `com.apple.private.security.no-sandbox` + `platform-application` + `com.apple.private.security.storage.AppDataContainers` → 脱沙盒后可扫描并读取 BARK 的数据容器

云编译脚本用 `ldid -S` 伪签名把这些权限写进 IPA，TrollStore 安装时原样保留。

> 关于真·APNs 推送：BARK 的通知走苹果服务器，需要开发者账号 + 推送证书 + 非巨魔签名，巨魔版做不到。所以本方案让 BARK 继续负责通知，本 App 只负责数据管理——这是零成本且最稳的组合。

## 云编译出 IPA（无需 Mac / 开发者账号）

`.github/workflows/build.yml` 已配好：XcodeGen 生成工程 → 编译 → ldid 伪签名写入 entitlements → 打 IPA。

1. 把 `LeBark/` 整个目录作为一个仓库推到 GitHub（仓库根目录能看到 `project.yml`、`LeBark/`、`exportOptions.plist`、`.github/`）
2. 推送到 `main`/`master` 自动触发，也可在 Actions 页手动 Run workflow
3. 跑完后在 Artifacts 下载 `LeBark-TrollStore-IPA`，解压得 `LeBark.ipa`
4. 用巨魔安装：文件 App 打开 IPA → 分享 → TrollStore 安装

详细图文步骤见 `云编译傻瓜教程.md`。

## 本地编译（有 Mac + Xcode 时）

```bash
brew install xcodegen ldid
cd LeBark
xcodegen generate
open LeBark.xcodeproj
```

真机编译后，用 ldid 重新伪签名写入 entitlements，再打包安装。

## 重新生成图标

```bash
python make_ios_icon.py
```

纯标准库生成 1024×1024 AppIcon 和 512×512 预览图，无需 Pillow。

## 兼容性

- 部署目标 iOS 15.0，用 NavigationView + 单参数 onChange，兼容 iOS 15~18
- 需要巨魔（TrollStore）环境才能读取 BARK 数据；普通签名安装只能粘贴导入
- 数据全部存 UserDefaults，不联网上传
