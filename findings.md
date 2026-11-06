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

## 2026-10-31 inspection
Commander entrypoints: BotWorkspaceStore/Profile/Archive, HelperRunner delegation+resume, tool schema/system prompt, debug new-chat. Preserve group/session ownership and generic helper lifecycle. Existing backup format contract and credential import/writeback require inspection.

### 2026-10-31 current repair findings
- Browser first-open used Boolean sheet and separate session state; item-based retained VM fixes presentation state coupling. Active manager notifications must reach browser pool UI.
- Input measurement missed suspended-state strip; title geometry used full screen and editor toolbar role instead of actual navigation pane.
- Credential store previously auto-imported and rewrote plaintext source; new path is explicit one-way import and Keychain-only saves.
- Core review caught stale debug isNewSession reference; fixed with actual canonical session-ID comparison and updated debug parameter contract.
- Tree-sitter is installed under build/validation-python, but does not typecheck Swift or exercise UIKit/WebKit/Keychain.

### Final integration findings
Manual navigation previously relied only on URLRequest timeout; a page waiting for load completion could leave the native UI loading. Added a bounded manual-navigation deadline and existing retry error presentation. Async browser reads begun before native login can complete while the user is entering a secret; interaction-generation checks now discard their response/error before model delivery. Current native fill/cleanup production JS passes 55 synthetic DOM assertions. Native WebKit, authentication, Keychain and device layout still require iOS acceptance.

## Device UI follow-up
- Device screenshots show chat message clipped behind navigation/reply strip and sparse capability Form rows with trailing-only separators.
- Target platform is SwiftUI/UIKit iOS. Keep native grouped settings, semantic fonts/colors, >=44pt controls and Dynamic Type.
- UI skill search confirms fixed elements must reserve viewport space; use SwiftUI settings grouping where appropriate.

### Follow-up implementation decisions
- Main chat opts out of iOS 26 under-navigation content; every top strip (including BotRunStatusView) now shares one safeAreaInset. Removed async banner-height compensation; collection rendering is confined to its viewport. Helper transcript presentation remains unchanged.
- Agent Runtime icons now match adjacent settings: 21pt circle, 9pt white glyph, default system row/text sizing.
- Capability identity and live OS status moved into card; one full-width internal divider, compact Bot-call policy menu. OS grants and tool permissions retain independent actions/state. Native text styles and semantic colors retained.

### Follow-up validation boundary
- 7 source-contract checks passed; 8 Swift files have no added grammar errors versus HEAD. Capability authorization/refresh/mapping implementation unchanged by byte-normalized comparison. Diff whitespace passed.
- Updated existing Swift guards that required the retired banner-height compensation. Swift guards have not executed on Windows. Native rendering, Dynamic Type, VoiceOver, rotation, keyboard and streaming-scroll acceptance remain pending; no new package produced.

### Follow-up cloud results
Superseding the local-only limitations for executed checks: fe7d5a3 device build succeeded in run41168685061; corrected scheduler test references at93918e5 passed all source checks in run41169079297. Application source is identical across these revisions. Downloaded unsigned arm64 IPA has valid ZIP CRC and matching artifact provenance; device UI acceptance still belongs to the user.

## Four-area visual consistency audit started
Target: Settings, main chat chrome, Bot profile and built-in capabilities. Preserve prior reserved chat viewport fix. Existing code is SwiftUI/UIKit, with native grouped settings and semantic colors. Audit shared icon/row components before adding abstractions.

### Audit findings and direction
- Main settings uses 21pt circular white-glyph icons; Skills SettingsActionIcon and BackupActionIcon already repeat this specification. Reuse this established visual language across settings, Bot profile and capability identity.
- Bot profile has a large empty 188pt browser tile, labels mixed with unbounded trailing values, a 32pt browser-menu target and no explicit page title. Adaptive rows and a compact browser header/preview will improve hierarchy without changing actions.
- Chat title currently stacks three tightly spaced rows with negative spacing and 9pt model text. Preserve legacy non-Bot paths and reserved viewport; give Bot chats a readable two-row principal item, one model-picker target and a quiet status strip.
- UX domain search retry remained web-oriented; no applicable native match was accepted. Adopt verified SwiftUI Dynamic Type/adaptive-layout results and skill built-in native checklist, anchored to repository components.
- Read/search error: Views/Components does not exist; use actual Views/Settings and existing shared files.

### Implementation checkpoint
- Extracted established SettingsActionIcon into ContentView/Support/SettingsRowStyle.swift (synchronized group); shared SettingsRowLabel/SettingsDetailRow cover normal and accessibility layouts. Main settings, skill detail, backup actions, Bot profile and capability cards reuse it.
- Profile now has an explicit inline title, 72pt avatar, native browser card with a compact empty state/optional 140pt screenshot, 44pt options menu, and adaptive configuration summaries.
- Bot chats use one-line navigation titles and a 44pt model/status control plus a separate 44pt reasoning control in the reserved top stack. Non-Bot title and composer measurement paths retained; thinking-sheet presentation moved to the stable chat root. Status text wraps up to two lines and uses readable semantic secondary text; active spinner retains green.
- Local 7 contracts and 10-file tracked Swift grammar comparison passed. New shared source still needs explicit syntax/native checking. Full rendering, keyboard/scroll interaction and cloud compile pending.

### Native visual QA
ARM ui-layout/run41173472074 passed all 16 cases. Downloaded actual iOS simulator renders and inspected 375pt light/dark standard plus 320pt light AX5 and 667pt dark AX5. Normal values align on the trailing edge, long values move below the label, and AX5 text wraps without horizontal overflow; dark surfaces and primary/secondary hierarchy render correctly. These are shipping shared-row component renders, not full-page or keyboard/scroll interaction tests. Source regressions still running; no final overall pass claimed yet.

## Device list regression findings
The device screenshots show missing titles only in adaptive SettingsDetailRow rows (instructions/skills/connectors/agents/environment and built-in capability identities). Direct label rows such as the model group and memory toggle remain visible. The adaptive row places an automatic SwiftUI Label inside ViewThatFits, so container-driven label presentation and size negotiation need to be removed from this path. Verify the repaired rows in an actual native List with Button and NavigationLink wrappers, rather than only detached sizeThatFits/ImageRenderer samples.

### Regression verification infrastructure
Run41179959963 ended before any job steps because of GitHub billing/spending limits; this is not a compile failure or a test pass. User authorized switching to saved build account3, verified as owner of the existing private origin repository. Retry41180487104 builds exact6a1b372. Native list/title/height verification still pending.

The account3 retry41180487104 was also refused before any steps with the same billing/spending-limit annotation in all3 jobs. ARM capacity notices are informational; the explicit failure is billing. The proposed title/layout repair remains unverified on iOS. Neither run produced a current-fix IPA. Do not retry without an external account-state change or further user direction.

### Build account2 verification
Saved account2 is gaopan513. No existing Minis repository; new private gaopan513/OpenMinis-iOS verified with ADMIN access. Registering the workflow on a matching main push resolved initial workflow discovery, but source-checks/run41181156783 was immediately refused before steps with the same Billing & plans payment/spending-limit annotation. Default branch of this newly created build copy is main. No full-build dispatch was attempted after the explicit account restriction. All three requested build accounts are now confirmed blocked before execution; no current-fix IPA exists.

### Actual public native list results
Public run41194088809 passed source-checks and ui-layout. Native OCR/height assertions all passed in4 production-row List/control fixtures, beyond the earlier detached-only validation. Regular maximum row112.67pt, AX5 maximum220pt. Representative actual snapshots show titles render in both color schemes and AX text wraps. This validates shared rows inside the fixture containers, not complete production pages/keyboard/scroll/VoiceOver/device behavior. Final device build remains in progress.

### Final public build outcome
Changing only the user-authorized account3 repository visibility removed the prior pre-execution quota/billing refusal for this run. All3 jobs succeeded in41194088809 at ce9061e, whose compiled app source matches repair6a1b372. New unsigned IPA downloaded and verified (100915125 bytes, artifact13040725385); complete verification manifest stored beside package. This proves cloud compilation and the recorded native fixture checks, not full application/device acceptance.

## Latest device screenshots and scope
User requests original model selector under Bot name, browser section title/time layout fix, and trailing instruction Not set. Browser screenshot shows long heading wrapping while relative time sits next to it instead of a clean trailing alignment; keep restored188pt preview card. Instructions are stacked because valueLineLimit2 unconditionally forces SettingsDetailRow vertical layout even when empty. Earlier visual pass replaced Bot principal title with a single name plus a separate model strip; user now asks rollback of that presentation. Keep reserved top message viewport. UI skill verified Compact Label Overflow (All platforms), and SwiftUI standard-stack guidance; apply bounded title/whole status badge and ordinary native alignment.

### Follow-up implementation
Restored chatNavPrincipalContent exactly froma796a2e, reusing the existing title/model/group/provider/thinking badge presentation. Removed separate Bot model/thinking strip; retained wrapping BotRunStatusView in the same reserved top stack and kept root thinking-sheet presentation. Browser188pt preview and Bot action/persistence code match baseline exactly. Isolated browser section header in a production view for real native List testing: flexible one-line middle-truncated title, whole trailing time badge,44pt menu; AX metadata stacks. Empty instruction uses ordinary trailing detail row; nonempty instruction retains2-line preview. Added native OCR geometry checks for same-row trailing Not set and readable trailing browser time, while reusing20 existing native cases.

Native failure detail: ARM worker SDK lookup exceeded60s after boot, not a Swift error or layout assertion failure. Move toolchain discovery before simulator startup to avoid first-boot contention; keep total job and subprocess bounds. Device app remains bedcc9d.

### Final polish results
Preflight-first native retry succeeded:20 cases passed, no layout failures. Standard list images show browser heading/time/menu in one horizontal header and empty instruction value on the far trailing side; AX metadata stacks without losing the time text. Maximum visible list cells112.67pt normal/212pt AX5. Device app compiled successfully, source checks passed and downloaded IPA provenance matches bedcc9d. Native test-only3807e07 changed no app code. Full app/device interaction still needs user acceptance.

## 2026-11-01 execution findings
Native secure_input fails at the pre-session active/first-scene/key-window guard; the screenshot does not establish which subcondition failed. Replace guard with lifecycle-aware retry while preserving cancellation and secret isolation. Memory gates require verbatim current-user evidence, durable keyword allowlists and a single category/scope entry, and store the quote instead of the summary; remove these ordinary-save gates, retain destructive-operation authorization and deletion suppression.

## Avatar rollback decision
User explicitly requests removing the avatar changes and restoring original behavior. Baseline1326902 differs in the selected six files only by the new avatar feature, so those files are restored exactly. Mixed native interaction fixtures retain only security tests. Browser/memory source hashes are unchanged; no device/workspace data is rewritten. Existing iconSymbol/iconImageData continue to decode; the unused optional preset field from the prior package is ignored by the restored Codable model.
# Bot team implementation findings — 2026-11-01

- Baseline 7450d01 restored original avatar UI; security and proactive scoped memory fixes must remain intact.
- Existing helpers own queue/cancel/timeout/callback/transcript infrastructure. Bot dispatch must explicitly use target configuration and allow only scoped memory reads; generic helper behavior remains unchanged.
- Backup currently samples chats and Bot/memory at different instants. New delegation graph requires one staged snapshot and preflight before writes.
- Current backups are minisbak/3 + Bot archive v2. User explicitly selected new formats only.
- Original worktree clean; no project AGENTS.md found. Git writes require managed escalation. RTK inaccessible, use executable paths.
### Bot team / original avatar findings
- Generated atlases are 1254 x 1254, so native cropping must support fractional 4 x 4 cell coordinates.
- Transparent first drafts had matte speckles; final warm-neutral opaque plush atlases were regenerated and visually inspected. Prompts and SHA-256 are recorded in `docs/bot-avatar-generation.json`.
- ContentView uses synchronized Xcode file membership; Agent/Chat and Agent/Backup require explicit project entries.
- Frozen graph files are private resumable staging under `.bot-snapshot`; every encryption/checksum/ZIP walk must skip this directory, including configuration-only backups.
- Restoring only the new minisbak/4 and Bot v3 formats is explicit user scope. Old backup files must remain untouched and must not be imported.

## Avatar clipping and return replay
- User screenshot shows a roughly80-point circle displaying an enlarged section of a cloud bear face during playback, with a much taller preview row. The source16-frame atlas contains complete characters.
- BotAvatarAnimation wraps UIImageView with image-size intrinsic metrics and has no UIViewRepresentable.sizeThatFits implementation. The outer SwiftUI square/circle does not establish a native-view measurement contract.
- BotWorkspaceView uses BotAvatarPreview for its commander header. Its onAppear calls replay, so returning from a chat starts it again. Use the existing static BotAvatar for this list entry; leave picker preview/replay behavior intact.
- Existing native tests directly sized UIImageView and captured picker images after animation ended; they missed the represented view's layout while moving. Add live SwiftUI Form bounds/snapshots. No image assets need regeneration.

## 2026-11-02 screenshots
- Profile browser card shows URL strip over blank content; full browser works.
- Commander created-Bot section overlaps existing messages on first mount and is inserted before the user's creation request.
- Specialist onboarding renders but all actions ignore taps.
- User sees no commander provenance/task/result in target Bot history. Must trace HelperRunner ownership and conversation indexing.
- Latest remote 56050b2; existing uncommitted avatar changes preserved.


- New feedback: entire Bot interface sometimes stops accepting interaction while replying, and no proactive long-term memory observed. Trace main-thread work/reentrancy and full memory availability/save/injection before changing policy.

## 2026-11-02 repair findings
- Browser preview used scaledToFill inside a fixed-height card, cropping a tall page. Preview now uses an explicit GeometryReader viewport and scaledToFit.
- Empty/loading chat installed a transparent tap layer above the collection view, swallowing onboarding choices/skip/close. The dismiss layer is now behind the list.
- Created-Bot summary lived globally above history. Synthetic presentation-only cards now follow the matching bot_create tool message, scoped by creationRequestID/session; none enter stored/model history. Bot cards get first-layout measurement and content-sensitive height invalidation.
- Target Bot private chats and delegated task transcripts are intentionally distinct. HelperRunner binds a specialist child session to the target's BotSessionOwner/delegationID, target instructions/provider/memory and own browser pool. It still reuses the subagent runner and parent filesystem workspace; this is not full process isolation. Incoming task/result cards link to the dedicated transcript. Empty private-session update timestamps no longer hide delegation previews.
- Full-interface freeze is confirmed by user report (text also stops; reopen required). Source inspection found two synchronous hosting measurements per uncached cell, repeated background decoration registration per snapshot and broad overview resize notifications. Removed these redundant paths; no device stack exists to establish the exact deadlock or prove the freeze resolved.
- Memory was enabled and tools/prompt present, but there was no runtime review after an otherwise successful reply. Added a separate post-answer request that only proposes up to two additive notes from the latest persisted user source. It does not execute arbitrary tool calls or replace/forget entries; source/owner/enable/cancel gates are rechecked before writes. One extra request may consume up to 1024 output tokens, counted in live session usage; successful writes display a notice. Existing successful memory calls skip the fallback. Credential topic mentions can now pass while recognizable assignments/values remain rejected.

## 2026-11-02 requested interaction redesign
User explicitly requests combined document memory reading/editing, and direct target Bot execution inside its own normal conversation (not a commander-owned helper task). Target may choose its own helpers, returns results to commander for review. Existing memory UI is one section/editor/share action per SQLite entry; redesign must preserve active entries/grants/tombstones.

## 2026-11-02 implemented document and direct execution design
- User clarified: retain target Bot incoming-task hint and tap-through independent conversation with commander; only replace execution. New handoffs create target-owned normal source=bot conversations (no HelperConfig, no child job registration, no HelperRunner call). The target's private chat IDs remain unchanged. Optional own helpers belong to the target task conversation and their results must return to that target before reporting to commander.
- Normal Bot system prompt includes the target profile and scoped memory plus direct-task context; full brief and subsequent corrections persist in the task conversation. Incoming hints open the normal interactive AIChatView; legacy transcripts remain viewable. Rework reuses direct conversations; explicit resume creates a fresh attempt. A directExecution optional field distinguishes historical helper sessions without rewriting them.
- BotTeamRuntime retains normal VM execution tasks, serializes tasks per target, sends course corrections to the normal loop, waits for its own helper callbacks, and returns final results to commander for review. Stop retains the cancelling turn until unwound. UserAskCenter exposes pending-card/answer-handoff state so the task stays active and the inactivity timer pauses while awaiting the user. Partial resumable replies are interrupted rather than marked review-ready.
- Memory UI is one continuous document with full edit/search/copy/export/share/clear actions and a read-only shared section. No per-entry cards. Underlying records remain authoritative for provenance, scoped recall, archives and forgotten-source suppression. Ordered document saves retain unchanged IDs/grants/pins, keep new/rewritten paragraphs private, clear removed plaintext and sharing, and reject stale drafts rather than overwrite newly remembered content. Editing currently requires paragraphs <=2000 characters, matching existing memory storage limits; a validation error retains the draft.

## 2026-11-02 Mika browser comparison
- Target worktree: build/worktrees/bot-team-original-avatars, local HEAD 56050b2d3fdc7391cc27d3bf0ca49ffbada848b8 (2026-11-01).
- Mika README identifies Android-only application; distinguish Android native control from portable web automation mechanisms.


- iOS execute() routes visual-change actions through DOM settle + awaited preview snapshot. collectDomChangeSummary uses three 500ms non-increasing mutation intervals: approximately 1.5s minimum on quiet pages, cap 5s excluding individual JS call duration.
- Existing features: async execute_js, scroll_and_collect, per-tab serial execution, cross-tab concurrent tools, get_readable/backbone, cookies and session-aware fetch; avoid recommending these as absent.
- Mika code confirms bounded web_script bridge, targeted CSS reads, page quality verdicts, CDP network ledger and text/url/network wait conditions. CDP-specific mechanisms need iOS adaptation.


- Important correction: SystemPrompt already recommends shell batches of minis-browser-use. Native batch is incremental, not a newly absent capability.
- Preview snapshots are local UI artifacts, not automatically model images; suppressing them reduces local work, not their non-existent image-token cost.
- Mika PagePacing can impose dwell; do not infer globally faster behavior. Main commit ebb0e44750d80aabb6b642c69908825d6b1a8107 confirmed.
- P0 recommendations: action/condition-specific wait and demand-driven preview snapshots. P1: compact reads, site skills, measurement-led native batch. Other options: protocol cache, route known data tasks to existing fetch, bounded parallel pages.

## 2026-11-02 confirmed review findings — implemented fixes
- Direct task user Stop now enters BotTeamRuntime.stopByUser from the actual UI stop path. Per-task suppression survives cancellation cleanup; persisted cancellation remains visible without triggering a new commander model turn. Restore checks include pending execution, asynchronous result delivery and outstanding memory-review writes.
- Direct result handling checks canResume before interpreting the cap error, preserving an interrupted record and valid resume route.
- Shared memory rendering uses source grouping and the same document-order comparator as the author's document. Retrieval relevance ordering remains separate.
- Memory-review accounting is optional auxiliary metadata on the existing assistant token_usage JSON. Primary request counts and context/calibration measurements stay unchanged; session totals use billedUsage, global usage expands auxiliaryUsage once, updates are restricted to the existing assistant row/session and mark sync dirty. No new chat turn is introduced.
- Portable SQLite/source/syntax checks passed, and Astra source re-review found no new definite defect. Windows cannot establish Swift type correctness, fixture runtime behavior, UIKit interaction or live provider/device acceptance; these remain explicitly unverified.

## 2026-11-02 native build and delivery verification
- Final bbce47b / run41375506667: source-checks, ui-layout and full unsigned device-build all successful. Actual macOS fixtures now verify memory document editing/order, auxiliary SQLite accounting/reload, memory runtime, direct target execution/Stop/draining restore/resume and timeline projection. First run's only failure was missing commander owner setup in the new fixture; fixed without application changes.
- Final IPA copied to original project root build/ipa/OpenMinis-bbce47b-unsigned.ipa; ZIP CRC/arm64/Bundle ID/hash/provenance verified. Unsigned package requires re-signing. Isolated fixtures and build do not replace user's physical-device/live-provider acceptance.

## 2026-11-02 browser plan refinements
- Implicit preview policy and post-wait policy must be explicit; disabling preview alone should not silently change waiting semantics.
- Summary deadline must cover setup/poll/read with one shared budget, not fresh per-call budgets; observation timeout must not imply the action was not executed.
- Plan saved in docs/ios-browser-optimization-execution-plan.md; actual performance remains unmeasured.
- Commander settings displayed only profile.instructions, while system prompt separately injected commanderPolicy. Fixed UI and canonical source without seeding/replacing user configuration or changing model instruction wording. Shared workspace policy includes the live specialist roster, so the expanded text matches runtime content.
- Native validation for commander instruction display now passed: actual editor iOS16 typecheck, all existing source/command/direct lifecycle regressions, native UI suite and full device build. Full policy shared by runtime and UI, including live roster. Updated IPA delivered as4c3c91d, older bbce47b package does not contain this display fix.

- Implementing pool-owned manual-control gate with active-action count separate from15s reservations, per-generation queued-action rejection, and shared cancellable waiters. UI now observes pool state; removed captured busy Bool from BrowserSheetView call sites. Postprocessing uses independent cancellable task; manual takeover stops navigation without dead-tab rebuild.

- Added actual-production extraction regression harness (dispatcher, postprocessing, budget/cancellation box, takeover control/admission guard) with fake WebKit boundaries. Portable observer JS11 assertions pass. Swift tests require Mac swiftc and are explicitly skipped here; registered --require-swift in future validation workflow (not triggered).
- Full static data-guard failure verified baseline-only: every finding is in byte-equivalent existing test source; Windows backslash paths do not match slash-keyed allowlist. New tests add no findings. No unrelated guard edits.

## 2026-11-02 chat-send and Bot delivery implementation findings
- Explicit send previously resumed historical self-sizing and streamed snapshots before the new message was positioned; a serialized, coalesced latest-position transaction now fences snapshot/settle reentry.
- ChatMessage.timestamp is construction time on reload; the task timeline now retains RawMessage.createdAt separately for historical positioning.
- Bot runtime already uses the target Bot VM; generic AgentCallback rendering obscured that ownership. Actual owned Bot callbacks now open the Bot conversation.
- Delivery is tied to consumed callback content/version and a confirmed persisted endTurn answer. Legacy complete is a receipt. No separate factual-verification stage is implied.

### Verified cloud results for final delivery
- Final public build account3 run41393013773 on660fa38 passed all source/runtime/native/device-build jobs. Native fixture18/18, zero failures and maximum snapshot depth1.
- Native top send offset24970.0 vs bottom24969.999999999996; middle25749.333333333332 vs bottom25749.33333333333. These fixtures compile shipping transition/guard/layout with platform/model boundaries stubbed; physical gestures, selection and real provider acceptance are not claimed.
- Build account3 is the existing public origin fogharbor544/OpenMinis-iOS. Current branch now tracks its matching origin branch; do not default this delivery to the quota-blocked private remote.

## Historical Bot send hang follow-up
- Affected source is 660fa38; the main checkout is an older branch. Preserve pre-existing browser optimization edits in this worktree.
- requestLatestPosition had three synchronous layout triggers: applySnapshot itself calls collectionView.layoutIfNeeded, followed by two more forced layouts/tail pins. Cold-tail hosted-cell updates can therefore re-enter UIKit/SwiftUI in the same main-thread callback.
- The repair retains the normal snapshot apply and initial pin, deferring cold-tail correction to the next runloop turn. Native validation compiles the extracted shipping methods; Windows cannot execute UIKit/Xcode.

### Browser takeover review
- 6f95f94 matches the reviewed head; 5d5f29c calls a sheet initializer argument its snapshot does not define.
- Model and CLI share BrowserTabPool.execute; the pool serializes WebKit actions per tab, while inUse also includes reuse grace.

### Browser takeover follow-up
- A tool batch can arrive after takeover has already ended; capture the browser generation at model-context creation, not only when a tool enters the pool.
- Group fallback and auto-retry both send requests after awaited work. In-loop compaction restarts the outer iteration, but model switching, prompt persistence and routing/retry also suspend.
- Protect selected and previously visited tabs during takeover; leave unrelated tabs eligible for reclaim.

### Browser takeover shell and handoff follow-up
- iSH stamps fs_context on the guest task group and browser offloads read it on that guest thread. The scoped token keeps the same filesystem route and stores the original browser pool, issuer and generation separately.
- Handoff records the selected tab and its manager identity, keeps snapshot routing separate from selection, and falls back to a text reminder if a safe snapshot is unavailable.
- Child cleanup transfers takeover tabs to the chat and releases untouched child tabs normally.

## 2026-11-05 agent prompt audit
- Prompt assembly begins in AIChatViewModel+SystemPrompt.swift and AgentLoop; normal Bot profile includes Commander/direct-task rules, helpers use a separate identity.
- Candidate mismatch: base long-running-work rules say nothing runs after a turn ends, while subagent and Bot policies promise automatic callbacks. Verify delivery paths before final assessment.
- Existing root planning files contain prior work; append this audit only.
- Confirmed: Commander uses bot_task for specialists; direct task VM has helperConfig == nil, keeps specialist profile/capabilities/memory and can start its own depth-one helpers.
- Confirmed candidate: Commander policy unconditionally advertises bot_create/bot_task even when agents switch hides/rejects those tools.
- Confirmed candidate: bot_create description calls onboarding optional, while schema/handler require a nonempty question and 2–6 choices.
- Helper tools have no Bot/group memory owner; memory tool exposure still depends only on memoryEnabled, and base prompt lists memory tools unconditionally. Check constructor/default behavior.
- Memory tool exposure is correctly disabled for generic helpers by memoryEnabled getter; earlier candidate about exposed schemas is discarded. Unconditional base memory bullets still advertise absent tools, with an unavailable footer later.
- Group runner adds a separate user-level prompt saying not to contact members, while a Commander member still receives its higher-level bot_task policy; check group behavior and report as context ambiguity if concrete.
- Confirmed automatic helper and direct-Bot callbacks invoke submitProgrammaticPrompt after job completion; base no-future-work statement is stale.
- Confirmed high-impact issue: agentBehaviorPromptFragment for listed Codex IDs says never ask permission under any circumstances, appended after Commander/user_ask authorization rules.
- Confirmed fallback issue: four fallback branches reconstruct from baseSystemPrompt + model fragments only. AgentLoop passes undecorated base separately from full userSystemPrompt. Skills/MCP/memory reinjection occurs only after accepted stream, too late for fallback's first request.
- App user guide, mandated by base prompt as source of truth, still says /memory disables writes only and /var/minis/memory stores memory; shipping runtime suppresses reads, writes and injection when disabled and uses scoped SQLite.
- Review remains source-based; no Swift compiler or iOS runtime available locally.

### Agent prompt audit final findings
1. High: listed Codex model autonomy fragment forbids confirmation unconditionally, conflicting with Commander and user_ask authorization contracts (LLMTypes.swift:1011).
2. High: four inner group-fallback prompt rebuilds drop skills/MCP/retrieved memory until a later outer-loop refresh (Fallback.swift:287,398,446,546; AgentLoop.swift:997).
3. Medium: base long-running instructions deny all post-turn work and encourage polling, conflicting with helper and direct Bot automatic callbacks (SystemPrompt.swift:80-83).
4. Medium: Commander policy advertises bot_create/bot_task with agents disabled; base memory bullets advertise tools absent in memoryless/disabled sessions. Runtime rejects/unregisters correctly; prompt is inconsistent.
5. Medium: mandatory app guide claims /memory affects writes only, contrary to runtime gates on reads, writes and injection (manual:330; BotMemory runtime and ToolDefinitions).
6. Low: bot_create calls onboarding optional while schema and handler require question/options (BotTeamRuntime.swift:40-76).
- Main architecture is otherwise aligned: direct specialist runs its own profile/configuration/skills/connectors/memory; generic helpers are memoryless, share the parent's filesystem and inherit capability scope; depth-one helper delegation; completed Bot delivery is automatic after persisted summary rather than complete command.
- Group contact wording, full helper artifact-inlining and callback old prefix remain possible wording improvements, not promoted to confirmed material findings without behavior acceptance.


## 2026-11-05 resumed backup / credential review
- Recovered all three prior reviewer final reports instead of launching duplicate reviews.
- Confirmed six P1 findings: missing bridge registration after WebView rebuild, SPA delayed capture, untrusted declared origin, unbounded waiting/closed-tab prompt, no active-page vault refresh, and false-success source writeback.
- Confirmed three P2 findings: emptied nested vault rejection, premature folder fallback success, and username selector coverage/order. Details and source locations: docs/ios-backup-credential-review-2026-11-05.md.
- Native WebKit/FileProvider behavior remains unexecuted on Windows; broader coverage questions are explicitly separated from confirmed defects.

## 2026-11-05 agent prompt alignment implementation
- User approved all six audit recommendations. Executing the plan in docs/superpowers/plans/2026-11-05-agent-prompt-alignment.md inline.
- Shared full composer now serves initial dispatch, all four inner fallback paths and outer refresh, retaining scoped skill/MCP/memory fragments before the fallback model receives a request.
- Scoped Codex autonomy to authorized actions; clarified real automatic callbacks; gated memory guidance and Commander/direct-Bot delegation wording; synchronized displayed Commander rules and required onboarding descriptions.
- Guide now describes scoped SQLite memory, Bot/group-wide /memory read/write/injection gating and Sub Agents control of Bot creation/delegation.
- Preserved user onboarding schema and existing Bot persistence format.
- Final alignment: the universal tool-call-style sentence now also limits direct execution to already-authorized actions; corresponding UserAsk source guard synchronized. No new confirmation requirement was introduced for authorized routine work.
- Independent review concluded no further blocking issue after the stale ProviderLiveCheck guard repair. Details and remaining native validation limits are recorded in the implementation plan.

## 2026-11-05 Commander roster growth
- BotWorkspaceStore.commanderInstructions builds each roster entry from id/name/instructions.prefix(1200), without a total roster limit.
- BotInstructionsEditor displays the exact runtime built-in policy; this is computed dynamically, not appended by the LLM or saved into Commander custom instructions.
- bot_task currently supports delegation/status/follow_up/cancel/complete/resume, without Bot discovery. Removing the roster requires an explicit discovery path so named specialist routing remains possible.
- User preference requested asynchronously: on-demand discovery (recommended) or compact name/short-introduction roster. No product code changed yet.


## 2026-11-05 repair decisions
- Use actual WK frame security origin plus WebView identity at the credential bridge; do not use delayed currentURL as authority. Rebind handlers at both WebView rebuilds.
- Save prompts use weak manager ownership, an optional waiting deadline, and explicit close/eviction/rebuild/termination cleanup. Secure-input waiting behavior remains unchanged.
- The visible manager owns a cancellable monitor; unchanged shared-file bytes avoid repeated Keychain writes. Shared imports need no bookmark. Linked writes require exactly one unchanged source row; missing/conflicting source fails before Keychain changes.
- Valid empty nested/domain collections clear shared rows; invalid JSON preserves the last good state.
- Mount metadata is committed only after acquiring an active scope. Fallback awaits bounded bookmark resolution, and resolution uses a locked one-shot continuation rather than a task group that joins blocked XPC.

- Final review corrections: carry recognized collection ancestry into accounts.primary, starting root recognition false; synchronize native case gate to15. No further confirmed P1/P2 reported. Native behavior remains pending.

- Approved implementation removes dynamic roster from shared Commander rules. bot_task list reads current configuration only; no specialist instructions, persistence writes, queue admission or model start in this branch. Returning missing introductions as empty strings preserves name-based discovery without copying working instructions.


## 2026-11-06 backup destination rollback
- Working tree initially clean for tracked files; untracked .codegraph/ and AGENTS.md preserved.
- Destination changes originate in f31e408, a5e2b63 and 01a5cbb; upstream still uses synchronous MountedFoldersManager.add and system Files picker.
- BackupDestinationPicker, BackupDestinations, BackupAndRestoreView and MountedFoldersManager differ only in this folder-add/resolution work.
- Current minisbak/4 (Bot archive version 3) is independent of destinations; retained exporter/importer, category dependencies and Bot workspace/memory restore. The older baseline document describes an earlier format.

- Final differences from upstream are limited to the pre-existing cold-launch bookmark deadline helper/resolver. Folder addition and reactivation match upstream exactly; no parallel destination storage or new agent adaptation is needed.
- Upstream synchronously creates bookmarks/probes writes during addition; slow FileProvider behavior and two-device restore remain native acceptance items.


## 2026-11-06 simple local backup and restore
- BackupDelivery.backupsDirectory already resolves to the FileProvider-visible Backups sibling of the agent shared workspace. Reuse it to avoid recursive backup and agent access.
- BackupSettingsView gates Start on hasDestination, delivers to saved remote/mount selections and deletes the local copy after verified delivery; remove those settings dependencies.
- Restore currently omits local Backups entirely and synchronously copies selected files before showing progress. Default to the local directory list; move preparation I/O into the asynchronous open path.
- Keep category dependencies, current minisbak/4 agent archive and import merge behavior. Files import/share remain optional for moving backups between devices.

- Implemented local store creates Backups, preserves same-name older packages, returns complete regular .minisbak files newest first and propagates directory errors. Settings no longer access saved mounts/remotes or delete finished local packages.
- Restore list refreshes on backup completion and pull-to-refresh. Preparing a selected package runs off the main actor; cancellation immediately stops its ticker and discards scratch after in-flight preparation/inspection ends.
- Independent review found no remaining concrete defect; corrected directory URL fixture isDirectory flag and cancellation window during implementation.


# 核查发现

- SharedFoldersSettingsView 当前列出 shared、skills、memory 三个目录。
- BotMemoryStore 将真实长期记忆保存到 Library/MinisBotMemory/entries.sqlite，与共享 memory 目录分离。
- 需继续核查 BackupDelivery、FileProvider 和旧目录的其他用户入口。
- 实际本地备份位于 MinisFileProvider/Backups，LocalBackupStorage 已提供安全筛选和按时间排序。此目录有意不挂载给 Agent，避免备份被二次备份及暴露凭据。
- 恢复页已列出本地备份，但没有删除入口；备份目的地管理页只面向服务器和外部挂载目录，不能直接复用为本地目录。
- FileProvider 仍默认创建并展示 memory；@ 文件候选索引也包含旧 memory 根目录。其他 Linux 路径映射属于历史文件兼容，需保留。
- UI 规范检索匹配删除前确认和明确反馈，使用现有 SwiftUI List/alert 交互。
- 核查设置、Files、@ 文件候选及内置手册：已移除旧 memory 的三个展示入口；MemoryManagementView 和设置“共享记忆”都指向 SQLite，非旧目录。
- Storage 页“Skills, Memory & Shared Files”仅是遗留共享文件容量统计，无目录跳转；仍有历史链接、文件预览、Linux 挂载和迁移兼容，保留以免破坏旧文件访问。
- Windows 中 swiftc 不可用；Swift 行为用例可由现有 macOS CI 的 run_local_backup_storage_tests.py 执行。

## 2026-11-06 thinking / secure-input investigation
- Initial worktree clean. Screenshot shows extra blank space between first collapsed thinking header and browser tool row.
- Existing browser_use secure_input already keeps raw values out of model results; current entry point uses a native overlay in BrowserPasswords.swift.
- UI guidance matches: visible field labels, submission feedback and stable view identity/spacing.
- Search wrapper misinterprets regex pipe; use rg -e alternatives.

### 2026-11-06 findings and decisions
- User confirmed browser login only; no generic API-key tool. Existing browser_use secure_input schema now explains the resumable chat card and status-only result.
- Confirmed overlay cancellation on didEnterBackground; replaced automatic primary-chat presentation with memory-only block-UUID routing and native inline fields. Optional webpage shares the same session; subagents without a host chat cell retain native presentation. Request stays until completion/cancel/tab lifecycle/process termination.
- Background lifecycle belongs to the session rather than a mounted view, so scrolling/reuse does not release input. Background shields values, resets reveal and locks the vault. Page cleanup remains required after native or manual page input.
- Thinking memo identity omitted expansion state, clearCachedHeight retained a seed, and the toggle path retained precalc estimates. Fixed all three and moved expansion invalidation into ChatModels so offscreen changes are observed.
- General native UI guidance applied: visible input label, secure text content type, loading/feedback, privacy shield, 44pt button frames and system semantic colors. Device layout, accessibility, Dynamic Type and small/landscape acceptance remain unverified here.

## 2026-11-06 follow-up code review
- Confirmed BrowserSheetView adds the reopen button below an AgentBrowsingOverlay. secure_input keeps tab.inUse while awaiting the continuation; the overlay covers the button and removes takeover during hasSecureInput.
- Reviewing inline state identity, store observation, cleanup ownership and thinking cache invalidation. No application-source edits during review.

### 2026-11-06 code review conclusions
- P1 (source-confirmed): primary-agent routing at AIChatViewModel+ConcurrentTools.swift:737 checks only helperConfig and block indices. Scheduled new-chat/follow-up jobs create ordinary VMs and submit silent programmatic turns (ScheduledJobRunner.swift:348,364). They get an inline-only request even without a visible chat. startInline and foreground lifecycle have no presentation, jump-to-request notification or expiry, while BrowserTabPool.hasSecureInput uses the global owner and rejects browser calls from all pools. A hidden request can therefore leave unrelated Bot browser work failing until the original request is found/ended. Preserve resumable foreground requests but give nonvisible requests a discoverable/actionable lifecycle or reject/defer them before acquiring the global lock.
- P2 (source-confirmed): the new BrowserSheetView.swift:54 reopen button is under the ZStack's AgentBrowsingOverlay at line 85. executeInner sets tab.inUse before awaiting secureInput, so isAgentBrowsingInSheet remains true for the whole interaction. Overlay covers the button; hasSecureInput also removes takeover. Opening the browser sheet during the pending request cannot use its advertised reopen action. Render the secure-input entry above/outside that overlay, or exclude waiting secure input from the ordinary automation overlay.
- No additional confirmed new defect in the thinking-cache changes after examining model notifications, cell seeds, memo keys and precalc fallback. Discarded a possible scrolling-screenshot leak: that legacy capture function has no live caller; current export builds from persisted block metadata. Active-chat re-entry also reuses the running VM, so no confirmed block-UUID loss on normal navigation.
- Fresh checks: run_secure_input_tests.py PASS 55 production-JS assertions + 14 source contracts; run_browser_takeover_tests.py PASS 14; check_chat_settings_contracts.py PASS 7; git diff --check PASS. The existing tests do not exercise hidden programmatic secure requests or browser-sheet reopen hit testing.
- Source control-flow assertions confirmed both findings. Native Swift/XCTest/simulator/build/device verification remains unavailable (Windows lacks swiftc/xcodebuild). No application code changed during this review.

## 2026-11-06 review-fix execution
- Continued planning-with-files and ui-ux-pro-max workflow; read current dirty worktree and prior review/decision notes. No user changes overwritten.
- Chosen fix: reject newly arriving hidden/programmatic main-agent requests before global secure ownership instead of adding a new notification/persistence subsystem. Already-created requests continue across background transitions.
- Admission must read current visibility at manager request creation, after cookie/tab waits, rather than snapshot visibility at dispatch.

### 2026-11-06 review fixes completed locally
- New main-agent secure input receives a native-only weak admission callback. Manager checks it immediately before session creation/global lock: foreground active + owning chat visible + interactive origin + non-silent turn. Normal user turns and foreground userAskAnswer continuations allowed; hidden/scheduled/silent requests return localized reopen/retry guidance. Existing sessions never re-evaluate this gate.
- The browser-sheet automation overlay no longer covers an active secure-input session's reopen control. Navigation/tab/takeover restrictions remain in place.
- Native simulator fixture extracts and compiles the actual production admission closure against a memory-only owner; six new cases cover changing visibility, scheduled/silent origins, deferred answer continuation and owner release. Total native assertions now 24; syntax only verified on Windows, runtime NOT RUN.
- Added one English/Simplified Chinese/Traditional Chinese rejection message, preserved existing entries, updated bundled guide and appended superseding decision note.

## 2026-11-06 assistant reply trailing gutter
- Reference image 1 has a visible fixed right-hand gap; current screenshot 2's assistant background reaches the existing 8pt edge. User requests model replies only.
- Assistant groups use full-width collection cells plus a separate BotReplyBackground decoration inset 8pt on each side. Header/block/tool-group/footer are distinct hosted views; text precalc/first seeds currently assume 32pt total internal gutters.
- Direction: keep collection cell geometry and user messages unchanged, add shared 32pt assistant trailing content inset and match decoration; total right background clearance becomes 40pt.

### Assistant trailing gutter implemented
- Added AssistantReplyLayout.trailingInset = 32 and shared availableWidth; reply background now ends 40pt from the list trailing edge (existing 8pt + 32pt). Four assistant hosting configurations apply the same inset; user whole-message configuration is unchanged.
- Updated assistant first-display seed, snapshot text precalc, cached/plain Markdown estimates and thinking estimate to use reduced available width. Existing internal gutters, regular cap and split-row architecture preserved.
- Updated the two adjacent Swift source guards and bundled guide. No new tests that merely mirror padding were added.
- Geometry/source inspection passed for 320/375/393/414/844/1024/1366pt list widths. Native visual acceptance remains unavailable on this Windows host.

## 2026-11-07 Bot memory categories
- Current BotMemoryView has fixed/history; history combines every non-fixed entry. The editor always loads ordinary text plus fixed and event entry editors, and saveDocument checks/replaces the whole owner document.
- Existing categories: preference/fact/convention/experience/event. Fixed status is pinned && !automatic. UI-only hiding is insufficient: category-scoped save must preserve other records exactly.
- Asked user whether facts means event records (decision/delivery/verification) or category=fact. No data mapping change before clarification.
- Initial git status clean. Native SwiftUI and Swift compiler not available on Windows; use portable checks plus queued native fixtures.

- User confirmed facts means event records, label 事实记忆. Shared BotMemorySection classifies explicit fixed entries first, then event facts, then ordinary categories. No persisted type migration.
- Reader uses three tabs and filters shared content/search by the same section. Sheet item captures the selected section; draft and save baseline contain only that section.
- Scoped document save compares only that section and writes/deletes only selected records; whole-document callers retain their original behavior. Added native fixture cases for category isolation and concurrent updates; not executed on Windows.

- Final source review: category saves match/delete against scoped current records only; unrelated records are not rewritten. Whole-document size validation still includes preserved categories; whole-document menu operations remain explicit and unchanged.
- PASS: grammar parses of both modified app Swift files and the expanded native fixture; current Bot source contracts; category selection/editor/save wiring inspection; 13 new English/Simplified/Traditional Chinese entries with every pre-existing catalog entry unchanged; diff whitespace. These are source/grammar checks, not runtime evidence.

## 2026-11-07 category editor review
- Reviewing the current uncommitted category/editor changes. Scope includes category matching, scoped persistence, existing whole-document operations, sheet state and regression fixtures. No app/test repair authorized by the review request.

### Category editor review result
- P2: saveDocument scopes the baseline/mutations, but still unconditionally clears global lastSaved at BotMemoryStore.swift:413. If automatic ordinary/event review finishes while a fixed editor is open, the newly allowed fixed save preserves that new row but clears its Remembered/Undo banner. BotWorkspaceView.swift:204/692 gates the banner on lastSaved. Previous whole-document baseline would reject this concurrent same-owner addition. Preserve lastSaved when its entry is outside the edited scope; add a regression to the existing category fixture, which currently performs this sequence without checking lastSaved. Source-confirmed; no native runtime reproduction.
- No other actionable defect found in category membership, scoped row deletion/writes, secret rejection, event identity/grants preservation or catalog changes. Whole-document menu operations remain explicitly documented; not classified as a new defect.

## 2026-11-07 category editor review repair
- Use the actual current transaction record IDs to decide whether to clear lastSaved. This preserves other categories/owners without relying on potentially stale metadata in the lastSaved snapshot. Cleanup remains after COMMIT, so rejected/failed saves preserve the notification.

- Fixed: after COMMIT, saveDocument clears lastSaved only when its ID is present in the transaction current records. Unrelated categories/owners keep the exact snapshot; early exits and failures retain it.
- Existing native fixture now asserts unrelated automatic-addition retention, cleanup on own-category save/deletion, retention on baseline rejection, retention for another owner during whole-document save and successful Undo afterward. Native execution remains pending.

## 2026-11-07 Poki automation research
- Requested sources: https://github.com/JosssphZhou/poki and https://github.com/carrotciallo/poki-for-linux.
- Research scope: source-backed iOS integration feasibility; no app implementation or runtime validation yet.
- 已确认两仓库实际控制的是 iPhone，Mac/Linux 是运行自动化协议栈的主机。用户明确目标是同一台 iPhone 上的其他 App，不是电脑。
- 固定调研快照：poki 7ee03e3426db8a7b118a987e1dff7f74bef91124；poki-for-linux c2e90ae58b75a159445877a5f28638acc9f1c9ad（默认 linux-port）。两者 AGPL-3.0-only；底层 Rust idevice + CoreDevice/AX/HID，不能先验按 WDA/XCTest 假定。
- Linux README 声称支持真实设备 USB/Wi-Fi、需要 Developer Mode + UI Automation + DDI；这属于维护者实测声明，本机未复现。
- 重要修正：不能把“iOS 公开 SDK 没有通用跨 App 点击 API”推成“非越狱设备上绝对不可做”。idevice 已有 iOS 嵌入使用者，StikDebug 通过配对文件、loopback VPN 和原生 FFI 创建开发者隧道。该事实证明连接路径可行，尚未证明 Poki AX/HID 在同机后台端到端成立。
- StikDebug 最新 PAIRING.md 还声明 iOS/iPadOS 27+ 支持设备端配对；此为额外候选路径，不能把始终需要首次电脑当作绝对条件。
- Apple 安全文档确认沙箱/entitlement 限制；需将稳定公开能力与开发者协议实验能力分开判断。
- Deepened on-device candidate with pinned StikDebug 9d7a917c7d698ed6d393ee3dc1a8ff1feba773fe: JITEnableContext.swift:387-449 reads RemotePairing file, connects to configured device IP, calls tunnel_create_rppairing, and obtains adapter/RSD handles. This is stronger evidence than a README alone.
- Poki pins idevice 89702099f4d7552f704f93b4526756abda319ceb, matching the idevice revision inspected. Its Rust library is MIT; Poki wrapper/AX parser/interaction orchestration are AGPL-3.0-only. Do not conflate library and wrapper licensing.
- Main technical gaps for same-phone integration: iOS static library + C ABI, own-device network transport, DDI/media/HID availability, switching target app with background agent continuity, serialization across Bots, screenshots and cancellation outcomes.
- 本地关键约束：BrowserUseOffloadBridge.swift:159-165 已明确 shell 可跨聊天并发，不能沿用旧 sandbox summary 的串行假设。同机 UI 只有一块前台屏幕，必须单独建立全局设备操作 owner/lease。
- MCP screenshot 不是开箱即用：Poki 返回 MCP image content；当前 minis-mcp-cli call 将完整 result JSON 打印到 shell stdout，shell_execute 把它作为文本，现有视觉输入通过 read_image/browser 原生分支。桥接方案需图片落盘并接 read_image，不能声称“填 URL 就完整可用”。
- 当前 app 已有 BGContinuedProcessingTask、audio/location 后台机制；仍需实际验证切走到其他 App 后的 agent+Rust+模型请求链，不能声称现有增强后台已解决同机控制。
- 当前 src/shared/cli/a11y-cli.md 是待定历史草稿，写明 iOS 不提供普通 OS accessibility client 命令，不能据此否认开发者配对协议实验路线；也不能把草稿中的旧 Android 状态当作当前 fork 事实。报告将明确现状无此功能，并补充研究范围内的新候选路径。
- 初步结论：有依据支持投入最小同机 PoC；没有依据宣称可直接接入或已实现稳定控制。Linux port 解决的是主机兼容性，不是 iOS 自控能力。

### Poki research final findings
- Added docs/ios-poki-automation-feasibility-2026-11-07.md with pinned source links, capability map, current-fork integration boundaries and A-F hardware acceptance gates.
- Recommended candidate: native Swift/C ABI/Rust static library + idevice + AX/DVT/CoreDevice HID through an authorized same-device developer tunnel. StikDebug establishes the connection half; Poki establishes host-driven automation half. Their combined same-phone background loop remains unverified.
- No app implementation or tests executed; existing user code changes preserved. Report distinguishes on-device experimental automation, host-assisted control of the phone and limited public intent workflows.
