"""Exercise the shipping handoff runtime with chat inference/platform boundaries stubbed.

Requires macOS Swift/SwiftUI. Does not run a provider or simulate UIKit gestures.
No HelperRunner or helper execution method is supplied by this harness.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix="minis-direct-bot-") as temp:
    directory = Path(temp)
    store = (ROOT / "Views/ContentView/Bots/BotWorkspaceStore.swift").read_text(encoding="utf-8")
    original = "static let shared = BotWorkspaceStore()"
    assert original in store
    store = store.replace(original, 'static let shared = BotWorkspaceStore(fileURL: URL(fileURLWithPath: CommandLine.arguments[1]))', 1)
    (directory / "Workspace.swift").write_text(store, encoding="utf-8")
    services = (HERE / "BotSessionBindingTests.swift").read_text(encoding="utf-8").split("@main struct", 1)[0]
    types = (HERE / "BotToolCommandTests.swift").read_text(encoding="utf-8").split("@MainActor final class AgentJobRegistry", 1)[0]
    (directory / "Services.swift").write_text(services + types, encoding="utf-8")
    runtime = (ROOT / "Views/ContentView/Bots/BotTeamRuntime.swift").read_text(encoding="utf-8").replace("import UIKit", "")
    # Advance the real watchdog without sleeping through its two-minute intervals.
    runtime += """
extension BotTeamRuntime {
    func checkInactivityNow(for id: String, elapsed: TimeInterval) async {
        lastTick = Date()
        activity[id] = lastTick.addingTimeInterval(-elapsed)
        await tick()
    }
}
"""
    (directory / "Runtime.swift").write_text(runtime, encoding="utf-8")
    helper = (ROOT / "Agent/Jobs/HelperRunner.swift").read_text(encoding="utf-8")
    stop = helper.split("    func stopByUser() {", 1)[1].split("    /// [T-stop-sibling-subagent]", 1)[0]
    restore = (ROOT / "Agent/Backup/BotBackupSnapshot.swift").read_text(encoding="utf-8")
    begin = restore.split("    static func begin(databaseURL: URL) async throws {", 1)[1].split("    private static func stageCheckpoint", 1)[0]
    boundary = "import Foundation\nextension AIChatViewModel {\n    func stopByUser() {" + stop + "}\n"
    boundary += "@MainActor enum BotGraphRestore {\nstatic var staged = false\n"
    boundary += 'static var ready: URL { URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathExtension("ready") }\n'
    boundary += "static func stageCheckpoint(databaseURL: URL) throws { staged = true }\n"
    boundary += "static func begin(databaseURL: URL) async throws {" + begin + "}\n"
    (directory / "StopAndRestore.swift").write_text(boundary, encoding="utf-8")
    binary = directory / "direct-bot-tests"
    subprocess.run(["swiftc", "-swift-version", "5", str(directory / "Workspace.swift"),
                    str(ROOT / "Views/ContentView/Bots/BotWorkspaceStore+Sessions.swift"),
                    str(directory / "Services.swift"), str(directory / "Runtime.swift"), str(directory / "StopAndRestore.swift"),
                    str(ROOT / "Agent/Jobs/AgentCallback.swift"), str(HERE / "BotDirectExecutionTests.swift"), "-o", str(binary)], check=True, timeout=120)
    subprocess.run([str(binary), str(directory / "workspace.json")], check=True, timeout=30)
