"""Run shipping usage accounting and SQLite methods with app boundaries stubbed (macOS Swift)."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="minis-auxiliary-usage-") as temp:
    directory = Path(temp)
    models = (ROOT / "Agent/Chat/ChatStoreModels.swift").read_text(encoding="utf-8")
    usage = "struct StoredTokenUsage" + models.split("struct StoredTokenUsage", 1)[1].split("/// A single message", 1)[0]
    (directory / "Usage.swift").write_text("import Foundation\n" + usage, encoding="utf-8")
    source = (ROOT / "Agent/Chat/ChatStore+UsageStats.swift").read_text(encoding="utf-8")
    for module in ("SwiftAnthropic", "UIKit", "os.log"):
        source = source.replace("import " + module, "")
    (directory / "Store.swift").write_text(source, encoding="utf-8")
    binary = directory / "usage-tests"
    subprocess.run(["swiftc", "-swift-version", "5", str(directory / "Usage.swift"), str(directory / "Store.swift"),
                    str(Path(__file__).with_name("AuxiliaryUsagePersistenceTests.swift")), "-lsqlite3", "-o", str(binary)], check=True, timeout=120)
    subprocess.run([str(binary)], check=True, timeout=30)
