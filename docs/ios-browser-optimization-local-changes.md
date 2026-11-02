# 浏览器自动化本地改动

基线：`4c3c91d`（包含用户指定的 `bbce47b`）。本次只修改本地文件，未提交、未推送、未触发云构建。

## 已实现

- 浏览器池统一拥有接管状态。UI、直接工具调用、CLI 和共享池的通用子代理使用同一入口限制；已排队动作通过接管代次检查，结束接管后也不会重放旧动作。
- 实际执行计数与 15 秒标签保留期分开。点击后立即显示接管状态，不等待保留期；导航只结束 Agent 的等待，网页可以继续加载，用户可手动停止。取消 DOM 后处理和隐式预览不会走卡死标签重建路径。
- 当前不可取消的网页操作仍在运行时显示“接管中”，待其结束后开放交互。任意网页 JS 不能保证保留页面且立即终止，不把这一等待伪装成已交还控制。
- 结束按钮、浏览器关闭统一释放接管等待者；子代理取消只取消自己的等待，不结束用户的共享接管。去掉原来中途接管的五分钟自动恢复，避免用户操作中自动重新执行。
- DOM summary 的 setup、poll、read 共用单调时钟截止时间；取消会退出等待和截图。观察失败会说明原动作已经执行，避免误报导致重复点击。observer 自带清理定时器，下次安装也会清除旧 observer。
- 隐式/显式截图等待增加 10 秒宿主侧边界，隐式截图可取消；调整视口后用 defer 恢复。宿主结束等待不代表终止 WebKit 内部工作。
- 接管期间不把该池的标签当成空闲页面回收；旧操作的图片不会冒充接管后的当前页面。

## 新参数

| 参数 | 默认 | 语义 |
|---|---|---|
| `preview` | `default` | `none` 仅省略该次动作的隐式预览，保留 DOM 观察；不返回旧图。显式 `screenshot` 和安全输入仍走各自路径。 |
| `result_mode` | `standard` | `collected` 仅支持 `scroll_and_collect` 且必须搭配 `preview=none`；保留滚动内部等待与采集，只省略采集结束后的统一 DOM summary/截图。 |

直接工具 JSON、CLI flags、帮助和模型说明同步更新。无效枚举、类型和参数组合在 JSON 解析边界拒绝。默认调用保留原有等待及预览；没有全局缩短网页加载条件。

```sh
minis-browser-use navigate --url https://example.com --preview none
minis-browser-use scroll_and_collect --scroll-count 5 --preview none --result-mode collected
minis-browser-use screenshot
```

复用 `MgrTiming`、`SettleTiming`、`PoolTiming`，增加跳过后处理/预览策略和接管请求日志，未增加监控系统。

## 已执行的本地验证

- 新增生产 DOM observer JavaScript：11 项断言通过。
- 现有安全输入 JavaScript：55 项断言通过。
- 聊天/设置检查：7 项通过；当前 Bot 源码契约检查通过。
- 修改过的 Swift 文件及生成的 Swift fixture：tree-sitter 无新增语法错误。这不是 Swift 类型检查或 Xcode 编译。
- `git diff --check` 通过。Python 新测试 runner 语法检查通过。
- 全仓数据访问静态检查在 Windows 失败：68 条命中全部在与基线一致的 39 个旧测试文件内，新测试无命中；Windows 路径分隔符与 allowlist 的键不一致。本次没有修改该检查器。

## 待执行的原生验证

Windows 无 `swiftc`、Xcode 和 iOS 模拟器。新增 runner 会明确跳过 Swift；未来 macOS 验证工作流使用 `--require-swift`，不允许静默跳过。

```sh
python3 src/ios/MinisTests/Standalone/run_browser_automation_tests.py --require-swift
python3 src/ios/MinisTests/Standalone/run_browser_form_tests.py
python3 src/ios/MinisTests/Standalone/run_native_interaction_tests.py
```

Swift 回归 fixture 提取实际 dispatcher、后处理、截止时间/取消桥接和接管状态代码，只有 WebKit/平台边界使用假对象；覆盖默认兼容、参数拒绝、快速采集 payload、预览省略、显式截图、setup/poll/read 卡住、任务取消、接管取消后处理、共享等待者和旧队列拒绝。它仍不能代替原生 WebKit 和 UI 验证。

真机需核对：导航/输入/DOM 等待/截图期间接管；聊天、Bot 页面和工具详情入口；结束、关闭、Stop 和子代理取消；接管期间 CLI；安全输入与前后台切换。对静态文章、延迟搜索、虚拟列表分别交替测量默认/快速路径，确认数据集合与任务完成率，再比较总时长、DOM/截图耗时和模型轮次。

当前状态：本地实现及可运行检查完成，原生编译、交互验收与真实性能收益未验证。不承诺具体加速倍数。
