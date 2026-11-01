# Secure input, scoped memory and avatar integration — 2026-11-01

## Changes
- Native secure input waits for a usable foreground window, prefers the browser's window, excludes overlay/hidden windows and retries transitions. The 180-second timeout begins after presentation. Pending requests contain no credentials; stop/tab close/source change/WebContent termination ends the request. Existing displayed-card background cancellation and secret erasure remain.
- Scoped SQLite memory restores model-selected factual summaries, optional provenance, multiple same-scope entries and recent daily injection (pinned plus three nonempty dates within 30 days, 200 lines/day). No extra per-turn LLM call. Owner/grant boundaries, toggle, explicit correction/deletion, deduplication, secret refusal and tombstones remain. Old todos are context, never execution authorization.
- Shared transactional avatar selector across new/edit/profile. Optional stable preset ID preserves old data and backup compatibility. First new Bot selects Pikachu; later Bots use the least-used preset. Photos/icons remain available. Static list avatars retain whole-row chat navigation; previews use one-shot native playback. Two-set decoded-frame cache, visibility/background/power/reduce-motion stop rules.

## Asset blocker — not delivered
The built-in imagegen rejected the first Pikachu 24-frame atlas with `moderation_blocked` (output stage, category `other`). No character image or animation was produced. No CLI fallback, static-motion substitute or unapproved original creature was used. All 12 catalog identities are implemented, but the picker only enables presets with actual cover assets. Missing art falls back to the legacy symbol and the picker explains availability. User has a pending choice about providing assets, choosing original creatures or deferring art.

### Asset integration contract
For each stable ID (`pikachu`, `bulbasaur`, `charmander`, `squirtle`, `eevee`, `jigglypuff`, `snorlax`, `psyduck`, `gengar`, `mew`, `togepi`, `meowth`):
- `BotAvatar-<id>-cover.imageset`: square PNG with alpha; full figure within a circular safe zone.
- `BotAvatar-<id>-atlas.dataset`: alpha PNG in a 6-column, 4-row equal-square grid, row-major 24 poses; recommended 256px/cell, maximum 512px/cell. Native playback is 12fps / 2 seconds, once then cover.
- Place sets in `src/ios/Assets.xcassets`. Do not ship placeholder character art. Final production frames still require visual identity, silhouette, alpha, action and seam review.

## Validation status
Windows local: production JavaScript fill tests (55 assertions), current Bot contracts, seven chat/settings contracts, fresh database initialization, Python syntax and whitespace checks pass. Swift compilation, simulator fixtures and cloud package are pending at this checkpoint.
New native fixture uses a real UIWindowScene and the shipping presentation coordinator/renderer, synthetic notifications and test images. It does not validate real website login, actual device background lifecycle, final character artwork, hardware power settings, VoiceOver navigation or keyboard behavior. Those remain explicit device acceptance items.
