"""Compile real backup models and sync metadata; no app services or network."""
from pathlib import Path
import argparse
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def declaration(path, name):
    text = read(path)
    start = text.index("struct " + name + ":")
    end = text.index("\n}", start) + 2
    return text[start:end]


def source():
    # Check both initial and fallback prompts, not only the scope helper itself.
    loop = read("Agent/Chat/AIChatViewModel+AgentLoop.swift")
    assert "helperConfig?.parentSessionId ?? sessionId" not in loop
    assert loop.count("if let sid = capabilitySessionId,") == 4
    export = read("Agent/Backup/BackupExporter.swift")
    hydrate = read("Agent/Sync/V2/ChatStoreSyncHydrators.swift")
    assert "exportAgents(dataDir:" in export
    assert "capabilityOwnerJSON(for:" not in export
    assert hydrate.count("capabilityOwnerJSON(for:") == 2
    assert hydrate.count("restoreCapabilityOwner(") == 2
    assert "BotWorkspaceTransfer.apply(incoming" in read("Agent/Backup/BackupImporter+Categories.swift")
    declarations = [
        declaration("Shared/EnvVarStore.swift", "EnvVarBackupEntry"),
        declaration("Agent/Backup/BackupFormat.swift", "BackupSubAgentRecord"),
        declaration("Agent/Sync/V2/SyncedTypes.swift", "SyncedEnvVar"),
        declaration("Agent/Sync/V2/SyncedTypes.swift", "SyncedSubAgentV3"),
    ]
    return "import Foundation\n" + "\n".join(declarations) + r'''
enum UploadPolicy { static func allowsRecordType(_ type: String) -> Bool { true } }
enum TestFailure: Error { case expected }

@main struct CapabilityTransportTests {
    @MainActor static func main() async throws {
        let now = Date(timeIntervalSince1970: 100)
        let owner = "bot-id"
        let json = "{\"id\":\"bot-id\",\"name\":\"Reviewer\"}"
        let env = EnvVarBackupEntry(id: "env", key: "EXAMPLE", createdAt: now,
            note: "fixture", enabled: false, ownerBotId: owner)
        let envData = try JSONEncoder().encode(env)
        let restoredEnv = try JSONDecoder().decode(EnvVarBackupEntry.self, from: envData)
        precondition(restoredEnv == env)
        let agent = BackupSubAgentRecord(id: "agent", name: "Reviewer",
            subAgentDescription: "Review", instructions: "Check output", modelGroupId: nil,
            thinkingLevelOverride: nil, sortOrder: 0, updatedAt: now,
            ownerBotId: owner)
        let agentData = try JSONEncoder().encode(agent)
        let restoredAgent = try JSONDecoder().decode(BackupSubAgentRecord.self, from: agentData)
        precondition(restoredAgent.ownerBotId == owner)
        let registry = SyncableTypeRegistry.shared
        registry.register(SyncedEnvVar.self)
        registry.register(SyncedSubAgentV3.self)
        let syncedEnv = SyncedEnvVar(id: "env", key: "EXAMPLE", valueB64: "",
            note: "fixture", createdAt: now, updatedAt: now, ownerBotId: owner, ownerBotJSON: json)
        let syncedAgent = SyncedSubAgentV3(id: "agent", name: "Reviewer",
            subAgentDescription: "Review", instructions: "Check output", modelGroupId: nil,
            thinkingLevelOverride: nil, isBuiltIn: 0, sortOrder: 0, updatedAt: now,
            ownerBotId: owner, ownerBotJSON: json)
        let envMeta = registry.metadata(for: "EnvVarItem")!
        let agentMeta = registry.metadata(for: "SubAgentV3")!
        let envRecord = envMeta.buildPortable(syncedEnv)!
        let agentRecord = agentMeta.buildPortable(syncedAgent)!
        for record in [envRecord, agentRecord] {
            let wire = try JSONEncoder().encode(record)
            let decoded = try JSONDecoder().decode(PortableRecord.self, from: wire)
            precondition(decoded.fields["ownerBotJSON"] == .string(json))
            precondition(decoded.fields["ownerBotId"] == .string(owner))
            precondition(decoded.schemaVersion == 2)
        }
        var blankEnv = syncedEnv
        blankEnv.ownerBotJSON = nil
        let appliedEnv = envMeta.applyPortableToExisting(blankEnv, envRecord) as! SyncedEnvVar
        precondition(appliedEnv.ownerBotJSON == json)
        var blankAgent = syncedAgent
        blankAgent.ownerBotJSON = nil
        let appliedAgent = agentMeta.applyPortableToExisting(blankAgent, agentRecord) as! SyncedSubAgentV3
        precondition(appliedAgent.ownerBotJSON == json)
        blankEnv.ownerBotId = nil
        precondition(envMeta.buildPortable(blankEnv)!.fields["ownerBotJSON"] == .null)

        let hydrators = SyncCoreHydrators.shared
        hydrators.register(recordType: "EnvVarItem",
            builder: { _ in throw TestFailure.expected },
            merger: { _ in throw TestFailure.expected })
        do {
            _ = try await hydrators.buildPortable(recordType: "EnvVarItem", id: "env")
            preconditionFailure("A failed owner export must not become a missing row")
        } catch TestFailure.expected { }
        do {
            try await hydrators.mergeRemote(envRecord)
            preconditionFailure("A failed owner restore must not count as applied")
        } catch TestFailure.expected { }
        print("PASS: capability backup round trips, sync metadata and failure propagation")
    }
}
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--emit", type=Path, help="Generate Swift only; does not run tests")
    args = parser.parse_args()
    generated = source()
    if args.emit:
        args.emit.write_text(generated, encoding="utf-8")
        print("Generated transport test source; Swift tests NOT executed")
        return
    with tempfile.TemporaryDirectory(prefix="minis-capability-transport-") as temp:
        test = Path(temp) / "tests.swift"
        test.write_text(generated, encoding="utf-8")
        binary = Path(temp) / "tests"
        support = ["PortableRecord.swift", "Syncable.swift", "SyncableTypeRegistry.swift", "SyncCoreHydrators.swift"]
        subprocess.run(["swiftc", *[str(ROOT / "Agent/Sync/V2" / p) for p in support],
                        str(test), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True, timeout=30)


if __name__ == "__main__":
    main()
