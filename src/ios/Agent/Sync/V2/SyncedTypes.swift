import Foundation

/// Mirror types used as the "syncable shape" of local models. Kept as
/// separate structs (not Syncable conformance directly on the local
/// models) so v2 sync metadata stays decoupled from the rest of the app —
/// adding/removing sync fields doesn't ripple into ChatStore, etc.
///
/// Each Synced* type exposes a `from(...)` builder that converts a local
/// model into its synced shape. The reverse direction (Synced* → local
/// SQLite write) lives in SyncCore (P3) where the merge policy executes.

// MARK: - SyncedSession

struct SyncedSession: Syncable {
    var id: String
    var title: String?
    var category: String?
    var modelId: String
    var createdAt: Date
    var updatedAt: Date
    var memoryEnabled: Int          // 0/1
    var modelBinding: String?
    var pinnedAt: Date?
    var folderId: String?
    // [T-p1-delegate-task] Child-session linkage; optional, no version bump
    // (same shape as folderId). Old builds ignore it and show the child as a
    // normal session titled "Agent · …" — accepted build-skew.
    var parentSessionId: String?
    var parentToolUseId: String?

    static let syncMetadata: SyncTypeMetadata<SyncedSession> = {
        typealias F = FieldDescriptor<SyncedSession>
        return SyncTypeMetadata<SyncedSession>(
            recordType: "SessionV2",
            idKeyPath: \SyncedSession.id,
            scope: .perObject(\SyncedSession.id),
            fields: [
                F.string("sessionId",        \SyncedSession.id),
                F.optionalString("title",    \SyncedSession.title),
                F.optionalString("category", \SyncedSession.category),
                F.string("modelId",          \SyncedSession.modelId),
                F.date("createdAt",          \SyncedSession.createdAt),
                F.date("updatedAt",          \SyncedSession.updatedAt),
                F.int("memoryEnabled",       \SyncedSession.memoryEnabled),
                F.optionalString("modelBinding", \SyncedSession.modelBinding),
                F.optionalDate("pinnedAt",   \SyncedSession.pinnedAt),
                // Optional field added the same way pinnedAt was (no version
                // bump): old devices ignore the unknown CKRecord field on read
                // and omit it on write, both of which decode as nil here.
                F.optionalString("folderId", \SyncedSession.folderId),
                F.optionalString("parentSessionId", \SyncedSession.parentSessionId),
                F.optionalString("parentToolUseId", \SyncedSession.parentToolUseId),
            ],
            conflictPolicy: .lastWriteWinsByField(\SyncedSession.updatedAt),
            version: 1
        )
    }()

    static func from(_ s: ChatSession, memoryEnabled: Bool, modelBinding: String?) -> SyncedSession {
        SyncedSession(
            id: s.id,
            title: s.title,
            category: s.category,
            modelId: s.modelId,
            createdAt: s.createdAt,
            updatedAt: s.updatedAt,
            memoryEnabled: memoryEnabled ? 1 : 0,
            modelBinding: modelBinding,
            pinnedAt: s.pinnedAt,
            folderId: s.folderId,
            parentSessionId: s.parentSessionId,
            parentToolUseId: s.parentToolUseId
        )
    }
}

// MARK: - SyncedMessage

struct SyncedMessage: Syncable {
    var id: String
    var sessionId: String
    var role: String
    var partsJson: String           // JSON-encoded [ContentPart]
    var tokenUsageJson: String?
    var reasoningContent: String?
    var streamInterruptCount: Int
    /// Best-effort hint only. Receivers MUST derive their own sort_order from
    /// (created_at, id) rank — see `ChatStore.mergeRemoteMessage`. Trusting
    /// the wire integer leaks ordering bugs across devices with differing
    /// message counts.
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    /// [T-token-attribution-snapshot] Which model actually produced this
    /// message. Optional so a device on an older build — which sends none of
    /// these — still decodes: `optionalString` returns nil for a missing key
    /// rather than throwing, so no protocol version bump is needed.
    ///
    /// A receiver must treat nil as "no information", never as "empty": see the
    /// COALESCE guards in `ChatStore.mergeRemoteMessage`, without which an
    /// older device echoing a message back would wipe a newer device's
    /// correctly-recorded attribution.
    var modelId: String?
    var modelDisplayName: String?
    var providerType: String?
    var providerInstanceId: String?

    static let syncMetadata: SyncTypeMetadata<SyncedMessage> = {
        typealias F = FieldDescriptor<SyncedMessage>
        return SyncTypeMetadata<SyncedMessage>(
            recordType: "MessageV2",
            idKeyPath: \SyncedMessage.id,
            scope: .perParent(parentType: "SessionV2", \SyncedMessage.sessionId),
            fields: [
                F.string("messageId",                 \SyncedMessage.id),
                F.string("sessionId",                 \SyncedMessage.sessionId),
                F.string("role",                      \SyncedMessage.role),
                F.string("partsJson",                 \SyncedMessage.partsJson),
                F.optionalString("tokenUsageJson",    \SyncedMessage.tokenUsageJson),
                F.optionalString("reasoningContent",  \SyncedMessage.reasoningContent),
                F.int("streamInterruptCount",         \SyncedMessage.streamInterruptCount),
                F.int("sortOrder",                    \SyncedMessage.sortOrder),
                F.date("createdAt",                   \SyncedMessage.createdAt),
                F.date("updatedAt",                   \SyncedMessage.updatedAt),
                F.optionalString("modelId",           \SyncedMessage.modelId),
                F.optionalString("modelDisplayName",  \SyncedMessage.modelDisplayName),
                F.optionalString("providerType",      \SyncedMessage.providerType),
                F.optionalString("providerInstanceId", \SyncedMessage.providerInstanceId),
            ],
            conflictPolicy: .lastWriteWinsByField(\SyncedMessage.updatedAt),
            version: 1
        )
    }()

    static func from(_ m: RawMessage, updatedAt: Date) -> SyncedMessage {
        let partsJson: String = (try? String(data: JSONEncoder().encode(m.parts), encoding: .utf8)) ?? "[]"
        let tokenUsageJson: String? = m.tokenUsage.flatMap {
            (try? JSONEncoder().encode($0)).flatMap { String(data: $0, encoding: .utf8) }
        }
        return SyncedMessage(
            id: m.id,
            sessionId: m.sessionId,
            role: m.role.rawValue,
            partsJson: partsJson,
            tokenUsageJson: tokenUsageJson,
            reasoningContent: m.reasoningContent,
            streamInterruptCount: m.streamInterruptCount,
            sortOrder: m.sortOrder,
            createdAt: m.createdAt,
            updatedAt: updatedAt,
            modelId: m.modelId,
            modelDisplayName: m.modelDisplayName,
            providerType: m.providerType,
            providerInstanceId: m.providerInstanceId
        )
    }
}

// MARK: - SyncedCompactMarker

struct SyncedCompactMarker: Syncable {
    var id: String
    var sessionId: String
    var summary: String
    var firstKeptSortOrder: Int
    var compactedCount: Int
    var createdAt: Date
    var uiBoundarySortOrder: Int?
    var boundaryMessageId: String?
    var firstKeptMessageId: String?
    var lastCompactedMessageId: String?
    var version: Int

    static let syncMetadata: SyncTypeMetadata<SyncedCompactMarker> = {
        typealias F = FieldDescriptor<SyncedCompactMarker>
        return SyncTypeMetadata<SyncedCompactMarker>(
            recordType: "CompactMarkerV2",
            idKeyPath: \SyncedCompactMarker.id,
            scope: .perParent(parentType: "SessionV2", \SyncedCompactMarker.sessionId),
            fields: [
                F.string("markerId",                     \SyncedCompactMarker.id),
                F.string("sessionId",                    \SyncedCompactMarker.sessionId),
                F.string("summary",                      \SyncedCompactMarker.summary),
                F.int("firstKeptSortOrder",              \SyncedCompactMarker.firstKeptSortOrder),
                F.int("compactedCount",                  \SyncedCompactMarker.compactedCount),
                F.date("createdAt",                      \SyncedCompactMarker.createdAt),
                F.optionalInt("uiBoundarySortOrder",     \SyncedCompactMarker.uiBoundarySortOrder),
                F.optionalString("boundaryMessageId",    \SyncedCompactMarker.boundaryMessageId),
                F.optionalString("firstKeptMessageId",   \SyncedCompactMarker.firstKeptMessageId),
                F.optionalString("lastCompactedMessageId", \SyncedCompactMarker.lastCompactedMessageId),
                F.int("markerVersion",                   \SyncedCompactMarker.version),
            ],
            conflictPolicy: .alwaysAccept,
            version: 1
        )
    }()

    static func from(_ m: CompactMarker) -> SyncedCompactMarker {
        SyncedCompactMarker(
            id: m.id,
            sessionId: m.sessionId,
            summary: m.summary,
            firstKeptSortOrder: m.firstKeptSortOrder,
            compactedCount: m.compactedCount,
            createdAt: m.createdAt,
            uiBoundarySortOrder: m.uiBoundarySortOrder,
            boundaryMessageId: m.boundaryMessageId,
            firstKeptMessageId: m.firstKeptMessageId,
            lastCompactedMessageId: m.lastCompactedMessageId,
            version: m.version
        )
    }
}

// MARK: - SyncedSessionFile

struct SyncedSessionFile: Syncable {
    var sessionId: String
    var relativePath: String
    var fileSize: Int
    var mimeType: String?
    var compositeKey: String { "\(sessionId):\(relativePath)" }
    var updatedAt: Date

    /// Local file URL referenced by this record. Not transmitted directly
    /// — transports surface it through PortableAsset.
    var fileURL: URL

    static let syncMetadata: SyncTypeMetadata<SyncedSessionFile> = {
        typealias F = FieldDescriptor<SyncedSessionFile>
        return SyncTypeMetadata<SyncedSessionFile>(
            recordType: "SessionFileV2",
            idKeyPath: \SyncedSessionFile.compositeKey,
            scope: .perParent(parentType: "SessionV2", \SyncedSessionFile.sessionId),
            fields: [
                F.string("sessionId",        \SyncedSessionFile.sessionId),
                F.string("relativePath",     \SyncedSessionFile.relativePath),
                F.int("fileSize",            \SyncedSessionFile.fileSize),
                F.optionalString("mimeType", \SyncedSessionFile.mimeType),
                F.date("updatedAt",          \SyncedSessionFile.updatedAt),
            ],
            conflictPolicy: .lastWriteWinsByServerEtag,
            version: 1
        )
    }()
}

// MARK: - SyncedSkill

struct SyncedSkill: Syncable {
    var id: String
    var name: String
    var description: String
    var version: String
    var importSource: String
    var isEnabled: Int
    var installedAt: Date
    var updatedAt: Date
    var bodyText: String?
    /// Local URL of the bundled ZIP (SKILL.md + scripts/ + references/ + assets/).
    /// Transmitted by the transport as a PortableAsset.
    var bundleZipURL: URL?

    static let syncMetadata: SyncTypeMetadata<SyncedSkill> = {
        typealias F = FieldDescriptor<SyncedSkill>
        return SyncTypeMetadata<SyncedSkill>(
            recordType: "SkillV2",
            idKeyPath: \SyncedSkill.id,
            scope: .global,
            fields: [
                F.string("skillId",           \SyncedSkill.id),
                F.string("name",              \SyncedSkill.name),
                F.string("description",       \SyncedSkill.description),
                F.string("version",           \SyncedSkill.version),
                F.string("importSource",      \SyncedSkill.importSource),
                F.int("isEnabled",            \SyncedSkill.isEnabled),
                F.date("installedAt",         \SyncedSkill.installedAt),
                F.date("updatedAt",           \SyncedSkill.updatedAt),
                F.optionalString("bodyText",  \SyncedSkill.bodyText),
            ],
            conflictPolicy: .lastWriteWinsByField(\SyncedSkill.updatedAt),
            version: 1
        )
    }()
}

struct SyncedMCPServer: Syncable {
    var id: String          // server name — also the CK recordName
    var entryJson: String   // full ServerEntry JSON, verbatim round-trip
    var createdAt: Date
    var updatedAt: Date     // per-entry LWW clock (servers.json `updatedAt`)

    static let syncMetadata: SyncTypeMetadata<SyncedMCPServer> = {
        typealias F = FieldDescriptor<SyncedMCPServer>
        return SyncTypeMetadata<SyncedMCPServer>(
            recordType: "MCPServerItem",
            idKeyPath: \SyncedMCPServer.id,
            scope: .global,
            fields: [
                F.string("serverName", \SyncedMCPServer.id),
                F.string("entryJson",  \SyncedMCPServer.entryJson),
                F.date("createdAt",    \SyncedMCPServer.createdAt),
                F.date("updatedAt",    \SyncedMCPServer.updatedAt),
            ],
            conflictPolicy: .lastWriteWinsByField(\SyncedMCPServer.updatedAt),
            version: 1
        )
    }()
}


struct SyncedProviderInstanceV3: Syncable {
    var id: String                       // = ProviderInstance.id (UUID)
    var label: String
    var providerType: String             // ProviderType.rawValue
    var credentialType: String?          // ProviderCredential.rawValue
    var customBaseURL: String?
    /// 0/1 — keeps wire shape uniform with existing booleans on
    /// SyncedSession.memoryEnabled and SyncedSkill.isEnabled.
    var appendV1Suffix: Int
    var imageEndpointMode: String?       // ImageEndpointMode.rawValue
    var imageEndpointResolved: String?
    var isEnabled: Int                   // 0/1
    var sortOrder: Int
    var secretBlob: String?              // base64-wrapped Keychain secret; nil = no secret yet
    var secretKind: String?              // 'apiKey' | 'manual-oauth-token' | 'oauth-token' | nil
    var secretUpdatedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var extrasJson: String?              // forward-compat envelope
    var customUserAgent: String?         // per-provider outbound UA override; nil = default
    /// [T-ios-azure-openai] 0/1 — Azure OpenAI mode (api-key auth + Azure URL).
    /// Older records / older builds lack this CloudKit field; it decodes to 0
    /// (off), so a peer that never heard of Azure simply treats the instance as
    /// a normal OpenAI/Responses instance. New value rides extrasJson-free on its
    /// own field; LWW by updatedAt as with every other field.
    var azureMode: Int                   // 0/1

    static let syncMetadata: SyncTypeMetadata<SyncedProviderInstanceV3> = {
        typealias F = FieldDescriptor<SyncedProviderInstanceV3>
        return SyncTypeMetadata<SyncedProviderInstanceV3>(
            recordType: "ProviderInstanceV3",
            idKeyPath: \SyncedProviderInstanceV3.id,
            scope: .global,
            fields: [
                F.string("label",                  \SyncedProviderInstanceV3.label),
                F.string("providerType",           \SyncedProviderInstanceV3.providerType),
                F.optionalString("credentialType", \SyncedProviderInstanceV3.credentialType),
                F.optionalString("customBaseURL",  \SyncedProviderInstanceV3.customBaseURL),
                F.int("appendV1Suffix",            \SyncedProviderInstanceV3.appendV1Suffix),
                F.optionalString("imageEndpointMode",     \SyncedProviderInstanceV3.imageEndpointMode),
                F.optionalString("imageEndpointResolved", \SyncedProviderInstanceV3.imageEndpointResolved),
                F.int("isEnabled",                 \SyncedProviderInstanceV3.isEnabled),
                F.int("sortOrder",                 \SyncedProviderInstanceV3.sortOrder),
                F.optionalString("secretBlob",     \SyncedProviderInstanceV3.secretBlob),
                F.optionalString("secretKind",     \SyncedProviderInstanceV3.secretKind),
                F.optionalDate("secretUpdatedAt",  \SyncedProviderInstanceV3.secretUpdatedAt),
                F.date("createdAt",                \SyncedProviderInstanceV3.createdAt),
                F.date("updatedAt",                \SyncedProviderInstanceV3.updatedAt),
                F.optionalString("extrasJson",     \SyncedProviderInstanceV3.extrasJson),
                F.optionalString("customUserAgent", \SyncedProviderInstanceV3.customUserAgent),
                F.int("azureMode",                 \SyncedProviderInstanceV3.azureMode),
            ],
            conflictPolicy: .lastWriteWinsByField(\SyncedProviderInstanceV3.updatedAt),
            version: 1
        )
    }()
}

struct SyncedProviderModelEntryV3: Syncable {
    var id: String
    var providerInstanceId: String
    var baseModelJson: String            // LLMModel JSON (contains modelId)
    var overridesJson: String?           // ModelOverrides JSON; nil if no overrides
    var isCustom: Int                    // 0/1
    var isHidden: Int                    // 0/1
    var userModifiedAt: Date?
    var sortOrder: Int
    var updatedAt: Date
    var extrasJson: String?

    static let syncMetadata: SyncTypeMetadata<SyncedProviderModelEntryV3> = {
        typealias F = FieldDescriptor<SyncedProviderModelEntryV3>
        return SyncTypeMetadata<SyncedProviderModelEntryV3>(
            recordType: "ProviderModelEntryV3",
            idKeyPath: \SyncedProviderModelEntryV3.id,
            scope: .global,
            fields: [
                F.string("providerInstanceId",  \SyncedProviderModelEntryV3.providerInstanceId),
                F.string("baseModelJson",       \SyncedProviderModelEntryV3.baseModelJson),
                F.optionalString("overridesJson", \SyncedProviderModelEntryV3.overridesJson),
                F.int("isCustom",               \SyncedProviderModelEntryV3.isCustom),
                F.int("isHidden",               \SyncedProviderModelEntryV3.isHidden),
                F.optionalDate("userModifiedAt", \SyncedProviderModelEntryV3.userModifiedAt),
                F.int("sortOrder",              \SyncedProviderModelEntryV3.sortOrder),
                F.date("updatedAt",             \SyncedProviderModelEntryV3.updatedAt),
                F.optionalString("extrasJson",  \SyncedProviderModelEntryV3.extrasJson),
            ],
            conflictPolicy: .lastWriteWinsByField(\SyncedProviderModelEntryV3.updatedAt),
            version: 1
        )
    }()
}

struct SyncedProviderModelGroupV3: Syncable {
    var id: String                       // = ModelGroup.id (UUID)
    var name: String
    var strategy: String                 // RoutingStrategy.rawValue
    var fallbackStrategy: String         // FallbackStrategy.rawValue
    var defaultThinkingLevel: String?    // ThinkingLevel.rawValue
    var contextLimitTokens: Int?
    var contextLimitRemembered: Int?     // = ModelGroup.lastContextLimitTokens
    var memberEntryIdsJson: String       // JSON array, ordered
    var sortOrder: Int
    var updatedAt: Date
    var extrasJson: String?
    /// [T-icloud-provider-sync-consistency] JSON object {entryId: removedAtEpoch}.
    /// Member-removal tombstones; travels with the record so every device can
    /// honour a removal across the UNION merge. optionalString (defaults "{}"
    /// for records from pre-v2 builds, which simply never removed members).
    var removedMembersJson: String?

    static let syncMetadata: SyncTypeMetadata<SyncedProviderModelGroupV3> = {
        typealias F = FieldDescriptor<SyncedProviderModelGroupV3>
        return SyncTypeMetadata<SyncedProviderModelGroupV3>(
            recordType: "ProviderModelGroupV3",
            idKeyPath: \SyncedProviderModelGroupV3.id,
            scope: .global,
            fields: [
                F.string("name",                 \SyncedProviderModelGroupV3.name),
                F.string("strategy",             \SyncedProviderModelGroupV3.strategy),
                F.string("fallbackStrategy",     \SyncedProviderModelGroupV3.fallbackStrategy),
                F.optionalString("defaultThinkingLevel", \SyncedProviderModelGroupV3.defaultThinkingLevel),
                F.optionalInt("contextLimitTokens",      \SyncedProviderModelGroupV3.contextLimitTokens),
                F.optionalInt("contextLimitRemembered",  \SyncedProviderModelGroupV3.contextLimitRemembered),
                F.string("memberEntryIdsJson",   \SyncedProviderModelGroupV3.memberEntryIdsJson),
                F.int("sortOrder",               \SyncedProviderModelGroupV3.sortOrder),
                F.date("updatedAt",              \SyncedProviderModelGroupV3.updatedAt),
                F.optionalString("extrasJson",   \SyncedProviderModelGroupV3.extrasJson),
                F.optionalString("removedMembersJson", \SyncedProviderModelGroupV3.removedMembersJson),
            ],
            conflictPolicy: .lastWriteWinsByField(\SyncedProviderModelGroupV3.updatedAt),
            version: 1
        )
    }()
}

/// [T-icloud-thinking-rules-sync] One USER-AUTHORED thinking rule.
///
/// Built-in rules are deliberately absent from this type. They are code constants
/// recomputed per request on every device, are never persisted (`is_builtin = 0` is
/// hardcoded on every write path), and must never travel over the wire — a built-in
/// arriving as a record would become an undeletable duplicate on the receiver.
///
/// `wireFormatJson` is carried as an OPAQUE STRING, not a decoded enum. This is the
/// forward-compatibility guarantee: a rule authored on a newer build using a
/// `wire_format.kind` this build has never seen round-trips byte-for-byte instead of
/// being dropped or coerced into a wrong shape. Decoding happens only at the point of
/// use (`ProviderConfigDB.loadThinkingRules`), which already skips an unreadable row
/// individually rather than failing the whole read.
struct SyncedProviderThinkingRuleV3: Syncable {
    var id: String                  // rule UUID (custom rules only)
    var instanceId: String          // owning ProviderInstance UUID
    var sortOrder: Int              // position = priority; first match wins
    var scopeKind: String           // "allModels" | "modelPattern"
    var scopePattern: String?       // non-nil only for .modelPattern
    var wireFormatJson: String      // opaque {"kind":…} payload — see above
    var echoField: String?          // ReasoningEchoPolicy.fieldName
    var echoTiming: String?         // "everyTurn" | "afterToolUseOnly" | "never"
    var label: String
    var createdAt: Date
    var updatedAt: Date

    static let syncMetadata: SyncTypeMetadata<SyncedProviderThinkingRuleV3> = {
        typealias F = FieldDescriptor<SyncedProviderThinkingRuleV3>
        return SyncTypeMetadata<SyncedProviderThinkingRuleV3>(
            recordType: "ProviderThinkingRuleV3",
            idKeyPath: \SyncedProviderThinkingRuleV3.id,
            scope: .global,
            fields: [
                F.string("instanceId",           \SyncedProviderThinkingRuleV3.instanceId),
                F.int("sortOrder",               \SyncedProviderThinkingRuleV3.sortOrder),
                F.string("scopeKind",            \SyncedProviderThinkingRuleV3.scopeKind),
                F.optionalString("scopePattern", \SyncedProviderThinkingRuleV3.scopePattern),
                F.string("wireFormatJson",       \SyncedProviderThinkingRuleV3.wireFormatJson),
                F.optionalString("echoField",    \SyncedProviderThinkingRuleV3.echoField),
                F.optionalString("echoTiming",   \SyncedProviderThinkingRuleV3.echoTiming),
                F.string("label",                \SyncedProviderThinkingRuleV3.label),
                F.date("createdAt",              \SyncedProviderThinkingRuleV3.createdAt),
                F.date("updatedAt",              \SyncedProviderThinkingRuleV3.updatedAt),
            ],
            conflictPolicy: .lastWriteWinsByField(\SyncedProviderThinkingRuleV3.updatedAt),
            version: 1
        )
    }()
}

/// [T-subagent-own-store] One CK record per sub agent definition.
///
/// Per-record rather than whole-roster so two devices editing different agents
/// merge as a natural union instead of one overwriting the other — the same
/// reason EnvVarItem replaced the whole-file EnvVarV2.
///
/// `sortOrder` rides on each record because it is disclosure order in the
/// roster the model reads, i.e. real content, and a single record cannot
/// express "the list moved" — a reorder therefore pushes one upsert per id.
///
/// `modelGroupId` is the one field pointing into provider-land. It is a plain
/// foreign key and is synced verbatim; a group that does not exist on the
/// receiving device resolves to "model chooses", which is the same fallback a
/// locally-deleted group produces.
struct SyncedSubAgentV3: Syncable {
    var id: String                  // definition UUID (or SubAgentDefinition.builtInId)
    var name: String
    var subAgentDescription: String // `description` is taken on Syncable conformers
    var instructions: String
    var modelGroupId: String?
    /// [T-subagent-thinking-override] ThinkingLevel raw value, nil = not set.
    /// `optionalString`, so a peer on an older build that sends no such key
    /// decodes as nil rather than throwing — no protocol version bump needed.
    var thinkingLevelOverride: String?
    /// 0/1 rather than Bool: the sync framework's FieldDescriptor offers
    /// string / int / date only, and adding a bool descriptor for one field
    /// would change shared infrastructure for no behavioural gain.
    var isBuiltIn: Int
    var sortOrder: Int
    var updatedAt: Date

    static let syncMetadata: SyncTypeMetadata<SyncedSubAgentV3> = {
        typealias F = FieldDescriptor<SyncedSubAgentV3>
        return SyncTypeMetadata<SyncedSubAgentV3>(
            recordType: "SubAgentV3",
            idKeyPath: \SyncedSubAgentV3.id,
            scope: .global,
            fields: [
                F.string("name",                 \SyncedSubAgentV3.name),
                F.string("description",          \SyncedSubAgentV3.subAgentDescription),
                F.string("instructions",         \SyncedSubAgentV3.instructions),
                F.optionalString("modelGroupId", \SyncedSubAgentV3.modelGroupId),
                F.optionalString("thinkingLevelOverride", \SyncedSubAgentV3.thinkingLevelOverride),
                F.int("isBuiltIn",               \SyncedSubAgentV3.isBuiltIn),
                F.int("sortOrder",               \SyncedSubAgentV3.sortOrder),
                F.date("updatedAt",              \SyncedSubAgentV3.updatedAt),
            ],
            conflictPolicy: .lastWriteWinsByField(\SyncedSubAgentV3.updatedAt),
            version: 1
        )
    }()
}

struct SyncedEnvVar: Syncable {
    var id: String         // EnvVarEntry.id (UUID) — also CK recordName
    var key: String        // variable name, e.g. "API_KEY"
    var valueB64: String   // base64(value); empty for "no value yet"
    var note: String       // human description; "" when omitted
    var createdAt: Date
    var updatedAt: Date

    static let syncMetadata: SyncTypeMetadata<SyncedEnvVar> = {
        typealias F = FieldDescriptor<SyncedEnvVar>
        return SyncTypeMetadata<SyncedEnvVar>(
            recordType: "EnvVarItem",
            idKeyPath: \SyncedEnvVar.id,
            scope: .global,
            fields: [
                F.string("entryId",   \SyncedEnvVar.id),
                F.string("key",       \SyncedEnvVar.key),
                F.string("valueB64",  \SyncedEnvVar.valueB64),
                F.string("note",      \SyncedEnvVar.note),
                F.date("createdAt",   \SyncedEnvVar.createdAt),
                F.date("updatedAt",   \SyncedEnvVar.updatedAt),
            ],
            conflictPolicy: .lastWriteWinsByField(\SyncedEnvVar.updatedAt),
            version: 1
        )
    }()
}

// MARK: - SyncedEnvVarState [T-envvar-disable]
//
// A variable's enabled / disabled state, one record per variable
// (recordName = EnvVarEntry.id). Its own record type rather than a field on
// EnvVarItem, so that builds predating the feature can never write or delete
// it: they do not register the type (SyncCore ignores unknown types on
// inbound) and never emit it. A field on EnvVarItem would be exposed to an
// older build's delete-and-recreate of that record and to a fresh zone
// re-upload by an older build; here neither can happen. `updatedAt` is the
// state's own clock (EnvVarStateBook), independent of EnvVarItem's.
// Note: like every new record type, it must be deployed to the CloudKit
// Production schema before a release; until then only state sync is off.
struct SyncedEnvVarState: Syncable {
    var id: String         // EnvVarEntry.id - also CK recordName
    var key: String        // variable name at the time; diagnostics only
    var enabled: Int       // 1 enabled, 0 disabled
    var updatedAt: Date    // the state's own LWW clock

    static let syncMetadata: SyncTypeMetadata<SyncedEnvVarState> = {
        typealias F = FieldDescriptor<SyncedEnvVarState>
        return SyncTypeMetadata<SyncedEnvVarState>(
            recordType: "EnvVarStateItem",
            idKeyPath: \SyncedEnvVarState.id,
            scope: .global,
            fields: [
                F.string("entryId",  \SyncedEnvVarState.id),
                F.string("key",      \SyncedEnvVarState.key),
                F.int("enabled",     \SyncedEnvVarState.enabled),
                F.date("updatedAt",  \SyncedEnvVarState.updatedAt),
            ],
            conflictPolicy: .lastWriteWinsByField(\SyncedEnvVarState.updatedAt),
            version: 1
        )
    }()
}

// MARK: - SyncedDevice

struct SyncedDevice: Syncable {
    var id: String                  // device UUID
    var deviceName: String
    var lastSeen: Date
    var osVersion: String
    var uploadTypes: String         // CSV: "Sessions,Messages,..." for diagnostic
    /// App version code (e.g. CFBundleVersion as Int) — see §3.6.6 for use
    /// alongside minimumCompatibleVersion.
    var appVersion: Int

    static let syncMetadata: SyncTypeMetadata<SyncedDevice> = {
        typealias F = FieldDescriptor<SyncedDevice>
        return SyncTypeMetadata<SyncedDevice>(
            recordType: "SyncDeviceV2",
            idKeyPath: \SyncedDevice.id,
            scope: .global,
            fields: [
                F.string("deviceId",    \SyncedDevice.id),
                F.string("deviceName",  \SyncedDevice.deviceName),
                F.date("lastSeen",      \SyncedDevice.lastSeen),
                F.string("osVersion",   \SyncedDevice.osVersion),
                F.string("uploadTypes", \SyncedDevice.uploadTypes),
                F.int("appVersion",     \SyncedDevice.appVersion),
            ],
            conflictPolicy: .alwaysAccept,
            version: 1
        )
    }()
}

// MARK: - Bootstrap

/// Call once during app launch (before any sync activity) to register
/// every Syncable type with the singleton registry. Idempotent.
// MARK: - SyncedSoul (SOUL.md personality/identity file)
//
// One singleton record per iCloud account holding the full SOUL.md text
// (frontmatter + body). LWW by updatedAt — SOUL.md is small and edited
// rarely; per-field merging would not buy anything. The file lives at
// <minisMemoryPersistentDir>/SOUL.md and is read/written by SoulStore.
struct SyncedSoul: Syncable {
    /// Constant id — only one SOUL.md per app/account.
    var id: String = "soul"
    /// Full SOUL.md serialized text (yaml frontmatter + markdown body).
    var contentMarkdown: String
    var updatedAt: Date

    static let syncMetadata: SyncTypeMetadata<SyncedSoul> = {
        typealias F = FieldDescriptor<SyncedSoul>
        return SyncTypeMetadata<SyncedSoul>(
            recordType: "SoulV2",
            idKeyPath: \SyncedSoul.id,
            scope: .global,
            fields: [
                F.string("contentMarkdown", \SyncedSoul.contentMarkdown),
                F.date("updatedAt",          \SyncedSoul.updatedAt),
            ],
            conflictPolicy: .lastWriteWinsByField(\SyncedSoul.updatedAt),
            version: 1
        )
    }()
}

// MARK: - SyncedFolder

/// Home-list session folder (FolderV2). Identity is the locally generated
/// UUID; `name` intentionally carries no uniqueness guarantee — two devices
/// may each create "Work" offline and both records coexist after sync (no
/// auto-merge). Rename is a single LWW field here precisely because members
/// reference the UUID, so a rename never touches SessionV2 records.
/// Deleting a folder propagates as a tombstone whose apply-side clears
/// members' folderId — it never deletes sessions.
struct SyncedFolder: Syncable {
    var id: String
    var name: String
    var icon: String?
    var color: String?
    var origin: String
    var sortIndex: Int
    var pinnedAt: Date?
    var desc: String?
    var createdAt: Date
    var updatedAt: Date

    static let syncMetadata: SyncTypeMetadata<SyncedFolder> = {
        typealias F = FieldDescriptor<SyncedFolder>
        return SyncTypeMetadata<SyncedFolder>(
            recordType: "FolderV2",
            idKeyPath: \SyncedFolder.id,
            scope: .global,
            fields: [
                F.string("folderId",        \SyncedFolder.id),
                F.string("name",            \SyncedFolder.name),
                F.optionalString("icon",    \SyncedFolder.icon),
                F.optionalString("color",   \SyncedFolder.color),
                F.string("origin",          \SyncedFolder.origin),
                F.int("sortIndex",          \SyncedFolder.sortIndex),
                F.optionalDate("pinnedAt",  \SyncedFolder.pinnedAt),
                F.optionalString("desc",    \SyncedFolder.desc),
                F.date("createdAt",         \SyncedFolder.createdAt),
                F.date("updatedAt",         \SyncedFolder.updatedAt),
            ],
            conflictPolicy: .lastWriteWinsByField(\SyncedFolder.updatedAt),
            version: 1
        )
    }()

    static func from(_ f: ChatFolder) -> SyncedFolder {
        SyncedFolder(
            id: f.id, name: f.name, icon: f.icon, color: f.color,
            origin: f.origin, sortIndex: f.sortIndex, pinnedAt: f.pinnedAt,
            desc: f.desc,
            createdAt: f.createdAt, updatedAt: f.updatedAt
        )
    }
}

enum SyncedTypesBootstrap {
    static func registerAll() {
        let r = SyncableTypeRegistry.shared
        r.register(SyncedSession.self)
        r.register(SyncedMessage.self)
        r.register(SyncedCompactMarker.self)
        r.register(SyncedFolder.self)
        r.register(SyncedSessionFile.self)
        r.register(SyncedSkill.self)
        r.register(SyncedMCPServer.self)    // per-server, current schema
        r.register(SyncedProviderInstanceV3.self)
        r.register(SyncedProviderModelEntryV3.self)
        r.register(SyncedProviderModelGroupV3.self)
        r.register(SyncedProviderThinkingRuleV3.self)
        // [T-subagent-own-store] Missing this line is a SILENT failure:
        // metadata(for: "SubAgentV3") returns nil, buildPortable is never
        // reached, and the builder pushes nothing while dirty rows drain.
        r.register(SyncedSubAgentV3.self)
        r.register(SyncedEnvVar.self)    // per-variable, current schema
        r.register(SyncedEnvVarState.self) // [T-envvar-disable] enabled state
        r.register(SyncedDevice.self)
        r.register(SyncedSoul.self)
    }
}
