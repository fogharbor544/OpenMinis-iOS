# Fresh-product agent backup baseline

Date: 2026-10-30. This supersedes the upgrade-policy recommendations in
`ios-legacy-data-inventory.md`. The product baseline is the current Bot model,
not migration from a previous released app.

## Removed upgrade-only behavior

- Unowned ChatStore sessions are no longer automatically assigned to the
  commander at home-screen load/refresh. Current Bot creation, shortcuts and
  delegation establish ownership explicitly; restore now restores that mapping.
- Bot/room memory switches no longer read old session switches. Bot skill/MCP
  choices no longer read a former main session as a migration fallback. Editors
  and session creation no longer copy those settings. New profiles explicitly
  default to enabled memory and empty override dictionaries (global tool defaults).
- Skills no longer run the one-time bundled-file re-upload migration. The
  `use_count` column is part of fresh table creation, not an upgrade ALTER step.
- Retired SOUL backup export/import and sync registration/hydration/force-sync
  helper were removed. Shared identity structures still referenced by live
  activity/widget interfaces were not deleted indiscriminately.
- Speed tiers now use only the current string preference. The old fast-mode
  Boolean, its SwiftUI storage and its UI fallback were removed. The legacy
  Boolean thinking-setting decode was removed; current thinking levels remain.
- Removed the empty MCP legacy-cleanup heading.

No on-device files, databases, conversations or credentials were deleted by
these edits. Old formats are not migrated or automatically cleaned from disk.

## Retained because they serve current functionality

- Shared password vault reading and linked-source updates: the name
  `legacyVaultURL` did not make this an unused migration.
- MCP import layouts and missing creation-time normalization for externally
  authored current config files.
- Optional/default fields in sparse external configurations; model-group
  membership clocks, tombstones and current sync conflict protections.
- Provider JSON loading when a DB is not attached; this is also an initialization
  path, not only upgrade recovery.
- Folder records in the current ChatStore/backup/sync schema. Removing home UI
  does not itself remove those current data references.
- Optional wire fields needed by the current synchronization protocol. Sync is
  not the same operation as importing a device-transfer archive.

## New backup contract

New packages use `minisbak/2`; `minisbak/1` is not imported by this baseline.
Required manifest identity/category fields are no longer fabricated when absent.

The new `agents` category writes `data/agents.json`, a versioned logical archive:

- All current Bot configurations, even Bots without private env-vars/subagents.
- Groups, membership, display ordering/pins, and group transcripts when chats
  are selected. A restored group is not marked as running.
- Bot/group conversation bindings and session ownership, including delegated
  child sessions. Only sessions actually exported can be referenced.
- Current BotMemoryStore entries, owner IDs, grants, source references, status,
  replacement links and timestamps. Forgotten-entry markers travel too, so an
  older archive does not resurrect a newer local deletion.

Selecting chats, providers or environment variables also includes `agents`.
The picker displays this dependency; deselecting agents deselects those related
categories. The export validates private capability owners against the archived
Bots, not a later live snapshot. Backup capability records now carry owner IDs
without redundant embedded Bot profiles. Separate sync records retain their
owner snapshots; this patch does not introduce full workspace cloud sync.

Without chats, agent configurations and memories still export, but session
bindings, group transcripts and memory source-message links are cleared.
For a device migration, select every default category and include credentials.
Credential handling and the existing encryption choice are unchanged; an
unencrypted package may contain readable credentials. Use a passphrase when
transporting a credential-bearing backup.

## Restore and conflicts

1. Validate the archive and its relationships before category writes. Restore
   conversation rows before applying agent ownership. Missing referenced
   conversations fail agent restore rather than silently changing their owner.
2. Merge by stable IDs. Existing local Bot settings win, except an untouched
   factory commander, which is replaced by the archived commander. Missing
   session bindings can be filled. Same-ID groups with different members and
   contradictory session/memory owners fail instead of being guessed.
3. Memory uses its own updatedAt clock; equal/newer local records win, including
   deletion markers. Repeated restore does not create duplicate Bots or entries.
4. Agent workspace and memory updates share a durable undo journal. Memory uses
   a SQLite transaction; workspace publication follows its atomic file write.
   Failure restores the prior snapshot. If recovery fails, the journal stays
   for startup recovery rather than reporting a successful rollback.
5. Running agents/groups or pending conversation creation prevent agent restore.
   The previously unused duplicate-session option is explicitly rejected; this
   baseline does not implement a second identity-remapping/keep-both mode.
6. Failed chat restoration blocks agent restore; failed agent restoration blocks
   scoped provider/env-var restore. Other categories retain the existing
   per-category merge behavior: this is not an all-databases transaction.
7. Restore displays missing model-group/skill/MCP dependencies and retained-local
   item counts. Partial-category restore is not represented as a fully ready
   device when those dependencies are missing.

If a live owned session changed past the backup cutoff and was not exported,
the full agent backup fails with a request to stop tasks and start a fresh backup.
It does not publish dangling agent-to-session references.

## Not transferred

Runtime jobs/timers (AgentJobRegistry is intentionally in-memory), active
generation, device authorization, and arbitrary OS/app-local preferences are
not recreated. System permissions must be granted on the new device. This is
agent/configuration/history transfer through backup, not a claim of a complete
OS image or automatic full-workspace iCloud synchronization.

## Verification

`BotWorkspaceArchiveTests.swift` exercises the real workspace/memory stores:
fresh-device restore, factory commander, independent Bots, groups and delegated
ownership, tombstones, repeat restore, local edits, config-only exports, invalid
relationships, filesystem write failure and interruption recovery. The test is
wired into the existing macOS validation workflow. Transport tests were updated
to distinguish first-class backup owners from sync owner snapshots.

On Windows, source wiring, generated harnesses, Python/JSON/YAML parsing, fresh
SQLite skill schema and Swift grammar comparisons are checked locally. Swift
type checking/runtime tests, Xcode build and a real two-device migration remain
unverified until run on macOS/devices. No remote CI was dispatched, and no
commit, push or CloudKit schema deployment was performed.
