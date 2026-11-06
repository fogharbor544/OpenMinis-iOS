# Poki 同机 iPhone 自动化集成调研

日期：2026-11-07。目标：由 OpenMinis 控制同一台 iPhone 上的其他 App。本文为源码与平台资料调研，没有实现、编译或真机验证该能力。

## 结论

**值得做最小同机 PoC，但不能把两个仓库直接装进 iSH 就视为完成。**

Poki 已有读取其他 App 界面、截图、发送触摸和键盘事件的实现。它们当前的运行主体仍是 Mac/Linux：电脑持续运行设备协议栈，iPhone 接受开发者服务连接。Linux 移植没有把这一运行主体搬进 iPhone。

存在比“iOS 沙箱不允许，所以绝对做不到”更具体的候选路线：把 `idevice` 编译进 OpenMinis，通过配对记录和本机 loopback VPN 连接自身开发者服务，再使用 Poki 的 AX/DVT/HID 执行链。StikDebug 的真实 iOS 工程已实现前半段连接路径，Poki 实现了后半段自动化操作；**尚未验证的是两段组合后，同一台 iPhone 上的后台闭环能否持续工作。**

因此：

| 用户期望 | 判断 |
| --- | --- |
| 普通安装后，不做额外配置，通用读取并点击任意其他 App | 没有找到支持此承诺的公开 SDK 路径；这两个仓库也不提供该交付形态 |
| 接受开发者设置、配对记录、本机 VPN，先在个人设备上实验 | 有足够源码依据启动验证；端到端能力仍待真机证明 |
| 可以有 Mac/Linux 持续中转，但操作对象仍是这台 iPhone | 现有 Poki 架构较接近；OpenMinis 客户端还需适配，并非控制电脑 |
| 只做目标 App 已开放的动作，例如 URL/Shortcuts 工作流 | 可走已有系统集成，但覆盖范围取决于目标 App，不能代替通用 UI 操作 |

优先建议：验证原生同机连接与 AX/HID 闭环，成功后再接 Bot。不要先移植整套 Node Agent、桌面安装脚本或完整工具目录。

## 1. 调研快照与证据范围

| 项目 | 固定版本 | 用途 |
| --- | --- | --- |
| `JosssphZhou/poki` | [`7ee03e3426db8a7b118a987e1dff7f74bef91124`](https://github.com/JosssphZhou/poki/tree/7ee03e3426db8a7b118a987e1dff7f74bef91124) | 主自动化实现，默认分支 `main` |
| `carrotciallo/poki-for-linux` | [`c2e90ae58b75a159445877a5f28638acc9f1c9ad`](https://github.com/carrotciallo/poki-for-linux/tree/c2e90ae58b75a159445877a5f28638acc9f1c9ad) | Linux 主机移植，默认分支 `linux-port` |
| `jkcoxson/idevice` | [`89702099f4d7552f704f93b4526756abda319ceb`](https://github.com/jkcoxson/idevice/tree/89702099f4d7552f704f93b4526756abda319ceb) | 两个 Poki 安装脚本固定使用的底层库；本次也检查了此版本 |
| `StikDebug/StikDebug` | [`9d7a917c7d698ed6d393ee3dc1a8ff1feba773fe`](https://github.com/StikDebug/StikDebug/tree/9d7a917c7d698ed6d393ee3dc1a8ff1feba773fe) | 证明 iOS App 内嵌协议栈及同机连接路径已有实现 |
| 当前 OpenMinis | 本地 `0e2ba58` 加既有未提交修改 | 以实际 Swift/Objective-C/Python 实现为准；保留现有 Bot memory 工作 |

主要直接阅读 GitHub 固定版本源码；Exa 的四次定向搜索共请求 19 条候选结果，最终采用项目原始源码、维护者材料和 Apple 文档。搜索摘要与维护者测试记录均未当作本机测试结果。

## 2. Poki 的能力实际来自哪里

运行链路可概括为：

```text
AI / MCP client
  → Node MCP daemon（会话、调度、工具策略）
  → poki-native（Rust）
  → 已配对设备隧道 / RSD / RemoteXPC / DTX
  → iPhone 开发者服务
  → 当前前台 App 的界面与输入
```

### 2.1 读取界面：开发者 AX 服务

`native/bridge/src/ax.rs:61-124` 从 RSD 公告中寻找 `com.apple.accessibility.axAuditDaemon.remoteAXService`，通过 DTX 调用 `clientNeedsAccessibility:`，解码归档并还原元素树。它能给出角色、名称、值、坐标、应用根和前台应用信息。

这与普通 iOS App 给自身视图添加 accessibility label 是不同的执行路径。它也不需要在每个目标 App 中装 SDK；可读取程度仍依赖目标界面的无障碍信息。

来源：[AX 实现](https://github.com/JosssphZhou/poki/blob/7ee03e3426db8a7b118a987e1dff7f74bef91124/native/bridge/src/ax.rs#L61)、[原生桥接说明](https://github.com/JosssphZhou/poki/blob/7ee03e3426db8a7b118a987e1dff7f74bef91124/native/NATIVE.md)。

### 2.2 截图：DVT Screenshot

`main.rs:435-449` 通过 `RemoteServerClient` 和 `ScreenshotClient` 获取屏幕字节。MCP 层会再处理图片并返回 image content。这里截取的是设备屏幕，不是 OpenMinis 的 WKWebView。

来源：[截图实现](https://github.com/JosssphZhou/poki/blob/7ee03e3426db8a7b118a987e1dff7f74bef91124/native/bridge/src/main.rs#L435)、[MCP 图片返回](https://github.com/JosssphZhou/poki/blob/7ee03e3426db8a7b118a987e1dff7f74bef91124/src/device.mjs#L369)。

### 2.3 点击、滑动、键盘：CoreDevice HID

`main.rs` 使用 `UniversalHidServiceClient`、`IndigoHidClient` 和 `MainKeyboardService`。输入前还要建立 CoreDevice display media session，而不是拿到 TCP 连接就立即发送 tap。触摸坐标归一化到 `0..65535`；上层负责从屏幕逻辑点转换。

此版本的真实设备输入主路径不是 WebDriverAgent/XCTest Runner。不能按“签一个 WDA 就能原样接入”来估算工作量。

来源：[HID 与 media 初始化](https://github.com/JosssphZhou/poki/blob/7ee03e3426db8a7b118a987e1dff7f74bef91124/native/bridge/src/main.rs#L11)、[输入会话准备](https://github.com/JosssphZhou/poki/blob/7ee03e3426db8a7b118a987e1dff7f74bef91124/native/bridge/src/main.rs#L477)。

### 2.4 上层的价值：操作后核验

Poki 不只是提供 tap 接口。它还实现了按文字定位、等待、稳定坐标、输入框确认、过期元素拒绝、批处理停止条件、设备占用和取消。`sent=true` 仅表示写入连接；设备可能丢弃输入，不能据此报告操作完成。

文字输入当前依靠剪贴板加 Command-V，并核验目标字段与文本；剪贴板快照不一定可恢复，密码遮蔽也可能使核验失败。这些限制必须保留在产品设计中。

来源：[交互与定位](https://github.com/JosssphZhou/poki/blob/7ee03e3426db8a7b118a987e1dff7f74bef91124/src/interaction.mjs)、[输入及核验边界](https://github.com/JosssphZhou/poki/blob/7ee03e3426db8a7b118a987e1dff7f74bef91124/native/NATIVE.md)。

### 2.5 设备准备是运行能力的一部分

官方配置要求信任配对、Developer Mode、UI Automation、可用的 Developer Disk Image。Wi-Fi 可以代替 USB 运行，但当前 Poki 主机仍持续参与协议执行。其 RemotePairing/Tailscale 方案也仍有电脑端 helper，不等于 iPhone 已能独立运行。

来源：[真机设置](https://github.com/JosssphZhou/poki/blob/7ee03e3426db8a7b118a987e1dff7f74bef91124/docs/physical-iphone.md)、[RemotePairing 架构及限制](https://github.com/JosssphZhou/poki/blob/7ee03e3426db8a7b118a987e1dff7f74bef91124/docs/remote-iphone.md)。

## 3. Linux 仓库解决了什么

已经核对 `LINUX.md` 以及 `bin/setup`、`bin/build-native`、`bin/prepare-device.mjs`、`src/platform.mjs`、`src/human.mjs`、`src/daemon.mjs`、Rust OCR 源码。

| 改动 | 实际作用 | 对同机 iOS 的意义 |
| --- | --- | --- |
| Linux prerequisite / usbmuxd | 让 Linux 电脑发现和连接手机 | 不会给 iOS App 增加 USB 主机能力 |
| pymobiledevice3 | 安装 DDI，并替代部分 devicectl 管理动作 | 可参考服务流程；不是适合直接塞进 app 的部署方式 |
| tesseract Rust OCR helper | 替代 macOS Vision OCR | iOS 已有 Vision，通常无需带入这套外部进程 |
| zenity | 替代 macOS 人工确认弹窗 | 需要改成 iOS 自己的授权与交互 |
| XDG、plistutil、zip/unzip、sharp 适配 | 消除 Linux 主机上的桌面依赖差异 | 不解决同机隧道、iOS 生命周期或原生链接 |
| RemotePairing helper 预热 | 减少首次调用建立会话的等待 | 持久隧道设计值得参考 |

维护者记录的 Arch Linux + iPhone18,4 / iOS 27.0.1 实测，包括 AX、截图、触摸、文字与 LAN 控制，是其测试声明，本轮没有复现。Linux 的 `open_url`、模拟器、Xcode 构建及部分 RemotePairing 管理工具仍有明确限制。

两个调研快照并非同一个上游时刻；文件树差异不能全部归因于 Linux 移植。尤其不能根据“跨平台 Rust”直接推导“现成 iOS build”。

来源：[Linux 能力与实测范围](https://github.com/carrotciallo/poki-for-linux/blob/c2e90ae58b75a159445877a5f28638acc9f1c9ad/LINUX.md)、[DDI 安装](https://github.com/carrotciallo/poki-for-linux/blob/c2e90ae58b75a159445877a5f28638acc9f1c9ad/bin/prepare-device.mjs)、[Linux OCR](https://github.com/carrotciallo/poki-for-linux/blob/c2e90ae58b75a159445877a5f28638acc9f1c9ad/native/bridge/src/bin/ocr.rs)。

## 4. 为什么同机运行仍值得验证

### 4.1 已有 iOS 原生连接的实现证据

`idevice` 是可嵌入的 Rust 库，提供 C FFI；StikDebug 是使用它的 Swift iOS App。

在所检查的 StikDebug 中：

1. `DeviceConnectionContext.swift` 默认目标地址是 `10.7.0.1`，也允许配置。
2. `JITEnableContext.swift:387-449` 读取 RemotePairing 文件，解析目标端口，调用 `tunnel_create_rppairing`，得到 adapter 和 RSD handshake。
3. `IdeviceFFIBridge.swift` 使用这些句柄访问 DDI、应用列表、进程等服务。
4. README 要求 loopback VPN，如 LocalDevVPN；后者提供设备内网络回环路径。

**已证实：设备端 App 内嵌协议库并连接设备服务已有源码。合理推断：这些隧道句柄可能承载 Poki 的 AX/DVT/HID 客户端。待验证：同机的 AX/HID/media 服务是否完整可用，以及 OpenMinis 后台运行时是否仍可用。**

来源：[StikDebug 隧道](https://github.com/StikDebug/StikDebug/blob/9d7a917c7d698ed6d393ee3dc1a8ff1feba773fe/StikDebug/Device/JITEnableContext.swift#L387)、[StikDebug FFI](https://github.com/StikDebug/StikDebug/blob/9d7a917c7d698ed6d393ee3dc1a8ff1feba773fe/StikDebug/Device/IdeviceFFIBridge.swift)、[LocalDevVPN](https://github.com/jkcoxson/LocalDevVPN)、[idevice FFI](https://github.com/jkcoxson/idevice/tree/89702099f4d7552f704f93b4526756abda319ceb/ffi)。

### 4.2 配对不应写死为“永远先接电脑”

Poki 当前配置从受信任电脑开始。StikDebug 此快照的 `PAIRING.md` 则声明 iOS/iPadOS 27+ 可在设备上生成配对文件，也保留电脑生成方式；工程包含相应 `OnDevicePairingService.swift`。

这提供了后续减少电脑依赖的候选路径，不能据此承诺 OpenMinis 已能无电脑初始化。最小 PoC 应先采用已知有效的配对记录，把配对产品化和自动化执行分开验证。传统 Lockdown 记录与 RemotePairing 记录也不能不经检查就混用。

来源：[配对文档](https://github.com/StikDebug/StikDebug/blob/9d7a917c7d698ed6d393ee3dc1a8ff1feba773fe/PAIRING.md)、[设备端配对实现](https://github.com/StikDebug/StikDebug/blob/9d7a917c7d698ed6d393ee3dc1a8ff1feba773fe/StikDebug/Services/OnDevicePairingService.swift)。

### 4.3 不能承诺任意系统版本都稳定

Poki 明示物理设备桥接依赖 Apple 私有接口；idevice 自身也标注仍处研究开发阶段。idevice 作者记录过 iOS 26.4 beta 对设备连接自身路径的改变，说明 loopback 连接会随系统版本失效或需要调整。这是兼容性风险的历史证据，不是当前所有版本均不可用的证明。

需要按用户的具体 iOS build 建立实测范围，不应给出未经验证的最低支持版本或成功率。

来源：[Poki 验证限制](https://github.com/JosssphZhou/poki/blob/7ee03e3426db8a7b118a987e1dff7f74bef91124/docs/verification.md)、[idevice 状态说明](https://github.com/jkcoxson/idevice/blob/89702099f4d7552f704f93b4526756abda319ceb/README.md)、[作者对自连接变更的记录](https://jkcoxson.com/blog/i-made-apple-mad)。

## 5. 与当前 OpenMinis 的接入点

| 当前实现 | 可以复用 | 必须补齐 |
| --- | --- | --- |
| `NativeOffloads/` 的原生命令桥接 | iSH 命令转 Swift/ObjC，以及 JSON 回执模式 | 原生 Rust 静态库与最小 C ABI，避免依赖启动桌面 native helper 进程 |
| `MCPStore.swift` 与 Python HTTP transport | 远程 MCP 的 URL、headers、JSON/SSE 处理 | 同机原生路径无需强行套 MCP；外部中转路径需额外会话头、网络与图片适配 |
| `BrowserUseOffloadBridge.swift` | caller `fsContext` → 会话归属、截图落盘、取消入口模式 | 独立的设备屏幕 owner/lease；浏览器每会话隔离不能复制为多个“手机前台” |
| `OffloadPermissionManager.swift` | 原生命令开关与会话授权框架 | 切到目标 App 前完成本轮授权；后台新授权不能依赖不可见的前台弹窗 |
| `BackgroundKeepAliveManager.swift` | 已有 continued processing、audio/location、生命周期与停止基础 | 真机验证后台 Agent、Rust runtime、隧道和模型网络请求的组合 |
| `read_image` 与会话文件工具 | 用模型视觉读取落盘截图 | 把原生/MCP 截图转为当前视觉通路可读的文件 |
| `apple-open` 与 App Intents | 跳转和有限结构化工作流 | 不具备其他 App 的通用界面树和点击控制 |

本地源码参考：

- [Native browser bridge](../src/ios/NativeOffloads/BrowserUseOffloadBridge.swift)：第 159 行起明确指出不同聊天的 shell 会并发，必须按实际调用者归属数据。
- [ISHExecutionCoordinator](../src/ios/Agent/ISH/ISHExecutionCoordinator.swift)：当前为跨会话及同会话并发执行；旧 sandbox summary 的 FIFO 描述不能用于新设计。
- [MCPStore](../src/ios/Agent/Session/MCPStore.swift)、[HTTP transport](../src/ios/default_mount/usr/local/lib/minis-mcp-cli/transport/http.py)、[CLI call](../src/ios/default_mount/usr/local/lib/minis-mcp-cli/main.py)。
- [权限管理](../src/ios/Agent/Offload/OffloadPermissionManager.swift)、[后台运行](../src/ios/Agent/Background/BackgroundKeepAliveManager.swift)、[工具结果及图片处理](../src/ios/Agent/Chat/AIChatViewModel+ConcurrentTools.swift)。

### 5.1 推荐的同机架构

以下是建议结构，尚未创建这些文件或命令：

```text
OpenMinis Bot / Agent
  → device automation tool / apple-device-use 原生命令（拟议）
  → DeviceAutomationCoordinator（拟议：全局屏幕占用、会话归属、取消）
  → Swift / C ABI / Rust static library
  → idevice + 原生 AX / DVT / CoreDevice HID 客户端
  → 本机 VPN 路径 + 已授权配对记录
  → 本机开发者服务
  → 当前前台目标 App
```

Poki 原生 bridge 目前是 Rust executable，其 stdin、Unix socket 和外部进程生命周期不适合原样作为 iOS 子进程部署。应提取少量操作为链接库。检查到的 idevice FFI 已覆盖 tunnel、provider、DVT screenshot 等边界，但未看到与 Poki 所需 AX parser、完整 HID/media 路径对应的现成高层 C 接口，仍需要自己的小型桥接层。

iSH 提供用户态 Linux 环境，不会因此获得桌面 usbmuxd、iPhone 的任意宿主权限或独立于 app 的后台进程寿命。即使能安装 Node/Python，运行条件也没有自动满足。

### 5.2 最重要的是后台闭环

启动其他 App 后，OpenMinis 会退到后台。这与电脑控制手机时 Agent 始终运行的情况不同。

当前仓库已有后台机制，不能简单断言“退后台就立即停止”；同样不能反过来承诺永久运行。Apple 的 `BGContinuedProcessingTask` 面向前台用户发起、可报告进度的任务，允许用户取消，也会因资源条件终止。应复用现有机制，先验证具体工作负载，不在本轮另造保活系统。

第一版应由用户在 OpenMinis 前台启动一个有界任务。不要提前承诺锁屏运行、定时唤醒后操作其他 App、重启后自动恢复，或密码与 Face ID 自动处理。

来源：[Apple 后台任务文档](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask.md)、[WWDC25 后台任务说明](https://developer.apple.com/videos/play/wwdc2025/227/)。

### 5.3 多 Bot 与取消必须共享同一控制边界

手机只有一个前台界面。Bot A 打开搜索、Bot B 同时切换 App，就会让 A 的后续输入落到错误位置；这是当前并发工具架构中的直接故障模式。

需要全局独占执行，并记录调用会话/owner。操作前校验前台 bundle 与本轮观察，失联或取消后区分 `not_sent`、`sent_unverified`、`verified`、`unknown`。已经发送但回执丢失的输入不能自动重放，应先重新观察。这些语义可以参考 Poki 的协调与回执设计。

## 6. 其他路径及其边界

### 外部 Poki 中转

如果只需尽快检验“OpenMinis 发起任务，手机上的其他 App 被操作”，可以临时让 Mac/Linux 跑 Poki，手机作为 MCP 客户端回连电脑；操作对象仍是手机。这种实验不证明无需电脑的同机产品方案。

源码揭示三个实际接入点：

- Poki 主仓库默认绑定 loopback；需要按 `POKI_BIND_HOST` / `POKI_HOST_ALLOW` 配置可达地址或受控代理。
- daemon 除 Bearer token 外还要求 `x-poki-mcp-session`；普通 MCP URL 配置不自动产生这个自定义会话头。多个 Bot 不应无意共享同一个控制 owner。
- Poki `take_screenshot` 返回 MCP image content；当前 `minis-mcp-cli call` 将结果 JSON 输出到 shell，`shell_execute` 把它作为文本。需要把图片落盘并转入 `read_image`，不能把打印 base64 JSON 当作模型已看到屏幕。

来源：[daemon 认证、会话与监听](https://github.com/JosssphZhou/poki/blob/7ee03e3426db8a7b118a987e1dff7f74bef91124/src/daemon.mjs)、[截图结果](https://github.com/JosssphZhou/poki/blob/7ee03e3426db8a7b118a987e1dff7f74bef91124/src/device.mjs#L369)。

### 公开系统集成

App Intents / Shortcuts 适用于目标 App 主动开放的动作，URL Scheme 用于跳转和目标 App 支持的参数。ReplayKit 提供录屏/广播能力，不能单独解决输入控制。

Apple 的沙箱与 entitlement 模型并没有给普通第三方 App 提供任意读取和修改其他 App 的通用权限。这里的同机实验是开发者服务协议路线，不能宣传为常规 accessibility 授权能力。

来源：[App Intents](https://developer.apple.com/documentation/appintents.md)、[ReplayKit](https://developer.apple.com/documentation/replaykit.md)、[Apple 运行时安全](https://support.apple.com/guide/security/security-of-runtime-process-sec15bfe098e/web)。

## 7. 最小验证范围与停止条件

先做原生诊断入口，不接模型，不增加自动化后台守护，不移植整个 Poki Agent。建议按以下依赖顺序验收：

| 阶段 | 验证动作 | 通过标准 / 失败处理 |
| --- | --- | --- |
| A：原生构建 | 固定 idevice 版本，构建 iOS 静态库和 C ABI | 真机可加载并释放 runtime；失败先解决工具链，不接 Agent |
| B：同机连接 | 已知有效配对记录 + LocalDevVPN，创建 RSD 隧道 | 可重复查询设备信息和服务列表；区分网络、配对、DDI 失败 |
| C：观察 | 用户手动把无敏感数据的目标 App 放前台，OpenMinis 后台读 AX 和截图 | 确认内容与屏幕一致；若 AX 不可用，单独记录截图是否可用 |
| D：输入 | 在专用 fixture/测试页面进行一次 tap、一次 swipe、输入中英文 | 每一步均由后续 AX/截图证明结果；测试文本无个人数据 |
| E：闭环 | 用户从 OpenMinis 启动，再切到目标 App，执行“观察→动作→观察” | 多轮成功，记录每步耗时、失败与后台状态；单次成功不算稳定验收 |
| F：中止恢复 | 用户停止、锁屏、VPN 断开、配对失效，以及第二个 Bot 请求 | 及时停止后续输入、释放占用；不重放不确定动作，不写错会话目录 |

如果 B 失败：同机连接路线尚不成立。如果 C/D 失败：StikDebug 的隧道证据不足以证明自动化服务可用，应定位具体服务限制。如果 E 持续失败：不能把“前台能调一个接口”包装为同机自动化完成。

通过后才进入产品集成：最初只暴露 status、observe、screenshot、launch、tap、swipe、type_text、stop，优先支持已测试设备/系统和无敏感操作；再按真实需求增加工具。支付、发送、删除和凭据输入需要明确的任务授权/人工接管边界，不能直接继承桌面全放行策略。

## 8. 许可证、分发及凭据

`idevice` 是 MIT；Poki 与 Linux fork 的 wrapper 是 AGPL-3.0-only，StikDebug 也采用 AGPL。当前 OpenMinis 根 `LICENSE` 是 GPLv3 文本。直接复制 AX parser、交互策略等实现与只链接 MIT 底层库不是同一个许可边界；正式复用前需要确定组合、源码提供和分发要求。本调研不作“全部代码必须改许可证”或“无影响”的法律结论。

开发者服务路径也不能仅凭技术运行成功就保证 App Store/TestFlight 分发。Poki 自己明确依赖 Apple 私有接口；应将个人开发安装验证和公开分发评估分别记录。

配对记录含设备连接凭据。设计时应置于受保护的原生私有存储，排除普通共享目录、会话文本、模型上下文、日志和默认备份导出；不得把整份 pairing file 当作普通 MCP 配置同步。第一版可复用外部 LocalDevVPN，是否内置 Network Extension 留待核心路径验证后决定。

来源：[Poki license](https://github.com/JosssphZhou/poki/blob/7ee03e3426db8a7b118a987e1dff7f74bef91124/LICENSE)、[idevice license 与状态](https://github.com/jkcoxson/idevice/blob/89702099f4d7552f704f93b4526756abda319ceb/README.md)、[配对凭据说明](https://github.com/StikDebug/StikDebug/blob/9d7a917c7d698ed6d393ee3dc1a8ff1feba773fe/PAIRING.md)。

## 9. 对既有文档的解释与本轮验证限制

`src/shared/cli/a11y-cli.md` 是历史待定跨平台草稿，其中“iOS 没有普通 OS accessibility client 等价命令”的判断仍解释了现有产品为什么不提供该命令。它不应被扩大为排除配对开发者服务研究的绝对结论。本报告补充这一实验路径，**没有改变现有支持范围或声称有命令已安装**。

已完成：固定源码快照、执行链核查、Linux 适配核查、StikDebug 同机连接交叉证据、当前 OpenMinis 接入边界与 Apple 公开资料核查。

未完成且本轮环境无法完成：Rust iOS 交叉构建、Swift/Xcode 编译、两仓库测试套件、用户设备 AX/HID/截图/后台闭环及系统版本兼容性测试。当前 Windows 环境未发现 `cargo`、`rustc`、`swiftc`、`xcodebuild`。本轮仅新增报告并追加规划记录，没有修改应用代码或访问真实配对凭据。

设备型号、具体 iOS 版本、OpenMinis 安装方式及本机 VPN 接受程度尚待用户补充；这些信息用于确定 PoC 环境，不影响“有研究依据、尚未端到端验证”的当前结论。
