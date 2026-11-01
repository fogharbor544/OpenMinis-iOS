"""Run the shipping command extension with model/job boundaries stubbed.

Only the shared workspace's disk address is redirected into a temporary folder.
No production command body is replaced. This does not start live inference.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="minis-bot-commands-") as temp:
    directory = Path(temp)
    store = (ROOT / "Views/ContentView/Bots/BotWorkspaceStore.swift").read_text(encoding="utf-8")
    original = "static let shared = BotWorkspaceStore()"
    assert original in store
    store = store.replace(original, 'static let shared = BotWorkspaceStore(fileURL: URL(fileURLWithPath: CommandLine.arguments[1]))', 1)
    (directory / "Workspace.swift").write_text(store, encoding="utf-8")
    runtime = (ROOT / "Views/ContentView/Bots/BotTeamRuntime.swift").read_text(encoding="utf-8")
    command_extension = runtime.split("/// Admission and inactivity monitoring", 1)[0].replace("import UIKit\n", "")
    (directory / "Commands.swift").write_text(command_extension, encoding="utf-8")
    binary = directory / "bot-command-tests"
    subprocess.run(["swiftc", "-swift-version", "5", str(directory / "Workspace.swift"), str(directory / "Commands.swift"),
                    str(Path(__file__).with_name("BotToolCommandTests.swift")), "-o", str(binary)], check=True, timeout=120)
    subprocess.run([str(binary), str(directory / "workspace.json")], check=True, timeout=30)
