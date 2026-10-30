# iOS legacy-data inventory (2026-10-30)

Historical investigation: the user subsequently chose a fresh-product baseline.
See `ios-agent-backup-baseline.md` for the implemented removals, retained current
contracts and new backup format. The table below records the earlier state,
not a claim that all these branches still exist.

Scope: the current local workspace on `codex/bot-single-chat`, including its
uncommitted changes. This is a source-based inventory of the Bot/session,
configuration, backup and sync paths relevant to the review, not a claim that
every compatibility branch in the repository has been audited. No migration or
historical-conversation policy was changed for this inventory.

## Decisions closest to the single-chat change

| Location (under `src/ios`) | Existing behavior | Decision / consequence |
| --- | --- | --- |
| `Views/ContentView/Bots/BotWorkspaceStore.swift`, `adoptIntoCommander`; called by `ContentView.swift` and `ContentView+SessionRefresh.swift` | Sessions without an owner are assigned to the commander. All IDs are retained in `conversationIds`; only the first becomes the main session if the commander has none. | Decide whether old sessions should be listed, archived with an entry point, or explicitly reassigned. Keeping IDs is not the same as making history accessible. This also handles unowned sessions arriving later, not only the first upgrade. |
| `Views/ContentView/Bots/BotWorkspaceStore.swift`, search-hit filtering near line 353 | Bot-owned search hits are kept only when their session matches the Bot's current `sessionId`. | Decide together with history navigation; merely adopting old sessions does not make their search hits reachable. |
| `Views/ContentView/Bots/BotWorkspaceStore.swift`, `inheritOwner` and Bot deletion | Copied sessions inherit ownership and join `conversationIds`. Deleting a Bot does not delete ChatStore history or its retained ownership mappings. | A future history decision must cover copies and deleted owners too; do not treat every retained mapping as a visible conversation. |
| `Views/ContentView/Bots/BotWorkspaceStore+Sessions.swift`, `prepareSession` | If skill/MCP overrides are nil, read the former main session's effective choices and save them on the Bot. Without a source session, initialize empty dictionaries. | This is lazy settings adoption. Removing it can change the tools enabled for existing Bots. Nil and an empty dictionary have different meanings. |
| `Agent/Session/SkillStore.swift:1209`; `Agent/Session/MCPStore.swift:521`, `isEnabledForSession` | Until the Bot dictionaries exist, read overrides from its former canonical session, then fall back to global settings. Unowned sessions still use per-session overrides. | These runtime fallbacks are paired with the lazy adoption above; removing just one path can make old Bots behave differently depending on how they were opened. |
| `Views/ContentView/Bots/BotWorkspaceStore+Sessions.swift`, `adoptLegacyMemorySetting`; called by `Agent/Chat/AIChatViewModel+Persistence.swift:246` | A nil Bot memory flag inherits the old main-session flag. A nil room flag inherits a selected member-session flag. Existing explicit flags are not overwritten. | Decide whether to preserve the old switch or establish a new default. Room adoption chooses the lexicographically first saved session ID, not a merge of member settings. |
| `Views/ContentView/Bots/BotWorkspaceView.swift:492` and `:594` | Editors also load old memory switches; Bot save fills missing skill/MCP choices from the session. | Runtime and editor paths need the same policy if lazy adoption is later removed. |
| `Views/ContentView/Bots/BotWorkspaceStore.swift`, `init(fileURL:)` and `BotProfile` | A workspace decode failure marks the store unreadable and prevents overwriting it. Optional fields tolerate absence; there is no general per-record migration/recovery layer. | Do not assume Swift property initializers make required Codable fields optional. A future file-format change needs explicit decoding/version decisions. |

## Other compatibility handling still present

| Location (under `src/ios`) | Existing behavior | Why it is not just old UI residue |
| --- | --- | --- |
| `Shared/EnvVarStore.swift`, `EnvVarEntry`, `EnvVarBackupEntry`, `EnvVarStateBook` | Missing notes become empty; missing ownership means global; old backups without an enabled flag default to enabled. Remote state without its value/clock does not overwrite local enabled state. | Supports existing files, old backup packages and mixed-version peers. The state clock remains a current conflict-resolution requirement. |
| `Agent/Backup/BackupFormat.swift:142`, manifest/category decoders | Missing optional manifest fields get defaults; unknown/new optional metadata is not required to restore older packages. | Removing defaults would invalidate otherwise usable archives. This is independent of old chat navigation. |
| `Agent/Backup/BackupImporter+Categories.swift`, `importProviders` / `importSoul`; `BackupFormat.swift:53` | Thinking-rule/subagent files are imported when present. Old SOUL packages remain importable, although new exports exclude SOUL. | Import-only compatibility can remain even after a feature's entry point is removed. |
| `Agent/Sync/V2/ChatStoreSyncHydrators.swift`, `FolderV2` / `SoulV2` registration and mergers | Folder rows and SOUL files still have registered inbound/outbound sync paths. | Removing sidebar/persona UI does not remove these data surfaces. Decide retention separately from UI cleanup. |
| `Agent/Session/SoulStore.swift`, parser and `serialize` | Parses old emoji metadata; current serialization omits emoji and writes a nonempty icon. | This is real format conversion. Some surrounding comments still describe old prompt/UI behavior and should not be treated as proof of current runtime use. |
| `Agent/Session/SkillStore.swift:172`, `migrateAddUseCount`; `:411`, `migrateMarkBundledSkillsDirty` | Adds the usage-count column when absent; a one-time preference flag causes skills with bundled files to be marked for upload. | The second path addresses old SKILL.md-only sync. It still names the old `Skill` dirty-record type; end-to-end effectiveness was not validated in this inventory. Do not equate the presence of this function with a verified modern re-upload. |
| `Agent/Session/MCPStore.swift:235`, config load; `parseImport` | Assigns missing stable creation times and persists them. Imports accept supported JSON layouts. | Missing dates can also come from current CLI edits; multiple import layouts are current interoperability, not necessarily upgrade-only code. The trailing `Legacy whole-file record cleanup` heading contains no implementation. |
| `Providers/ProviderConfigStore.swift:111`, decoder; `reloadFromDisk` | Optional configuration fields receive defaults and model groups are decoded leniently. If no provider DB is attached, reload still uses the JSON file. | Supports older configuration and non-DB initialization paths. Tombstones and local-change merge protections are current data-integrity behavior, not disposable legacy migration. |
| `Providers/ModelGroup.swift`, member timestamp maps; `Providers/LLMTypes.swift:1237` | Old model groups without member timestamps are treated as additions at time zero. Old `thinkingEnabled` is converted to the newer thinking-level setting. | Removing compatibility can lose memberships or change inference settings after restoring old config. |
| `Providers/OpenAI/SpeedTier.swift:48`, `SpeedTierSettings` | If the new tier key is absent, reads the old fast-mode Boolean; writes both keys for older readers. | This proves preference compatibility exists, not that the prior profile page exposed a Fast Mode control. It is not evidence for the withdrawn UI-migration claim. |
| `Agent/BrowserUse/BrowserPasswords.swift:65`, `unlock`, `sharedVaultURL`, `importFile` | The field named `legacyVaultURL` defaults to the current shared password-manager vault; unlock imports it, preserving a source link for edits. | This is an active shared-file integration, not a safe-to-delete one-time migration based on its name. No credential content was read for this inventory. |

## Fixes implemented separately from the history decision

1. Delegated Bot tasks now resolve skill/MCP prompts through their owned child
   session in both the initial and fallback prompt. Ordinary helper sessions
   without ownership still inherit the parent session's capabilities. Filesystem
   and browser session sharing were not changed.
2. Scoped environment-variable and subagent transport records carry
   `ownerBotJSON` alongside `ownerBotId`. The snapshot includes Bot configuration
   but removes `sessionId`, `conversationIds` and `pinnedAt`. Restore creates
   only a missing owner with the same ID; an existing local Bot is not replaced.
   Invalid/missing owner data is reported instead of turning private settings
   into global settings. Sync build failures retain the dirty row; failed
   inbound owner restores are not counted as applied.

This is dependency restoration for scoped capabilities, **not full Bot-profile
or workspace synchronization**. It does not transfer rooms, session ownership,
transcripts or memory entries. Referenced model groups, skills and connectors
still depend on their own backup/sync categories. Nil legacy per-session
overrides are not materialized by this transport change.

Already-exported packages cannot acquire the new snapshot. An old private
record remains importable if the owner already exists locally; otherwise it
must be exported/uploaded again from a device that has the owner. Existing cloud
records gain the snapshot only when uploaded again; this patch does not add a
one-time mass re-upload. Existing helpers include `EnvVarStore.markAllEntriesDirty`,
`SubAgentStore.markAllDirty` and `ForceSyncHelper.markProvidersDirty`. Failed
inbound records may need an explicit full fetch after correction; no durable
inbound retry queue was added.

## Verification and release gates

- Added store tests for scope selection, missing-owner seeding, persistence,
  sanitization, local-profile preservation and invalid snapshots.
- Added `run_capability_transport_tests.py`: shipping backup model round trips,
  old-package defaults, real sync metadata/portable records, and propagation of
  builder/merger errors. Added it to the existing macOS validation workflow.
- On this Windows machine, source generation/wiring checks and local Swift
  grammar checks are available; Swift type checking, test execution, Xcode build
  and device validation are not. A generated harness is not a passing Swift test.
- CloudKit production schema must accept the optional `ownerBotJSON` fields on
  `EnvVarItem` and `SubAgentV3`. Schema deployment and two-device sync validation
  were not performed. No CI was triggered, and nothing was committed or pushed.
