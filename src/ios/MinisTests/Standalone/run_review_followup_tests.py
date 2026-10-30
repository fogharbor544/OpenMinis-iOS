"""Exercise shipping format tests and inbound apply/cursor code with I/O stubs."""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def format_source():
    importer = read("Agent/Backup/BackupImporter.swift")
    acceptance = importer.split("    static func isFormatSupported(", 1)[1].split(
        "\n    // MARK: - Integrity", 1
    )[0]
    tests = read("MinisTests/BackupFormatCompatibilityTests.swift").replace(
        "@testable import Minis", "@testable import BackupModels"
    )
    methods = re.findall(r"    func (test\w+)\(", tests)
    assert len(methods) >= 12
    return (
        tests
        + "\nenum BackupImporter {\n    static func isFormatSupported("
        + acceptance
        + "\n}\n"
    )


def inbound_source():
    core = read("Agent/Sync/V2/SyncCore.swift")
    inbound = core.split("    private static let applyRank:", 1)[1].split(
        "    // MARK: - Diagnostics", 1
    )[0]
    transport = read("Agent/Sync/V2/ICloudSharedZoneTransport.swift")
    completion = transport.split("        let fetchStampForCursor =", 1)[1].split(
        "        // Also poke CKSyncEngine", 1
    )[0]
    # Guards for the other repaired paths; behavioral archive tests run separately.
    exporter = read("Agent/Backup/BackupExporter.swift").split("private func exportAgents(", 1)[1].split(
        "// MARK: - Providers", 1
    )[0]
    assert "allSessionIds" not in exporter and "isSubset" not in exporter
    assert "BotWorkspaceArchive.sessionIDs(in: dataDir)" in exporter
    assert "sessionIDs: exportedSessions" in exporter
    assert "adoptIntoCommander" not in read("Debug/DebugRPCProviderChat.swift")
    for path in ("Agent/Session/SoulStore.swift", "Agent/Chat/ChatStore+SyncDirty.swift",
                 "Agent/Sync/V2/ICloudSharedZoneTransport.swift"):
        assert '"SoulV2"' not in read(path)
    return r'''
import Foundation

struct Logger {
    func info(_ text: String) {}
    func warning(_ text: String) {}
    func error(_ text: String) {}
    func debug(_ text: String) {}
}
let logger = Logger()
extension Notification.Name {
    static let cloudSyncDidFetchChanges = Notification.Name("test-sync-applied")
}
struct Metadata { let version = 1 }
enum UploadPolicy { static func allowsRecordType(_ type: String) -> Bool { true } }
final class SyncableTypeRegistry {
    static let shared = SyncableTypeRegistry()
    func metadata(for type: String) -> Metadata? { type == "SubAgentV3" ? Metadata() : nil }
}
// In-memory preference and provider-readiness boundaries; never touch real defaults.
final class UserDefaults {
    static let standard = UserDefaults()
    var values: [String: Any] = [:]
    func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
}
@MainActor final class ProviderConfigStore {
    static let shared = ProviderConfigStore()
    var db: Int? = 1
}
@MainActor final class Core {
    var inboundTail: Task<Void, Never>?
    var lastFetchAt: Date?
    var totalReceived = 0
    var recentlyPushedIds: [String: Date] = [:]
    let echoTTL: TimeInterval = 30
    var loggedUnknownFieldKeys: Set<String> = []
    static let scrollPauseBudget: TimeInterval = 0
    static func waitWhileChatScrolls(budget: TimeInterval) async -> TimeInterval { budget }
    private static let applyRank:''' + inbound + r'''
}
@MainActor final class Transport {
    var observeHandler: ((SyncInboundBatch) -> Void)?
    var commits = 0
    static let recentFetchWindow: TimeInterval = 86400
    static let fullHistoryConfigTypes: Set<String> = ["SubAgentV3"]
    static func configTypeAnchoredKey(_ type: String) -> String { "anchor.\(type)" }
    static func configTypeAnchorPendingCountKey(_ type: String) -> String { "pending.\(type)" }
    func commitRecentFetchCursor(_ stamp: TimeInterval) { commits += 1 }
    func handOff(_ portables: [PortableRecord], fetchHadError: Bool = false) {
        let typesWithError: Set<String> = fetchHadError ? ["SubAgentV3"] : []
        let byType = ["SubAgentV3": portables.count]
        let totalFetched = portables.count
        let fetchStampForCursor =''' + completion + r'''
    }
}

enum MergeError: Error { case missingOwner }
@main struct InboundCompletionTests {
    @MainActor static func main() async {
        func records(_ count: Int, blocked: Int? = nil) -> [PortableRecord] {
            (0..<count).map { i in
                PortableRecord(id: .init(type: "SubAgentV3", id: String(i)),
                    minimumCompatibleVersion: blocked == i ? 2 : nil, updatedAt: Date())
            }
        }
        // More than two slices: a failure in the first, middle or final slice
        // must suppress BOTH the poll cursor and full-history anchor updates.
        for failedID in ["0", "50", "100"] {
            UserDefaults.standard.values = ["pending.SubAgentV3": 101]
            let core = Core(), transport = Transport()
            transport.observeHandler = { core.processInbound($0, from: "test") }
            var applied: [String] = []
            SyncCoreHydrators.shared.register(recordType: "SubAgentV3", builder: nil, merger: { record in
                if record.id.id == failedID { throw MergeError.missingOwner }
                applied.append(record.id.id)
            })
            transport.handOff(records(101))
            precondition(transport.commits == 0)
            await core.inboundTail?.value
            precondition(applied.count == 100 && transport.commits == 0)
            precondition(!UserDefaults.standard.bool(forKey: "anchor.SubAgentV3"))
            // Corrected data is retried through the same core, not a new process.
            SyncCoreHydrators.shared.register(recordType: "SubAgentV3", builder: nil, merger: { _ in })
            transport.handOff(records(101))
            await core.inboundTail?.value
            precondition(transport.commits == 1)
            precondition(UserDefaults.standard.bool(forKey: "anchor.SubAgentV3"))
        }
        UserDefaults.standard.values = [:]
        let core = Core(), transport = Transport()
        transport.observeHandler = { core.processInbound($0, from: "test") }
        transport.handOff(records(51, blocked: 0))
        await core.inboundTail?.value
        precondition(transport.commits == 0 && UserDefaults.standard.values.isEmpty)
        transport.handOff(records(51), fetchHadError: true)
        await core.inboundTail?.value
        precondition(transport.commits == 0 && UserDefaults.standard.values.isEmpty)
        transport.handOff(records(51))
        await core.inboundTail?.value
        precondition(transport.commits == 1)
        precondition(UserDefaults.standard.object(forKey: "pending.SubAgentV3") as? Int == 51)
        // Empty callbacks still wait for previous work; an empty poll can commit.
        var completedEmpty = false
        core.processInbound(.init(records: [], deletes: [], sourceDeviceId: nil,
            onApplied: { completedEmpty = $0 }), from: "test")
        precondition(!completedEmpty)
        await core.inboundTail?.value
        precondition(completedEmpty)
        transport.handOff([])
        precondition(transport.commits == 2)
        let unobserved = Transport()
        unobserved.handOff(records(1))
        precondition(unobserved.commits == 0)
        print("PASS: shipping inbound merge failures, chunk aggregation, retry, version gate and cursor/anchor timing")
    }
}
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--emit", type=Path, help="Generate only; does not execute Swift")
    args = parser.parse_args()
    sources = {"format": format_source(), "inbound": inbound_source()}
    if args.emit:
        args.emit.mkdir(parents=True, exist_ok=True)
        for name, source in sources.items():
            (args.emit / f"{name}.swift").write_text(source, encoding="utf-8")
        print("Generated format/inbound harnesses and checked wiring; Swift tests NOT executed")
        return
    support = {
        "format": ["Agent/Backup/BackupFormat.swift"],
        "inbound": ["Agent/Sync/V2/PortableRecord.swift", "Agent/Sync/V2/SyncCoreHydrators.swift"],
    }
    with tempfile.TemporaryDirectory(prefix="minis-review-followup-") as temp:
        for name, source in sources.items():
            if name == "format":
                package = Path(temp) / "format-package"
                models = package / "Sources/BackupModels"
                tests = package / "Tests/FormatTests"
                models.mkdir(parents=True)
                tests.mkdir(parents=True)
                (package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "BackupFormatRegression", platforms: [.macOS(.v13)], targets: [
    .target(name: "BackupModels"),
    .testTarget(name: "FormatTests", dependencies: ["BackupModels"])
])
''', encoding="utf-8")
                (models / "BackupFormat.swift").write_text(read(support[name][0]), encoding="utf-8")
                (models / "Localization.swift").write_text(
                    'func AppLocalized(_ text: String) -> String { text }\n', encoding="utf-8"
                )
                (tests / "FormatTests.swift").write_text(source, encoding="utf-8")
                subprocess.run(["swift", "test", "--package-path", str(package)], check=True, timeout=180)
                continue
            test = Path(temp) / f"{name}.swift"
            test.write_text(source, encoding="utf-8")
            binary = Path(temp) / name
            subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library",
                            *[str(ROOT / p) for p in support[name]], str(test), "-o", str(binary)], check=True)
            subprocess.run([str(binary)], check=True, timeout=30)


if __name__ == "__main__":
    main()
