# iOS 使用手册

面向用户和 Agent 的完整 iOS 使用手册位于：

- [openminis-ios-user-guide/references/ios-user-manual.md](../src/ios/Resources/BundledSkills/openminis-ios-user-guide/references/ios-user-manual.md)

该目录会作为内置 Skill `openminis-ios-user-guide` 随 App 安装：

- Skill 入口：`SKILL.md`
- App 内路径：`/var/minis/skills/openminis-ios-user-guide/references/ios-user-manual.md`
- 基座提示词要求模型在回答 Minis/OpenMinis 应用自身问题前先读取该手册。

修改手册时直接编辑上述 Markdown 文件；`SkillStore` 会在启动时同步内置 Skill 及其资源文件。

只修改 `references/ios-user-manual.md` 时无需升级版本；修改 `SKILL.md` 的元数据或触发规则时，需要同时提高 frontmatter 中的 `version`，否则已有安装不会覆盖入口文件。
