#!/usr/bin/env python3
"""Verify the permission store shared by MCP/settings and shell execution."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'Agent/Offload/OffloadPermissionManager.swift').read_text(encoding='utf-8')
# Isolate this executable's preferences; leave the shipping permission methods intact.
source = source.replace('private let defaults = UserDefaults.standard',
                        'private let defaults = UserDefaults(suiteName: CommandLine.arguments[1])!')
tests = '''import Foundation
func AppLocalized(_ key: String) -> String { key }
import Combine
struct AppLogger {
    init(category: String) {}
    func info(_ message: String) {}
}
@main struct Permissions {
    @MainActor static func main() async {
        let suite = CommandLine.arguments[1]
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let manager = OffloadPermissionManager.shared
        var changes = 0
        let observer = manager.objectWillChange.sink { changes += 1 }
        let command = "apple-clipboard"
        precondition(OffloadPermissionManager.extractOffloadCommand(from: "/usr/local/bin/apple-clipboard read") == command)
        manager.setPermissionLevel(.notAllowed, for: command)
        precondition(changes > 0 && manager.permissionLevel(for: command) == .notAllowed)
        let denied = await manager.checkPermission(for: command, sessionId: "bot-session")
        guard case .denied = denied else { fatalError("Disabled capability was permitted") }
        manager.setPermissionLevel(.bypass, for: command)
        let bypass = await manager.checkPermission(for: command, sessionId: "bot-session")
        guard case .allowed = bypass else { fatalError("Enabled capability was denied") }
        manager.setPermissionLevel(.askOnce, for: command)
        let request = Task { await manager.checkPermission(for: command, sessionId: "bot-session") }
        while manager.pendingRequest == nil { await Task.yield() }
        manager.respond(to: manager.pendingRequest!.id, allowed: true)
        let granted = await request.value
        guard case .allowed = granted else { fatalError("Grant was ignored") }
        let repeated = await manager.checkPermission(for: command, sessionId: "bot-session")
        guard case .allowed = repeated else { fatalError("Session grant was lost") }
        let other = Task { await manager.checkPermission(for: command, sessionId: "group-session") }
        while manager.pendingRequest == nil { await Task.yield() }
        manager.respond(to: manager.pendingRequest!.id, allowed: false)
        let refused = await other.value
        guard case .denied = refused else { fatalError("Grant leaked across sessions") }
        manager.setPermissionLevel(.notAllowed, for: command)
        let revoked = await manager.checkPermission(for: command, sessionId: "bot-session")
        guard case .denied = revoked else { fatalError("Disable failed to override session grant") }
        withExtendedLifetime(observer) {}
        print("PASS: capability policy notifications, disabled/enabled execution, ask-once grants, session isolation and revocation")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='minis-permission-tests-') as temp:
    temp = Path(temp)
    manager = temp / 'Manager.swift'
    manager.write_text(source, encoding='utf-8')
    test = temp / 'Tests.swift'
    test.write_text(tests, encoding='utf-8')
    binary = temp / 'permission-tests'
    subprocess.run(['swiftc', str(manager), str(test), '-o', str(binary)], check=True)
    subprocess.run([str(binary), 'test.openminis.' + temp.name], check=True, timeout=30)
