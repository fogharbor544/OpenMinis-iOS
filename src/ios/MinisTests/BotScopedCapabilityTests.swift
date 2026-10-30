import XCTest
@testable import Minis

/// Bot-scoped sub agents and environment variables: stored data from before
/// the field existed stays global, a private definition is visible only to its
/// Bot, and the built-in can never be scoped away from the others.
final class BotScopedCapabilityTests: XCTestCase {

    func testSubAgentWithoutOwnerFieldDecodesAsGlobal() throws {
        let legacy = #"[{"id":"a","name":"Reviewer","description":"d","instructions":"","isBuiltIn":false,"sortOrder":1,"updatedAt":700000000}]"#
        let decoded = try JSONDecoder().decode([SubAgentDefinition].self, from: Data(legacy.utf8))
        XCTAssertNil(decoded[0].ownerBotId)
        XCTAssertTrue(decoded[0].isAvailable(toBot: "any"))
        XCTAssertTrue(decoded[0].isAvailable(toBot: nil))
    }

    func testPrivateSubAgentIsOnlyAvailableToItsBot() {
        let def = SubAgentDefinition(name: "Docs", description: "d", ownerBotId: "bot-a")
        XCTAssertTrue(def.isAvailable(toBot: "bot-a"))
        XCTAssertFalse(def.isAvailable(toBot: "bot-b"))
        XCTAssertFalse(def.isAvailable(toBot: nil), "a non-Bot conversation does not see private definitions")
    }

    func testBuiltInIsNeverScopedToABot() {
        var builtIn = SubAgentDefinition.makeBuiltIn()
        builtIn.ownerBotId = "bot-a"
        let out = SubAgentRoster.normalize([builtIn])
        XCTAssertNil(out[0].ownerBotId, "every unnamed delegation falls back to the built-in")
    }

    func testOwnerSurvivesNormalizeAndMerge() {
        let local = SubAgentDefinition(id: "x", name: "Docs", description: "d", ownerBotId: "bot-a")
        let merged = SubAgentRoster.merge(local: [local], remote: [])
        XCTAssertEqual(merged.first { $0.id == "x" }?.ownerBotId, "bot-a")
    }

    func testEnvVarEntryWithoutOwnerDecodesAsGlobal() throws {
        let legacy = #"[{"id":"A","key":"API_KEY","createdAt":700000000,"note":""}]"#
        let entry = try JSONDecoder().decode([EnvVarEntry].self, from: Data(legacy.utf8))[0]
        XCTAssertNil(entry.ownerBotId)
        XCTAssertTrue(entry.isAvailable(toBot: "bot-a"))
    }

    func testPrivateEnvVarRoundTripsAndScopes() throws {
        let entry = EnvVarEntry(key: "CUE_API_KEY", ownerBotId: "bot-a")
        let back = try JSONDecoder().decode(EnvVarEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(back.ownerBotId, "bot-a")
        XCTAssertTrue(back.isAvailable(toBot: "bot-a"))
        XCTAssertFalse(back.isAvailable(toBot: "bot-b"))
        XCTAssertFalse(back.isAvailable(toBot: nil), "the global terminal only gets global variables")
    }

    func testBackupEntryWithoutOwnerDecodesAsGlobal() throws {
        let legacy = #"{"id":"A","key":"API_KEY","createdAt":700000000,"note":"","enabled":true}"#
        let entry = try JSONDecoder().decode(EnvVarBackupEntry.self, from: Data(legacy.utf8))
        XCTAssertNil(entry.ownerBotId)
    }
}
