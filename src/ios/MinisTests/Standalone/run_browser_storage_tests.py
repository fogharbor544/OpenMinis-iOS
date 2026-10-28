#!/usr/bin/env python3
"""Compile shipping storage components on macOS without launching the app or using real Keychain data."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='minis-browser-tests-') as temp:
    temp = Path(temp)
    sources = []
    for name, boundary in [('BrowserBookmarks', 'struct BrowserBookmarksView:'), ('BrowserPasswords', 'struct BrowserPasswordsView:')]:
        text = (root / 'Agent/BrowserUse' / (name + '.swift')).read_text(encoding='utf-8')
        assert text.count(boundary) == 1
        out = temp / (name + '.swift')
        out.write_text(text.split(boundary)[0], encoding='utf-8')
        sources.append(str(out))
    auth = temp / 'BiometricAuth.swift'
    auth.write_text('import Foundation\n@MainActor enum BiometricAuth { static func authenticate(reason: String) async -> Bool { false } }\n')
    executable = temp / 'browser-tests'
    subprocess.run(['swiftc', '-swift-version', '6', *sources, str(auth), str(Path(__file__).with_name('BrowserStorageBehaviorTests.swift')), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
