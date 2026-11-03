# iOS browser observe and run implementation plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task by task. The current user authorized inline execution without commits.

**Goal:** Allow callers to observe an existing tab and execute a bounded sequence of same-document actions while reporting partial progress.

**Architecture:** The native per-tab serial slot owns the batch. An isolated JavaScript world owns document and DOM-node identity and condition checks. One compact observation is captured at the end if the original document and automation context are still valid.

**Tech stack:** Swift, WebKit, existing browser_use direct and CLI routes, Node and Swift standalone harnesses.

**Spec:** C:/Users/shijiu/Desktop/General/dev/OpenMinis/build/investigations/browser-design-1479234/comparison.md; implementation base a0e31dd407bb09f906c641e26550b723f5734b4c (browser sources unchanged from 1479234).

## Protocol and limits

- observe: optional existing tab_id and selector, default scope body. Returns tab_id, documentVersion, frameId=main, bounded text (2,000 characters), at most 20 interactive elements with ref/role/name/disabled, and whether iframes are present. Light DOM in the main frame only. No form values; use secure_input for credentials.
- run: required tab_id, document_version, frame_id=main and 1–12 steps. Steps use click/type and ref; type requires text (max 512 UTF-16 units). Optional per-step until and top-level until. Conditions are visible/enabled with unique CSS selector or url_contains with value. Top-level and per-step conditions accept JSON object or encoded JSON string where needed by schema. Timeout is shared, 100–15,000 ms, default 8,000. No automatic retry. New actions default preview=none; run may request one final UI preview with preview=default within the same budget.
- Partial results use completedSteps (array of zero-based step indices), failedStep (zero-based index), uncertainStep (zero-based index) when dispatch was not confirmed, stopReason, and optional observation. A successful dispatch counts even when its condition fails. A pre-action ambiguity or stale node must not dispatch. Stop on document navigation, intercepted dialog, popup, native takeover, secure input, cancellation or budget exhaustion; re-observe before deciding next action.
- Maintain current single-step/execute_js/scroll and collection/secure input/download/CLI behavior. Batch stops on a download transition while the existing download delegate handles it. No frame injection, delta caching, or new concurrency.

## Implementation

- [x] Write a Node fixture for observed references, duplicate targets/conditions, replaced nodes, immediate and delayed goal checks, and blocked secondary actions after a modal or changed document. Run it red against absent runtime.
- [x] In BrowserUseActions.swift validate typed batch input before dispatch, model progress and output, and retain legacy defaults. Add invalid-input cases to the existing Swift behavior fixture.
- [x] In BrowserUseJavaScript.swift implement isolated runtime and reuse click/type DOM snippets for selector and ref entry points. Register the condition observer before mutation, check synchronously after mutation, then wake on a useful DOM change with bounded polling fallback. Run fixture green.
- [x] In BrowserUseManager.swift dispatch observe and run before legacy postprocessing; check native epoch and automation state between bridges; retain completed/uncertain steps on interruption. In BrowserTabPool.swift use the existing serial slot and reject missing explicit tabs; keep structured progress across takeover and safe termination. Exercise real manager flow through extracted standalone Swift where swiftc is available.
- [x] Update direct schema and parse once, preserve CLI --json routing, document example and limitations, run targeted tests and git diff --check, then write implementation report.

## Review focus

- WebKit can deliver a navigation or popup asynchronously; runtime document identity and synchronous delegate epoch updates both guard the next step.
- A bridge timeout can leave the last dispatch unknown; report uncertainStep and never suggest replay.
- A replaced node or ambiguous condition cannot redirect an action to another element.
- Secure input and takeover invalidate observations, including when a batch is queued.
- Windows standalone checks are not evidence of a WebKit or Xcode build.


Execution evidence and unresolved Apple-host verification: docs/ios-browser-batch-implementation-report.md.
