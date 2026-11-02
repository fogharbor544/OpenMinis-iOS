"""Run shipping Bot timeline projection with model/UI boundaries stubbed.

Requires macOS Swift (BotWorkspaceStore imports SwiftUI). This does not claim
UIKit hit-testing, first-frame collection layout, or live-provider execution.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="minis-bot-chat-") as temp:
    directory = Path(temp)
    store = (ROOT / "Views/ContentView/Bots/BotWorkspaceStore.swift").read_text(encoding="utf-8")
    original = "static let shared = BotWorkspaceStore()"
    assert original in store
    store = store.replace(original, 'static let shared = BotWorkspaceStore(fileURL: URL(fileURLWithPath: CommandLine.arguments[1]))', 1)
    (directory / "Workspace.swift").write_text(store, encoding="utf-8")
    source = (ROOT / "Views/ContentView/Bots/BotMessagePresentation.swift").read_text(encoding="utf-8")
    projection = source.split("/// These are presentation rows only.", 1)[1].split("struct BotCreatedCard:", 1)[0]
    projection = projection[projection.index("extension AIChatViewModel {"):]
    (directory / "Projection.swift").write_text("import Foundation\n" + projection, encoding="utf-8")
    binary = directory / "bot-chat-tests"
    subprocess.run(["swiftc", "-swift-version", "5", str(directory / "Workspace.swift"),
                    str(directory / "Projection.swift"), str(Path(__file__).with_name("BotChatPresentationTests.swift")),
                    "-o", str(binary)], check=True, timeout=120)
    subprocess.run([str(binary), str(directory / "workspace.json")], check=True, timeout=30)
