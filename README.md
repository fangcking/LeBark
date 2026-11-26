# TrollAutoClicker（巨魔环境 iOS 悬浮连点器）

一个可注入到目标 App 里的连点器动态库，产出 **`.deb`**（内含 `.dylib`），适配 TrollStore + TrollFools 工作流。

> **关于 `packages/` 里现成的 deb**：这是本仓库源码经 GitHub Actions 云编译（Theos，rootless）产出的**正式版本**，支持「每一步独立延时」「步骤上下调整顺序」，不是上游占位包。可直接用于 TrollFools 注入。内部 dylib 为 arm64 + arm64e 双架构 Mach-O。
>
> - 现成 deb：`packages/com.trollautoclicker.tweak_1.0.0_iphoneos-arm64.deb`（67 KB）
> - 现成 dylib：`packages/TrollAutoClicker.dylib`（387 KB，从上面的 deb 中提取）
> - 云编译仓库分支：`https://github.com/fangcking/LeBark` 的 `autoclicker-build` 分支
> - 公开下载直链：`https://github.com/fangcking/LeBark/releases/download/autoclicker-latest/TrollAutoClicker.deb`

## 已实现的功能

- **多套方案**：把一串选点保存成一套「方案」，可自定义方案名字。面板顶部的方案区是一个**下拉选择**：收起时只显示当前方案名和步数，点一下展开全部方案，点某一行即切换为当前方案（会先停止运行）；展开列表随条目自动撑开，面板自身可滚动，方案再多也不会挤爆界面。每套方案的步骤互相独立，可新建、改名、删除（删除需二次确认，至少保留一套）。
- **屏幕选点**：点「选点」后在屏幕上点按添加点击点，拖动添加滑动步骤；已添加的点可用带编号的标记拖动微调，也可单条删除 / 撤销 / 清空。
- **每步独立延时**：每个步骤行内都有「此步后延时」输入框（毫秒，10 ~ 60000，默认 500 ms），点击和滑动各自独立控制，执行到该步后按其延时等待。全局的「点击间隔」「滑动后延时」已取消。
- **步骤上下调整**：每个步骤行带 ↑ / ↓ 按钮，可上下移动步骤位置、调整执行顺序。
- **悬浮可拖动**：悬浮球可拖到屏幕任意位置并自动吸附边缘，位置会保存；它所在窗口的 `windowLevel = UIWindowLevelAlert + 1`，覆盖在目标 App 的所有视图之上。
- **循环执行**：支持无限循环或指定轮数；滑动动作本身另有「滑动时长」设置。
- **执行进度**：循环次数设为有限值时，面板「开始/停止」按钮上方显示进度百分比和进度条（按「已完成步数 / 总步数」计算），跑完停在 100% 并提示「已完成 N 轮」；运行时面板会自动收起，所以百分比同时贴在悬浮球上方，随时能看到。无限循环不显示。
- **不挡触摸**：悬浮层是 TouchSynth 的 `excludedView`，选点/运行期间点悬浮球下方仍能命中 App；运行时标记自动禁用交互。
- **无 Substrate 依赖**：用 constructor 直接启动，注入 App Store / TrollStore 应用后不会因缺少 CydiaSubstrate 而闪退。

## 环境要求

- 越狱环境：**不需要**。设备需已安装 TrollStore（iOS 14.0 – 17.0）。
- 注入工具：TrollFools（支持 `.dylib` / `.deb` / `.zip` / `.bundle` 注入，并可一键推出）。
- 编译环境：macOS / Linux 上装好 Theos（`THEOS` 环境变量指向 Theos 目录），以及 iOS SDK。

## 编译

```bash
cd TrollAutoClicker
make package FINALPACKAGE=1
```

产物：

- dylib：`.theos/obj/ arm64(e)/TrollAutoClicker.dylib`（具体路径以 Theos 输出为准）
- deb：`packages/com.trollautoclicker.tweak_1.0.0_iphoneos-arm64.deb`

如果只想快速得到 dylib：

```bash
make FINALPACKAGE=1
```

> deb 包内的 dylib 路径为 `/var/jb/Library/MobileSubstrate/DynamicLibraries/TrollAutoClicker.dylib`（rootless 布局）。若你的 TrollFools 版本不支持直接注入 deb，直接用 `packages/TrollAutoClicker.dylib` 即可。
>
> 云端已编译成功（run 44724162610，success）。本仓库推送到 `autoclicker-build` 分支后 Actions 会自动重新编译并覆盖 Release 直链。

## 注入与使用

1. 打开 TrollFools → 选择要挂连点器的 App → 注入 `TrollAutoClicker.dylib`（或 deb）。
2. 完全退出并重新打开该 App。
3. 屏幕右侧出现悬浮球：
   - **拖动**悬浮球调整位置（贴边吸附）。
   - **点按**悬浮球打开面板。
4. 面板操作：
   - 「方案」区：收起状态显示当前方案（名字 + 步数 + `▾`），点这一行展开全部方案；点某一行切换为当前方案。`+` 新建方案（自动进入改名），点铅笔改名，点垃圾桶删除（再点一次「确认」）。
   - 点「选点」→ 在屏幕上点按添加点击点，或拖动添加滑动；点「完成」退出选点。
   - 每个步骤行里的「此步后延时」输入毫秒数，例如 `500` 表示该步执行后等待 500 ms；点击、滑动各自独立。
   - 用步骤行的 ↑ / ↓ 调整上下顺序；需要时调整循环次数、滑动时长、显示触摸。
   - 点「开始」运行；运行时再点悬浮球即可停止。
5. 方案与步骤保存在各 App 自己的 `NSUserDefaults` 中，下次打开该 App 会恢复，方案列表也在。

## 推出 / 卸载

TrollFools → 已进入的 App → 右滑对应插件选择「推出」，或一键全部推出。deb 本身不需要在设备上单独安装。

## 重要限制（请先了解）

- **只作用于被注入的那个 App 内部**：TrollFools 是原位注入，不能修改 SpringBoard，也无法从 A App 触发 B App 的点击。要让多个 App 都能用，需要分别注入。
- **触摸是进程内合成的 UIEvent**：不是系统级 HID 事件。绝大多数 UIKit 界面可用；部分游戏引擎（Unity 等）或自绘渲染的 App 可能需要关闭「显示触摸」或改用目标 App 原生支持的输入方式。
- **App 切到后台会自动停止**，避免误触。
- 私有 API 行为随 iOS 版本变化。若新系统上点击无效，请先确认 TouchSynth 的诊断（仓库中的 `runtimeDiagnostics`）是否正常。
- 请只在自己的设备、合规场景使用；不要用于游戏作弊、刷量等违反平台条款的行为。

## 目录结构

```
TrollAutoClicker/
├── Makefile                  # Theos 构建，USE_SUBSTRATE=0，产出 deb
├── control                   # deb 元数据（rootless: iphoneos-arm64）
├── TrollAutoClicker.plist    # Theos filter（TrollFools 注入时忽略，可按需改目标 bundle）
└── Source/
    ├── Tweak.xm              # 占位，本插件不用 Logos
    ├── AutoTap.m             # 悬浮窗、选点录制、标记、运行入口（constructor）
    ├── ATSession.h/.m        # 步骤数据、毫秒间隔、循环播放与持久化
    ├── ATViews.h/.m          # 悬浮球、设置面板、毫秒输入框
    └── Vendor/               # TouchSynth 触摸合成库（TSPrivateUIKit / TSTouchSynthesizer / TSTouchLogic）
```

触摸合成基于开源项目 [TouchSynth](https://github.com/Gladimore/TouchSynth)（其设计反向自 iGameGod 的 touch replay），已内嵌到 `Source/Vendor`，无需额外安装。
