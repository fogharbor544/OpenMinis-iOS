"""Run production DOM-observer JS and extracted Swift automation with fake WebKit.

No network, real accounts, Keychain or ChatStore. Swift tests require swiftc;
--emit-swift writes the extracted fixture for inspection on other hosts.
This is a boundary regression harness, not a native rendering/performance test.
"""
from pathlib import Path
import argparse
import json
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def section(text, start, end):
    return start + text.split(start, 1)[1].split(end, 1)[0]


def sources():
    manager = (ROOT / "Agent/BrowserUse/BrowserUseManager.swift").read_text(encoding="utf-8")
    pool = (ROOT / "Agent/BrowserUse/BrowserTabPool.swift").read_text(encoding="utf-8")
    control = pool.split("// BEGIN BrowserTakeoverControl", 1)[1].split("// END BrowserTakeoverControl", 1)[0]
    control += section(pool, "    var isAgentBrowsing: Bool {", "    /// The manager for")
    # Exercise the actual queued-action admission guard too, without routing/UI I/O.
    admission = section(pool, "        guard !isUserTakeoverActive, generation == takeoverGeneration else {", "        executingActionCount += 1")
    control += "\n    func queuedAction(generation: UInt64) -> BrowserActionResult {\n" + admission + '\nreturn BrowserActionResult(text: "admitted")\n}\n'
    control += "\nfunc generationForTest() -> UInt64 { takeoverGeneration }\nfunc setExecutingForTest(_ count: Int) { executingActionCount = count }\n"
    sheet = (ROOT / "Agent/BrowserUse/BrowserSheetView.swift").read_text(encoding="utf-8")
    agent_loop = (ROOT / "Agent/Chat/AIChatViewModel+AgentLoop.swift").read_text(encoding="utf-8")
    # Must be updated together: this harness has no SwiftUI/ViewModel runtime, but a missing
    # persistent control or a resumed loop-wait would rebuild the audited deadlocks.
    assert "TakeoverControlOutsideAction" in sheet
    assert "await waitIfBrowserTakeover()" not in agent_loop
    background_task = (ROOT / "Agent/Chat/AIChatViewModel+BackgroundTask.swift").read_text(encoding="utf-8")
    # The VM must not park loops or tools on the takeover gate; execution admission is the only wait point.
    assert "browserTabPool.waitForUserTakeover()" not in background_task
    members = section(manager, "    private var userTakeoverRequested = false", "    private var secureCleanupNavigation")
    members += section(manager, "    private static let visualChangeActions:", "    private func requestSecureInput")
    members += section(manager, "    private func waitForDomSettleAndSnapshot(", "    /// Enrich navigate result")
    members += "\nstruct JSEvalTimeout: Error {}\n"
    members += section(manager, "    private func callAsyncJavaScriptBounded(", "    private func navigationMetadata()")
    members += "\nfunc summaryForTest(timeout: Double) async throws -> String { try await collectDomChangeSummary(timeout: timeout) }\n"
    fixture = (HERE / "BrowserAutomationBehaviorTests.swift").read_text(encoding="utf-8")
    fixture = fixture.replace("// INSERT PRODUCTION MANAGER", members).replace("// INSERT PRODUCTION CONTROL", control)
    actions = (ROOT / "Agent/BrowserUse/BrowserUseActions.swift").read_text(encoding="utf-8")
    return manager, actions + "\n" + fixture


def observer_tests(manager):
    summary = section(manager, "    private func collectDomChangeSummary(", "    /// Enrich navigate result")
    setup = re.search(r'let setupJS = """\n(.*?)\n\s*"""', summary, re.S).group(1)
    setup = setup.replace(r"\(Int(timeout * 1000))", "5000")
    read = re.search(r'let readJS = """\n(.*?)\n\s*"""', summary, re.S).group(1)
    program = r"""
const assert=require('node:assert/strict');
const timers=[];
global.window={};global.location={href:'https://fixture.invalid/'};
global.document={documentElement:{},title:'Fixture'};
global.setTimeout=fn=>timers.push(fn);
global.MutationObserver=class {
 constructor(callback){this.callback=callback;this.disconnected=false;}
 observe(root,options){this.root=root;this.options=options;}
 disconnect(){this.disconnected=true;}
};
const setup=new Function(SETUP),read=new Function(READ);
assert.equal(setup(),'ok');
const first=window.__postActionObserver;
first.callback([{type:'childList',addedNodes:[{nodeType:1,tagName:'ARTICLE',innerText:'fixture content'}],removedNodes:[]}]);
const result=JSON.parse(read());
assert.equal(result.mutations,1);assert.equal(result.addedTags.ARTICLE,1);
assert.deepEqual(result.newTexts,['fixture content']);assert.ok(first.disconnected);
assert.equal(window.__postActionObserver,null);
setup();const second=window.__postActionObserver;
setup();const third=window.__postActionObserver;
assert.ok(second.disconnected);assert.ok(!third.disconnected);
timers[1]();assert.ok(!third.disconnected); // old cleanup must not stop a later observer
timers[2]();assert.ok(third.disconnected);
assert.equal(JSON.parse(read()).urlChanged,false);
console.log('PASS: 11 production DOM-observer JS assertions');
""".replace("SETUP", json.dumps(setup)).replace("READ", json.dumps(read))
    with tempfile.TemporaryDirectory(prefix="browser-observer-") as temp:
        path = Path(temp) / "observer.cjs"
        path.write_text(program, encoding="utf-8")
        subprocess.run(["node", str(path)], check=True, timeout=20)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--emit-swift", type=Path)
    parser.add_argument("--require-swift", action="store_true")
    args = parser.parse_args()
    manager, fixture = sources()
    observer_tests(manager)
    if args.emit_swift:
        args.emit_swift.parent.mkdir(parents=True, exist_ok=True)
        args.emit_swift.write_text(fixture, encoding="utf-8")
    swiftc = shutil.which("swiftc")
    if not swiftc:
        if args.require_swift:
            raise SystemExit("swiftc required but unavailable")
        print("SKIP: Swift behavior tests (swiftc unavailable); JS checks alone do not validate Swift behavior")
        return
    with tempfile.TemporaryDirectory(prefix="browser-automation-") as temp:
        temp = Path(temp)
        source = temp / "Automation.swift"
        source.write_text(fixture, encoding="utf-8")
        binary = temp / "automation-tests"
        subprocess.run([swiftc, "-swift-version", "5", "-parse-as-library", str(source), "-o", str(binary)], check=True, timeout=120)
        subprocess.run([str(binary), str(temp)], check=True, timeout=40)


if __name__ == "__main__":
    main()
