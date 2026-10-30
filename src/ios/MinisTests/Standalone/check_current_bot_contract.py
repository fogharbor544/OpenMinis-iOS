"""Source guards only; use the Swift regression harnesses for runtime behavior."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


for path in ROOT.rglob("*.swift"):
    if "MinisTests" in path.parts or "MinisUITests" in path.parts:
        continue
    source = path.read_text(encoding="utf-8")
    for retired in ("ensureCommander", "defaultCommander", "isCommander", "commanderID",
                    "registerDelegation", "delegationDefinition", 'args["bot_id"]'):
        assert retired not in source, (path, retired)

store = read("Views/ContentView/Bots/BotWorkspaceStore.swift")
assert "static let shared = BotWorkspaceStore()" in store
assert "var bots: [BotProfile] = []" in store
assert "func capabilitySessionID" in store and "func inheritOwner" in store
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
assert "var version = 2" in archive and "require(version == 2" in archive
assert "interrupted = false" in archive
assert "AgentJobRegistry" not in archive and "submitProgrammaticPrompt" not in archive
assert 'static let current = "minisbak/3"' in read("Agent/Backup/BackupFormat.swift")
importer = read("Agent/Backup/BackupImporter.swift")
inspect = importer.split("func inspect(packageURL:", 1)[1].split("// MARK:", 1)[0]
assert "try checkFormat(manifest)" in inspect
debug = read("Debug/DebugRPCProviderChat.swift")
assert 'params["botId"] as? String' in debug and "workspace.ensureCommander" not in debug
print("PASS: source contracts for empty initialization, generic delegation, current backup versions and no restore replay")
print("NOT RUN: Swift runtime, Xcode build, simulator or device acceptance")
