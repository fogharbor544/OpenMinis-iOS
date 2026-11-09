# OpenMinis

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/Platforms-iOS-lightgrey.svg)](#building-from-source)

**Your private, on-device AI agent.**

OpenMinis brings leading models — Claude, GPT, Gemini and more — into a native
iOS app and gives them a real computer to work with: a sandboxed Alpine Linux
shell, browser automation, extensible skills, scoped memory, device
integrations and deep file access.

It is free, and fully open source.

**We believe that in the age of AI, technical design and code are no longer
where a product's advantage lies. The best agent emerges from a tight feedback
loop with the people who use it — their expectations and their reports are
what converge on the product.**

This repository is the actively developed `fogharbor544/OpenMinis-iOS` fork.
It is iOS-only; the Android client has been removed, and development happens
directly on this repository's `main`.

![Minis on iOS — deep research, chat, agent runtime, integrations, iCloud sync and granular permissions](assets/screenshots.png)

---

## What it does

| | |
|---|---|
| **Bring your own model** | Claude, GPT, Gemini and other providers, via your own API keys or account sign-in. |
| **A real Linux shell** | A sandboxed Alpine Linux environment runs on-device — the agent can install packages, run scripts, and work with real files. |
| **Device integration** | Health, Calendar, Reminders, Contacts, HomeKit, Bluetooth, Clipboard, Media, Alarms and more, exposed to the agent as tools. |
| **Browser automation** | The agent can browse and interact with the web; bookmarks, Keychain-backed passwords and an inline secure-input card for browser logins are available. |
| **Bots & groups** | Bot-first home navigation, bounded group rounds, per-Bot configuration with a single scroll area for long instructions, and scoped memory with fixed / ordinary / fact categories and per-entry editing. |
| **Skills & MCP** | On-demand skills, external MCP connectors, a catalog of built-in capabilities and execution-time permission controls. |
| **Workspaces** | Session working files at `/var/minis/workspace/`, addressable as `minis://workspace/...`; shared and external folders can be mounted. |
| **Schedules & Shortcuts** | Unified in-app task management, iOS Shortcuts, a share extension and a widget. |
| **Sync, backup & restore** | Optional iCloud sync, plus local `.minisbak` snapshots in `Minis ▸ Backups`. Select Chats for local Bot history; sessions with missing or invalid IDs and unreadable messages are reported separately. Browser Bookmarks are selectable, and Browser Passwords (including the shared vault) and Browser Cookies are separate opt-in categories requiring encryption. Partitioned cookies are skipped. Shared Folders exposes local packages for restore, share and deletion. |
| **Native offloads** | Heavy or platform-specific work is handed to native code instead of the sandbox. |

Chat keeps consecutive tool cards evenly spaced when the model emits only whitespace between them.

The bundled in-app guide is the authoritative user-facing feature reference:
[`src/ios/Resources/BundledSkills/openminis-ios-user-guide/references/ios-user-manual.md`](src/ios/Resources/BundledSkills/openminis-ios-user-guide/references/ios-user-manual.md).
Implementation scope and verification limits are recorded in
[`src/ios/IOS_FEATURES.md`](src/ios/IOS_FEATURES.md).

---

## What you can do with Minis

A few things people actually use it for:

- **Photograph a meal, log the nutrition** — Minis identifies the dishes, estimates
  calories and macros, and writes them to Apple Health.
- **Wake up to your timeline** — Shortcuts triggers Minis to fetch your X timeline,
  summarise it, synthesise speech, and play it as your alarm.
- **Turn group chatter into tasks** — pull messages from a Telegram group, extract
  bugs and action items, deduplicate them, and file them into Apple Reminders.
- **Mount your Obsidian vault** — research, clean up and write Markdown notes back
  into the vault as a mounted folder.
- **Share anything into a calendar event** — send a page or message to Minis via the
  iOS Share Sheet and it creates the event, time and place included.

**→ [OpenMinis/AwesomeMinis](https://github.com/OpenMinis/AwesomeMinis)** — a curated,
community-contributed collection of use cases and workflows across health,
productivity, research, finance and developer tooling.

---

## Skills

A **skill** is a folder with a `SKILL.md` file — instructions, and optionally scripts,
references and assets — that the agent loads on demand when a request matches it.
Metadata stays in context for triggering; the body and bundled resources load only
when the skill is actually used.

Minis has its own tool system, but it does not require skills written specifically
for it: **skills built for Claude, Codex, OpenClaw or Hermes Agent generally run in
Minis as-is.** Skills that have been adapted to Minis' tools simply run better —
they can reach the Linux shell, device integrations and native offloads directly.

**→ [OpenMinis/MinisSkills](https://github.com/OpenMinis/MinisSkills)** — skills
adapted for Minis alongside ones built for it from scratch, covering TTS, search,
media downloads, health analysis, cloud APIs and more.

---

## Press

> "the most impressive indie app I've seen in a while"
>
> — Federico Viticci, [**Open Minis Is the iOS Agent I Wish Siri AI Could Be**](https://www.macstories.net/reviews/open-minis-is-the-ios-agent-i-wish-siri-ai-could-be/),
> MacStories (July 2026)

> "在很大程度上实现甚至局部超越了 Apple Intelligence"
>
> — Ye Han, [**这可能是 iPhone 最强 Agent 软件，没有之一 丨Open Minis 入门指南**](https://zhuanlan.zhihu.com/p/2045570157783807562),
> 知乎 / Zhihu (June 2026)

> "可能是 iOS 端最强 AI Agent"
>
> — [**Open Minis：可能是 iOS 端最强 AI Agent**](https://www.appinn.com/open-minis/),
> 小众软件 / Appinn (March 2026)

---

## Building from source

Minis ships a Linux sandbox inside the app, so the native dependencies (iSH,
FFmpeg, LAME, rclone) and the Alpine rootfs are **built from source** rather
than committed as binaries.

**→ See [BUILDING.md](BUILDING.md) for the full first-build guide.**

The short version, from a macOS host with Go 1.25+, Xcode's Metal Toolchain
(`xcodebuild -downloadComponent MetalToolchain`) and the other tools listed in
`BUILDING.md`:

```sh
git clone https://github.com/fogharbor544/OpenMinis-iOS.git
cd OpenMinis-iOS

# Required: the Xcode project references this ignored build configuration.
# Leave values empty unless the corresponding feature needs them.
cp src/ios/Configs/ProviderCustomization.xcconfig.example \
   src/ios/Configs/ProviderCustomization.xcconfig

# Order matters: FFmpeg links against LAME. These scripts build device arm64.
./deps/build_lame.sh && ./deps/build_ffmpeg.sh
./deps/build_ish.sh && ./deps/prepare_alpine_rootfs.sh
./deps/build_rclone_ios.sh

open src/ios/Minis.xcodeproj
```

To build without opening Xcode:

```sh
xcodebuild -project src/ios/Minis.xcodeproj -scheme Minis \
  -configuration Debug -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

`BUILDING.md` covers the toolchain requirements, build-time customization and
troubleshooting. Native dependencies are built for iOS devices; simulator
builds require simulator-architecture dependencies. On macOS, run
`./scripts/ios-unit-tests.sh` for the isolated XCTest host, or a targeted
standalone fixture such as
`python3 src/ios/MinisTests/Standalone/check_fresh_install.py`. The
`python3 scripts/ios-unit-tests/static_check.py` guard verifies test-data
isolation for the local XCTest harness; its allowlist currently assumes macOS
path separators and is not registered as a CI step. The
[`iOS validation`](.github/workflows/ios-validation.yml) workflow runs portable
source checks, Swift fixtures and UI checks; its optional `full_build` dispatch
produces an unsigned IPA.

---

## Repository layout

```
src/ios/          iOS app (Swift 6 / SwiftUI), extensions, resources and tests
src/shared/       Cross-platform specifications, CLI docs and regression fixtures
deps/             Native dependency build scripts and vendored sources
scripts/          Developer, localization and isolated iOS test tooling
assets/           Screenshots and branding
```

The project-level `AGENTS.md`, the `docs/` tree and the planning and
decision records `task_plan.md`, `findings.md` and `progress.md` are local, ignored
files: they stay on the developer's machine and are not part of the repository.

---

## Acknowledgements

OpenMinis stands on a great deal of open-source work. Our thanks to the
maintainers of these projects — the full inventory, with versions and license
terms, is in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

**The sandbox** — the heart of the product:

- **[iSH](https://github.com/OpenMinis/ish-arm64)** (GPLv3, ARM64 fork) — Linux
  usermode emulation on iOS.
- **[Alpine Linux](https://alpinelinux.org)** — the minirootfs the sandbox boots.
- **[rclone](https://github.com/rclone/rclone)** (MIT) — optional remote backup
  destinations.
- **[Tailscale](https://github.com/tailscale/tailscale)** (BSD-3-Clause) — the
  optional embedded network node.

**Media & text** — [FFmpeg](https://ffmpeg.org) (LGPL-2.1+),
[LAME](https://lame.sourceforge.io) (LGPL), [cppjieba](https://github.com/yanyiwu/cppjieba) (MIT),
[KaTeX](https://katex.org) (MIT).

**iOS** — [SwiftAnthropic](https://github.com/jamesrochabrun/SwiftAnthropic),
[SwiftMath](https://github.com/mgriebling/SwiftMath),
[RealTimeCutVADLibrary](https://github.com/helloooideeeeea/RealTimeCutVADLibrary) (all MIT),
[swift-cmark](https://github.com/swiftlang/swift-cmark) (BSD-2-Clause), and the
Apple / Swift Server Workgroup packages (Apache-2.0).

---

## License

OpenMinis is licensed under the **[GNU General Public License v3.0](LICENSE)**.

The app links GPL-licensed components — [iSH](https://github.com/OpenMinis/ish-arm64)
(GPLv3) — so the combined work is distributed under GPLv3. Bundled third-party
licenses are listed in
[THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

---

## Community

- **Repository**: [fogharbor544/OpenMinis-iOS](https://github.com/fogharbor544/OpenMinis-iOS)
- **Issues**: Bug reports, feature requests and discussion via
  [GitHub Issues](https://github.com/fogharbor544/OpenMinis-iOS/issues)

Development happens directly on `main` in this fork, so it **does not take pull
requests**. [AwesomeMinis](https://github.com/OpenMinis/AwesomeMinis) and
[MinisSkills](https://github.com/OpenMinis/MinisSkills) both take contributions;
see [CONTRIBUTING.md](CONTRIBUTING.md) for the issue-reporting checklist.
Its "public mirror" paragraph describes the upstream project's workflow and
does not govern this fork.
