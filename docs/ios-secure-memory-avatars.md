# Secure input, scoped memory and avatar integration — 2026-11-01

## Changes
- Native secure input waits for a usable foreground window, prefers the browser's window, excludes overlay/hidden windows and retries transitions. The 180-second timeout begins after presentation. Pending requests contain no credentials; stop/tab close/source change/WebContent termination ends the request. Existing displayed-card background cancellation and secret erasure remain.
- Scoped SQLite memory restores model-selected factual summaries, optional provenance, multiple same-scope entries and recent daily injection (pinned plus three nonempty dates within 30 days, 200 lines/day). No extra per-turn LLM call. Owner/grant boundaries, toggle, explicit correction/deletion, deduplication, secret refusal and tombstones remain. Old todos are context, never execution authorization.
- Shared transactional avatar selector across new/edit/profile. Optional stable preset ID preserves old data and backup compatibility. First new Bot selects Pikachu; later Bots use the least-used preset. Photos/icons remain available. Static list avatars retain whole-row chat navigation; previews use one-shot native playback. Two-set decoded-frame cache, visibility/background/power/reduce-motion stop rules.

## Asset blocker — not delivered
The built-in imagegen rejected the first Pikachu 24-frame atlas with `moderation_blocked` (output stage, category `other`). No character image or animation was produced. No CLI fallback, static-motion substitute or unapproved original creature was used. All 12 catalog identities are implemented, but the picker only enables presets with actual cover assets. Missing art falls back to the legacy symbol and the picker explains availability. User briefly selected original creatures, then explicitly changed the requirement back to Pokémon in a 2D chibi sticker style: rounded outlines, clear color blocks, transparent background and readable small-size actions. A second built-in Pikachu 2D atlas request was also rejected with moderation_blocked. No Pokémon art was produced. The unrelated original-rabbit trial was not integrated. Do not silently substitute original characters or a 3D look. Final art remains blocked; photos and system icons remain usable.

### Asset integration contract
For each stable ID (`pikachu`, `bulbasaur`, `charmander`, `squirtle`, `eevee`, `jigglypuff`, `snorlax`, `psyduck`, `gengar`, `mew`, `togepi`, `meowth`):
- `BotAvatar-<id>-cover.imageset`: square PNG with alpha; full figure within a circular safe zone.
- `BotAvatar-<id>-atlas.dataset`: alpha PNG in a 6-column, 4-row equal-square grid, row-major 24 poses; recommended 256px/cell, maximum 512px/cell. Native playback is 12fps / 2 seconds, once then cover.
- Place sets in `src/ios/Assets.xcassets`. Do not ship placeholder character art. Final production frames still require visual identity, silhouette, alpha, action and seam review.

## Validation status
Windows local: production JavaScript fill tests (55 assertions), current Bot contracts, seven chat/settings contracts, fresh database initialization, Python syntax and whitespace checks pass. Final revision d0c4949 / run41279022146: all source-checks and the native ui-layout job succeeded. The full unsigned arm64 device build and package verification also succeeded. All three jobs passed for the same revision.
New native fixture uses a real UIWindowScene and the shipping presentation coordinator/renderer, synthetic notifications and test images. It does not validate real website login, actual device background lifecycle, final character artwork, hardware power settings, VoiceOver navigation or keyboard behavior. Those remain explicit device acceptance items.


## Latest native evidence
Run41279022146 passed16 component cases,4 real List contexts and26 native presentation/renderer assertions with no reported failures. Manually inspected the final320/light,375/dark/AX3 and667/dark picker snapshots. Accessibility-size choices now use one readable column and icons stay proportionate. The isolated fixture omits the application's localization catalog, so its system-category labels are English; shipping selection labels use SwiftUI localization keys.
The recent-memory fragment is appended before ContextSizeMeter.estimateFixedTokens(systemPrompt:tools:) in AgentLoop; injected notes therefore participate in the existing request budget, including model fallback reconstruction.


## Package delivery
- Cloud run41279022146, revisiond0c4949bb29846db3cb0a7ee4cb2f65122da74e7, all3 jobs SUCCESS. Earlier superseded runs were cancelled; the initial test/compile failures are recorded in progress.md and are resolved in this revision.
- IPA: `build/cloud/41279022146/OpenMinis-unsigned.ipa`,100971918 bytes, Bundle ID`com.openminis.app`, version1.15/build1, unsigned arm64.
- ZIP CRC, Mach-O architecture, Bundle ID, artifact-to-commit provenance and lack of signing envelope checked. SHA256:`4cc3e6b40c070459f01dbf36f0b8086fe29bb9c325122799b20a7eca57f5cac0`.
- `verification.json`, run/result/artifact metadata and native results beside the IPA retain evidence. Documentation-only follow-up does not change the compiled app.
- Real mailbox login, actual OS background/foreground while entering credentials, photo-library interaction, hardware power settings, keyboard/orientation/VoiceOver navigation and final character animation appearance remain device acceptance items. The12 requested2D Pokémon sticker assets are NOT delivered because generation was rejected. Existing images/icons remain available; the native animation tests use synthetic art.
