# iOS implementation plan

Goal: implement browser bookmarks and credentials, Bots and collaborative groups, unified scheduled tasks, and a built-in capability catalog in the MCP entry. Only iOS code; seek approval before shared/backend changes.

## Phases
1. Inspect current implementation and DS-Bot reference (in progress).
2. Browser bookmarks and credential management.
3. Bot configuration and bounded group orchestration using existing agent runtime.
4. Unified scheduled-task UI and MCP capability management.
5. Targeted tests, cloud build if available, requirement-by-requirement audit.

## Constraints and issues
- Workspace is a source snapshot without .git; do not assume remote or clean baseline.
- Windows cannot run Xcode locally.
- RTK executable access denied; invoke native tools explicitly.
- GitHub page fetch failed; use GitHub API/raw source next.

## Current implementation status
- Bookmarks: source implementation and XCTest cases added; source registration checked. Not yet built or runtime tested.
- Credentials: awaiting scope confirmation; inspection can continue.
- Bots/groups: reference README read; implementation source and existing sub-agent/session contracts still to inspect.
- Scheduled tasks: registry and detail adapter identified; UI not yet implemented.
- MCP capability catalog: existing external server UI identified; built-in capability inventory pending.

## Additional errors
- Python static check initially decoded as GBK; fixed by explicit UTF-8, registration check passed.
- gh API unauthenticated rate limit; raw README retrieved through web tool.

## 2026-10-28 current status (supersedes earlier inventory)
- Repository created and uploaded: fogharbor544/OpenMinis-iOS (private), main based on exact matching upstream source snapshot with preserved submodules/history.
- Bookmarks: implemented, XCTest added; syntax validated in cloud, XCTest execution pending.
- Passwords: user confirmed Keychain scope; vault + capture/edit/delete/fill + device authentication + background lock implemented; exact-origin XCTest added. Syntax validated, integration/device tests pending.
- Scheduled tasks: global Settings entry and all non-immediate registry jobs, detail/history reuse, in-place editing + enable/disable/delete implemented. Existing scheduled regression scripts pass in cloud; new edit path still needs behavioral tests and full build.
- MCP: built-in catalog + existing control destinations + global gates + native permission controls implemented in e544593; no new MCP service. Complete inventory and runtime consistency verification pending.
- Bots/groups: not implemented. DS-Bot groups.js source examined (ordered rounds, mentions, member sessions, relay limits). Next primary implementation task.
- Localization/accessibility review and requirement-by-requirement completion audit remain.

## Live cloud handles
- Source validation f5f3ae1: run 40671230603 SUCCESS (Swift parse + ScheduledRunNowTests + ScheduledTaskDetailTests).
- Full device build f5f3ae1: run 40671460507, device-build job 122759001312 IN_PROGRESS at Toolchain as of last check. Poll this existing run; do not restart merely on observation timeout. It excludes later MCP commit.
- MCP commit e544593 pushed; its push validation run ID not yet inspected.
- Use gh with require_escalated to access Windows keyring. Sandbox gh falsely appeared unauthenticated.

## 2026-10-28 Bot implementation progress
- c9cf74d: BotWorkspaceStore persists profiles, group rosters, ordered transcripts and per-member ChatStore session IDs. Separate Sessions extension reuses ProviderConfigStore/ModelGroupRouter, SkillStore, MCPStore and ViewModelCache. System prompt reads Bot identity/instructions by session. BotRoomRunner uses submitProgrammaticPrompt + awaitProgrammaticTurn; no new LLM/tool loop.
- Collaboration rule announced before implementation: one user-triggered round, selected members (all or one) speak once in roster order, shared recent 30 messages, isolated group sessions, no implicit private-history injection, no bot-to-bot automatic relays; stop cancels active member and pending round.
- Bot CRUD + group creation/member ordering + group transcript/tool-conversation links implemented. Deleting Bot retains ChatStore conversations and old group messages; group deletion confirmation explicitly removes its shared transcript while keeping member conversations.
- 8da8572: Bots/Groups is now default home mode; History switches back to original session list. Settings remains accessible. Added 70 new en/zh-Hans catalog entries without replacing existing translations.
- Source checks + actual BotWorkspaceStore persistence executable passed at c9cf74d in run 40673560081 (also source-checks of full run).
- Full run 40671460507 failed at iSH VDSO due missing lld; fixed workflow installs lld and exports its bin.
- Full run 40673562093 passed iSH but failed Rclone build: go-json-experiment aliases incompatible with latest Go (undefined json.SkipFunc/DiscardUnknownMembers). 8da8572 pins setup-go to deps/rclone-mobile/go.mod (1.25.5), GOTOOLCHAIN=local; no shared dependency source changed.
- Latest full run: 40674325821 for 8da8572, created and separately status-checked. Follow this handle next; do not rerun until terminal/failure diagnosed.

## Remaining verification and defects to inspect
- No full app compile or simulator/device UX validation yet. All five feature sets now have initial code, NOT completion evidence.
- New schedule edit logic needs behavioral tests; bookmarks XCTest and credential-origin XCTest not yet run.
- Credential Keychain/auth cancellation/capture/fill and browser navigation need meaningful integration tests.
- Bot runner needs lifecycle tests (stop/failure/missing model, locked sessions, current-round output), and integration/UI checks. Home mode/navigation/accessibility not visually verified.
- Check Bot profile edit/delete while private chat runs and whether error paths preserve history; do not introduce broad unrelated race machinery.
- Complete MCP capability inventory against actual native command registration; verify permission controls match execution.
- Localization added only 70 new keys; remaining long descriptions/dynamic labels still need review, not all locales translated.
- Completion audit is outstanding; goal remains active.

## Current status (supersedes prior pending test notes)
All five feature implementations are committed and pushed. Source tests on ee6a46e passed (40677726185): existing schedules, shipping Bot persistence, browser storage Swift 5/6, shipping schedule edits, shipping group runner with runtime stubs. Catalog includes all 28 public native handlers. Full build 40677212206 remains active on de66115; latest app source is identical. Next: finish full-build diagnosis if needed, report five-feature acceptance and honest device-testing limits, then mark goal complete only if build succeeds and no required implementation remains.

Latest handles: full build 40679242581 (c47b4ef), source 40679532187 (bb24cfd, adds real WKWebView form tests), both QUEUED. Earlier 40677212206 failed on iOS17 onChange overload; all new two-arg usages fixed. Finish these before claiming completion.

Latest source handle now 40680004272 (1c5f0b1, includes actual permission-manager tests and WebKit tests). Retain full 40679242581. Both verified queued with no assigned runner; superseded source runs cancelled. No new full build should be dispatched for test-only changes.

## Completion
Full build 40679242581 attempt 2 SUCCESS. Latest comprehensive source tests 40687411282 SUCCESS. Latest main e20b4d7; app source matches successful build c47b4ef. All five requirements and evidence mapped in src/ios/IOS_FEATURES.md, including explicit device/auth/model-service limits and next validation steps. Implementation and available validation complete.

## Bot long-term memory design (2026-10-28)
- Inspect iOS memory storage, injection, tools and Bot session binding (in progress).
- Propose ownership, group behavior and migration; no business-code changes.
- Tool issues: RTK denied; use native rg. Broad search hit generated/localized content; restrict to Swift.


## Bot memory design result
- Code inspection complete; design and migration recommendations ready.
- Scope: current iOS Bot implementation. No application changes or tests run.
- Remaining product choice: whether group turns read the same Bot private long-term memory.
- Additional inspection issue: guessed ChatStore+Sessions.swift path absent; no dependency on that file for conclusions.


## 2026-10-29 Bot memory implementation
- Authoritative scope: latest final answer in thread 01a182a2-50da-7e12-8da5-074e9e4113ed, repeated verbatim by user.
- Implement: Bot multi-conversation ownership; SQLite entry store with provenance/status/tombstones; scoped bounded retrieval; explicit and conservative automatic saving; UI correction/deletion/undo; opt-in shared materials and group sharing. Private Bot memory never automatically injected into group turns.
- Keep legacy daily files intact for non-Bot conversations; no automatic migration or reinterpretation.
- Sequence: ownership/storage -> runtime/tool integration -> UI -> targeted tests and cloud build. No business-code edits made before this entry.

### Bot memory verification handles
Latest main 8e1e3db. Source 40748889694 passed edc53cf; 40749547752 currently running 8e1e3db. Full build 40748416825 running on Intel macOS26 at native dependencies, revision640fa34. Pending full compilation; see progress.md for all code paths/choices. No new full run until current diagnostic result, unless deliberately superseding code (not timeout).

Bot memory implementation and targeted cloud checks complete at 8c3e207; full unsigned ARM app build pending runner availability (40750367982).

## Fresh-product compatibility removal (2026-10-29)
User confirms no historical data. Remove old memory/Bot schema compatibility, configuration/directory migrations, sync migration UI and V1 paths, old compact format fallbacks; preserve current initialization and runtime. Verify targeted cloud checks and full build. In progress: dependency mapping.

## Code review fixes 2026-10-29
1. Verify CR-01 through CR-06 against shipping code (in progress).
2. Implement focused fixes and regression coverage.
3. Run available checks and update report with honest runtime limits.
Errors: RTK access denied; use git.exe/rg.exe. Root instruction file not found; inspect file inventory.

## Code review repair final status
1. CR-01–CR-06 source verification complete.
2. All six focused fixes and regression coverage implemented.
3. Available local checks complete; report updated. Swift/Xcode unavailable: macOS behavior/typecheck/full build remain explicitly unverified. No push or commit performed.
Errors: rg wildcard paths on Windows rejected; resolved with directory + glob searches. Swift parser limitations matched against HEAD, no new errors.

## New-account cloud packaging
User authorized private repository darkyuanbao06/OpenMinis-iOS, upload repaired source and cloud package. Account device authorization completed. Commit e9439b9 prepared; push in progress. Added unsigned IPA artifact packaging. Follow source tests and full macOS build; fix actual failures. Errors: protected .git requires escalation; report hard-break trailing whitespace normalized before commit.

## Cloud packaging complete
Private repository created and all code pushed to darkyuanbao06/OpenMinis-iOS. Full workflow40807208387 SUCCESS on4c0b1ff: source checks and unsigned device build/package/upload passed. Artifact12868927265 (OpenMinis-unsigned-ipa) available. Final report updated with cloud evidence; signed install/device interaction remain out of scope/unverified.

## Device feedback 2026-10-29
- Inspect launch/signing, connectors and permissions, Bot-only navigation, avatars, schedule localization and soul injection.
- Implement focused fixes; validate locally; do not commit or push.
- RTK wrapper denied; absolute executable paths work. Existing planning history preserved.

## Device feedback implementation status
- Local implementation complete: launch App Group fallback, connector system permissions, Bot-bound UI/intent/schedule/copy entry points, avatar selection, schedule localization.
- Soul analysis recorded in docs/ios-device-feedback-2026-10-29.md; SOUL behavior unchanged.
- Local grammar/catalog/diff checks completed; Swift runtime/Xcode/device testing unavailable. Crash root-cause confirmation still awaits signing details/logs.
- Preserve all changes uncommitted and unpushed as requested.

## Remove redundant settings (authorized)
- Keep existing Files entries, remove Files from connectors only.
- Consolidate skills/connectors and memory into Bot/room-owned settings; remove SOUL runtime/UI/tool registrations and new exports; retain old archive/sync compatibility.
- Simplify launch options, distinguish temporary model override, combine native OS authorization with local tool approval.
- Preserve existing uncommitted work and user data. No commit/push. Implemented; static checks passed. Swift compilation and device validation unavailable here.

## Additional device feedback (implemented; device validation pending)
1. Extend scheduled editor to date/time and repeat controls.
2. Unify password persistence and website autofill, suppress secrets in chat; inspect legacy file source.
3. Add browser settings bookmarks/password entries.
4. Move runtime entry points into Bot; scope conversation files.
5. Merge home into expandable Bot/group conversations, plus creation menu and same-Bot new chat.
6. Targeted static/regression verification; no commit/push.

Validation: 68 changed Swift files scanned against HEAD, no extra parser errors; JSON/diff/wiring checks passed. Production autofill JS executed successfully under Node. Swift regression cases added but not run (no Swift/Xcode). No commit/push.

## Review follow-up fixes
- Fixed all three reported issues: browser test boundary, calendar test extraction, homepage batch-selection routing.
- Verified actual generator output with Swift subprocesses mocked, Python syntax, generated Swift syntax, selection routing and whitespace. Added calendar regression cases for future macOS execution.
- Full Swift compilation and device interaction still require macOS/Xcode; no commit/push.

## Active seven-item Bot feedback (2026-10-29)
1. Home group-chat label and retire obsolete appearance grouping control.
2. Visible Bot run/completion/error status.
3. Keep Bot memory entry only below Model Group in Bot editor.
4. Remove in-chat Bot editing; add schedules/environment shortcut; rename Open Files.
5. Default renameable commander with real task decomposition/delegation.
6. Fix group result collection against actual runtime completion.
7. Global tools/subagents/environment settings; remove editor runtime section.
Status: inspecting source, implementing navigation first. No commit/push authorized in this continuation. All seven remain in scope; runtime and compilation verification pending.
Errors: RTK executable denied (use native tools with login=false); guessed source paths absent (use rg inventory).

### Seven-item current audit
Implementation present for all seven; local static checks passed (see progress.md). Added docs/ios-bot-team-feedback.md with exact behaviors and pending gates. Awaiting user response to commit/push/cloud-validation authorization. Do not infer approval, dispatch CI or claim tests passed. No goal completion yet.

## Commit review 76582ed (2026-10-30)
1. Read patch and repository guidance (complete).
2. Trace runtime, persistence, navigation and test coverage (in progress).
3. Run feasible focused checks and report actionable regressions (pending).
Scope: review only; preserve existing untracked planning files and application code.
Errors: RTK executable blocked in sandbox; read-only Git commands escalated. No project instruction file found in inspected source paths.

### Review completion
- Phase 2 complete: all 35 changed files reviewed, with runtime/capability, cache/session, backup/sync and UI callers traced.
- Phase 3 complete: commit diff whitespace check and changed Python AST checks passed. No Swift/Xcode tools available.
- Report three actionable findings: delegated capability selection, unreachable chat controls, unresolved owner IDs on restore/sync.
- Validation gaps: new profile UI stubbed in typecheck harness; EnvVarDisableTests old signature assertion no longer matches. No production code changed.

## Repair review findings 1 and 3 + legacy-data inventory (2026-10-30)
1. Inspect capability resolution and backup/sync dependencies; preserve current 41 unstaged changes (in progress).
2. Fix delegated capability ownership and transport/restore scoped capability owner identity; add focused regressions.
3. Inventory remaining old-data handling without modifying its behavior.
4. Run available focused checks and report limits; no commit/push.

### Repair status
- Steps 1-2 implemented, targeted validation pending.
- Step 3 inventory being written; no old-session adoption/search/UI behavior changed.
- Step 4: generated transport test source and wiring assertions pass; Swift execution remains unavailable.

### Repair completion
- Steps 1-3 complete: delegated capability resolution, scoped owner transport/restore, regression coverage source and legacy-data inventory.
- Step 4 complete for locally available checks: wiring/generation, Python AST, Swift grammar comparison and diff whitespace. Swift execution/typechecking and device/cloud verification remain external gates, not passed tests.
- Scope held: no change to issue 2 history/UI policy; no commit/push/CI dispatch.

## Fresh-product cleanup and complete Bot backup/restore (2026-10-30)
1. Inspect current backup/rollback/restore and remove upgrade-only behavior that is not part of current functionality.
2. Add first-class Bot workspace and memory backup with session/owner references and explicit restore collision/dependency handling.
3. Integrate restore ordering, rollback and live-store refresh; keep secrets in the existing protected path.
4. Add focused regression coverage and run available validation. No commit, push, external CI, real-user data deletion or CloudKit deployment.
Status: step 1 in progress. Preserve all known dirty files from prior work.

### Fresh-product phase update
1. Cleanup complete for confirmed upgrade-only paths; active data contracts retained.
2. First-class agent archive and stable-ID relationships implemented.
3. Restore sequencing, durable workspace/memory rollback, launch recovery and UI integration implemented.
4. Targeted tests added; final static validation/review in progress. Swift/Xcode/device checks remain unavailable locally.

### Fresh-product completion (local implementation)
- Steps 1-3 complete; step 4 complete for available local validation and added macOS regression coverage.
- Pending release gates: run the existing macOS workflow, then validate a fresh-device restore and repeat restore on iOS. These are not reported as passed.
- Final scope and retained compatibility rationale: docs/ios-agent-backup-baseline.md.

## Review follow-up 2026-10-30
1. Verify the three reported defects and inbound cursor / SOUL risks (complete).
2. Repair confirmed defects while preserving existing uncommitted work (complete).
3. Add focused archive, format and inbound completion regression coverage; run local checks (complete locally; Swift execution pending macOS).
Constraints: no Swift/Xcode locally; no commit, push or CI dispatch. Existing plan history preserved.
Read-only tooling: RTK access denied; native executable names work. No project-level instruction file found.
Validation: 11 touched Swift sources match baseline grammar, generated harness grammar / Python AST / workflow YAML / diff whitespace pass. Parser packages reused from build/validation-python after the global Python import failed. No Swift tests or cloud builds executed.

## Authorized cloud build and IPA delivery (2026-10-30)
1. Verify target and all pending changes (complete): existing private darkyuanbao06 remote; retain codex/bot-single-chat.
2. Commit/push all current project changes and dispatch full workflow (complete).
3. Follow tests and Debug device build; repair real failures and retry as needed.
4. Download successful unsigned IPA, verify archive and report exact revision/run.
User now explicitly authorizes commits, pushes, cloud builds and download. No signing requested. Native git/gh with keyring access required; sandbox gh falsely reports invalid tokens.

### Cloud delivery complete
- App revision d839804: run41037513427 device-build SUCCESS (Debug arm64, unsigned IPA packaged/uploaded). Source job failed only at unsupported macOS XCTMain runner.
- Test-only repair 3b54e72: run41038602235 SUCCESS; all source/regression steps including archive, capability transport and format/inbound passed. No application-source difference from the built revision.
- Downloaded build/cloud/41037513427/OpenMinis-unsigned.ipa (100708665 bytes). ZIP CRC and Mach-O arm64 validation passed; verification.json contains SHA256 and revision evidence.
- Complete local signing and real-device testing remain user-owned and unverified. Final documentation-only commit does not require rebuilding unchanged application code.

## 2026-10-31 Commander removal and device UX repairs
- Scope: iOS only, fresh product; no prior-data/backup/task compatibility; do not delete local/device data, commit, push or dispatch CI without authorization.
- Phase 1 in progress: remove commander and cross-Bot delegation; current-version backup/restore.
- Phase 2 pending: browser initial presentation, navigation title, streaming layout/scroll.
- Phase 3 pending: native secret input, restricted fill, explicit Keychain save/update.
- Phase 4 pending: transitions, Chinese strings, capability/settings consistency.
- Phase 5 pending: targeted behavioral checks and honest separate build/device results.
- Environment: Windows, python/node available, Swift/Xcode unavailable. RTK wrapper denied; native executable calls required. No project AGENTS file found. Initial git status clean.

### 2026-10-31 phase update
1. Commander removal and current-format backup/restore implemented; local contracts pass, Swift behavior pending macOS.
2. Browser/chat repair code implemented; device acceptance pending.
3. Native security implementation in final review; Node fill behavior executed, Keychain/device pending.
4. Chinese/settings/navigation completed at source level; focused checks passed.
5. Final integration and verification reporting in progress. No push/CI authorized; Windows cannot provide Xcode/device results.

### 2026-10-31 verification gate
Phases 1-4 implemented and locally integrated. Phase 5 locally available checks complete: Node 55 assertions, source contracts, isolated SQLite, generation/syntax/JSON/AST and whitespace checks passed. Swift runtime, Xcode build and device results are PENDING, not passed. No new package produced. See docs/ios-bot-single-chat-repairs.md for exact acceptance steps and build/validation/bot-removal/final-syntax.json for syntax evidence.

## Authorized repair cloud delivery (2026-10-31)
User authorizes commit, push, cloud validation/build and IPA delivery on codex/bot-single-chat. Include the reviewed iOS changes and new repair checks in the existing workflow. Follow actual macOS failures until tests/build pass; download and verify the unsigned arm64 IPA for user signing and device acceptance. No device results claimed.

### 2026-10-31 authorized delivery outcome
Commit/push complete at d4453fb. Full run41131029760 passed source-checks and device-build. Unsigned IPA downloaded and CRC/arm64 verified at build/cloud/41131029760/OpenMinis-unsigned.ipa; evidence verification.json/result.json. Requested cloud build/package delivery complete. Signing and device acceptance remain user-owned and unverified. Earlier Windows-only validation notes are superseded for checks actually executed in the cloud workflow; unexecuted native XCTest/device cases remain pending.

## 2026-10-31 device UI follow-up
1. Inspect settings typography, chat top geometry and built-in capability layout (complete).
2. Implement consistent settings scale, unobscured chat viewport and compact capability cards (complete).
3. Run targeted checks and record device/build limitations (complete for available local checks; native build/device acceptance pending).
Scope: requested three iOS UI defects; preserve existing work. No new commit/push/build dispatch requested.
Errors: RTK executable access denied; use native executable paths. No project instruction file found. Windows has no Xcode.

### Follow-up phase update
Inspection complete; source changes implemented for all three defects. Targeted local checks and manual source review in progress. Actual iOS rendering/build still pending.

### Follow-up local completion
7 Python source contracts pass. 8 edited Swift files have no new tree-sitter grammar errors relative to HEAD; Python AST and diff whitespace pass. Authorization/refresh/command-mapping source tail matches HEAD exactly. Updated existing Swift banner guards but did not execute Swift. Device/build acceptance and checklist: docs/ios-device-ui-followup.md. No commit, push, CI dispatch or new IPA.

## Device UI cloud delivery authorized
User requests successful cloud compilation and IPA download for real-device validation. Use existing private darkyuanbao06 remote and codex/bot-single-chat branch. Include the updated banner regression guards in the existing workflow. Commit/push reviewed changes, dispatch full build, resolve actual failures, download and verify unsigned arm64 IPA. CLI credentials require execution outside the sandbox; do not expose tokens. Native device acceptance remains user-owned.

### Cloud test correction
Run41168685061 source job failed only at two previously unexecuted ScheduledBannerTests source assertions referring to nextCronDate; current production code uses nextCalendarFire. Layout guards and compiled banner-model cases passed. Correct two test references, push test-only follow-up and run source checks while the unchanged app device build continues. Verify no application source difference between build/test revisions before artifact delivery. CLI run-log endpoint waits for all jobs; individual completed job logs fetched via API with ANSI stripped.
