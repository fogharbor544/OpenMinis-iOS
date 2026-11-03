
# iOS 浏览器批次执行实现报告

基线：`a0e31dd407bb09f906c641e26550b723f5734b4c`。与设计分析使用的 `1479234` 相比，浏览器源码没有变化。工作在现有 worktree，未切换分支、提交或推送。预存的 `.superpowers/` 保持不变。

## 实现

- `BrowserUseActions.swift`：新增 `observe` / `run`，在入口将步骤和目标验证为有界的类型。保留原有动作参数默认值。
- `BrowserUseJavaScript.swift`：使用独立 WebKit 内容世界保存主文档与元素引用；复用现有点击、输入脚本。动作前登记条件，动作后立即判断。DOM 变化唤醒检查，URL、样式等无 DOM 通知变化用最多 100 ms 的等待片段复查。
- `BrowserUseManager.swift` / `BrowserTabPool.swift`：沿用每标签串行，批次不循环调用单步 `execute`，也不运行旧的每步 DOM 稳定等待。仅在同一有效文档内生成一次末尾观察，显式 `preview=default` 允许在同一预算内取一张 UI 预览。导航、下载、弹窗、接管、安全输入、标签回收及超时均会中止后续步骤。
- `AIChatViewModel+ToolDefinitions.swift` / `AIChatViewModel+ConcurrentTools.swift`：更新直连工具 schema；同一份输入只调用一次浏览器参数解析。
- `BrowserUseOffload.m` / `BrowserUseOffloadBridge.swift`：复用既有 JSON 路由，更新 CLI 帮助并返回实际 `tab_id` 和结构化 `batch`。
- 产品实现位于现有 Xcode 源文件中，未新增需登记的产品编译单元。

## 协议示例

1. `{"action":"observe","tab_id":0,"selector":"main"}` 获取同一标签下的 `documentVersion`、`frameId`、区域文本及元素引用。省略 `selector` 默认观察正文。每次成功观察（包括批次末尾观察）替换旧引用。相同引用不会重定向到后来创建的节点。
2. 将输出的版本和引用传给 `run`。下面的 selector 应当唯一；末尾条件与末步自己的条件一起在末步动作前登记。

```json
{
  "action": "run",
  "tab_id": 0,
  "document_version": "<observe.documentVersion>",
  "frame_id": "main",
  "steps": [
    {"action":"type","ref":"e1","text":"OpenMinis"},
    {"action":"click","ref":"e2"}
  ],
  "until": {"kind":"visible","selector":"#results"},
  "timeout": 5000
}
```

在只提供标量 schema 的入口，`until` 可用等价 JSON 字符串。CLI 用 `minis-browser-use --json '<完整对象>'`。条件支持 `visible`、`enabled` 和 `url_contains`（传 `value`）。同一批最多 12 步；单步文本最长 512 UTF-16 单元；运行预算 100–15,000 ms（默认 8,000 ms，标签排队使用现有规则）。观察最多 20 个元素和 2,000 字符正文；不会读取表单 value。批次只支持主 frame 的 light DOM；iframe 会提示存在。凭证、PIN、验证码仍使用 `secure_input`。长列表提取、普通截图、`execute_js` 和滚动收集继续使用原有动作。

`completedSteps` 是确认已执行的零基索引数组；例如 `{"completedSteps":[0],"failedStep":1,"stopReason":"stale_ref"}` 表示第 0 步已执行，第 1 步未对替换节点执行。已派发的动作可能在等待条件期间失败，因此同一索引可同时出现在 `completedSteps` 和 `failedStep`。若无法确认最后一次派发，返回 `uncertainStep`；重新观察并核对实际结果后再决定后续动作。发生导航或接管时不返回旧文档的观察。

## 验证

- `node src/ios/MinisTests/Standalone/browser_batch_behavior.cjs src/ios/Agent/BrowserUse/BrowserUseJavaScript.swift`：观察到缺少运行时时失败；实现后通过。链接跨文档导航的提前停止也单独先红后绿。
- `python src/ios/MinisTests/Standalone/run_browser_automation_tests.py --emit-swift build/ios-browser-batch/Automation.swift`：15 个批次 Node 行为测试和 11 个既有 DOM 观察器断言通过；Swift fixture 成功生成。测试涵盖即时/延迟目标、目标组合、歧义、陈旧节点、文档绑定、弹窗、导航意图、SPA、过期派发、慢同步监听后禁止后续合成动作，过滤交互元素名称中的可编辑内容，以及在按钮被同步移除或主监听器耗尽预算时保留已确认点击。
- `git diff --check`：通过。
- `--require-swift` 在 Windows 上报告没有 `swiftc`。提取的 Swift 行为 fixture 覆盖批次部分成功、导航和接管提前停止；同一入口在 macOS 额外编译并运行真实 WKWebView fixture，覆盖隔离世界、真实输入/点击与条件、换文档后失效。同一 macOS 入口还会编译 CLI Objective-C 生产输出函数，验证普通失败格式、批次失败数据和 quiet 非零退出；这三类 Apple/Swift 原生验证在本机均未执行。

## 独立审查后的修复

- 分发前再次检查截止时间、运行实例和 DOM 节点；复用的点击与输入模板在可中断的事件边界复查，已经在执行的同步页面监听器无法抢占。前置解析耗尽预算时未发事件；若事件链部分发出则返回未确认派发。两项行为在修复前分别错误返回成功；修复后通过，慢监听用例执行真实点击模板。
- 观察正文和名称共用受限的文本提取，跳过可编辑节点和表单内容。以外层交互元素包含可编辑后代复现了名称泄露，修复前后分别失败与通过。
- CLI 原本在失败时丢弃 Swift bridge 的 `batch` 和 `tab_id`；现有标准错误 envelope 加 `data`，quiet 直接输出批次数据。普通动作的旧错误格式保持不变。对应 macOS 生产代码行为 fixture 已添加，本机未执行。

- 主点击返回后若按钮已被同步移除，跳过后续清理事件并正常检查目标；如果主监听器耗尽预算，则停止批次并保留已确认点击。真实模板的移除按钮用例先失败、后通过。

## 待验证边界

WebKit 的 JS 事件、导航和下载回调之间的实际时序、原生键盘清理、UI 预览以及 Xcode 编译需在 Apple 环境验证。执行器在收到导航信号时停止，标准链接/表单也检查同步默认行为；网页任意异步安排在未来执行的跳转无法提前预知。任意网页合成点击的效果仍取决于站点，失败后不得盲目重放。

没有 iOS 真机性能基准。验收时应在同一设备比较标准单步、批量 `execute_js` 和新 `run` 的成功率、模型往返、延迟和重复操作，并验证下载与人工接管。


## 最新复审：空串同步与批次失焦

- 空串替换在共享 type 模板中补发一次冒泡的 `input`（`deleteContentBackward`）；依赖 input 的表单在下一步提交时读到空值。非空的逐字符事件保持原样，批次仍拒绝通过 type 填写密码和验证码字段。
- 批次的真实失焦与 type 在同一个受控 JS 调用中执行；仅在文档、运行、节点和截止时间有效且该节点仍持有焦点时执行。已检测到新弹窗或未取消的链接/表单默认操作时跳过。原生 manager 不再为批次追加 page world 脚本或 `endEditing(true)`；旧单步与 `execute_js` 保留原键盘处理。若 type 已完成且清理前耗尽预算，回复 `timeout` 与 `applied=true`；原生仅在实际收到该回复时才能确认进度，桥接计时先结束仍可能报告 `uncertainStep`。
- Node 生产模板回归先红（4 个缺陷断言）、后绿（20/20 批次行为）；已有 11 项 DOM 观察器及 55 项安全输入 JS 断言通过。Swift 部分结果和 WKWebView 的空串提交、正常真实失焦、转移焦点及超时 fixture 已更新。本机未执行 Apple 原生验证；WKWebView 真实事件和 iOS 键盘收起效果仍需在 Apple 环境确认。增量证据见 `build/reviews/browser-batch/fix-two-p2-report.md`。
