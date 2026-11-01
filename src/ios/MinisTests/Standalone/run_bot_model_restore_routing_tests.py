"""Compile the production resolver cache/requirement boundary with provider fixtures."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "Agent/Chat/AIChatViewModel+ProviderFactory.swift").read_text(encoding="utf-8")
boundary = source.split("    private struct ResolveCacheKey", 1)[1].split("    private func resolveCurrentEntryUncached()", 1)[0]
with tempfile.TemporaryDirectory(prefix="minis-bot-model-boundary-") as temp:
    directory = Path(temp)
    wrapper = directory / "Resolver.swift"
    wrapper.write_text("import Foundation\nextension AIChatViewModel {\n    private struct ResolveCacheKey" + boundary + "\n}\n", encoding="utf-8")
    binary = directory / "model-tests"
    subprocess.run(["swiftc", "-swift-version", "5", str(wrapper), str(Path(__file__).with_name("BotModelRestoreRoutingTests.swift")), "-o", str(binary)], check=True, timeout=120)
    subprocess.run([str(binary)], check=True, timeout=30)
