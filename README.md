# 乐币BARK · iOS 结账账本（TrollStore 版）

一个用 SwiftUI 写的 iPhone App：**不接管 BARK 的通知，而是直接读取本机 BARK 里已有的历史消息**，把 7 台服务器的推送汇总成一个可搜索、可标记结账、可按周截图的账本。

全程复用 `SmsRemote`（短信转发）那套交付形式：源码 + GitHub 云编译 + 巨魔安装，无需 Mac、无需开发者账号、无需公网服务器。

## 它解决什么

你现在的流程：7 台服务器每天 12:00 各自推一条「今日汇总」到 BARK → 消息散在 BARK 里，不好统计、不好复制、没法标记谁结了账。

这个 App：

- **全自动同步**：进入 App 自动从 BARK 拉取一次，之后每 60 秒拉一次，**只拉「乐币」分组**（分组名可改），无需任何手动操作
- **完整历史**：在 BARK 里导出一次备份 JSON，本 App 自动读取全部历史（如 451 条、body 不截断）；以后每天新推送由 100 条快照自动增量同步，不再需要重复导出
- **本地持续累积**：每次拉取都把消息存进本 App 自己的库并永久累积，用得越久历史越全
- **一键复制名字**：名单里点一下名字就复制，直接拿去搜人
- **标记已结账**：点圆圈或左滑标记，实时看到谁没结
- **人数校验**：把推送声明的「账号成功数」与解析出的人数比对，不一致时标红提示，避免解析遗漏
- **按周截图**：干净的白色名单视图，可直接截屏发群；也能复制成文字；名单与按周均按时间倒序
- **本地存储**：所有数据只存你这台 iPhone 的 Documents 目录，覆盖安装更新 App 不丢，不上传任何地方

## 数据从哪来（全自动 + 兜底）

1. **完整历史（只需做一次）**：打开 BARK → 设置 → 导出/导入 → **导出** → 选择「存储到文件」。本 App 下次同步会自动扫描 BARK 容器的 `tmp/`、`Documents/` 与本 App 目录里的 `bark_messages_*.json`，把全部历史（含姓名明细）一次性入库。若自动扫描不到，可在设置 → 粘贴导入 → 「从『文件』选择 BARK 备份 JSON」手动选中；文件会长期保存在本 App 里，之后不用再选。
2. **每日增量（全自动）**：进入 App 立即拉一次，每 60 秒再拉一次（进前台也拉）。数据源为 BARK 快照 `group.bark/recent_messages_snapshot.json`（全局最近 100 条），按 group 过滤。服务器每天只推一次，100 条足够覆盖最新推送。
3. **手动拉取（设置里）**：点「立即刷新」或「粘贴导入 → 拉取并导入」随时触发一次，首页诊断行会显示找到的备份条数、快照条数与匹配分组条数，失败时列出 BARK 里现有的分组名。
4. **粘贴导入（兜底）**：从 BARK 长按复制历史消息，粘贴进来，支持一次多条自动切分。

> 已移除旧的局域网 HTTP 监听——不再需要机器直连手机，全部数据统一从 BARK 取。

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

- **今日**：顶部「今日抢到的金币总数 + 对应金额」，自动同步状态条（可手动刷新），各服务器汇总卡片（按设置里的服务器顺序排列，点右侧箭头看单账号明细 + 人数校验），待结账/已结账统计，异常信息
- **结账名单**：按日期分组，时间倒序（新到旧），搜索名字，标记结账，批量操作，一键复制全部名字
- **按周**：按自然周切换，时间倒序，截图专用视图（白底名单）。每天一个完整日期标题（如「2026年11月19日 周四」），明细只显示「名字 / 金币 / 需结账金额」三项，不出现序号和毫秒；顶部有周范围与合计，右上角可复制同样格式的文字版，底部可开启紧凑模式（只留名字，一屏更多）
- **设置**：自动同步（分组名、立即刷新）、服务器编号管理（顺序即展示顺序）、粘贴导入/手动拉取、数据管理与存储路径、清空数据。已移除监听/端口等旧设置

## 为什么能读 BARK 的数据（原理）

BARK 官方源码（Finb/Bark）里，历史消息存三处：

- BARK 自带「导出/导入」生成的 `bark_messages_*.json`（`id/title/body/group/createDate`，Unix 秒时间戳，body 完整不截断）——**完整历史读这个**
- App Group `group.bark` 容器下 `recent_messages_snapshot.json`（最近 100 条消息快照，body 截断 500 字符）——**每日增量读这个**
- 主 App 沙盒 `Documents/bark.realm`（Realm 完整数据库）——不读（见下方说明）

巨魔（TrollStore）允许 App 自带任意 entitlements。本 App 声明了：
- `com.apple.security.application-groups = group.bark` → 可读共享容器里的快照 JSON
- `com.apple.private.security.no-sandbox` + `platform-application` + `com.apple.private.security.storage.AppDataContainers` → 脱沙盒权限

> 为什么不读 Realm 库：引入 RealmSwift 静态库会让本 App 在巨魔伪签名环境下**启动即闪退**。改用 BARK 官方导出功能生成 JSON 作为完整数据源，纯 Foundation 解析，零第三方依赖，日期来自 `createDate` 时间戳，不会归错。

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

- 部署目标 iOS 15.0，用 NavigationView，兼容 iOS 15~18
- 零第三方依赖（不引入 RealmSwift 等二进制库，避免巨魔伪签名下启动闪退）；仅用 Foundation 读 BARK 官方导出 JSON + 小组件快照
- 需要巨魔（TrollStore）环境才能读取 BARK 数据；普通签名安装只能粘贴导入
- 数据存 App Documents 目录的 `lebark_data.json`（并镜像到 UserDefaults），覆盖安装更新 App 不丢；不联网上传
