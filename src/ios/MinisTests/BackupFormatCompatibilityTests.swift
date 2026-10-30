import XCTest
@testable import Minis

/// The v3 contract requires identity and category scope while tolerating
/// missing display metadata and unknown fields from same-major writers.
final class BackupFormatCompatibilityTests: XCTestCase {

    // MARK: - §2.2 rule 1 / rule 2 — version acceptance (review S3)

    func testFormatAcceptanceMatrix() {
        // Accepted: same prefix, same major.
        XCTAssertTrue(BackupImporter.isFormatSupported("minisbak/3"))
        XCTAssertTrue(BackupImporter.isFormatSupported("minisbak/3.1"))
        XCTAssertTrue(BackupImporter.isFormatSupported("minisbak/3.0.3"))

        // Refused: a different product that happens to use the same shape.
        // The pre-fix code ACCEPTED this — there was no prefix check at all.
        XCTAssertFalse(BackupImporter.isFormatSupported("otherformat/2"))
        // Refused: no prefix whatsoever. Also accepted pre-fix.
        XCTAssertFalse(BackupImporter.isFormatSupported("2"))
        // Both retired and future major versions are refused.
        XCTAssertFalse(BackupImporter.isFormatSupported("minisbak/2"))
        XCTAssertFalse(BackupImporter.isFormatSupported("minisbak/2.1"))
        XCTAssertFalse(BackupImporter.isFormatSupported("minisbak/1"))
        XCTAssertFalse(BackupImporter.isFormatSupported("minisbak/1.1"))
        XCTAssertFalse(BackupImporter.isFormatSupported("minisbak/4"))
        XCTAssertFalse(BackupImporter.isFormatSupported("minisbak/4.0"))
    }

    func testFormatAcceptanceRejectsMalformedStrings() {
        XCTAssertFalse(BackupImporter.isFormatSupported(""))
        XCTAssertFalse(BackupImporter.isFormatSupported("minisbak"))
        XCTAssertFalse(BackupImporter.isFormatSupported("minisbak/"))
        XCTAssertFalse(BackupImporter.isFormatSupported("minisbak/x"))
        XCTAssertFalse(BackupImporter.isFormatSupported("/2"))
        // Case matters: the prefix is compared literally.
        XCTAssertFalse(BackupImporter.isFormatSupported("MinisBak/2"))
        for malformed in ["minisbak/3.", "minisbak/3..1", "minisbak/3.x", "minisbak/3/1", "minisbak/+3"] {
            XCTAssertFalse(BackupImporter.isFormatSupported(malformed))
        }
    }

    /// Whatever this build writes must be something this build accepts.
    /// Catches a future bump of `BackupFormat.current` that forgets the reader.
    func testCurrentFormatIsSelfCompatible() {
        XCTAssertTrue(BackupImporter.isFormatSupported(BackupFormat.current))
    }

    // MARK: - §2.2 rule 2 — manifest tolerance (review S1)

    private let identity: [String: Any] = [
        "format": "minisbak/3", "created_at": "2026-08-14T00:00:00Z",
        "backup_id": "ABC123", "categories": [String: Any]()
    ]

    /// Ancillary-field fixtures always carry valid identity so a missing
    /// required field cannot mask the behavior under test (notably KDF errors).
    private func decode(_ json: String) throws -> BackupManifest {
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let manifest = identity.merging(fields) { _, incoming in incoming }
        return try decodeManifest(manifest)
    }

    private func decodeManifest(_ fields: [String: Any]) throws -> BackupManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupManifest.self, from: JSONSerialization.data(withJSONObject: fields))
    }

    func testIdentityAndScopeAreRequired() throws {
        XCTAssertThrowsError(try decodeManifest([:]))
        for key in identity.keys {
            var missing = identity
            missing.removeValue(forKey: key)
            XCTAssertThrowsError(try decodeManifest(missing), "manifest must require '\(key)'")
            var null = identity
            null[key] = NSNull()
            XCTAssertThrowsError(try decodeManifest(null), "manifest must reject null '\(key)'")
        }
    }

    func testMinimalIdentityDecodesWithMetadataDefaults() throws {
        let m = try decode("{}")
        XCTAssertEqual(m.format, BackupFormat.current)
        XCTAssertEqual(m.createdAt, ISO8601DateFormatter().date(from: "2026-08-14T00:00:00Z"))
        XCTAssertEqual(m.app.platform, "unknown")
        XCTAssertEqual(m.deviceName, "Unknown device")
        XCTAssertTrue(m.categories.isEmpty)
        XCTAssertNil(m.limits.maxFileBytes)
        XCTAssertEqual(m.limits.skippedFiles, 0)
        XCTAssertNil(m.encryption)
        XCTAssertTrue(m.integrity.isEmpty)
        XCTAssertNil(m.manifestMac)
        XCTAssertEqual(m.backupId, "ABC123")
        XCTAssertNil(m.snapshotAt)
    }

    /// A newer writer adding fields must not break an older reader.
    func testUnknownFieldsAreIgnored() throws {
        let m = try decode("""
        {"device_name":"iPhone",
         "future_field":{"nested":[1,2,3]},"another":"x"}
        """)
        XCTAssertEqual(m.deviceName, "iPhone")
        XCTAssertEqual(m.format, "minisbak/3")
    }

    /// §2.2 rule 2 turned into a test case directly: drop each optional key in
    /// turn from a complete manifest and assert the result still decodes.
    func testEveryOptionalFieldMayBeAbsent() throws {
        let full: [String: Any] = [
            "format": "minisbak/3",
            "created_at": "2026-08-14T00:00:00Z",
            "snapshot_at": "2026-08-14T00:00:00Z",
            "app": ["platform": "ios", "version": "1.13", "build": "42"],
            "device_name": "iPhone",
            "backup_id": "ABC123",
            "categories": ["chats": ["entries": 3, "bytes": 99, "encrypted": false]],
            "limits": ["max_file_bytes": 1024, "skipped_files": 1, "skipped_bytes": 2048],
            "integrity": ["manifest.json": "deadbeef"],
            "manifest_mac": "bWFj",
        ]
        for key in full.keys where identity[key] == nil {
            var reduced = full
            reduced.removeValue(forKey: key)
            let data = try JSONSerialization.data(withJSONObject: reduced)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            XCTAssertNoThrow(try decoder.decode(BackupManifest.self, from: data),
                             "manifest must still decode without '\(key)'")
        }
    }

    /// Nested optional counters get the same treatment — S1's concrete trigger
    /// was a missing `limits.skipped_files`.
    func testNestedOptionalCountersMayBeAbsent() throws {
        let m = try decode("""
        {"limits":{},
         "categories":{"chats":{},"providers":{"entries":2}},
         "app":{}}
        """)
        XCTAssertEqual(m.limits.skippedFiles, 0)
        XCTAssertEqual(m.limits.skippedBytes, 0)
        XCTAssertNil(m.limits.maxFileBytes)
        XCTAssertEqual(m.categories["chats"]?.entries, 0)
        XCTAssertEqual(m.categories["chats"]?.encrypted, false)
        XCTAssertEqual(m.categories["providers"]?.entries, 2)
        XCTAssertNil(m.categories["providers"]?.includesCredentials)
        XCTAssertEqual(m.app.version, "?")
    }

    /// Snake_case keys are part of the wire format. A rename to camelCase would
    /// silently produce defaults instead of failing, which is exactly the class
    /// of bug this file exists to stop.
    func testSnakeCaseKeysAreTheWireFormat() throws {
        let m = try decode("""
        {"device_name":"A","backup_id":"B",
         "limits":{"max_file_bytes":7,"skipped_files":8,"skipped_bytes":9},
         "categories":{"providers":{"entries":1,"includes_credentials":true}},
         "manifest_mac":"TUFD"}
        """)
        XCTAssertEqual(m.deviceName, "A")
        XCTAssertEqual(m.backupId, "B")
        XCTAssertEqual(m.limits.maxFileBytes, 7)
        XCTAssertEqual(m.limits.skippedFiles, 8)
        XCTAssertEqual(m.limits.skippedBytes, 9)
        XCTAssertEqual(m.categories["providers"]?.includesCredentials, true)
        XCTAssertEqual(m.manifestMac, "TUFD")
    }

    // MARK: - The deliberate exception: kdf.alg / kdf.salt stay required

    /// Tolerance stops at the KDF. Defaulting either field would derive the
    /// wrong key and surface to the user as "wrong passphrase" — sending them
    /// to look for a password problem that doesn't exist. Assert the constraint
    /// is actually enforced rather than merely documented.
    func testKDFAlgAndSaltAreRequired() {
        let base = """
        {"encryption":{"scheme":"minisbak-enc/1",
         "verifier":"dg==","kdf":{%@}}}
        """
        func manifest(_ kdf: String) throws -> BackupManifest {
            try decode(base.replacingOccurrences(of: "%@", with: kdf))
        }

        // Both present -> decodes.
        XCTAssertNoThrow(try manifest("\"alg\":\"pbkdf2-hmac-sha256\",\"salt\":\"c2FsdA==\""))

        // `salt` missing -> must throw.
        XCTAssertThrowsError(try manifest("\"alg\":\"pbkdf2-hmac-sha256\""))

        // `alg` missing -> must throw.
        XCTAssertThrowsError(try manifest("\"salt\":\"c2FsdA==\""))

        // Both missing -> must throw.
        XCTAssertThrowsError(try manifest(""))
    }

    /// The optional Argon2 parameters may be absent even though alg/salt aren't.
    func testKDFOptionalParametersMayBeAbsent() throws {
        let m = try decode("""
        {"encryption":{"scheme":"minisbak-enc/1",
         "verifier":"dg==","kdf":{"alg":"pbkdf2-hmac-sha256","salt":"c2FsdA==",
         "iterations":600000}}}
        """)
        let kdf = try XCTUnwrap(m.encryption?.kdf)
        XCTAssertEqual(kdf.alg, "pbkdf2-hmac-sha256")
        XCTAssertEqual(kdf.iterations, 600_000)
        XCTAssertNil(kdf.mKib)
        XCTAssertNil(kdf.t)
        XCTAssertNil(kdf.p)
    }

    // MARK: - Round-trip

    /// Encode then decode: the keys written must be the keys read. Catches a
    /// CodingKeys change on one side only.
    func testManifestRoundTripsThroughItsOwnEncoder() throws {
        let original = BackupManifest(
            createdAt: Date(timeIntervalSince1970: 1_760_000_000),
            app: .init(platform: "ios", version: "1.13", build: "7"),
            deviceName: "Test Device",
            backupId: "ID-1",
            categories: ["chats": .init(entries: 5, bytes: 512, encrypted: true,
                                        messages: 3, files: 2),
                         "providers": .init(entries: 1, bytes: 64, encrypted: true,
                                            includesCredentials: false)],
            limits: .init(maxFileBytes: 4096, skippedFiles: 2, skippedBytes: 9000),
            encryption: nil,
            integrity: ["data/sessions.jsonl": "abc"],
            manifestMac: nil)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(BackupManifest.self,
                                      from: try encoder.encode(original))

        XCTAssertEqual(back.deviceName, original.deviceName)
        XCTAssertEqual(back.backupId, original.backupId)
        XCTAssertEqual(back.format, original.format)
        XCTAssertEqual(back.createdAt.timeIntervalSince1970,
                       original.createdAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(back.limits.maxFileBytes, 4096)
        XCTAssertEqual(back.limits.skippedFiles, 2)
        XCTAssertEqual(back.limits.skippedBytes, 9000)
        XCTAssertEqual(back.categories["chats"]?.messages, 3)
        XCTAssertEqual(back.categories["chats"]?.files, 2)
        XCTAssertEqual(back.categories["providers"]?.includesCredentials, false)
        XCTAssertEqual(back.integrity["data/sessions.jsonl"], "abc")
    }
}
