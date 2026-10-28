#!/usr/bin/env python3
"""Compile the shipping room runner against controlled chat-runtime boundaries."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='minis-room-tests-') as temp:
    temp = Path(temp)
    store = (root / 'Views/ContentView/Bots/BotWorkspaceStore.swift').read_text(encoding='utf-8')
    # Redirect the singleton's file to this test's disposable directory.
    store = store.replace('static let shared = BotWorkspaceStore()',
                          'static let shared = BotWorkspaceStore(fileURL: URL(fileURLWithPath: CommandLine.arguments[1]))')
    source = temp / 'Store.swift'
    source.write_text(store, encoding='utf-8')
    binary = temp / 'room-tests'
    subprocess.run(['swiftc', str(source), str(root / 'Views/ContentView/Bots/BotRoomRunner.swift'),
                    str(Path(__file__).with_name('BotRoomRunnerBehaviorTests.swift')), '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(temp / 'workspace.json')], check=True, timeout=30)
