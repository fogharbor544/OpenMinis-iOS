"""Exercise the shipping snapshot and SQLite rollback against a live WAL database."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="minis-frozen-graph-") as temp:
    directory = Path(temp)
    sources = []
    for name, path in [("Workspace", "Views/ContentView/Bots/BotWorkspaceStore.swift"),
                       ("Memory", "Views/ContentView/Bots/BotMemoryStore.swift")]:
        text = (ROOT / path).read_text(encoding="utf-8")
        class_name = "BotWorkspaceStore" if name == "Workspace" else "BotMemoryStore"
        original = f"static let shared = {class_name}()"
        assert original in text
        text = text.replace(original, f'static let shared = {class_name}(fileURL: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("{name}.data"))', 1)
        output = directory / (name + ".swift")
        output.write_text(text, encoding="utf-8")
        sources.append(str(output))
    snapshot = (ROOT / "Agent/Backup/BotBackupSnapshot.swift").read_text(encoding="utf-8")
    snapshot = snapshot.split("/// A durable checkpoint", 1)[0]
    output = directory / "Snapshot.swift"
    output.write_text(snapshot, encoding="utf-8")
    sources += [str(output), str(ROOT / "Views/ContentView/Bots/BotWorkspaceArchive.swift"),
                str(Path(__file__).with_name("BotFrozenSnapshotTests.swift"))]
    binary = directory / "frozen-tests"
    subprocess.run(["swiftc", "-swift-version", "5", *sources, "-lsqlite3", "-o", str(binary)], check=True, timeout=120)
    subprocess.run([str(binary), str(directory)], check=True, timeout=30)
