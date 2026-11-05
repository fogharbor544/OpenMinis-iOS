# 备份目的地与密码同步修复审查（2026-11-05）

> 2026-11-06 调整：按用户要求，“添加备份目的地”的选择器、同步登记和文件夹添加/重新激活流程已恢复上游 `1a71df0` 实现。因此下文第 8 项的添加阶段等待修复已撤回；已有挂载冷启动的 one-shot 超时处理继续保留。智能体备份恢复与浏览器密码修复未改动。上游同步访问 Files 的交互、iOS 编译及真机备份恢复仍待原生环境验证。

> 修复状态（2026-11-05 后续）：九项代码修复已落实，独立复核未发现剩余确定 P1/P2。原生编译与运行仍待 macOS/Xcode 验证。下文“确认的问题”保留原始审查记录，文末为本次修复证据。

结论：需要修改后再验收。上次会话的三个 gpt-6.1-sol / high 审查均已完成；本次恢复最终结果，逐项核对当前本地源码，并复现 SPA 清空表单的漏采集。没有修改业务代码，没有提交、推送或触发云构建。

审查来源：会话 01a1ab2a-5ac9-7303-8d43-d3e79c7d1423，以及该会话的 review_folder_picker、review_vault_sync、review_save_prompt 子智能体。审查对象为当前未提交改动；历史“已修复”描述不能作为真机验收证据。

## 确认的问题

### 1. [P1] WebView 重建后不再弹出保存卡片

位置：`src/ios/Agent/BrowserUse/BrowserUseManager.swift:2064`、`:2090`，注册方法在 `:354`。

`setUserAgent` 和 `setViewport` 调用工厂创建新 WebView，工厂注入采集脚本，但这两条路径没有调用 `registerCredentialSaveHandler`。消息处理器只在两个初始化方法中注册。重建后脚本发送消息会失败，并被 JS 的空 catch 吞掉，后续登录无法触发卡片。

修正方向：每次创建/替换 WebView 时配齐脚本和处理器；覆盖 UA 与 viewport 重建后的原生 WebKit 测试。

### 2. [P1] SPA 同步清空表单时丢失保存候选

位置：`src/ios/Agent/BrowserUse/BrowserUseManager.swift:338`。

click 捕获监听器延迟到 `setTimeout` 才读取字段。若页面自己的 click handler 同步清空、隐藏或禁用密码框，且没有原生 submit 事件，采集直接退出。本次用现有 runner 提取的生产 JS，在 click 返回后立即清空字段，复现消息数为零。

修正方向：在页面处理点击之前读取候选，再按登录交互决定提交提示；回归测试应覆盖真实事件顺序。

### 3. [P1] 来源检查未绑定 WebKit 实际发送来源

位置：`src/ios/Agent/BrowserUse/BrowserUseManager.swift:360`。

原生只校验消息 body 中声明的 origin 与 `currentURL` 一致，没有检查 `message.webView` 或 frame 的实际 security origin。页面可直接调用消息桥；导航过程中 `currentURL` 还可能是旧页值，从而让新页面的候选以旧网站身份进入保存/更新卡片。这是静态确认的校验缺口；未在本机运行 WebKit 攻击复现，也没有发现借此读取已存密码的通道。

修正方向：由原生可信的发送 WebView/frame 来源建立网站归属，不信任 body 自报来源。

### 4. [P1] 等待展示的旧提示可长期占用全局卡片位置

位置：`src/ios/Agent/BrowserUse/BrowserPasswords.swift:971`、`:723`；`src/ios/Agent/BrowserUse/BrowserTabPool.swift:727`。

新会话使用恒真的 `sourceIsValid`；120 秒超时直到展示完成才启动。关闭 tab 只结束 secure-input 会话，没有结束 credential-save 会话。manager 与 prompt 相互强引用，无法靠静态 weak owner 自动释放。候选在没有窗口的阶段关闭 tab 后，可继续占用全局位置并阻止其它 tab 的提示，或稍后弹出已关闭页面的旧卡片。

修正方向：等待阶段也应有期限，关闭/销毁来源时明确结束候选，清理全局占位；正常登录跳转应有独立的保留规则。

### 5. [P1] 管理器持续前台打开时，共享文件变更不会刷新

位置：`src/ios/Agent/BrowserUse/BrowserPasswords.swift:121`、`:418`。

自动刷新仅在解锁与 scenePhase 变为 active 时发生。管理器已经打开且 app 保持前台时，agent 更新共享文件不会触发任一入口，列表继续显示旧内容。当前实现没有满足这一使用路径下的同步预期。

修正方向：为共享文件变更接入刷新机制，并在解锁期间保持列表一致。

### 6. [P1] 源记录被改名或删除后，编辑仍可能误报成功

位置：`src/ios/Agent/BrowserUse/BrowserPasswords.swift:280`、`:285`、`:295`。

例如管理器缓存账号 a，agent 将文件中的账号改成 b，随后编辑缓存 a。`replaceInFile` 未命中时原样返回对象，调用方不检查命中结果，仍写 Keychain 并返回成功。源文件消失时则直接跳过回写。用户看到保存成功，但共享文件没有修改，下次导入还可能覆盖该编辑。

修正方向：关联源缺失或记录未命中必须反馈冲突/失败，不能静默降级成本地成功。

### 7. [P2] 域名数组或嵌套集合清空后无法同步删除

位置：`src/ios/Agent/BrowserUse/BrowserPasswords.swift:220`。

解析器支持域名键控集合，但空值验证只接受顶层空数组、空字典及几个固定的顶层集合名。删除最后一条后产生的 `{"example.com":[]}` 会被拒绝，无法作为有效空文件同步，agent 清空该数组时 Keychain 中旧记录会保留。

修正方向：空值验证应与实际支持的文件结构一致，同时继续拒绝无关或损坏 JSON。

### 8. [P2] 文件夹回退激活尚未完成就返回添加成功

位置：`src/ios/Views/Settings/MountedFoldersManager.swift:379`；`src/ios/Agent/Backup/BackupDestinations.swift:92`。

直接获取 scope 失败时，代码启动独立 Task 解析 bookmark，但立即返回条目。调用方随即注册并勾选目的地、结束添加进度，此时 activeURLs 可能为空，立即备份会报目录不可用。后续激活失败也不会进入添加界面的错误处理。

修正方向：目的地添加流程应等待可用结果或明确显示激活中与失败状态，避免将尚不可用的目录当作添加成功。

### 9. [P2] 用户名采集可能漏掉常见字段或选错字段

位置：`src/ios/Agent/BrowserUse/BrowserUseManager.swift:312`。

选择器没有覆盖未显式写 `type` 的普通用户名 input。逗号选择器也不代表优先级，前面的其它文本框可能先被选中。因此卡片可能保存空账号或搜索词，并按错误的 origin + username 目标合并更新。此项已核对选择器源码；本次 synthetic DOM 没有验证真实浏览器选择器行为。

修正方向：优先明确的 username/email 语义，再筛选合理的文本字段；使用真实 DOM 回归验证。

## 验证与限制

本次重新执行：

- `python src/ios/MinisTests/Standalone/run_credential_save_tests.py`：通过。
- `python src/ios/MinisTests/Standalone/run_secure_input_tests.py`：55 项生产 JS 断言通过。
- 使用前者提取的生产 JS，内存替换测试主体：复现 SPA 同步清空字段后无保存候选；没有修改测试文件。
- `git diff --check`：通过。

这些检查不能证明修复已可验收：现有采集 fixture 使用 synthetic DOM，不覆盖真实选择器、WebView 重建、原生来源校验、卡片展示/销毁和 FileProvider。Windows 主机没有 swiftc/Xcode，未执行 Swift 编译、XCTest、Keychain/Face ID 或真机交互验证。

iframe、多步登录、改密、新建本地记录是否必须写入共享文件，以及 popup 是否共享 user-content controller，属于覆盖范围或待原生验证事项，没有在此升级为已确认缺陷。既有 bookmark resolver 的 task-group 超时问题另需在修复回退路径时核实，不把推测性的 symlink 竞争作为本次阻断项。

## 本次修复与验证

- WebView 两条重建路径均重新注册消息处理器；原生校验实际发送 WebView、主 frame 与 WebKit security origin，移除 currentURL 作为来源依据。
- click 捕获阶段立即采集，避免 SPA 清空字段；按 username autocomplete、账号 name/id、email、文本字段依次选择用户名，覆盖未声明 type 的文本字段。
- 保存提示弱引用 manager，等待窗口也有 120 秒期限；关闭、回收、抢占、重建标签及 WebContent 终止时清理提示和全局占位。原有 secure-input 元数据等待契约保留。
- 密码管理页可见期间运行可取消的共享文件 monitor，每秒检查一次，未变化字节不重复写 Keychain。锁定后不读取文件。固定共享文件不再创建 bookmark。
- 关联源必须存在且恰好匹配一条未变化的记录，否则在写 Keychain 前失败；保留已有文件回滚。共享文件删除与有效空嵌套/域名集合会移除共享来源记录，无关或损坏 JSON 不清空密码库。
- 文件夹取得 active scope 后才持久化并返回成功；回退路径等待解析结果，失败传给添加界面。新增 one-shot resolver 避免超时等待阻塞 FileProvider 工作结束，并复用于既有冷激活路径。

本次实际执行通过：

- 生产 JS 登录采集回归：包含先失败后通过的 SPA 同步清空、语义账号优先与隐式文本账号用例。
- `run_secure_input_tests.py`：55 项断言。
- `run_browser_takeover_tests.py`：14 项测试。
- `check_chat_settings_contracts.py`：7 项测试。
- `check_fresh_install.py`：会话和 provider SQLite 初始化/重复打开检查。
- `check_current_bot_contract.py`：源码契约检查（输出明确不包含 Swift 运行）。
- 修改的 Python runner 语法、六个完整 Swift 文件及 BrowserUseManager 五个修改方法、生成的 storage/form/mount Swift fixture 的 tree-sitter 语法检查。
- `git diff --check`。

独立 gpt-6.1-sol / high 复核发现的嵌套 accounts.primary 空集合遗漏及 native runner 13→15 计数遗漏已修正，复核结束时未发现其它确定 P1/P2 或确定 Swift 编译错误。计数门已用合成结果验证；未执行模拟器。

验证限制：本机缺少 swiftc/Xcode，storage runner 实际启动因找不到 swiftc 失败，新增 XCTest、原生 WebKit/form/presentation 和 mount resolver 行为测试均未执行。tree-sitter 不能替代 Swift typecheck；BrowserUseManager 整文件解析超时，已对五个改动方法分段解析。未提交、推送或触发云构建。
