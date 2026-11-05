# Agent prompt alignment implementation plan

> Execute inline with superpowers:executing-plans. The user approved the six findings and correction order from the current conversation.

**Goal:** Align shipped prompts with Commander, direct specialist Bots, memoryless helpers, tool switches and model-group fallback.

**Architecture:** Share full prompt composition between initial dispatch, inner model fallback and outer refresh. Keep existing capability ownership, memory gates, tool schemas and persisted Bot format.

**Tech Stack:** Swift, Python standalone regression runners, existing macOS validation workflow.

## Constraints and decisions

- Scope is the six approved audit findings; preserve unrelated working changes.
- Use current checkout for this focused repair. Git metadata is read-only in this environment; do not create branches, commit, push or trigger builds.
- Keep onboarding configuration required; clarify that answering the generated question is optional for the user.
- Keep current tool and memory authorization behavior. Fix conflicting claims rather than introduce new permissions.
- No new packages or Xcode project entries. Add the shared composer to the existing SystemPrompt extension.
- Native execution requires Swift/macOS; local source checks must explicitly distinguish skipped native checks.

## Tasks

- [x] Add a regression runner covering full prompt composition, all four inner fallback branches, initial dispatch and outer refresh. Run it before implementation and confirm the missing composer failure.
- [x] Add `agentSystemPrompt(for:basePrompt:)` to compose base, model fragments, scoped skills/MCP, retrieved memory and authoritative status. Use it at every full-build site.
- [x] Scope model autonomy to authorized actions; clarify asynchronous callback behavior and remove blanket post-turn inactivity claims.
- [x] Match Commander/direct-task/memory tool instructions to runtime availability. Align required onboarding descriptions and user guide memory semantics.
- [x] Update affected existing source guards to follow the shared composer. Add native composer fixtures for Bot/helper scope, fallback model fragments, missing capabilities, disabled memory and no duplicated context; extend existing command fixture for Commander switch behavior.
- [x] Run targeted portable checks; register native runner in existing validation workflow. Review final diff and preserve unrelated changes.

## Verification outcome

- Regression failed before implementation on the absent shared composer; dispatch wiring passed afterward.
- Existing Bot source contracts and all seven chat-settings source tests passed.
- Changed Python/YAML and scoped Swift source/fixture syntax parsed successfully. Full LLMTypes.swift tree-sitter parsing was inconclusive; its changed behavior property parsed independently.
- Independent review found one stale source-test assertion; corrected and rechecked. No other blocking findings.
- Swift runtime, native UI type checking, Xcode build and live model/device acceptance remain unexecuted on this Windows host. macOS workflow now requires the new behavior fixture; no workflow run was triggered.

## Review focus

- Inner fallback must include dynamic context before its first outbound request.
- Helpers inherit parent skill/MCP scope but never gain private memory; specialists retain target scope.
- Fallback must replace model-specific limits and behavior without duplicating fragments.
- Agents/memory disabled states must not advertise callable tools.
- Explicit user authorization remains valid; no blanket extra confirmation for ordinary authorized tool use.
