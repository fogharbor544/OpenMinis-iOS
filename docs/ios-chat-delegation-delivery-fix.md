# Historical sends and Bot delivery

Explicit composer sends/enqueues coalesce into one nonanimated latest-position transaction. It cancels old scroll/measurement deferrals, resumes updates asynchronously, applies the newest snapshot, lays out and positions at the tail. Snapshot and interaction callbacks defer reentry. Background results keep the history browsing position.

Target Bot private chat projects one stable presentation row per delegation, positioned using persisted message creation times. These rows never enter model or database history. Active tasks show the commander as source; completed/stopped/failed tasks retain their own conversation entry. Counts are queried asynchronously from ChatStore at persisted session boundaries and cached; tools, thought, reminders and callbacks do not count, and assistant tool-round continuations merge.

Bot callbacks resolve actual delegation/session ownership and open that Bot conversation instead of generic helper details. Missing records/sessions do not recreate or replay a task. Named Bot work uses bot_task; generic helpers remain available through subagent_task. The existing target Bot VM/configuration/scoped-memory execution path remains in use.

The default commander pass checks completeness and summarizes, without a mandatory independent verification request. Statuses are result returned, summarizing and delivered. A consumed callback is associated with its result content and record version. Only a nonempty, error-free endTurn answer confirmed in SQLite can deliver that version. Queueing, cancellation, resumable/errors and reworked newer versions do not deliver it. Legacy complete acknowledges receipt without changing delivery status.

Validation includes existing direct-runtime and chronological projection regressions, SQLite confirmation and logical counting, and a native UIKit fixture compiling the shipping latest-position transition, snapshot guard and MessageListLayout with controlled markdown/tool-shaped content. Model/network and diagnostic header memo boundaries are stubbed. The fixture does not substitute for physical keyboard/deceleration/text-selection or full-app/provider acceptance. Local Windows checks cannot execute Swift/UIKit; the GitHub workflow runs native checks and a full unsigned device build. The IPA remains unsigned and must be re-signed for installation.

Existing local browser optimization changes are preserved and excluded from this task commit.
