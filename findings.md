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
