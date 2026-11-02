# Mika 浏览器自动化与 OpenMinis iOS 对照分析

日期：2026-11-02。结论：值得借鉴的是条件等待、结构化观察、站点知识与有界流程执行；优先优化 OpenMinis 已有浏览器链路，不整体移植 Mika，也不先更换浏览器内核。

## 分析基线与限制

- OpenMinis：`codex/bot-team-original-avatars`，远端 `darkyuanbao06` 最新提交 `56050b2d3fdc7391cc27d3bf0ca49ffbada848b8`。通过 `git ls-remote` 核对，与现有工作树 HEAD 一致。
- Mika：`main` 提交 [ebb0e44750d80aabb6b642c69908825d6b1a8107](https://github.com/wangzan101/Mika/commit/ebb0e44750d80aabb6b642c69908825d6b1a8107)，版本提交标题为 0.1.33，提交时间为北京时间 2026-11-02 02:51。
- OpenMinis 目标工作树有其他任务的未提交变更；本分析保留了它们。浏览器核心、工具定义、并发执行器及 BrowserUseOffload 的相关文件与 HEAD 无差异。SystemPrompt 的未提交差异不涉及下述 CLI 批处理说明。
- 这是源码分析，没有进行 iPhone 真机 A/B、Mika 实机测试或端到端性能测量。下文区分可从源码推出的固定开销与待验证的收益。本次仅增加分析文档和追加规划笔记，没有修改应用代码。

## 咱们已经具备的能力

| 能力 | 已有实现 | 对分析的影响 |
|---|---|---|
| 页内脚本 | `execute_js` 支持 async/await、return、DOM 结果转 JSON | 不需要为了批量读 DOM 再造脚本引擎 |
| 多步批处理 | SystemPrompt 已明确建议 shell 脚本串联 `minis-browser-use` | “减少模型往返”已有实现路径；新增原生 batch 的增量收益必须单独测 |
| 滚动采集 | `scroll_and_collect` 已在一次调用内多次滚动、去重采集 | 优先改等待与输出策略，而非重复添加滚动批处理 |
| 内容读取 | `get_text`、`get_readable`、`get_backbone`、`find_elements` | Mika 的优势在观察质量、按需返回及失败分类 |
| 并行与隔离 | AgentLoop 并发工具调用；BrowserTabPool 同标签串行、跨标签执行、owner 隔离 | 不应把同一页有依赖的点击并发化 |
| 会话复用 | CookieBackupStore、标签池、页面会话内 fetch | 登录态和会话下载无需从 Mika 重新实现 |

本地证据：`src/ios/Agent/Chat/AIChatViewModel+SystemPrompt.swift:218`；`AIChatViewModel+AgentLoop.swift:1997`；`BrowserUseManager.swift:311`；`BrowserUseJavaScript.swift:727`；`BrowserTabPool.swift:805`。

## 最值得先做的两项优化

### 1. 将统一 DOM 等待改为按动作和结果等待

当前 `BrowserUseManager.execute` 对 navigate、click、scroll、scrollAndCollect、hover、type 都调用 `waitForDomSettleAndSnapshot`。后者先运行 `collectDomChangeSummary(timeout: 5.0)`。

这一函数每 500ms 通过一次 WebKit JS 调用读取 DOM mutation 计数，要连续 3 个区间的增量“不增加”才返回。安静页面上也要经历约 1.5 秒轮询，之后才截图。若有 8 次这样的操作，仅这段轮询的理论累计等待就约 12 秒；这是源码推导，不是实测耗时或承诺可节省的时间。

此外，“变动速率不增加”不等于“目标可用”：持续以相同速率更新也可满足它，而晚到的数据可能在提前返回后才出现。观察器是在动作完成后安装的，也可能漏掉动作同步触发的 DOM 更新。

建议：
- type 以输入值/目标状态回读为主；scroll 以滚动位置、目标列表更新为主；click 等待预期元素、文本或 URL；navigate 等待新文档及调用方所需的内容。
- 在动作前记录或安装观察信号，动作后只等待相关条件。将条件判断和观察尽量放进一次有时限的页内异步调用，减少 Swift ↔ WebKit 轮询。
- 没有指定条件时保留有上限的通用 quiet fallback；在结果中区分条件满足、仅已派发、等待超时。不要通过全局缩短超时制造“快但没完成”的结果。
- `scroll_and_collect` 自己已经逐步等待变化和稳定；完成后再统一等待一次，值得检查是否可以合并。

Mika 按用途区分等待：focus quiet 150ms、输入回读 quiet 200ms、scroll quiet 300ms、通用 quiet 500ms；提供 text_present、text_absent、url_contains、network_idle。其 SettlePolicy 仅在本次动作相关网络请求尚未结束时继续延长等待。这些数字是 Mika 实现参数，不能直接当成咱们的最佳配置。

来源：[WebScreen.kt](https://github.com/wangzan101/Mika/blob/ebb0e44750d80aabb6b642c69908825d6b1a8107/app/src/main/java/com/wangzan101/mika/cap/web/WebScreen.kt#L1277)、[SettlePolicy.kt](https://github.com/wangzan101/Mika/blob/ebb0e44750d80aabb6b642c69908825d6b1a8107/core/src/main/kotlin/com/wangzan101/mika/core/cap/web/SettlePolicy.kt#L11)、[PageReads.kt](https://github.com/wangzan101/Mika/blob/ebb0e44750d80aabb6b642c69908825d6b1a8107/core/src/main/kotlin/com/wangzan101/mika/core/cap/web/PageReads.kt#L209)。
落点：`BrowserUseManager.swift:307,459,537,1596`；`BrowserUseJavaScript.swift:849`。

### 2. 让预览截图退出每个动作的必经路径

当前成功的视觉变化动作会等待 `takeSnapshot`、JPEG 编码与写文件。需要调整视口时还等待 120ms。自动快照只用于 UI 预览，并未把 base64 图片默认发给模型；所以这里的直接收益是减少本地执行时间和资源消耗，不能声称节省了这些预览图的模型视觉 tokens。

建议：
- 显式 screenshot 请求照常完成并返回；没有展示浏览器预览的自动流程，可不为每个中间动作截图。
- 多步流程在最终状态截图，或按可见预览需求合并、限频更新。
- 需要视觉判断、用户接管和失败诊断时再提供对应截图；不能取消任务实际依赖的观察。
- 优先采用按需/批次结束截图。若异步截图，需要确保图片对应的页面状态，避免把后一步页面显示成前一步证据。

落点：`BrowserUseManager.swift:459–529`；`AIChatViewModel+ConcurrentTools.swift:727`。

## Mika 可借鉴的其他机制

| 机制 | Mika 的实现优势 | iOS 适配与优先级 |
|---|---|---|
| 有界多步执行 | web_script 在一次模型调用中循环，动作仍走正常执行和记录；限制动作/读取次数，跨文档导航会结束脚本 | P1：优先验证现有 CLI 批处理；若桥接/中间处理占比明显，再给 browser_use 增加原生结构化 batch，复用原动作分发。无需先引入完整沙箱 JS 运行时 |
| 页面摘要及质量信号 | PageDigest 折叠导航/页脚/推荐列表，保留主体，返回分页 offset、正文密度、薄内容/需登录/被拒绝/图片型内容等判定 | P1：扩展现有 get_readable，支持 max_chars、offset、按字段查询及结构化错误；减少无效重读和把整页交给模型筛选 |
| 站点知识与命令 | 按域名提供 SITE.md 和可参数化的只读站点命令，使用前验证当前站点 | P1：复用现有 SkillStore；先为实际高频站点补充导航路径、稳定选择器和列表提取脚本，失败回落通用浏览器。节省重复探索与生成脚本的模型轮次 |
| 语义元素与重定位 | 可见 DOM + CDP 无障碍树融合，返回 role/name/ref；解析时检查位置、遮挡、唯一对应关系 | P2：先在现有 find_elements 增加 role、accessible name、可见/遮挡、可用状态和短引用，减少选择器猜测。完整 CDP AX 融合需另行适配 |
| 网络账本与响应读取 | CDP 事件区分在途请求和动作关联请求，按需取 XHR/fetch 响应正文 | P2：有价值但不是小改动。WKWebView 现有路径不是 Chromium CDP；先用可观察条件及已有页面 fetch。页内 fetch/XHR 观测只能覆盖部分请求，不能冒充完整网络账本 |

来源：
- [BrowserScript.kt](https://github.com/wangzan101/Mika/blob/ebb0e44750d80aabb6b642c69908825d6b1a8107/core/src/main/kotlin/com/wangzan101/mika/core/cap/web/BrowserScript.kt#L18)、[web_script 工具说明](https://github.com/wangzan101/Mika/blob/ebb0e44750d80aabb6b642c69908825d6b1a8107/core/src/main/resources/prompts/tools/web_script.md)。
- [PageDigest.kt](https://github.com/wangzan101/Mika/blob/ebb0e44750d80aabb6b642c69908825d6b1a8107/core/src/main/kotlin/com/wangzan101/mika/core/cap/web/PageDigest.kt#L27)、[ReadPage](https://github.com/wangzan101/Mika/blob/ebb0e44750d80aabb6b642c69908825d6b1a8107/core/src/main/kotlin/com/wangzan101/mika/core/cap/web/PageReads.kt#L41)。
- [SiteCommands.kt](https://github.com/wangzan101/Mika/blob/ebb0e44750d80aabb6b642c69908825d6b1a8107/core/src/main/kotlin/com/wangzan101/mika/core/knowledge/SiteCommands.kt#L23)、[ReadScriptTool.kt](https://github.com/wangzan101/Mika/blob/ebb0e44750d80aabb6b642c69908825d6b1a8107/core/src/main/kotlin/com/wangzan101/mika/core/cap/web/ReadScriptTool.kt#L77)。
- [ElementFusion.kt](https://github.com/wangzan101/Mika/blob/ebb0e44750d80aabb6b642c69908825d6b1a8107/core/src/main/kotlin/com/wangzan101/mika/core/cap/web/ElementFusion.kt#L10)、[NetworkLedger.kt](https://github.com/wangzan101/Mika/blob/ebb0e44750d80aabb6b642c69908825d6b1a8107/core/src/main/kotlin/com/wangzan101/mika/core/cap/web/NetworkLedger.kt#L33)。

## 额外的低成本提速方向

1. **减少不必要的观察往返。** 对“打开文章并取正文”这类已知任务，复用现有 shell 把 navigate → read 串起来；可评估新增直接返回所需正文的导航模式。一次提取需要的标题、条目、链接，避免分别读取。
2. **数据任务选择更短的路径。** 已有明确网页链接/API 且任务只需数据时，复用 execute_js 中的会话 fetch 或已有 shell HTTP 能力；需要渲染与交互时才操作页面。已有页面 fetch 受源站策略约束，不能假设所有站点都能直接访问接口。
3. **评估正常主文档缓存策略。** navigate 当前使用 reloadIgnoringLocalCacheData。可评估以 useProtocolCachePolicy 为普通导航默认值，并保留显式刷新；收益取决于源站缓存头与访问模式，不应声称能消除所有子资源请求。安全清理/特殊重新加载路径应按原目的独立保留。
4. **让模型用好现有并发。** 独立页面分配明确 tab_id，并行导航/读取；同一页的输入、点击、回读保持顺序。当前每池常规上限 3、带 agents 可至 6、全局上限 8，已有内存回收逻辑，不建议先增加上限。
5. **缩小给模型的观察。** 已知目标时返回所需区域/字段与足够上下文；遇到定位失败或信息不足再扩大到骨架/截图。避免将每一步都变成全页视觉推理。

## 不建议照搬的部分

- Mika 是 Android 应用，其后台原生屏幕控制不能作为 iOS 内置浏览器的直接移植方案。[README](https://github.com/wangzan101/Mika/blob/ebb0e44750d80aabb6b642c69908825d6b1a8107/README.md)。
- Mika 的 CDP 输入、完整网络响应捕获和无障碍树读取不等于 WKWebView 的页面 JS API。WebKit 官方记录的 iOS 检查入口是 Safari Web Inspector；不要把启用 isInspectable 当成在应用内获得 Chromium CDP。[WebKit 官方文档](https://webkit.org/web-inspector/enabling-web-inspector/)。
- 不照搬它的主动浏览节奏作为“提速优化”。PagePacing 普通策略从第二页起计算 4–7 秒停留，逐步增长至 12 秒；careful 策略更长。已经用于模型思考/读取的时间会抵扣，因此不代表每次都额外睡这么久。[PagePacing.kt](https://github.com/wangzan101/Mika/blob/ebb0e44750d80aabb6b642c69908825d6b1a8107/core/src/main/kotlin/com/wangzan101/mika/core/cap/web/PagePacing.kt#L7)。
- 不通过删超时/无限加并发解决后台卡住。项目现有 BrowserResourceMonitor 记录过后台 WebContent 停滞的怀疑与诊断限制；这与正常前台操作慢应分别分析。没有真机日志不能断言所有慢都是 DOM 等待导致。

## 建议实施顺序与验收

**第一轮：条件等待 + 截图策略。** 改动集中在 BrowserUseManager、BrowserUseJavaScript、动作输入/工具 schema 和必要的 CLI 参数映射；先不改 Bot 团队编排和模型调度。

**第二轮：紧凑页面观察 + 高频站点 Skill。** 用真实常见任务选站点，利用现有 SkillStore 和 execute_js/CLI，不先引入大规模站点框架。

**第三轮：按测量决定是否增加原生 batch、网络观测或外部浏览器执行器。** 远程浏览器会改变部署、登录态和网络依赖，仅在需求确实包含长时间后台执行时再评估。

复用已有 MgrTiming / NavTiming / SettleTiming / PoolTiming 和 BrowserBench。当前 Bench 主要循环 example.com 导航与 JS，不能代替交互任务基准。建议新增以下测量场景：

| 场景 | 需要验证的正确性 |
|---|---|
| 静态文章打开并读取 | 内容完整、没有多余导航/截图 |
| 多字段表单 | 每个字段实际写入，提交后可确认状态 |
| SPA 延迟加载/晚到结果 | 不把暂时安静当作结果完成 |
| 虚拟列表滚动采集 | 不漏条目、不重复，终止行为正确 |
| 两三个独立页面并行 | 读取页面对应正确，不串标签/owner |
| 用户接管、取消、secure_input | 延续当前原生处理与中断语义 |

分开记录模型等待、导航/页面加载、DOM settle、截图、桥接/队列、输出 tokens、成功率、重试次数；比较任务耗时中位数与 P95。没有测量前不承诺“提升几倍”。若移除等待后只是失败更快，不算提速成功。

