"""Type-check the actual Bot SwiftUI screens against the iOS 16 SDK deployment target.

Only existing app services/screens are stubbed; the new memory UI and stores are
compiled unchanged. This catches UI/API errors without rebuilding the iSH runtime.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
stubs = Path(__file__).with_name('BotSessionBindingTests.swift').read_text(encoding='utf-8').split('@main struct')[0]
stubs = stubs.replace('import Foundation', 'import Foundation\nimport SwiftUI')
stubs = stubs.replace('struct TestSession { let id: String }', '''
struct TestSession: Identifiable, Equatable {
    let id: String
    var title: String? = nil
    var isPinned = false
    var isFiled = false
    var updatedAt = Date()
}
typealias ChatSession = TestSession
''')
stubs = stubs.replace('struct TestCapability { let id: String }', '''
struct TestCapability: Identifiable {
    let id: String
    var name: String { id }
    var isEnabled = true
    var enabled = true
}
''')
stubs = stubs.replace('struct TestGroup { let id: String }', 'struct TestGroup: Identifiable { let id: String; var name: String { id } }')
stubs = stubs.replace('final class ProviderConfigStore {', 'final class ProviderConfigStore: ObservableObject {\n    var modelGroups: [TestGroup] = []')
stubs = stubs.replace('final class SkillStore {', 'final class SkillStore: ObservableObject {')
stubs = stubs.replace('final class MCPStore {', 'final class MCPStore: ObservableObject {')
stubs += '''
enum SearchKeywords {
    static func terms(_ query: String) -> [String] { query.split(separator: " ").map(String.init) }
}
extension ChatStore {
    struct SearchResult { let session: ChatSession; let matchSnippet: String? }
    func searchSessions(query: String) -> [SearchResult] { [] }
}

func AppLocalized(_ value: String) -> String { value }
@MainActor final class SessionMenuActionChannel: ObservableObject {}
struct MenuKey {
    let sid: String
    let pinned: Bool
    let title: String?
    let filed: Bool
}
struct SessionRow: View, Equatable {
    let session: ChatSession
    var body: some View { EmptyView() }
}
struct SessionContextMenu: View {
    let key: MenuKey
    let actions: SessionMenuActionChannel
    var body: some View { EmptyView() }
}
struct ToolsSettingsView: View { var body: some View { EmptyView() } }
struct HelperSettingsView: View { var body: some View { EmptyView() } }
struct EnvironmentVariablesView: View { var body: some View { EmptyView() } }
struct ScheduledTasksManagementView: View {
    var botID: String? = nil
    var body: some View { EmptyView() }
}
@MainActor final class AIChatViewModel: ObservableObject {
    var botMemoryOwner: BotSessionOwner? = nil
}
enum SyncV2Bootstrap { static var isEnabled = false }
@MainActor final class SyncCore {
    static let shared = SyncCore()
    var userOnSyncSheet = false
    var isRunning = false
    var totalSent = 0
    var totalReceived = 0
    enum Trigger { case manual }
    func fetchNow(trigger: Trigger) async {}
    func sendNow(trigger: Trigger) async {}
}
extension ChatStore {
    struct DirtyCounts { var byType: [String: Int] = [:] }
    func countDirtyRecords() -> DirtyCounts { DirtyCounts() }
}
struct AIChatView: View {
    let sessionId: String
    var body: some View { EmptyView() }
}
struct SessionSkillsView: View {
    let sessionId: String?
    var body: some View { EmptyView() }
}
struct SessionMCPsView: View {
    let sessionId: String?
    var body: some View { EmptyView() }
}
struct MCPIntegrationsView: View { var body: some View { EmptyView() } }
@MainActor final class BotRoomRunner: ObservableObject {
    static let shared = BotRoomRunner()
    var activeRooms: Set<String> = []
    var speakers: [String: String] = [:]
    func stop(_ id: String) {}
    func send(_ text: String, roomID: String, recipient: String?) {}
}
'''
with tempfile.TemporaryDirectory(prefix='minis-memory-ui-') as temp:
    stub = Path(temp) / 'AppBoundaries.swift'
    stub.write_text(stubs, encoding='utf-8')
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
    folder = root / 'Views/ContentView/Bots'
    sources = [str(folder / (name + '.swift')) for name in [
        'BotWorkspaceStore', 'BotWorkspaceStore+Sessions', 'BotMemoryStore', 'BotMemoryView', 'BotWorkspaceView']]
    sources += [str(root / path) for path in [
        'Views/Chat/SessionMemoryView.swift', 'Views/Settings/MemoryManagementView.swift',
        'Views/Sync/SyncStatusView.swift']]
    subprocess.run(['xcrun', 'swiftc', '-typecheck', '-swift-version', '5', '-sdk', sdk,
                    '-target', 'arm64-apple-ios16.0', *sources, str(stub)], check=True, timeout=180)
    print('PASS: shipping Bot/memory SwiftUI screens type-check for iOS 16 with app-service boundaries stubbed')
