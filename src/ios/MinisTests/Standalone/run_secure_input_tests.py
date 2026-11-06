#!/usr/bin/env python3
"""Run production native-fill JS with synthetic DOM fixtures; not a WebKit/device test."""
from pathlib import Path
import json
import re
import subprocess

root = Path(__file__).resolve().parents[2]
source = (root / "Agent/BrowserUse/BrowserPasswords.swift").read_text(encoding="utf-8")
script = re.search(r"// BEGIN NativeSecureFillScript.*?static let fillScript = \"\"\"\n(.*?)\n\s*\"\"\"", source, re.S).group(1)
manager = (root / "Agent/BrowserUse/BrowserUseManager.swift").read_text(encoding="utf-8")
cleanup = re.search(r'private static let clearSecureFieldsScript = "(.*?)"', manager).group(1)
program = r"""
const assert = require('node:assert/strict');
const fill = new Function('origin', 'selector', 'secret', 'kind', SCRIPT);
let fields = [], events = [], listeners = {}, submitted = false;
class Input {
  constructor(type='password') { this.type=type; this.autocomplete=''; this.disabled=false; this.readOnly=false; this.visible=true; this.raw=''; }
  get value() { return this.raw; } set value(value) { this.raw=value; }
  getClientRects() { return this.visible ? [{}] : []; }
  dispatchEvent(e) { events.push(e.type); }
}
global.HTMLInputElement=Input;
global.Event=class { constructor(type, options) { this.type=type; this.bubbles=options.bubbles; } };
global.location={origin:'https://example.com'};
global.document={querySelectorAll(selector) { if (selector==='[') throw new SyntaxError('Invalid selector'); return fields; }};
global.window={addEventListener(event, handler) { listeners[event]=handler; }};
const secret='synthetic-only-'+Date.now();
function run(kind='password', origin='https://example.com', selector='#secret') { return fill(origin, selector, secret, kind); }
function reset(...items) { fields=items; events=[]; listeners={}; }
let checks=0;
function check(condition) { assert.ok(condition); checks++; }
let input=new Input(); reset(input);
check(run()===true); check(input.value===secret); assert.deepEqual(events,['input','change']); checks++;
check(!submitted); check(typeof run()==='boolean');
listeners.pagehide(); check(input.value==='');
reset(new Input()); check(run('password','https://other.example')===false); check(fields[0].value==='');
for (const key of ['disabled','readOnly']) { input=new Input(); input[key]=true; reset(input); check(run()===false); check(input.value===''); }
input=new Input(); input.visible=false; reset(input); check(run()===false);
input=new Input(); input.autocomplete='new-password'; reset(input); check(run()===false);
reset(new Input(), new Input()); check(run()===false);
reset(); check(run()===false);
reset({getClientRects(){return [{}]}}); check(run()===false);
reset(new Input('text')); check(run()===false);
for (const kind of ['pin','otp']) { for (const type of ['text','tel','number','password']) {
 input=new Input(type); reset(input); check(run(kind)===true); check(input.type==='password'); check(input.value===secret); listeners.pagehide(); check(input.value==='');
} }
reset(new Input('email')); check(run('otp')===false);
reset(new Input()); assert.throws(()=>run('password','https://example.com','['), SyntaxError); checks++;
const clear = new Function(CLEANUP);
const password = new Input(), code = new Input('text'), ordinary = new Input('text');
code.autocomplete='one-time-code';
reset(password, code, ordinary);
for (const field of fields) field.value=secret;
clear();
check(password.value===''); check(code.value===''); check(ordinary.value===secret);
console.log(`PASS: ${checks} production-JS assertions: native field fill, origin/field rejection, masking, input events, pagehide and cleanup erasure, Boolean-only return.`);
""".replace("SCRIPT", json.dumps(script)).replace("CLEANUP", json.dumps(cleanup))
subprocess.run(["node", "-e", program], check=True)

# Portable routing/privacy contracts; native lifecycle assertions live in
# BrowserSecureSessionTests and NativeInteractionTests (require iOS).
chat = (root / "Agent/Chat/AIChatViewModel+ConcurrentTools.swift").read_text(encoding="utf-8")
view = (root / "Views/Chat/AssistantBlockView.swift").read_text(encoding="utf-8")
actions = (root / "Agent/BrowserUse/BrowserUseActions.swift").read_text(encoding="utf-8")
session = source.split("final class BrowserSecureInputSession:", 1)[1].split("struct BrowserSecureInputCard:", 1)[0]
lifecycle = session.split("private func observeLifecycle()", 1)[1].split("func closeWebPage()", 1)[0]
assert "secureInputBlockID = messages[msgIdx].blocks[blockIdx].id" in chat
assert "if helperConfig == nil" in chat, "subagents without chat cells must retain native presentation"
assert "session.startInline(blockID: blockID)" in manager
assert "session.blockID == block.id" in view and "BrowserSecureInputCard(session: session)" in view
assert "secureInputBlockID" not in actions.split("static func parse(from json:", 1)[1], "model must not supply routing identity"
assert 'finish("cancelled")' not in lifecycle, "backgrounding must not end the pending request"
assert "self.shielded = true; self.reveal = false" in lifecycle
assert "self.store.lock()" in lifecycle
assert "timeoutNanoseconds: nil, cancelOnBackground: false" in session
assert 'secret = ""; username = ""; reveal = false' in session
assert 'callback?("reference=\\(id.uuidString); \\(status)")' in session
assert "if !pageNeedsCleanup" in session, "a page opened manually still needs cleanup"
assert 'didEnterBackgroundNotification)) { _ in session.finish' not in source
assert "Codable" not in session and "persist" not in lifecycle
print("PASS: 14 source contracts for inline routing, resumable lifecycle and status-only completion (not native runtime tests).")
