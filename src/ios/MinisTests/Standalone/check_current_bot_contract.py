"""Source guards only; use the Swift regression harnesses for runtime behavior."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


store = read("Views/ContentView/Bots/BotWorkspaceStore.swift")
assert "static let shared = BotWorkspaceStore()" in store
assert 'static let commanderID = "builtin-commander"' in store
assert "seedCommander" in store and "guard id != BotProfile.commanderID" in store
assert "func capabilitySessionID" in store and "func inheritOwner" in store
commander_policy = store.split("var commanderInstructions: String {", 1)[1].split(
    "/// Ephemeral UI state", 1
)[0]
assert "data.bots" not in commander_policy, "Commander built-in rules must not grow with the Bot roster"
assert "bot_task" in commander_policy and "action=list" in commander_policy
runtime = read("Views/ContentView/Bots/BotTeamRuntime.swift")
bot_task_schema = runtime.split("static var botTaskTool:", 1)[1].split("func executeBotCreate", 1)[0]
assert '"list"' in bot_task_schema, "Bot discovery must be exposed in the tool schema"
bot_list = runtime.split('case "list":', 1)[1].split('case "delegate":', 1)[0]
assert ".instructions" not in bot_list, "Discovery must not return specialist working instructions"
unread = store.split("func updateConversation", 1)[1].split("func latestDelegation", 1)[0]
assert "return next == data || persist(next)" not in unread
assert "writeQueue.async" in unread
merge = store.split("private static func mergeConversationState", 1)[1]
assert "if FileManager.default.fileExists(atPath: fileURL.path)" in merge
assert "workspace = fallback" in merge
assert "BotDataSnapshotLock.lock.lock()" in merge
assert "BotDataSnapshotLock.lock.unlock()" in merge
schema = read("Agent/Chat/AIChatViewModel+ToolDefinitions.swift")
assert '"bot_id"' not in schema
assert '"agent": AgentToolParam' in schema
dispatcher = read("Agent/Chat/AIChatViewModel+ConcurrentTools.swift")
subagent = dispatcher.split("case SubAgentDefinition.toolName:", 1)[1]
assert subagent.index("Set(toolArgs.keys).isSubset(of: supportedKeys)") < subagent.index('case "resume":')
assert '"invalid_arguments"' in subagent
helper = read("Agent/Jobs/HelperRunner.swift")
assert helper.index("Set(args.keys).isSubset(of: allowed)") < helper.index("registry.enqueueDelegation")
for retained in ("executeResumeAgents", "executeAgentStatus", "helperWrapUpToolPatience",
                 "markRunning", "delegationResultsAreMuted", "SubAgentRoster.resolve"):
    assert retained in helper, retained
archive = read("Views/ContentView/Bots/BotWorkspaceArchive.swift")
assert "var version = 3" in archive and "require(version == 3" in archive
assert "interrupted = false" in archive
assert "AgentJobRegistry" not in archive and "submitProgrammaticPrompt" not in archive
assert 'static let current = "minisbak/4"' in read("Agent/Backup/BackupFormat.swift")
importer = read("Agent/Backup/BackupImporter.swift")
inspect = importer.split("func inspect(packageURL:", 1)[1].split("// MARK:", 1)[0]
assert "try checkFormat(manifest)" in inspect
exporter = read("Agent/Backup/BackupExporter.swift")
chat_export = exporter.split("private func exportChats(", 1)[1].split("private struct SessionRecord", 1)[0]
# Legacy cloud deletion markers are ignored by the live session list. A visible
# local conversation carrying one must not be dropped from a backup.
assert "tombstonedSessionIds" not in chat_export, "Chat backup filters sessions by a retired sync deletion marker"
assert "BackupCrypto.sealBrowserPayload(" in exporter and "openBrowserPayload(" in importer
assert "CookieBackupStore.shared.cookiesForMigration()" in exporter
assert "CookieBackupStore.shared.restoreMigratedCookies(" in read("Agent/Backup/BackupImporter+Categories.swift")
assert "sessions.close(writingEmptyShard: true)" in chat_export
assert "messages.close(writingEmptyShard: true)" in chat_export
assert "try await store.sessionIdsForBackup()" in chat_export
assert "try await store.loadMessagesForBackup(" in chat_export
assert exporter.index("try BackupExportJournal.disallowResume()") < exporter.index("try encryptStagedMembers(in:")
assert "allowsMissingChatStream" in read("Agent/Backup/BackupImporter+Categories.swift")
assert "loadBackup()" in read("Agent/BrowserUse/CookieBackupStore.swift").split("func restoreMigratedCookies", 1)[1].split("/// Local backup directory", 1)[0]
debug = read("Debug/DebugRPCProviderChat.swift")
assert 'params["botId"] as? String' in debug and "workspace.ensureCommander" not in debug
print("PASS: source contracts for protected commander initialization, generic delegation, current backup versions and no restore replay")
print("NOT RUN: Swift runtime, Xcode build, simulator or device acceptance")
