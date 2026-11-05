#!/usr/bin/env python3
"""Run the shipping post-login capture script with a synthetic DOM."""
from pathlib import Path
import json
import re
import subprocess

root = Path(__file__).resolve().parents[2]
manager = (root / "Agent/BrowserUse/BrowserUseManager.swift").read_text(encoding="utf-8")
match = re.search(
    r"nonisolated static func credentialCaptureScript\(\).*?let js = \"\"\"\n(.*?)\n\s*\"\"\"",
    manager,
    re.S,
)
assert match, "credentialCaptureScript not found"
script = match.group(1).replace(r"\(credentialSaveMessageHandlerName)", "minisCredentialSave")
# The Swift literal escapes regex backslashes; the extracted JS needs the
# runtime form (for example `\s` rather than `\\s`).
script = script.replace("\\\\", "\\")

program = r"""
const assert = require('node:assert/strict');
const posted = [];
let listeners = {};

class Element {
  constructor() {
    this.form = null;
    this.type = 'button';
    this.innerText = '';
    this.value = '';
  }
  getClientRects() { return [{}]; }
  closest() { return this; }
  querySelector() { return null; }
  querySelectorAll() { return []; }
}

class Field extends Element {
  constructor(type='password', value='') {
    super();
    this.type = type;
    this.value = value;
    this.autocomplete = '';
    this.name = '';
    this.id = '';
    this.disabled = false;
    this.readOnly = false;
  }
}

class Form extends Element {
  constructor(fields, user) {
    super();
    this.fields = fields;
    this.user = user;
  }
  querySelectorAll(selector) {
    return selector === 'input' ? [this.noise, this.user, ...this.fields].filter(Boolean) : this.fields;
  }
  querySelector(selector) {
    return selector.indexOf('autocomplete="username"') >= 0 ? (this.noise || this.user) : null;
  }
}

global.Element = Element;
global.document = {
  addEventListener(name, handler) { listeners[name] = handler; },
  querySelectorAll() { return []; },
};
global.location = { protocol: 'https:', origin: 'https://example.com' };
global.window = {
  webkit: {
    messageHandlers: {
      minisCredentialSave: {
        postMessage(message) { posted.push(message); },
      },
    },
  },
};

new Function(SCRIPT)();

const user = new Field('text', ' test-user ');
const password = new Field('password', 'synthetic-secret');
const form = new Form([password], user);

listeners.submit({ target: form });
assert.equal(posted.length, 1);
assert.deepEqual(posted[0], {
  origin: 'https://example.com',
  username: 'test-user',
  password: 'synthetic-secret',
});

listeners.submit({ target: form });
assert.equal(posted.length, 1, 'duplicate submit must not repost');

password.value = 'rotated-secret';
listeners.submit({ target: form });
assert.equal(posted.length, 2);
assert.equal(posted[1].password, 'rotated-secret');

password.autocomplete = 'new-password';
password.value = 'signup-secret';
listeners.submit({ target: form });
assert.equal(posted.length, 2, 'new-password fields must not be saved');

password.autocomplete = '';
password.value = 'ambiguous';
form.fields = [password, new Field('password', 'second')];
listeners.submit({ target: form });
assert.equal(posted.length, 2, 'multiple password fields must not be saved');

form.fields = [password];
password.value = 'click-secret';
const button = new Element();
button.type = 'button';
button.innerText = 'Sign in';
button.form = form;
listeners.click({ target: button });
setTimeout(() => {
  assert.equal(posted.length, 3);
  assert.equal(posted[2].password, 'click-secret');

  password.value = 'spa-cleared-secret';
  listeners.click({ target: button });
  password.value = '';
  assert.equal(posted.length, 4, 'capture must precede synchronous SPA form clearing');
  assert.equal(posted[3].password, 'spa-cleared-secret');

  form.noise = new Field('text', 'unrelated search');
  user.autocomplete = 'section-login username';
  password.value = 'semantic-user-secret';
  listeners.submit({ target: form });
  assert.equal(posted[4].username, 'test-user', 'username semantics must beat document order');
  user.autocomplete = '';
  user.name = 'username';
  password.value = 'implicit-text-secret';
  listeners.submit({ target: form });
  assert.equal(posted[5].username, 'test-user', 'default text username must beat an unrelated text field');

  location.protocol = 'http:';
  password.value = 'insecure';
  listeners.submit({ target: form });
  assert.equal(posted.length, 6, 'HTTP pages must not offer credential saving');
  console.log('PASS: credential capture posts one HTTPS login, deduplicates, ignores new/ambiguous password fields, and covers JS login buttons.');
}, 20);
""".replace("SCRIPT", json.dumps(script))

subprocess.run(["node", "-e", program], check=True)
