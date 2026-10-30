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
