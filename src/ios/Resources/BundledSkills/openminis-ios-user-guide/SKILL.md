---
name: openminis-ios-user-guide
version: 1.0.2
description: Minis/OpenMinis iOS 应用自身的使用手册。用户询问它能做什么、某项功能怎么用、设置在哪里、某个选项是什么意思，或需要配置、数据位置、同步备份、权限、故障排查时，先查本手册再回答。Use for app-specific help, settings navigation, setup and troubleshooting.
---

# OpenMinis iOS 使用手册入口

完整手册在同目录的 `references/ios-user-manual.md`。

## 必须先读手册的问题

只要用户在问 Minis/OpenMinis **这个 App 自身**，先读完整手册再回答，例如：

- 这个 App 能做什么、适合做什么。
- 某个功能怎么用，某个按钮/菜单在哪里。
- 某个设置是什么意思，会影响哪些数据。
- 模型、Bot、群聊、记忆、Skills、MCP、环境变量怎么配置。
- 文件放在哪，如何与 Files、Obsidian、外部文件夹配合。
- iCloud 同步、备份恢复、共享文件夹 / 备份文件夹、存储清理、权限、Face ID、日志。
- 后台任务、定时任务、Shortcuts、分享扩展、浏览器、安全输入、终端、Rootfs。
- 某个功能失效时如何定位。

通用 AI、某个模型商、iOS 系统本身的问题不需要读本手册，除非问题涉及 Minis 如何接入它们。

## 读取方式

1. 读取 `references/ios-user-manual.md`。
2. 按 Markdown 标题检索相关段落；问题跨多个主题时读对应小节，不必逐字复述全文。
3. 回答以手册为准。

## 回答规则

- 给出完整设置路径，例如 `设置 → LLM Providers → Model Groups → Defaults`。
- 能跳转时附 Markdown 深链接，例如 `[打开模型组](minis://settings/model-groups)`。
- 说明选项作用、影响范围、数据后果；涉及删除、重置、同步、权限、费用时明确提醒。
- 手册不代表用户当前的具体配置；涉及“我现在用的是什么”时，不要猜。权限允许时可只读查询 `minis-config`，否则引导用户打开对应页面核对。
- 手册没覆盖的内容，明确说无法确认，不要编造菜单或设置名。
- 不要回显 API Key、OAuth Token、环境变量值、Cookie、密码或备份口令。

## 手册目录

- 适合做什么
- 概念区别：Provider、Model、Model Group、Bot、子代理、群聊
- 首次使用与主界面
- 聊天页、消息操作、斜杠命令、文件提及、中断/重试/队列
- 模型、提供商、Model Groups、Token Usage
- 工具、子代理、固定记忆 / 普通记忆 / 事实记忆的逐条编辑与左滑操作
- Skills、MCP 连接器、内置能力
- 环境变量
- `/var/minis/` 文件、Files 共享、外部挂载、终端、Rootfs
- 浏览器、密码管理器、Browser Use、聊天内安全输入卡（密码、PIN、验证码）
- HTML 网页应用与“添加到主屏幕”
- 后台执行、定时任务、Shortcuts、分享扩展
- 外观与交互设置
- 存储、iCloud 同步、本机备份恢复与 Shared Folders 备份管理
- 安全、权限、日志、关于
- 常见问题定位
- 设置路径速查与深链接
