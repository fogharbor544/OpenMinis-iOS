"""Check prompt dispatch wiring and compile the shipping composer with scoped stores stubbed."""
from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def declaration(source, signature):
    assert signature in source, "Missing shared full system-prompt composer"
    start = source.index(signature)
    end = source.index("\n    }", start) + len("\n    }")
    return source[start:end]


def composer_source():
    source = read("Agent/Chat/AIChatViewModel+SystemPrompt.swift")
    return "\n".join([
        declaration(source, "    func agentSystemPrompt(for model: LLMModel, basePrompt: String? = nil) -> String {"),
        declaration(source, "    var memoryStatusFragment: String {"),
        declaration(read("Agent/Chat/AIChatViewModel+Cancel.swift"), "    static func modelPromptFragments(_ model: LLMModel) -> String {"),
    ])


def check_dispatch_wiring():
    loop = read("Agent/Chat/AIChatViewModel+AgentLoop.swift")
    fallback = read("Agent/Chat/AIChatViewModel+Fallback.swift")
    assert "var userSystemPrompt = agentSystemPrompt(for: activeModel)" in loop
    assert "userSystemPrompt = agentSystemPrompt(for: newEntry.model)" in loop
    assert fallback.count(
        "currentSystemPrompt = agentSystemPrompt(for: nextEntry.model, basePrompt: baseSystemPrompt)"
    ) == 4, "Every inner fallback must rebuild the full scoped prompt before dispatch"
    assert "var rebuiltPrompt = baseSystemPrompt" not in fallback
    assert "skillPromptFragment" not in loop and "systemPromptSnippet" not in loop
    print("PASS: initial dispatch, outer refresh and all four inner fallback paths share full composition")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-swift", action="store_true")
    args = parser.parse_args()
    composer = composer_source()
    check_dispatch_wiring()
    swiftc = shutil.which("swiftc")
    if not swiftc:
        assert not args.require_swift, "swiftc is required for native composer regressions"
        print("NOT RUN: Swift composer behavior (swiftc unavailable)")
        return
    with tempfile.TemporaryDirectory(prefix="minis-agent-prompt-") as temp:
        directory = Path(temp)
        shipping = directory / "Composer.swift"
        shipping.write_text("import Foundation\nextension AIChatViewModel {\n" + composer + "\n}\n", encoding="utf-8")
        binary = directory / "prompt-tests"
        subprocess.run([swiftc, str(shipping), str(HERE / "AgentPromptTests.swift"), "-o", str(binary)], check=True, timeout=120)
        subprocess.run([str(binary)], check=True, timeout=30)


if __name__ == "__main__":
    main()
