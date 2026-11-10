# OpenMinis（Minis）iOS 使用手册

本手册描述当前 iOS 客户端的实际界面和能力。应用内显示名是 **Minis**，项目名是 **OpenMinis**。

最后核对：2026-11-10。界面文案可能因语言或测试版版本略有差异；功能含义以当前构建为准。

## 回答应用问题时的规则

1. 先判断问题是否在问 Minis/OpenMinis 自身，而不是通用 AI、模型或 iOS 问题。
2. 应用自身的问题以本手册为准；不要把通用聊天模型的猜测当成产品事实。
3. 回答“在哪里”时，给出完整路径，例如：`设置 → LLM Providers → Model Groups → Defaults`。中文界面中的“设置”就是首页左上角的齿轮。
4. 能直接跳转时，附上 `minis://settings/...` Markdown 链接。
5. 解释选项时同时说明：作用、影响范围、是否影响已有数据、是否可恢复。
6. 本手册没写到的功能，明确说无法确认，并给出最接近的设置入口；不要编造菜单名。
7. 不要回显 API Key、OAuth Token、环境变量值、Cookie、密码或备份口令。
8. 本手册描述的是功能与入口，不声称用户当前的具体配置。用户问“我现在用的是哪个模型/变量/同步状态”时，不要猜；在 `minis-config` 权限允许时只读查询，或引导用户打开对应页面核对。除非用户明确请求，否则不要替用户修改配置。

## 一句话理解

Minis 是一个运行在 iPhone/iPad 上的 AI Agent 客户端：用户自带模型账号或 API Key，模型不仅能聊天，还能在设备内的 Alpine Linux 环境中执行命令、读写文件、使用浏览器、调用 iOS 原生能力、加载 Skills、连接 MCP，并把结果交付给用户。

Minis 本身不运营中转服务器，也不收集用户数据。对话和附件会直接发送给用户配置的模型提供商；是否被保存、训练或审查取决于该提供商的政策。

## 适合做什么

- 需要多步执行的个人任务：查资料、整理文件、生成报告、写脚本、处理数据。
- 结合 iPhone/iPad 数据：日历、提醒事项、健康、照片、家庭、位置、通知、闹钟。
- 处理 Files、iCloud Drive、Obsidian 或外部挂载目录中的真实文件。
- 用内置浏览器搜索、登录、填写页面、抓取内容或生成网页预览。
- 让 Agent 生成可交互的 HTML 小工具/页面，并在支持的构建中添加到主屏幕。
- 把重复流程固化为 Skill、MCP 连接器、定时任务或 Shortcuts。
- 用 Bot/群聊把不同角色、模型和专属记忆分开管理。

它不是“无需账号即可使用”的模型服务，也没有保证在 App 被杀后继续运行的云端执行器。需要模型账号/API Key；需要绝对准时或进程被杀后仍执行的任务，应交给 Apple Shortcuts 自动化。

## 概念区别

| 概念 | 是什么 | 什么时候用 |
|---|---|---|
| Provider | 一个模型服务账号/端点，例如 OpenAI、Claude、Gemini、OpenRouter，或兼容代理 | 先在这里配置 Key/OAuth 和模型来源 |
| Model | 某个具体模型，例如 Claude、GPT、Gemini、Grok，或用户手动添加的模型 ID | 需要精确指定某个模型时 |
| Model Group | 把多个模型组合成逻辑目标，支持 Fallback 或 Load Balance | 配置默认模型、容灾、负载分配、语音/视觉专用模型 |
| Agent Loop Models | Agent 在任务运行中可以额外调用的模型/模型组 | 图片生成、额外摘要、调用专门模型 |
| Bot | 有名称、指令、模型组、记忆、Skills/MCP 开关和专属资源的长期角色 | 需要固定人格、长期记忆或专属权限时 |
| 子代理（Subagent） | 主 Agent 临时派出的隐藏助手，在自己的隐藏会话里执行独立子任务 | 独立、明确、值得并行的子任务；不适合简单的一步操作 |
| 群聊（Group / Room） | 多个 Bot 按顺序对同一条用户消息各回复一次 | 需要多角色讨论、比较观点或分工产出时 |

注意：

- Bot 是用户可见的长期会话；子代理是 Agent 内部临时执行单元，用户通常只看到任务卡和结果。
- 群聊成员不会自动读取彼此的私聊历史；每条消息启动一轮，成员可以读取本轮中前一个成员的回复。
- “指挥官”是一个内置 Bot，负责处理任务、委派给匹配的专职 Bot，并汇总/核查结果。

## 首次使用

首页第一次打开时显示三步：

1. **Add a Provider**：添加模型提供商。
2. **Select Models**：选择一个或多个模型并创建 Model Group。
3. **Create Bots and Groups**：创建 Bot，再开始对话。

完整路径：

1. `设置 → LLM Providers → Manage Providers`，点右上角 `+`。
2. 选择提供商类型，选择 `API Key` 或 `OAuth`，完成密钥填写或登录。
3. 进入 `设置 → LLM Providers → Model Groups`，创建或检查模型组。
4. 在 `Model Groups → Defaults` 指定默认模型组。
5. 返回首页 `Bots & Groups`，点 `+` 创建 Bot，进入对话。

如果已经有 `.minisbak` 备份，可以在首次引导底部选择 `Have a backup? Restore from it`，或使用 `设置 → Storage → Backup & Restore → Restore`。

## 主界面

### Bots & Groups 首页

- 顶部中央是默认的“指挥官”Bot。它负责处理任务、协调其他 Bot，并汇总结果；不能删除。
- `+` 菜单可以创建 Bot 或群聊。群聊至少需要两个 Bot。
- 搜索可以查找 Bot、群聊和消息。
- 长按 Bot/群聊可以打开资料、置顶或取消置顶。
- Bot 行和聊天顶部会显示运行状态：回复中、工具执行、等待子任务、等待定时任务、回复完成、错误、已停止可继续或空闲。历史任务不会在重启后重新加载，没有活动时显示空闲。
- 右上角终端图标菜单提供：`Shell Terminal`、`Rootfs Management`、`Open Browser`、`Browser Settings`。
- 左上角齿轮进入 `Settings`。
- 首次没有模型组时，首页显示设置步骤；创建模型组后自动切换为 Bot 工作区。
- 长按 iPhone/iPad 桌面上的 Minis 图标，还有 `New Chat`、`Chat with Voice`、`Chat with Camera` 三个快捷动作，分别打开新对话、语音输入或相机。

### Bot 资料

从首页长按 Bot、聊天标题或 Bot 头像进入。可查看/修改：

- 名称和头像。
- `指令`：Bot 的角色、语气、规则和工作方式。长指令直接在编辑框内滑动到底；指挥官可点「查看完整内置指令」打开只读页面，返回时会保留未保存的自定义指令。
- `模型组`：这个 Bot 默认使用的模型组。
- `技能`：按 Bot 覆盖全局 Skill 开关。
- `连接器 (MCP)`：按 Bot 覆盖全局 MCP 连接器开关。
- `启用长期记忆`。
- `子代理`：只属于该 Bot 的子代理。
- `环境变量`：只注入该 Bot 对话的变量。
- 会话相关操作：在聊天中搜索、分享、压缩、用量统计、清空聊天、朗读回复、保持屏幕常亮、屏幕保护、增强缓存、快速模式、强制 iCloud 同步/拉取。

Bot 的模型组是首次打开该 Bot 时的默认值；已有会话若在标题栏单独切换过模型，会保留自己的绑定，除非再次切换。

删除 Bot 时，它的专属长期记忆、专属子代理、专属环境变量和记忆共享授权会一并删除；已有对话记录保留。

也可以直接让指挥官创建 Bot；当用户没有指定 Bot 时，指挥官可以用通用子代理处理任务，当任务匹配某个专职 Bot 时则把任务委派给该 Bot。委派任务会显示进度/结果卡，用户可以停止正在运行的任务。

第一次打开某些 Bot 时，聊天顶部可能显示介绍卡和引导问题。你可以多选偏好后点 `记住选择`，选择会写入长期记忆（若该 Bot 开启了记忆）；也可以跳过。引导不会自动执行任务。

委派任务在聊天中显示为 `消息来自 …` 或 `与 … 的会话` 卡片。点开可以查看该任务的独立会话、工具记录和结果；已结束的历史任务只读，不会因为打开而重新执行。

### 群聊

- 群聊成员按 `Speaking Order` 顺序发言。
- 每条用户消息启动一轮，所有成员各回复一次，后面的成员能看到前面的回复。
- Bot 的私聊记录不会自动共享给群聊。
- 可以随时停止本轮；也可在输入区选择只让 `All Members` 或某个成员接收消息。
- 成员回复下方的 `View Tools and Conversation` 可以打开该成员在这一轮里的工具记录和独立会话。
- 群聊有独立长期记忆。

## 聊天页

模型回复使用左侧会话块，右侧保留固定留白；头像标题、正文、思考和工具卡片保持同一宽度，用户消息仍靠右显示。
连续工具卡片之间保持正常间距；模型只输出空格或换行时，不会插入空白行。

### 发送与生成

- 输入框左侧 `+` 可以 `Take Photo`、`Choose Photos & Videos`、`Add File`。
- 支持粘贴图片、视频和文件。
- 附件可以包含图片、音频、视频、PDF 和常见文档；模型是否真正理解取决于它的输入模态。聊天模型没有视觉能力时，配置 `Vision Input` 模型组或换用支持图片输入的模型。
- 麦克风用于语音输入。
- 生成中再次点发送会排队下一条消息；长按停止按钮可切换“停止前确认”。
- 上传区会显示附件；长文本粘贴会折叠为 chip，避免撑爆输入框。
- `Return` 键行为可在 `设置 → Appearance → Return Key` 选择换行或直接发送。

### 标题栏

- 点击 Bot 名称/头像打开 Bot 资料。
- 点击模型名或状态点打开模型选择器，可切换当前会话的模型组/模型。
- 模型名前的状态点提示已登录、未登录或额度偏低。
- 思考强度、快速模式等状态会显示在标题区。

### 右上角 `…` 菜单

常用项包括：

- `Scheduled Tasks`：查看该 Bot 的定时任务。
- `Compact`：压缩上下文为摘要。
- `Clear Chat`：清空当前对话消息。
- `Force iCloud Sync` / `Force Pull`：强制上传或从 iCloud 拉取当前会话。
- `Open Terminal`、`Open Browser`、`Browse Files`。
- `Environment Variables`。
- `Read Replies`：朗读回复。
- `Enhanced Cache`：增强缓存（仅部分模型/路由支持）。
- `Fast Mode`：快速模式（仅部分 OpenAI/Responses/Codex/xAI 模型支持）。
- `Keep Screen On` / `Screen Saver`：只影响当前对话。
- `Token Usage`：当前会话用量。
- `Share`、`Search in Chat`。

### 斜杠命令

在输入框输入 `/`：

- `/clear`：清空当前会话消息。
- `/compact`：压缩会话历史。
- `/memory`：切换所属 Bot/群组的长期记忆，对其全部会话生效；关闭后停止记忆读取、写入和自动注入。
- `/thinking`：切换深度思考。
- 已启用的 Skill 会以 `/skill-name` 出现。
- 已配置的 MCP 服务也会出现在列表中，作为输入提示。

### 消息操作

长按消息可打开上下文菜单：

- 用户消息：`引用`、`Copy`、`Edit`、`Retry`、`Share Chat…`、`Search in Chat`、`Delete From Here`、`Compact Above`。
- 助手回复：`Copy All`、`Copy as Markdown`、`Read from Start`、`Share Chat…`、`Search in Chat`、`Compact Above`。
- 工具卡：复制工具详情；部分工具/任务卡还支持重新运行或停止。

注意：

- `Delete From Here` 会删除该消息及其后的全部消息，不可撤销。
- `Compact Above` 把该消息之前的历史压缩成摘要，保留后续上下文。
- `Share Chat…` 会打开消息选择器，可按回合选择要导出的消息；工具调用是否折叠取决于设置的 `Fold Consecutive Tool Calls`。
- 生成中断后会出现 `Resume`，继续未完成的回合；网络/服务错误可能显示自动重试倒计时。
- 生成中发送的新消息会进入队列，排队消息带虚线边框和取消按钮；停止当前任务后可恢复队列。
- Agent 需要确认或选择时，会显示 `user_ask` 卡片；若开启后台通知，锁屏/通知中心也会提示。该工具只在真实交互聊天中可用，不用于子代理、Shortcuts 或定时任务。
- 记忆写入成功后聊天底部可能出现 `Remembered: …`，可点 `Undo` 撤销这一次写入。

### 文件提及

在输入框输入 `@` 可以从可访问文件中选取并引用。引用的是文件，不会把整份内容永久复制进提示词；模型按需读取。

## 模型、提供商与模型组

### 支持的提供商类型

- OpenAI（Chat Completions 或 Responses API）。
- Anthropic / Claude。
- Google Gemini。
- Antigravity。
- OpenRouter。
- OpenAI Responses API（可作为独立协议实例）。
- xAI / Grok。
- Kimi Code / Coding Plan。
- GitHub Copilot（非官方集成，风险自负）。

同一种类型可以添加多个实例，例如工作账号和个人账号。OpenAI/Anthropic 等协议也可通过自定义 Base URL 接第三方兼容服务。

首次添加提供商前，应用会显示 `AI Data Sharing Notice`：对话内容、附件、工具结果等会直接发送给所选提供商，需遵守该提供商自己的隐私政策。Minis 不自建中转服务。

模型费用由各提供商按自己的计费规则收取。子代理并发、Agent Loop 额外调用、图片生成和 Fallback 重试都会增加实际用量；`Token Usage` 只是本机统计，不等于 provider 账单。

### 添加提供商

`设置 → LLM Providers → Manage Providers → +`

可选认证：

- `API Key`：Key 保存在 iOS Keychain，不会离开设备（发给该提供商时除外）。
- `OAuth`：在应用内登录提供商账号。登录过期后需要在提供商详情页重新登录。

也可以从之前导出的提供商配置文件导入，或通过 `Add Provider → Or Import Provider from File` 快速恢复。

提供商详情里还可以配置：

- `Label`：自定义显示名。
- `Enabled`：临时停用该实例。
- `Custom API Base`：代理、Azure、第三方兼容端点。
- `Auto Append "/v1"`：自动补 `/v1`。如果地址已包含完整版本路径，可关闭。
- `API Format`：Chat Completions 或 Responses API。
- `Azure OpenAI`：使用 `api-key` 头，Base URL 需填完整 Azure 端点（含 `?api-version=...`）。
- `Custom User-Agent`：仅供部分代理/中继端点使用。
- `Response idle timeout`：等待首包和流式片段的最长时间，不是总生成时间上限。
- `Image Endpoint`：图片生成走 `/images/generations` 或 `/chat/completions`，默认 `Auto` 会探测并缓存。
- `Manual Bearer Token`：某些代理使用静态 Token，代替 OAuth。
- `Thinking Rules`：针对模型的思考字段/参数映射。
- 模型列表、刷新模型、添加自定义模型。
- 配额/余额信息与提供商控制台链接。
- 导出提供商配置。

提供商列表中的 `Voice Services` 是语音服务的合并视图：点进去可管理 ASR/TTS 模型和该行是否显示；凭据和端点仍来自原提供商实例。

删除提供商实例会同时删除它的模型条目，并从 Keychain 删除对应凭据；不会删除聊天记录。

### 模型详情

点某个模型可设置：

- `Hidden`：从聊天模型选择器隐藏。
- `Context Window`。
- `Max Output Tokens`。
- `Thinking` 及强制开关。
- 输入模态：Text、Image、PDF、Audio、Video。
- 输出模态：Image、Audio。
- `Quick Test`：按模型能力做一次测试。
- `Reset to Default`：清除自定义覆盖。

如果服务商未返回模型，或模型 ID 不在列表里，可用 `Add Custom Model` 手动添加。

### Model Groups

`设置 → LLM Providers → Model Groups`

模型组把多个模型组合成一个逻辑目标：

- `Fallback`：按列表顺序尝试。第一个失败就尝试下一个。
- `Load Balance`：把不同会话分配到不同模型；单个会话会固定在已分配模型，除非失败。
- `Fallback Strategy: Default`：只在提供商级错误（限流、Key 无效、提供商拒绝）时切换；网络/服务器错误先在当前模型重试。
- `Fallback Strategy: Always`：任何错误都立即切换，不在当前模型重试。
- 拖动成员可调整优先级；Fallback 下第一个模型优先。
- 创建的**第一个**模型组会自动成为 `Default Primary`；后续模型组需要手动指定。
- 删除模型组不会删除模型或提供商，但会清空指向该组的 Default/Voice/Vision 选择。

`Model Groups → Defaults`：

- `Default Primary`：主 Agent 任务使用的模型组。
- `Default Sub`：标题生成等轻量任务使用的模型组。
- `Voice Input`：语音转文字；未指定时使用离线系统语音。
- `Voice Output`：文字转语音；未指定时使用离线系统语音。
- `Vision Input`：当聊天模型不能看图时，用该组模型描述图片；未指定则无视觉能力的模型无法读图。

模型组详情里的 `Session Defaults` 可设置新会话默认思考强度和上下文窗口上限。

`Agent Loop Models` 是另一份列表：只有这里加入的模型/模型组，主 Agent 才能在任务中通过 `minis-model-use` 调用它们，例如生成图片、音频或视频、调用专门模型或做额外摘要。它不是聊天默认模型设置；实际能力取决于模型的输出模态。

### Token Usage

`设置 → LLM Providers → Token Usage`

按提供商和模型统计输入、输出、缓存写入、缓存读取 Token，以及日均和会话均值。配置了模型但未产生用量时不会出现数据。

## 工具、子代理与交互

### Agent Tools

`设置 → Agent Runtime → Agent 工具`

- `Browser Use`：允许模型操作内置浏览器。默认开启；关闭后模型完全看不到该工具。
- `User Interaction`：允许模型在聊天中弹出选择/确认卡片。可设置等待时间（包括无限等待）和后台通知。

关闭工具不是“拒绝一次”，而是从模型工具列表和提示词中移除，因此模型不会知道它存在。

### 子代理

`设置 → Agent Runtime → 子代理`

- 总开关 `Sub Agents` 同时控制通用子代理及其状态查询，也控制指挥官创建 Bot 和委派专职 Bot 的能力。
- 可新建多个子代理，设置名称、描述、指令、模型组、思考强度和适用范围。
- `描述` 是主 Agent 判断何时调用它的主要依据，写成“什么情况下使用”。
- 适用范围可选 `全部 Bot` 或某个 Bot。
- 内置子代理不能删除，是所有未指定名称委派的默认目标。
- `Auto` 会让它按任务选择模型：可复用当前对话模型、Default 组或轻量组。
- 多个子代理可并发运行，会按实际调用量消耗额度。

简单、低风险、可一口气完成的任务通常不应开子代理；独立且可并行的任务才适合。

## 长期记忆

长期记忆只在 Bot 和群聊中可用；普通临时会话没有长期记忆。

入口：

- Bot：`Bot 资料 → 长期记忆`，或开启/关闭 `启用长期记忆`。
- 群聊：群聊资料或聊天右上角菜单 → 记忆。
- 共享：`设置 → Storage → 共享记忆`。
- 记忆总览页可用 [记忆总览](minis://settings/memory) 打开；Bot/群组专属记忆从各自资料页进入。

记忆文档包含：

- 固定记忆：长期保留的规则和偏好。
- 普通记忆：逐条编辑，包括未固定的偏好、事实、约定和经验。
- 事实记忆：决定、交付、验证等事件记录，按记录时间浏览；底层仍为事件类型。
- 共享记忆：可授权给指定 Bot/群组读取。之后新增或改写的内容默认仍为私有，需要重新共享。

记忆页提供“固定记忆、普通记忆、事实记忆”三个标签，查找和共享给我的记忆也按当前分类显示。在哪个标签点击“编辑”，就只编辑该分类。每条记忆都有独立输入框，长内容会撑开输入框，滑动整页即可查看；清空某一条并保存即可删除该条。普通记忆和事实记忆由对话自动生成，编辑页不提供新增入口；固定记忆可在浏览页新增。浏览页的每条自有记忆可左滑删除，固定记忆和普通记忆还可左滑固定或取消固定；删除前会再次确认。保存或删除当前分类不会改动其他分类；若当前分类在编辑期间已有更新，会保留草稿并提示重新打开编辑。复制全文、导出、共享和“清空当前文档”仍作用于完整记忆文档。

编辑期间若其他分类新增了记忆，保存当前分类后仍会保留新记忆的提示和“撤销”入口。

模型通过 `memory_get` 检索、`memory_write` 写入。记忆存储为按 Bot/群组隔离的 SQLite 条目，模型应使用这些工具，不应把 Markdown 文件当作当前记忆库。`/memory` 切换所属 Bot/群组的长期记忆，对其全部会话生效；关闭后停止读取、写入和自动注入，但不会删除已保存的记忆。清空记忆文档不会让旧聊天自动恢复记忆。

## Skills

`设置 → Agent Runtime → Skills`

Skill 是一个带 `SKILL.md` 的目录，可包含脚本、参考资料和素材。被披露的 Skill 元数据会进入上下文；正文在触发或读取时才加载，以节省上下文。超过披露上限的 Skill 需要从 `/var/minis/skills/` 目录中查找。

管理：

- 列表开关控制全局启用。
- 搜索、按名称/修改时间排序。
- `+ → Import Skill` 支持三种来源：
  - `URL`：GitHub 上的 `SKILL.md` 或目录。
  - `Paste`：直接粘贴 `SKILL.md` 内容。
  - `File`：选择 `SKILL.md`、`.skill` 或 `.zip`。
- `Minis Skills` 可浏览官方技能库。
- 从 GitHub 目录导入时，会同时下载同级目录中的脚本、参考资料和素材；只导入单个 `SKILL.md` 时，需要另外补齐这些文件。
- 删除 Skill 会删除本地目录和数据库记录。
- `按 Bot 配置` 或 Bot 资料里的 `技能` 可做每个 Bot 的开关覆盖。
- Agent 也可以在会话中创建 Skill；写入 `/var/minis/skills/<name>/SKILL.md` 后，App 会扫描并登记。

设备路径：`/var/minis/skills/<skill-id>/SKILL.md`。

启用后，技能会出现在 `/` 菜单；也可以直接在对话里描述任务，让模型按描述触发。

内置的 `openminis-ios-user-guide` 就是本手册。

## 连接器与内置能力

### MCP 连接器

`设置 → Agent Runtime → 连接器`

- 支持 HTTP 和 STDIO 两种传输。
- 可手动 `Add Server`，也可 `Import JSON`（Claude Desktop 的 `mcpServers` 格式）。
- 需要 OAuth 的服务可在编辑页完成授权。
- 长按服务器或左滑 `Tools` 可强制重连并刷新工具列表。
- `按 Bot 配置` 或 Bot 资料里的 `连接器 (MCP)` 可做每个 Bot 的开关覆盖。

服务器配置保存在 `/var/minis/mcp-servers/servers.json`，日志在 `/var/minis/mcp-servers/mcp-cli.log`。

### 内置能力

`设置 → Permissions → 连接器与内置能力`，或 `连接器 → Built-in Capabilities`。

支持：

- 日历、提醒事项。
- 照片、相机。
- 音乐、家庭、健康。
- 时钟与闹钟（iOS 26+）。
- 通知、地图、天气、位置、剪贴板。
- 通讯录、蓝牙、NFC、语音识别/朗读、媒体播放。
- Vision：OCR、条码/二维码、图像分类、人脸/矩形检测、图片相似度、截图重叠拼接。

时钟与闹钟通过 AlarmKit 工作（iOS 26+）。Minis 创建的闹钟/计时器需要在 Minis 首页点闹钟图标，或打开 `minis://views/alarm` 管理；不要到 iOS 自带“时钟”App 里找。

这里有**两层权限**：

1. **系统授权**：iOS 是否允许 Minis 访问该数据。由系统弹窗或 iOS 设置控制。
2. **Bot 调用许可**：Agent 是否可以使用对应命令行工具。可选：
   - `允许`：不再逐会话询问。
   - `每个会话首次询问`：第一次调用时弹确认。
   - `禁止`：工具直接返回拒绝。

“允许”不能绕过 iOS 系统授权；健康读取权限在 iOS 中可能显示为隐藏，地图和天气无需独立授权，相机和音乐共用媒体工具许可。

## 环境变量

`设置 → Agent Runtime → 环境变量`

- 可创建全局变量（`全部 Bot`）或 Bot 专属变量。
- 每项包含 Key、Value、备注、启用状态。
- 禁用后不会注入 Shell；删除会立即移除。
- 重名会显示警告；实际使用时注意作用域和注入顺序。
- 在 Shell 中通过 `$KEY` 引用。
- `Privacy Mode` 开启后，环境变量值出现在 shell 输出中时会在送给模型前被掩码；聊天中用户看到的输出不变。
- 变量名称、备注和作用域保存在本机元数据文件；变量值保存在 iOS Keychain，并通过 iCloud Keychain 同步（如同步开启）。
- `minis-config` 不能读取环境变量值；Agent 只能通过 Shell 环境变量名引用，不应把值打印到聊天或日志。

适合放 Skill/CLI 需要的第三方 Token。模型提供商的 API Key 更适合放在提供商详情页，那里由 Keychain 管理。

## 文件与工作区

### `/var/minis/` 目录

| 路径 | 用途 |
|---|---|
| `/var/minis/attachments/` | 对话附件、图片、音频、视频 |
| `/var/minis/workspace/` | 当前任务的工作文件、脚本、数据 |
| `/var/minis/offloads/` | 自动保存的大输出 |
| `/var/minis/browser/` | 浏览器截图与提取结果 |
| `/var/minis/shared/` | 跨会话共享文件、文档、数据集 |
| `/var/minis/skills/` | Skills |
| `/var/minis/memory/` | 仅保留旧文件兼容，不再提供目录入口；当前 Bot/群组的 SQLite 记忆通过资料页和记忆工具管理 |
| `/var/minis/mounts/<name>/` | 用户挂载的外部文件夹 |
| `/var/minis/mcp-servers/` | MCP 配置与日志 |

聊天中链接文件用 `minis://workspace/...`、`minis://attachments/...` 或 `minis://shared/...`。非 ASCII 文件名必须百分号编码。

### Files App 共享

`设置 → Storage → Shared Folders`

在 `Files → On My iPhone → Minis` 中显示：

- `Shared`：对应 `/var/minis/shared`，Files 中可读写。
- `Skills`：对应 `/var/minis/skills`，Files 中只读。
- `Backups`：本机 `.minisbak` 备份文件，Files 中可读写；不挂载到 Agent 的 Linux 环境。

Minis 应用自身可以管理这些目录；Skills 的只读限制只针对 Files App。

`Shared Folders → 备份文件夹` 可查看备份文件名、大小和修改时间，点击文件进入恢复检查，也可通过菜单分享或删除备份。删除前会确认，只删除本机选中的文件，不删除当前聊天和记忆、备份历史或其他目的地上的副本。支持下拉刷新；返回前台、备份完成或调整 Files 可见性后会重新载入列表。备份目录不会挂载到 Agent、加入 `@` 文件候选或作为共享文件再次备份。

旧 `memory` 文件保留在磁盘上，但不再显示在共享文件夹、Files App 根目录和聊天 `@` 文件候选中。真正的“共享记忆”仍从 `设置 → Storage → 共享记忆` 管理。

`Shared Folders` 中可以切换目录是否在 Files 中显示；隐藏后仍可在应用内管理。Shared 和 Skills 的 Agent 访问也不受影响。

### 挂载外部文件夹

`设置 → Storage → Mount External Folders`

- 从 Files 选择一个文件夹，挂载到 `/var/minis/mounts/<name>`。
- 最多同时挂载 10 个。
- 可设置是否允许写入。
- `Read-only` 表示系统层面不可写；`Locked` 表示系统可写但用户关闭了允许写入。
- 支持 iCloud Drive、其他 App 的文件夹、Files 中已连接的 SMB/WebDAV 等。
- 外部文件夹离线或被系统收回权限时，Shell 读写会失败。

### Terminal、文件浏览与 Rootfs

- `Shell Terminal`：进入交互式 Alpine Shell；适合 `ssh`、需要 stdin 的 TUI、密码输入等场景。
- `Browse Files`：在 App 内浏览 rootfs 和工作区，可导入、排序、查看源码/渲染结果、预览、复制、移动、导出、删除。
- Shell 基于 Alpine Linux；可用 `apk add`、`pip`、`git` 等工具。安装的包和 rootfs 内文件会保留，直到重置 rootfs。
- `Rootfs Management`：
  - `Install Rootfs`：安装 Alpine 文件系统。
  - `Reset Rootfs`：删除整个 rootfs，所有 rootfs 内数据丢失。
  - `Reset & Backup User Data`：先备份 `/root`，再重置。
  - `Restore User Data`：恢复用户数据备份。
  - `DNS Mode`：跟随系统或自定义 DNS。
  - `Mirrors`：软件源镜像检测与切换。
  - `AOJIT`：AOT 编译缓存设置。

Rootfs 是底层 Linux 环境，不等同于用户备份。重要聊天、Bot、模型配置和共享文件应使用 `Backup & Restore`。

### HTML 网页应用与主屏幕

Agent 可以在 `/var/minis/workspace/` 等位置生成多文件 HTML 应用并在内置浏览器预览。预览页、文件浏览器或聊天中的 HTML 文件支持 `Add to Home Screen`：

- 输入标题、选择图标分类，然后按提示在 Safari 中 `分享 → 添加到主屏幕`。
- 只支持会话文件夹、`/var/minis/shared` 或已挂载外部文件夹中的 HTML 文件。
- 生成的快捷方式会重新打开对应 HTML；其可用性取决于当前构建是否配置了 WebApp launcher host。

## 浏览器

### 手动浏览

首页终端菜单 → `Open Browser`。支持：

- 多标签页、地址栏搜索/输入网址。
- 前进/后退/刷新。
- 书签、历史（默认保留 7 天）、下载。
- 浏览器标签页按会话隔离；一个 Bot/会话的浏览器状态不会自动出现在另一个会话。
- 页面长按、文本选择、分享。
- `Browser Settings`：
  - User Agent：移动 Safari、桌面 Safari、自定义。
  - Web Viewport：自定义宽高或使用 UA 默认值。
  - Cookies 与按域名查看/清理网站数据。
  - 书签管理、密码管理器。
- 下载会显示进度，可从浏览器或聊天里的下载按钮查看；完成后可 `Show in Files`。
- Agent 正在操作浏览器时，页面会显示自动化边框和 `Takeover`。点击后由用户接管当前标签页，Agent 暂停；点 `Return to Minis` 把页面交还给 Agent。接管期间按下的页面操作不会排队执行。
- 清理 Cookies 会让 Minis 浏览器中所有网站退出登录；密码管理器中的密码不会因此删除。

### Browser Use

Agent 通过 `browser_use` 操作同一套内置浏览器，可导航、点击、输入、滚动、截图、读取文本等。默认从桌面 Safari UA 开始。

开关：`设置 → Agent Runtime → Agent 工具 → Browser Use`。

### 密码

`Browser Settings → 密码管理器` 或浏览器工具栏钥匙图标。

- 密码保存在本机 Keychain。换机时可以在加密的 `.minisbak` 中单独勾选「浏览器密码」。
- 自动填充只匹配相同 HTTPS 网站，不会自动提交登录。
- 可以导入已有的密码数据文件，导入不会修改源文件。
- Agent 可通过 `browser_use(action: secure_input)` 请求密码、PIN 或验证码。主聊天中会出现安全输入交互卡，直接在卡片填写，不要把敏感值作为聊天消息发送；模型只收到请求引用和状态。
- 新的主聊天安全输入请求需要当前会话已在前台打开，并由交互式对话发起；后台、定时任务或未打开的会话会收到明确提示，需打开会话后让 Bot 重新请求，不会占用安全输入锁。
- 需要手动点网页登录时，点“打开网页继续登录”，之后可“返回聊天”。切后台只遮蔽内容，不取消请求；回到应用可继续。请求和输入仅保留在运行时内存中，应用被系统终止或主动停止任务后需重新请求。
- 临时输入不写入聊天历史、工具结果或备份。只有密码可在确认登录成功后选择保存到本机 Keychain；已保存的密码可显式加入加密备份。PIN、验证码不保存。完成或取消会清空临时值和网页输入框并刷新网页，保留登录状态。

## 后台、定时任务与快捷指令

### 后台执行

`设置 → Permissions → Background`

- `Enhanced Background Execution`：退到后台后继续执行 Agent 任务，并通过 Live Activity 显示进度；同时启用 Background Speak。
- `Prefer Continued Background Processing (iOS 26+)`：使用系统持续处理能力。
- `Live Activity`：锁屏/灵动岛显示任务进度。
- `Task Notifications`：任务开始/完成时发本地通知，包括 Shortcuts 触发的任务。
- `Task Status Privacy`：隐藏会话标题、工具状态和回复内容，只显示完成数和耗时。
- `Background Speak`：后台继续朗读和播放音频。
- `Rate/Pitch/Volume`、中英文语音：调节朗读。
- 需要更多系统语音时，在 iOS `设置 → 辅助功能 → 朗读内容 → 声音` 下载；Minis 的语音选择器会读取系统可用声音。
- `Location Tracking`：只使用低精度位置作为后台心跳，不记录精确轨迹。
- `Status` 显示当前后台存活级别。

没有后台保活时，iOS 通常会在约 30 秒后挂起应用。需要长时间运行时，保持应用前台、开启屏幕常亮，或配置后台能力。

### 定时任务

从 Bot 资料或聊天菜单进入 `Scheduled Tasks`。

定时任务由 Agent 通过 `minis-scheduled` 创建，可执行一次、按间隔循环、按每天/每周/每月/每年日历重复，或在前置任务完成后触发。结果可以回到当前聊天、新建聊天，或交给隐藏子代理。管理页可查看下次运行时间、运行历史、启用/暂停、编辑、删除和 `Run Now`。

限制：

- 定时器只在 Minis 进程存活时可靠运行。
- 到点时应用已被系统杀死，任务不保证执行；会注册提醒通知作为兜底。
- 必须保证“应用被杀也执行”时，应使用 Apple Shortcuts 自动化调用 Minis。

### Shortcuts / Siri

Minis 提供：

- `Ask Minis`：打开应用提问/新建会话。
- `Quick Task`：运行预定义任务。
- `Send Prompt`：发送提示并在后台运行。
- `Get Session Status`：查询会话是否仍在运行。
- `List Sessions`：列出会话及 ID。
- `Follow Up`：继续已有会话。
- `Open Session`：打开会话。
- `Retry Run`：从某条用户消息重跑（可在 Shortcuts 的全部操作中找到）。
- `Save Env Var`：把 Shortcuts 文本保存为 `MINIS_SHORTCUT_OPT_` 前缀的环境变量。

Siri 可以说“问问 Minis”等短语；具体提示词会在参数追问中收集。

### 分享扩展

在 Safari、照片、Files 或其他 App 中分享到 Minis，会把文本、链接、图片或文件放进当前/新建对话的输入区，可按需选择 `Move to…`。

## 外观与交互设置

`设置 → Appearance`

- `Theme`：跟随系统、浅色、深色。
- `Launch Session`：启动时显示 `Bots & Groups`，或恢复上次会话。
- `Return Key`：回车换行或发送。
- `Keep Screen Awake`：任务运行时防止自动锁屏；可设置屏保等待时间。
- `Auto-Focus Input After Reply`：回复结束后自动弹出键盘。
- `Confirm Before Stopping`：停止任务前确认。
- `Tool Status Bar`：显示工具执行预览。
- `Deep Thinking → Expand Thinking While Streaming`：流式思考时自动展开。
- `Tool Calls → Fold Consecutive Tool Calls`：折叠连续工具调用。
- `Font Size`：分别调整输入框、消息正文、应用基础字号。
- `App Icon`：自动、浅色、深色、旧版图标。
- `Language`：应用内语言。支持简体中文、繁体中文、英语、日语、韩语、西班牙语、法语、德语、俄语、印尼语、马来语、菲律宾语、泰语、土耳其语、波兰语、罗马尼亚语、巴西葡萄牙语、克罗地亚语等。

## 存储、同步与备份

### Storage

`设置 → Storage → Storage`

- `Total` 是 App 容器总大小，应与 iOS 设置中的 Minis 占用接近。
- 分类包括：Shell Container、聊天数据库、Logs & Caches、Temporary Files、Orphaned Session Files、Stale Shell Leftovers、Skills/Memory/Shared Files、Other。
- `Clear Logs & Caches`：删除全部日志（包括崩溃报告）、网页缓存、模型列表缓存等；不影响聊天、文件和设置。
- `Clean Up Orphaned Session Files`：删除没有会话记录的遗留目录；不影响现有聊天、Skill、记忆和共享文件。
- 会话列表可 `Clear Files`（只删该会话生成的文件，保留对话）或 `Delete`（删除会话及其文件）。

### iCloud Sync

`设置 → Storage → iCloud Sync`

- 开关修改后**下次启动 App 生效**。
- 需登录同一 iCloud 账号。
- 可选择本机上传：`Chat Sessions`、`Session Files`、`Skills`、`Providers`、`Environments`。
- Session Files 可设置单文件大小上限：256 KB、1 MB、4 MB、16 MB、64 MB。
- 可设置设备名，查看其他设备及最后活跃时间。
- API Key 和密钥通过 iCloud Keychain 安全同步。
- 单个会话菜单里的 `Force iCloud Sync` / `Force Pull` 用于强制修复。

iCloud Sync 是持续的多设备同步，不是备份快照；它也不快照整个 Alpine rootfs。

### Backup & Restore

`设置 → Storage → Backup & Restore`

**Backup**

- 包格式 `.minisbak`。
- 可选择类别：Chats、Shared Files、Skills、Agents and Memory、Providers、MCP Servers、Environment Variables、浏览器书签、浏览器密码和浏览器 Cookie；语音纠正数据保留独立导出支持。
- 本机智能体的历史会话和消息需要勾选 Chats 才会写入。恢复前请确认消息数；如果以前的备份漏掉了仍在原设备上的聊天，需要在原设备重新备份。
- 个别会话的 ID 缺失或无效，或消息无法解析时，备份保留其余可读记录，并在备份结果、记录和恢复预览中分别提示遗漏的数量。聊天数据库读取失败时仍会停止备份。
- 可设置单文件大小上限；超过上限的文件只记录，不打包。
- 可加密整包。口令无法找回；没有口令无法恢复。
- 浏览器书签可单独备份。浏览器密码和浏览器 Cookie 默认都不选，选中任一项后须设置加密口令，并通过 Face ID 或设备密码验证。「浏览器密码」包含本机保存的账号和从 `shared/password_manager/vault.json` 直接读取的共享账号；「共享文件」不再重复打包这个密码库。
- 未加密备份包含 API Key、OAuth Token 和环境变量值，任何人拿到文件都能读取。
- 点击 `Start Backup` 会自动创建 `Minis ▸ Backups` 文件夹并保存 `.minisbak` 文件，无需选择备份目的地。
- 备份文件会保留在本机；需要换机或另存时，可用 `Share` 或 `Save to Files` 复制到其他设备、iCloud Drive 或外部存储。
- 备份历史保留近一个月。
- 加密备份在开始加密前可续备；加密开始后中断，下次会重新备份。
- 升级后若旧暂存不兼容，开始新备份前会清理这份暂存；已保存的备份包不受影响。

**Restore**

- 默认列出 `Minis ▸ Backups` 中的备份，最新备份排在前面，点选要恢复的文件即可进入恢复流程。
- 其他设备上的备份可通过 `Choose from Files` 选择 `.minisbak` 文件导入。
- 恢复是**合并**，不会先删除现有数据。
- 按稳定 ID 匹配；已有较新内容会保留。
- 可勾选要恢复的类别；加密备份需要口令。
- 书签按 ID 合并；浏览器密码按 HTTPS 站点和账号合并，已有记录保留。新增共享账号写回共享密码库，解锁密码管理器后继续同步；其他新增账号写入 Keychain。外部密码文件的设备授权不迁移。
- 能确认聊天确实为空的旧备份可以恢复；如果清单显示有聊天数据却缺少对应内容，恢复会报错。
- 旧备份若在「共享文件」里携带密码库，仍会尝试按账号合并。密码库解析或合并失败时会单独提示，其他已恢复的共享文件仍会保留。
- 浏览器 Cookie 单独恢复，保留目标机 WebKit 和本地 Cookie 恢复缓存中已有的同域名、路径、名称记录，并跳过过期或重复项。分区 Cookie 不迁移，避免丢失网站隔离信息。已失效或与原设备绑定的会话仍须重新登录；浏览历史和其他网页存储不随 Cookie 迁移。
- 恢复后可能仍需重新登录已过期的 OAuth；未包含密钥的备份需要重新填 Key。

**iCloud Sync 与 Backup & Restore 的区别**

| 能力 | 适合 | 关键限制 |
|---|---|---|
| iCloud Sync | 多台设备持续同步聊天、会话文件、Skills、Providers、环境变量 | 需要同一 iCloud 账号；不是时间点快照；不包含完整 rootfs |
| Backup & Restore | 迁移设备、保留可恢复的历史快照 | 默认保存到本机 `Minis ▸ Backups`；可分享或另存副本；恢复是合并；文件大小上限和加密口令需自行确认 |

两者都不备份完整根文件系统和已安装的 Alpine 软件包。重要文件应放在 `/var/minis/shared` 或会话文件夹，并把对应类别加入备份。外部挂载目录的内容由原存储负责备份，Minis 不会复制它。

## 安全、权限与日志

### 应用锁

`设置 → Permissions → Face ID Protection`（设备支持时显示实际生物识别名称）

- `Lock App`：每次打开 Minis 需要 Face ID/Touch ID 或设备密码。
- `App Lock Timeout`：离开后多久重新上锁。
- `Lock Sessions`：长按会话锁定单个会话。
- `Session Lock Timeout`：会话离开多久后重新上锁。
- `Remove All Locks`：验证生物识别后清除全部会话锁。

### minis-config

`设置 → Permissions → Configuration Tool → Allow minis-config`

允许 Agent 通过 `minis-config` 读取/修改设置。每次写入都会弹出确认，并记录到 `Logs → Config Changes`，可回退最近 1000 条。关闭后 Agent 会收到 `permission_denied`，应改用深链接引导用户。

不能通过此工具读取 API Key/OAuth Token，也不能修改权限或环境变量值。

### 语音纠正数据

`设置 → Permissions → Voice Correction Learning`

- 默认关闭。
- 开启后，用户对语音转写的手动修正、接受/拒绝的 AI 修正、常用词会存入本机数据库，用于后续纠正。
- 不上传。
- `Clear Collected Data` 可清除。

### Logs

`设置 → Logs`

- `Enable Logging`：是否记录控制台输出到每日日志。
- `Detail Level`：`Info`（常规）或 `Verbose`（高频文件系统/渲染/上下文追踪）。Verbose 增长很快，排障后应切回 Info。
- `Log Files` / `Crash Reports`：查看、分享、删除。
- `Crash Diagnostics`：面包屑、崩溃上下文、MetricKit 报告，可导出脱敏 ZIP。
- `Config Changes`：`minis-config` 修改审计与回退。
- 日志超过 15 天自动清理。
- 分享日志或崩溃报告前先检查是否含敏感内容。

### About

`设置 → About → About Minis`

显示版本、构建号、构建时间、运行环境（真机/iOS App on Mac/Catalyst）、GitHub、问题反馈和隐私政策。提交问题时应附上这些信息。

## 常见问题定位

| 现象 | 优先检查 |
|---|---|
| 没有可聊的模型 | `LLM Providers → Manage Providers` 是否添加上；提供商是否启用；模型是否刷新/手动添加 |
| 模型报 401/未登录 | 提供商详情页重新填 Key 或重新 OAuth 登录 |
| 频繁限流 | 给模型组添加备用模型，使用 Fallback；检查提供商额度 |
| 模型看不到工具 | `Agent Tools` 的 Browser Use、`子代理` 总开关是否关闭；关闭会从工具列表移除 |
| 原生能力被拒绝 | `Permissions → 连接器与内置能力`：先看系统授权，再看 Bot 调用许可；`禁止` 会直接拒绝 |
| 调用时弹出权限确认 | 工具许可为“每个会话首次询问”；改为“允许”可停止逐会话确认 |
| 普通会话没有长期记忆 | 长期记忆只支持 Bot/群聊；改用 Bot 或群聊，并开启记忆 |
| Skill 没出现在 `/` 菜单 | 全局或该 Bot 是否启用；文件是否是合法 `SKILL.md`；重新导入/刷新 |
| MCP 没有工具 | 检查服务器状态、OAuth、网络；长按服务器 `Refresh Tools` |
| 图片/PDF 无法识别 | 当前模型是否支持该输入模态；没有视觉能力时配置 `Vision Input` 模型组 |
| 语音输入/朗读不可用 | `Model Groups → Voice Input/Voice Output`；系统麦克风/语音权限；Background Speak 设置 |
| 后台任务很快停止 | iOS 约 30 秒挂起；开启 Enhanced Background、Live Activity、后台音频或位置心跳；必要时保持前台 |
| 定时任务没执行 | 定时器只在 Minis 进程存活时可靠；需要绝对执行时改用 Shortcuts 自动化 |
| 生成中断后继续 | 点消息上的 `Resume`；若看不到 Resume，重新发送一条消息并说明从哪一步继续 |
| 排队消息没有发送 | 等待当前回合结束；检查排队消息右侧取消按钮是否被误触；停止当前任务后队列会恢复 |
| iCloud 不同步 | 两端同一账号且已开启；开关需下次启动生效；在会话菜单尝试 Force Sync/Pull |
| 恢复后缺少密钥 | 备份未包含凭据；重新填 API Key 或重新 OAuth |
| 恢复页没有备份 | 先在 Backup 页创建备份；其他设备上的文件可通过 `Choose from Files` 导入；也可下拉刷新备份列表 |
| 无法把 HTML 添加到主屏幕 | 文件必须在会话、共享目录或已挂载目录；当前构建需配置 WebApp launcher host；在 Safari 中手动“添加到主屏幕” |
| 闹钟在系统时钟 App 里找不到 | Minis alarm 使用 AlarmKit，需在 Minis 首页闹钟图标或 `minis://views/alarm` 查看 |
| 存储占用很大 | `Storage` 查看 Shell、日志、临时文件、孤儿会话；清理前确认影响 |
| Rootfs 损坏/命令异常 | `Rootfs Management` 先 `Reset & Backup User Data`；重要数据先做 `.minisbak` 备份 |
| 网页登录状态丢失 | `Browser Settings → Cookies & Data` 是否被清理；密码管理器/网站 Cookie |
| 应用启动要求生物识别 | 已启用 `Lock App`；在 Face ID Protection 中关闭或调整超时 |

## 设置路径速查

| 要做什么 | 路径 |
|---|---|
| 添加/编辑模型提供商 | `设置 → LLM Providers → Manage Providers` |
| 配模型回退、默认模型、语音/视觉模型 | `设置 → LLM Providers → Model Groups` |
| 查看 Token 用量 | `设置 → LLM Providers → Token Usage` |
| 开关浏览器工具、交互卡片 | `设置 → Agent Runtime → Agent 工具` |
| 管理子代理 | `设置 → Agent Runtime → 子代理` |
| 管理环境变量 | `设置 → Agent Runtime → 环境变量` |
| 导入/开关 Skills | `设置 → Agent Runtime → Skills` |
| 管理 MCP | `设置 → Agent Runtime → 连接器` |
| 管理共享记忆 | `设置 → Storage → 共享记忆` |
| 管理本机备份文件 | `设置 → Storage → Shared Folders → 备份文件夹` |
| 清理存储 | `设置 → Storage → Storage` |
| Files 共享目录 | `设置 → Storage → Shared Folders` |
| 挂载外部文件夹 | `设置 → Storage → Mount External Folders` |
| iCloud 同步 | `设置 → Storage → iCloud Sync` |
| 备份/恢复 | `设置 → Storage → Backup & Restore` |
| 系统/工具权限 | `设置 → Permissions → Permissions` |
| 后台执行 | `设置 → Permissions → Background` |
| 应用/会话锁 | `设置 → Permissions → Face ID Protection` |
| 日志与配置审计 | `设置 → Logs` |
| 主题、语言、字号 | `设置 → Appearance` |
| 版本与反馈 | `设置 → About → About Minis` |
| 终端 | 首页右上角终端菜单 → `Shell Terminal` |
| 浏览器 | 首页右上角终端菜单 → `Open Browser` |
| Rootfs 管理 | 首页右上角终端菜单 → `Rootfs Management` |

## 可直接给用户的深链接

- 提供商：`minis://settings/providers`
- 模型组：`minis://settings/model-groups`
- 用量：`minis://settings/usage`
- Agent 工具：`minis://settings/tools`
- Skills：`minis://settings/skills`
- 记忆总览：`minis://settings/memory`
- 存储：`minis://settings/storage`
- Files 共享目录：`minis://settings/shared-folders`
- 外部挂载：`minis://settings/mount-external`
- iCloud 同步（先打开存储页）：`minis://settings/storage`
- 日志：`minis://settings/logs`
- 配置变更审计：`minis://settings/logs?tab=config-audit`
- 外观：`minis://settings/appearance`
- 后台：`minis://settings/background`
- 权限：`minis://settings/permissions`
- 环境变量：`minis://settings/environments`
- MCP 连接器：`minis://settings/mcp-servers`
- 单个 MCP 服务器（打开编辑/授权页）：`minis://settings/mcp-servers/<server-id>`
- 关于：`minis://settings/about`
- Rootfs：`minis://settings/rootfs`
- 闹钟列表：`minis://views/alarm`
- 终端：`minis://open_terminal`
- 终端并预填命令：`minis://open_terminal?init_command=<百分号编码后的命令>`

链接应写成 Markdown，例如：`[打开模型组](minis://settings/model-groups)`。

`minis://settings/...` 是 App 深链接，不是网页；不要用 `browser_use` 打开它，直接作为 Markdown 链接返回给用户。

## 回答模板

当用户问“X 在哪/怎么用”时，按以下顺序回答：

1. 一句话说明 X 是什么、解决什么问题。
2. 给出完整路径（中文界面 + 必要时括注英文标签）。
3. 给出可点击深链接。
4. 说明关键选项和副作用，尤其是删除、重置、覆盖、同步、权限和费用。
5. 如果涉及频繁操作或排障，给一个最短操作序列。
6. 如果问题依赖用户当前配置，明确说“这取决于你的当前设置”，再给只读查询方式或打开页面的建议，不要假装知道。

示例：

> 想把默认聊天模型换成另一个模型组：前往 **设置 → LLM Providers → Model Groups → Defaults → Default Primary**。可选 [打开模型组](minis://settings/model-groups)。
> `Default Primary` 影响主 Agent 任务；`Default Sub` 只影响标题生成等轻量任务。已有会话如果单独绑定过模型组，不会被自动改掉。
