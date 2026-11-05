# Commander Roster Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline. User has approved the design and explicitly requested implementation.

**Goal:** Keep Commander built-in rules independent of Bot count and discover specialists through `bot_task list`.
**Architecture:** Remove the computed roster from the shared prompt. Extend the existing guarded command with a read-only list operation returning `bots` containing `bot_id`, `name`, and a maximum 160-character `introduction` (empty when missing).
**Tech Stack:** Swift / existing standalone Swift fixture and Python source guards.
**Spec:** `docs/superpowers/specs/2026-11-05-commander-roster-design.md`.

## Constraints and review focus

- Preserve existing dirty-tree changes, Bot data, execution and shared UI/runtime prompt getter.
- No new tool, storage schema, dependency, migration or model call.
- List must exclude Commander and full instructions, reflect CRUD, tolerate missing introductions, preserve Unicode truncation, and obey existing disabled/helper/specialist guards.
- No commit, push or cloud dispatch; local Windows cannot run Swift/Xcode. Report native verification separately.

## Task 1: Fixed prompt and on-demand discovery

**Files:** `BotWorkspaceStore.swift`, `BotTeamRuntime.swift`, `BotToolCommandTests.swift`, `check_current_bot_contract.py` in their existing locations.
**Interfaces:** `commanderInstructions` remains String; `executeBotTask(_:toolUseID:)` keeps its existing result tuple. `list` returns `{ "bots": [...] }` through `jsonString`.

- [x] Add source regression for a roster-independent built-in policy and schema/handler discovery alignment. Observed failure on old dynamic roster, then pass after the change.
- [x] Extend existing native command fixture: empty list; unchanged policy after 24 long-instruction profiles; missing/long/Unicode/quoted introductions; CRUD freshness; unchanged workspace/runtime start count; capacity-independent listing; disabled/restoring/helper/specialist rejection.
- [x] Remove roster interpolation and describe `bot_task action=list` discovery and untrusted configuration handling in the fixed policy. Add schema enum/description and guarded handler branch returning compact configuration.
- [x] Run source regression, chat settings contract tests and agent prompt source checks. Swift syntax parsing passed; native runner attempted but blocked by missing swiftc.
- [x] Review focused diff against design; independent read-only final review found no Critical/Important defects. Preserved local changes for user review.

## Execution ledger

- Pre-flight: one task; existing prompt getter is shared by UI and runtime. `bot_task` already passes through common tool registration and dispatch; schema/handler change is sufficient.
- User authorization: implement approved design without another approval round.
- Implementation performed in the existing checkout to preserve the approved, uncommitted prompt-alignment changes that this fix builds on. No branch/stage/commit/push/cloud action.
- Verified: Bot source contracts, 7 chat settings tests, agent prompt dispatch source checks, 3 touched Swift sources plus extracted command fixture grammar, Python regression syntax, diff whitespace.
- Native limitation: `run_bot_tool_command_tests.py` could not launch swiftc (WinError 2); native test behavior and iOS compilation remain unverified.
- Extra global check: `scripts/ios-unit-tests/static_check.py` fails on Windows path separators (68 unexplained/59 stale); in-memory POSIX key normalization yields 59 allowed, 9 existing unexplained hits and 2 stale entries in other test files. No unrelated guard/test files changed by this fix.
- Final review: independent reviewer found no Critical/Important defect; review was static, not native compilation.
