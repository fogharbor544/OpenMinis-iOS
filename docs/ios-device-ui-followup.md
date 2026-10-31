# iOS 真机 UI 反馈修复（2026-10-31）

## 修改

- 设置页 Agent Runtime 使用系统正文，与相邻设置项一致的 21pt 圆形图标和 9pt 字形；取消 Label 额外的 44pt 高度，让系统列表决定行高。
- 主聊天不再将消息视口延伸到导航栏下。Bot 运行状态、定时任务、搜索、错误和临时提示共用一个顶部 safe-area inset；删除延迟测量和额外列表补偿。消息绘制限制在视口内。
- 内置能力名称、图标和实时系统授权状态整合进卡片。下方使用完整内缩分割线和“Bot 调用”菜单。保留原有系统授权、工具许可和返回应用后刷新的行为。

## 已执行验证

- `python src/ios/MinisTests/Standalone/check_chat_settings_contracts.py`：7 项源码约束通过，包含顶部统一占位的回归检查。
- 8 个修改过的 Swift 文件相对 HEAD 没有新增 tree-sitter 语法错误；Python AST 检查通过。报告保存在 `build/validation/device-ui-followup/syntax.json`。
- `git diff --check` 通过。

以上属于本地静态检查，不代表 Swift 编译、Swift 测试执行或真机显示验证。现有 `TopBannersTests.swift`、`ScheduledBannerTests.swift` 的旧布局断言已更新，尚未在 Swift 环境执行。

## 待真机验收

1. 在 iOS 26 的 Bot 会话发送短消息，检查初次进入、正在回复、回复结束和停止时，第一条消息能完整滚动到导航栏及状态条下方。
2. 在长会话上滑阅读，再打开搜索或显示定时任务/错误条；检查内容边界、跳转上一轮、回到底部及键盘弹出/收起。
3. 对比设置页运行时与外观、存储等相邻项目的字号、图标、行高。
4. 检查内置能力卡片的浅色/深色模式、375pt 窄屏、横屏及最大 Dynamic Type，确认文字可换行、菜单可操作、分割线完整。
5. 修改工具调用许可，触发系统授权并从系统设置返回；确认两种权限仍独立生效、状态刷新。

当前 Windows 环境没有 Swift/Xcode 和 iOS 真机运行环境；本次尚未产生新安装包。
