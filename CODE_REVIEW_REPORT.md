# OpenMinis iOS 代码审查报告

审查日期：2026-10-29
审查版本：`bcab00015bb4e1aebb83e12675e0d47d6b25c210`
上游基线：`1a71df0f381cefde80bf912b723de6f9831bc177`
状态：6 项问题均已核实并完成本地代码修复；已通过可在 Windows 执行的检查，Swift/macOS 与完整 iOS 构建验收待执行。具体证据见第 7 节。

## 1. 审查结论

两轮审查共发现 **6 项可操作问题：2 项 P1、4 项 P2**。其中，数据库辅助方法被删除后仍有调用，是需要优先解除的编译阻断；定时任务编辑存在提前执行风险。其余问题涉及持续集成测试、备份恢复、已删除会话的访问和记忆来源识别。

本报告基于代码差异、相关调用链及测试实现的检查。当前 Windows 环境没有 Swift/Xcode，未执行 iOS 编译或运行时测试。报告不代表整个应用已经通过发布验证，也不代表未列出的路径不存在缺陷。

## 2. 范围与方法

| 轮次 | 提交范围 | 数量 | 主要内容 |
| --- | --- | ---: | --- |
| 第一轮 | `8c3e207..bcab000` | 2 | 全新安装路径、旧数据与同步代码清理、备份恢复 |
| 第二轮 | `1a71df0..8c3e207` | 27 | 浏览器书签与密码、Bots 与群聊、长期记忆、多会话、定时任务编辑、MCP 能力与权限、测试与构建 |
| 合计 | `1a71df0..bcab000` | 29 | 相对本地上游基线的全部新增提交 |

合并后的净差异涉及 96 个文件，新增 6,263 行、删除 13,037 行。两轮分别检查了 69 和 47 个文件，存在重叠，不能相加作为独立文件数。

已核对本地 Git 引用：`main` 与 `origin/main` 指向审查版本，`upstream/main` 指向上述基线；没有其他分支上的额外提交。未联网刷新远端，因此该结论针对本地可见历史。上游基线及更早的 74 个历史提交不属于本次逐提交审查范围。

审查采用 `review-agent` 的只读、缺陷优先方法：检查变更及必要上下文，核对调用方和相关测试，只报告能够从代码说明触发条件、影响和修复方向的问题。审查期间未修改业务代码。

优先级：P1 表示应优先修复的严重问题；P2 表示应纳入修复计划的普通缺陷。编号用于跟踪，不表示发现顺序。

## 3. 问题清单

| 编号 | 优先级 | 问题 | 主要影响 | 状态 |
| --- | --- | --- | --- | --- |
| CR-01 | P1 | 已删除数据库辅助方法仍被调用 | 应用编译失败 | 已修复代码，待 macOS 验收 |
| CR-02 | P1 | 编辑完成触发任务可能执行旧等待任务 | 提前执行，破坏依赖顺序 | 已修复代码，待 macOS 验收 |
| CR-03 | P2 | Bot 持久化测试仍依赖旧所有权推导 | CI 测试断言失败 | 已修复代码，待 macOS 验收 |
| CR-04 | P2 | 统一备份合并路径丢弃非自定义模型 | iOS 16 恢复行为回归 | 已修复代码，待 macOS 验收 |
| CR-05 | P2 | Bot 会话列表仍可打开已删除会话 | 打开无有效持久化记录的聊天 | 已修复代码，待 macOS 验收 |
| CR-06 | P2 | 相同的新记忆请求被判为旧证据 | 明确重新保存请求遭拒 | 已修复代码，待 macOS 验收 |

## 4. 原始详细发现（修复前）

### CR-01 · [P1] 移除已删除辅助方法的残留调用

**位置：** [ProviderConfigDB.swift](src/ios/Providers/ProviderConfigDB.swift)，第 298 行；第一轮清理变更。

`ensureGroupTombstoneColumns` 的定义已经移除，但数据库读取路径仍调用 `Self.ensureGroupTombstoneColumns(db: db)`。在当前 Swift 源码中检索该名称，只剩这一处调用。类型检查时无法解析该成员，阻断应用编译；仅做语法解析无法检出这种错误。

**修复建议：** 依据全新数据库 schema 的实际字段，删除不再需要的调用；若该路径仍需补齐字段，则恢复承担该职责的实现。不要仅为通过检查加入空方法。

**验收建议：** 对真实应用目标进行类型检查或构建，并验证全新数据库创建后能成功读取模型分组。当前结论来自源码检查，未运行 Xcode 构建。

### CR-02 · [P1] 编辑完成触发任务时阻止旧等待任务继续执行

**位置：** [AgentJobRegistry.swift](src/ios/Agent/Jobs/AgentJobRegistry.swift)，第 520–531 行；关联 [ScheduledJobRunner.swift](src/ios/Agent/Jobs/ScheduledJobRunner.swift)，第 120–129 行。

用户编辑一个正在等待上游完成的 `.onCompletion` 任务并保存时，`updateSchedule` 取消旧任务，再重新注册等待。旧任务在通知异步序列因取消而结束后，会落入循环后的 `fire()` 和 `finish()`；取消检查只在循环体中，循环结束后没有检查。`fire()` 的执行占用检查也不检查任务取消状态。因此，保存提示词修改可能提前执行下游任务并将其标记完成，而上游尚未完成。

**修复建议：** 只有实际收到匹配的上游完成事件才允许执行；取消或通知序列结束时直接返回，避免旧任务执行或修改新任务状态。

**验收建议：** 使用真实等待逻辑创建依赖任务，在上游未完成时修改提示词。保存后应保持等待且执行次数为零；发送上游完成事件后应仅执行一次，并使用新提示词。现有 `run_schedule_edit_tests.py` 将 `arm()` 替换为计数器，不能验证这条生命周期路径。该风险尚未在 Apple 运行时复现。

### CR-03 · [P2] 更新 Bot 持久化测试的所有权数据

**位置：** [BotWorkspacePersistenceTests.swift](src/ios/MinisTests/Standalone/BotWorkspacePersistenceTests.swift)，第 16–23 行；关联 [BotWorkspaceStore.swift](src/ios/Views/ContentView/Bots/BotWorkspaceStore.swift)，第 63–68 行。

测试仅设置 `room.sessions[researcher.id] = "group-session"`，没有写入 `sessionOwners`，却在重新加载后断言 `bot(forSession:)` 能返回对应 Bot。清理变更已移除从旧会话字段推导所有权的逻辑，当前查询只读取 `data.sessionOwners`，所以该断言会失败。CI 工作流仍运行此测试，测试夹具与新存储契约不一致。

**修复建议：** 在测试中按真实会话创建路径持久化所有权映射，继续验证重新加载后的 Bot 查询、群聊绑定和删除保留行为。

**验收建议：** 在 macOS 上运行 `BotWorkspacePersistenceTests.swift` 及 Bot 会话绑定测试。此处为代码推导的断言失败，当前环境未实际执行 Swift 测试。

### CR-04 · [P2] 在备份恢复时保留备份中的非自定义模型

**位置：** [BackupImporter+Categories.swift](src/ios/Agent/Backup/BackupImporter+Categories.swift)，第 395 行；关联 [ProviderBackupMerger.swift](src/ios/Agent/Sync/ProviderBackupMerger.swift)，第 222–230 行。

原 iOS 16 恢复分支按 ID 补入备份中本地缺失的模型，不限制 `isCustom`。清理后所有系统版本统一调用 `ProviderBackupMerger.restore`，而该合并器只新增 `isCustom == true` 的缺失模型，其他条目直接跳过。因此在 iOS 16 的空配置或缺少相关模型的设备上恢复备份时，服务商或分组可能恢复，但备份中的非自定义模型没有恢复，不能还原原有可用配置。

**修复建议：** 将备份恢复的规则与设备同步中的“本地 API 列表为准”规则区分开；明确恢复备份缺失条目时的保留、ID 引用及冲突处理。

**验收建议：** 使用包含 `isCustom == false` 模型及引用它的模型分组的备份，在空配置上恢复，确认条目存在且分组可以解析到模型。此问题作为 iOS 16 路径变化引入的回归报告；不将原有 iOS 17 路径中的相同行为重复归因于本次改动。

### CR-05 · [P2] 从 Bot 会话列表排除已删除的会话

**位置：** [BotMemoryView.swift](src/ios/Views/ContentView/Bots/BotMemoryView.swift)，第 174–183 行。

用户在 History 删除 Bot 会话后，Bot 的 `conversationIds` 和所有权映射仍保留旧 ID。会话列表继续为这些 ID 生成按钮；`getSession` 返回空值时仅不设置标题，没有过滤条目。点击后 `selectConversation` 仍可成功，并直接用已删除的 ID 打开聊天。运行时 `ensureSession()` 在 `sessionId` 非空时直接返回，也不会重建有效会话。

**修复建议：** 列表只展示仍存在的会话，并在打开前确认目标有效；失效条目应从展示数据中清除或明确提示不可用。

**验收建议：** 创建多个 Bot 会话，在 History 删除其中一个，再打开该 Bot 的 Conversations。已删除项不应可选，其余会话及新会话创建应正常。当前结论来自删除、列表选择和聊天初始化调用链检查。

### CR-06 · [P2] 区分重新发送的记忆请求与旧消息重放

**位置：** [AIChatViewModel+BotMemory.swift](src/ios/Views/ContentView/Bots/AIChatViewModel+BotMemory.swift)，第 26、101–103 行。

私聊记忆来源标识只由消息内容指纹生成。用户发送“记住我喜欢简洁回答”、删除该记忆，再在同一会话重新发送相同内容，新消息会得到与旧消息相同的来源标识。删除记录检查发生在明确保存授权被处理之前，仍将其判为已忘记的旧证据并拒绝保存。当前方案避免了重新加载后的旧证据复活，却也阻止了合法的新请求。

**修复建议：** 使用可持久化的消息身份标识来源，使同一消息重新加载后保持身份，而用户重新发送的消息具有独立身份。继续保留对旧证据重放的阻止。

**验收建议：** 同时覆盖两种情况：删除后重放原消息不得重建记忆；用户随后发送内容相同的新明确请求可以保存。现有测试只覆盖“新 UI UUID、相同旧来源文本”的重放场景，未覆盖真正的新消息。

## 5. 已做验证与限制

| 项目 | 结果或限制 |
| --- | --- |
| 提交范围核对 | 已确认本地可见的 29 个新增提交全部纳入两轮范围 |
| 差异格式检查 | 两轮 `git diff --check` 均通过；不等同于编译或功能通过 |
| 全新数据库 schema | 第一轮完成 SQLite 建表检查；不覆盖 Swift 符号解析或应用启动 |
| 调用链与测试核对 | 已检查相关实现及测试覆盖；测试替身不能证明完整运行时行为 |
| iOS 构建与 Swift 测试 | 未执行：当前 Windows 环境没有 Swift/Xcode |
| 真机与模拟器 | 未执行，包含 Keychain、生物识别、WebKit、SwiftUI 和调度生命周期 |
| 原始审查时的修复状态 | 当时 6 项问题均未修复；本次修复更新见第 7 节 |

工作区原有 `findings.md`、`progress.md`、`task_plan.md` 为未跟踪文件，本次报告未改动这些文件。

## 6. 建议修复顺序

1. 修复 CR-01，恢复真实应用构建能力；同步修正 CR-03，使持久化测试符合当前存储契约。
2. 修复 CR-02，并补充取消、重新注册等待和单次执行的真实调度回归测试。
3. 修复 CR-04、CR-05、CR-06，分别验证恢复完整性、删除后访问和记忆重新授权。
4. 在具备 Xcode 的环境执行相关测试及应用构建，对受影响流程完成模拟器或真机验证后，再关闭对应问题。

所有验收步骤均为后续建议，不表示已经执行或通过。


## 7. 本次修复与验证（2026-10-29）

以下是本次修复记录；上文提交范围及行号描述原始审查版本。后续仓库上传与云构建状态单独记录，不能视为测试通过证据。

| 编号 | 已实施修复 | 回归覆盖 |
| --- | --- | --- |
| CR-01 | 删除 `loadGroups` 中已不存在的 schema 辅助方法调用；直接使用全新 schema 已提供的字段 | `check_fresh_install.py` 增加模型分组写入/读取和残留符号检查，已通过 |
| CR-02 | `.onCompletion` 仅在循环内收到匹配事件后执行；序列结束直接退出，执行中取消后不再完成旧任务 | 新增 `run_schedule_completion_tests.py`，抽取真实等待分支及 `updateSchedule`，使用真实 Foundation 通知和 Task，仅执行副作用使用替身；覆盖编辑重注册、无提前执行、无关事件、仅一次执行新提示词、直接取消。待 macOS 执行 |
| CR-03 | 夹具显式持久化 `sessionOwners`，与真实会话创建契约一致 | 增加群聊所有权重载及删除 Bot 后所有权保留断言。待 macOS 执行 |
| CR-04 | 备份专用合并器补入所有缺失模型，不再限制 `isCustom`/`isUserModified`；已有模型仍保留本地 API 元数据并按原时间戳规则合并用户覆盖 | 新增 `run_backup_model_restore_tests.py`，编译实际模型合并代码与 `ModelEntry`，覆盖非自定义/自定义模型、序列化后恢复、分组引用 ID 可解析、重复恢复、覆盖冲突和墓碑过滤。待 macOS 执行 |
| CR-05 | Conversations 仅加载 ChatStore 中存在的会话；选择方法移到 Sessions 扩展，异步确认记录存在后才更新选中项；失效点击项从列表移除 | 会话绑定测试增加已删除 ID 选择失败且当前选择不变的断言；现有 UI 类型检查继续覆盖该页面。待 macOS 执行 |
| CR-06 | 用 UI `historyAnchorId` 关联 `agentHistory.dbMessageId`，复用发送与重载路径已有的数据库身份；没有持久化身份时不接受保存 | 运行时测试区分新 UI 身份/相同数据库行的重放，以及相同文本/新数据库行的明确请求；前者拒绝、后者允许。待 macOS 执行 |

本地已执行：

- `python src/ios/MinisTests/Standalone/check_fresh_install.py`：全部通过，覆盖 SQLite 新建/重开、消息与同步写入、服务商 schema 和模型分组读取。
- 修改相关 Python 测试脚本的 AST 语法检查：通过。
- 修改的 Swift 文件及两个新测试脚本生成的 Swift harness 经 tree-sitter 语法检查：未出现新增错误；调度文件和 BotMemoryView 各有一处与 HEAD 相同的既有解析器限制。
- `git diff --check`：通过。

两个新增运行时套件已接入 `.github/workflows/ios-validation.yml`。本机没有 Swift/Xcode，未执行 Swift 类型检查、运行时测试、完整应用构建或真机/模拟器验证；Python/SQLite/tree-sitter 检查不替代这些验收。未把测试脚本生成和语法检查当成行为测试通过。

云打包配置：完整构建成功后将 Debug iOS app 封装为 `OpenMinis-unsigned.ipa`，上传到 Actions 的 `OpenMinis-unsigned-ipa` 产物，保留 14 天。此产物未签名，需要另行签名后安装。
