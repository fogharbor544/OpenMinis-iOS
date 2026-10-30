# Findings
- iOS is native Swift, targets iOS 26.2 / Swift 6.0 (BUILDING.md).
- Existing BrowserUse, AIChatViewModel, ScheduledTaskDetailView and MCPIntegrationsView modules are present.
- No project AGENTS.md found recursively.
- Native dependency build requires iSH submodule and generated frameworks/rootfs.
- Browser history persists JSON under Application Support/MinisChat; bookmarks reuse this location with a separate non-expiring file.
- AgentJobRegistry exposes list(), setEnabled and remove; ScheduledJobRunner.detailCallback(for:) can open existing task detail UI.
- Scheduled tasks currently live only during app process; task detail explicitly documents no restart persistence. Do not silently promise persistent OS scheduling.
- MCPIntegrationsView currently lists external servers only.
- DS-Bot README retrieved via web raw URL: persistent Bot conversations, group administrator/mentions, per-Bot skills/MCP; DSH-host architecture. Source code inspection still needed before choosing orchestration.
- DS-Bot actual groups.js inspected: ordered group log, roster-order turns/admin-first, @mentions, per-member sessions, bounded relays. File: https://github.com/QingJ01/DS-Bot-App/blob/main/ds-bot/src/host/groups.js. Adapt to local runtime; do not import DSH architecture.
- Existing AgentToolSwitch gates browser, agents, userAsk in tool schemas and execution. OffloadPermissionManager.allCommands supplies native command catalog and policies. Core shell/file/image tools intentionally have no global toggle.

## Bot memory design inspection
- iOS memory is currently global, not per-session: MemoryTools reads/writes one static directory. Session owns only memoryEnabled.
- BotProfile has stable id; private and group session mappings exist; bot(forSession:) resolves both.
- Daily entries contain timestamp/content only, no Bot/session provenance; automatic attribution of legacy files is unsafe.


- AgentLoop has initial and provider-rebuild injection paths; Persistence persona reminder also reads global fragment.
- FileTools minis://memory, iSH/offloading mappings, session UI and revoker also use global path; directory split alone is not strict tool/shell isolation.
- Sync uses singleton memory-global and date-only daily IDs; scoped IDs and deletion semantics required for Bot sync. Bot profiles not referenced in inspected Sync/Backup sources.
- BackupExporter.exportMemory copies top-level regular Markdown files only; nested Bot directories need explicit export/restore support.
- Recommend first scoped Markdown store keyed by stable Bot ID, explicit persisted session ownership, no legacy-global fallback for Bot contexts. Curated summary can follow without adding vector infrastructure.
- Group/private memory sharing is a product decision asked asynchronously; no implementation depends on an unanswered assumption.


## Review repair
Report lists six defects. Existing planning history preserved; current git tree has only report/planning untracked files.

## Verified repair findings
All six reports matched shipping code. CR-06 can reuse existing historyAnchorId -> agentHistory.dbMessageId links established by live send and reload; no new message schema needed. ProviderBackupMerger has only a backup caller, so preserving missing API models does not change sync ingestion. Conversation ownership records remain preserved while ChatStore existence gates selection.

## Device feedback findings
- Startup forcibly unwraps missing App Group in RequestBudget storage paths and MinisApp migration. Private-container fallback added; device crash signature still needed.
- UI new-chat paths include FAB, onboarding, quick action, launch preference and shares; route draft navigation through Bot selection.
- Global SOUL identity/body/style still prepend every normal Bot prompt; Bot instructions append afterwards. SOUL also owns global assistant name/avatar UI.
- HealthKit intentionally hides read permission; do not equate successful authorization request with granted read access. HomeKit callbacks refresh status.
- Schedule management displayed raw enum/log labels despite existing localized detail formatting; reuse detail formatter and add missing titles.

- User confirms signing tool 全能签, developer certificate, immediate exit on icon tap. This is consistent with startup App Group force unwrap but does not distinguish code-signature/dyld failure. Inspected original unsigned IPA structure; final re-signed signature and device crash log remain unavailable.

Bot settings previously copied capabilities and memory by session. They now resolve through ownership; model bindings intentionally remain per-session so Bot edits preserve conversation overrides. Legacy Soul data remains archival and is not injected into the current prompt.

Confirmed user legacy password path /var/minis/shared/password_manager/vault.json maps to minisSharedPersistentDir. Previous UI read Keychain only. Auto-import now links source updates/deletes; schema compatibility still needs device check. Runtime tools/helper/env controls remain shared; moved entry points only.

Current inspection: old auto-grouping targets ChatStore folders, unrelated to BotRoom. Both SwiftUI and UIKit chat menus must be changed. Group runner reads only new vm.messages IDs after awaitProgrammaticTurn; need check runtime message projection/finalization before choosing fix.

## Seven-item Bot feedback implementation
- Navigation: group chat label, single Bot memory entry below Model Group, removed in-chat edit and memory shortcuts, schedules/environment/Open Files in chat menus; global tools/subagents/environment restored, editor runtime section removed.
- Auto-folder offer is disabled as Bot navigation supersedes folder grouping. Existing manual folder data unchanged.
- Group reply defect: shipping ChatMessage stores assistant output in blocks; old runner read only content. Runner now reads text blocks, excludes reasoning/tools, falls back to plain content. Regression fixture now matches block-only live messages.
- Commander: stable builtin.commander ID, idempotent creation preserving rename; live roster injection and bot_id delegation through existing queue/helper runner, Bot model/capability ownership, isolated child context, no private memory injection. Resume resolves actual assigned Bot; missing model group is an explicit failure. Removed redundant memoryEnabled setter that would otherwise modify a Bot setting on fresh resumed child before helperConfig was assigned.
- Runtime status uses existing session activity/tool/subtask/schedule tracker plus completed assistant state; no background polling or eagerly loading all chats.
- Reference reviewed: https://github.com/nescafe2009/dsh-grokbot (team delegation/return/coordinator model); no external code copied. Name is ambiguous among GrokBot products, so actual requested behavior governs scope.

## Commit review 76582ed
- HEAD is target commit on codex/bot-single-chat. Only pre-existing planning files untracked.
- Patch covers 35 files: Bot UI, commander delegation, scoped capabilities, sync/backup, browser preview, tests.
- Investigating capability inheritance and persistence/backup ownership; no confirmed finding yet.

- Confirmed static mismatch: delegated Bot ownership is registered, but AgentLoop initial/fallback skill and MCP prompt selection still uses helperConfig.parentSessionId. Trace native execution before final severity.
- BotProfileView bypasses old trailing menu for every Bot chat; investigate availability of removed chat controls.
- Scoped records carry owner IDs through backup/sync, but no Bot workspace transport found so far.
- memoryEnabled already gates helperConfig; removal of explicit child.memoryEnabled=false is not a defect.

### Confirmed review findings
1. HelperRunner.swift:473 registers target Bot ownership, but AgentLoop.swift:227/233 and fallback :1047/1052 read skill/MCP configuration from parentSessionId (commander), not target child ownership.
2. AIChatView.swift:813-825 removes trailing menu for Bot sessions; profile only restores search/share/compact/clear/files/schedules. Speed tier, enhanced cache, token usage and per-chat display controls are no longer reachable there.
3. BackupImporter+Categories.swift:480/644 restores ownerBotId verbatim, while BotWorkspace remains local-only and is absent from backup/sync. On a fresh install/device these scoped records have no matching owner and are excluded by roster/env injection; same-name Bots get new UUIDs.
- Existing EnvVarDisableTests.swift:192 string assertion uses old allAsDict() signature and cannot match current source. This is static evidence, not execution of the Swift suite.
- check_bot_memory_ui.py replaces new BotProfileView with EmptyView; BotScopedCapabilityTests added but not exercised by existing source-check workflow.
- No runtime, device interaction or Swift compilation success claimed.

## Findings 1/3 repair and historical-data inventory
- Bot-owned child sessions now select their own skill/MCP configuration in both initial and fallback prompts; unowned helpers inherit parent scope.
- Private env-vars/subagents carry sanitized owner Bot snapshots in backup/sync. Missing owners are seeded without session histories or replacing local Bots; invalid owner records fail explicitly. Sync failures no longer clear pending outbound records or count inbound restoration as applied.
- Existing archives/cloud data without snapshots require a local owner or fresh export/upload. This does not implement full Bot/profile/history sync.
- Inventory: docs/ios-legacy-data-inventory.md. Key pending policy is old sessions adopted into the commander but excluded from main-session navigation/search; lazy memory/tool inheritance and archive compatibility are separate concerns.
- Local static checks pass; Swift/Xcode and two-device CloudKit behavior unverified.

## Fresh-product implementation decisions
- Remove orphan-to-commander upgrade adoption, lazy per-session Bot memory/tool migrations, stale skill bundle reupload migration; keep current per-session overrides for ordinary helpers and active import formats.
- Skill usage column is currently created by ALTER even on fresh installs: put it into CREATE before removing the upgrade ALTER path.
- Add first-class agents archive (workspace + memory), independent of private capability presence. Bump backup major format to avoid pretending older partial packages are complete device migrations.
- Restore stable IDs by merging without clobbering local edits; factory commander needs an explicit baseline exception. Unsupported duplicate-session option must fail before mutation rather than silently ignore it.
- Preserve current credentials behavior/disclosure; do not read actual credentials. New archive contains no secrets or running jobs.

## Fresh-product final result
- Removed confirmed upgrade-only adoption/inheritance, legacy speed/thinking preferences, skill migrations and retired SOUL transport. Did not delete live password-vault integration, sparse current import contracts, membership clocks, tombstones or current folder records.
- minisbak/2 agents archive restores every current Bot/group independent of private capabilities, memory entries and stable-ID session ownership. New-device ordering and factory-commander replacement covered; existing local settings preserved on merges.
- Archive preflight validates references. The workspace/memory pair has a persistent undo journal and startup recovery; failed dependent categories are reported and private configuration is blocked after agent failure.
- No jobs are resumed; runtime scheduling is in-memory in the current product. OS permissions and arbitrary device preferences are outside agent archive scope.
- All reported validation is static/source-generation/SQLite schema validation. Swift and device behavior await macOS/device execution.
# Review follow-up findings (2026-10-30)
- Repairs: explicit commander binding for new debug conversations; staged session IDs define archive history; v2 format/required-identity tests; per-slice apply results aggregate before poll cursor and full-history anchors; SOUL enqueue/poll/type-list residues removed.
- Regression coverage: snapshot-excluded conversation references, empty history, required/null identity fields, first/middle/last slice failures, corrected retries, version blocks and query failures. The runner extracts shipping code rather than reimplementing the cursor logic.
- Boundary: invalid owner payloads still fail until their source data is corrected; this does not recreate missing owner identities or re-enable retired SOUL compatibility. No existing local/remote data was deleted.
- Confirmed: DebugRPCProviderChat calls removed adoptIntoCommander; explicit new-session ownership must replace migration behavior.
- Confirmed: exportAgents compares live session IDs with snapshot-filtered exported IDs, rejecting valid exclusions. Archive.capture already prunes dangling relationships.
- Confirmed: format compatibility tests still expect v1 and optional identity fields; current contract requires v2 plus format/created_at/backup_id/categories.
- Confirmed: merge failures increment blocked but still call cursor completion. Poll slices need aggregate success, including failures before the final slice.
- Confirmed: retired SOUL still queues dirty records and remains in transport polling / dirty-type lists. No active SoulStore.save callers found.
