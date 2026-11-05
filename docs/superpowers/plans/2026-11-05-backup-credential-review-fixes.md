# Backup and credential review fixes implementation plan

> Execute inline using systematic debugging, test-driven development and verification-before-completion. Preserve the current dirty checkout; no commit, push or cloud dispatch.

Goal: fix all nine confirmed findings in docs/ios-backup-credential-review-2026-11-05.md.
Architecture: retain the existing stores, WebKit bridge and native presentation controller; validate message origin at the native boundary, keep imported-file identity explicit, and complete folder activation before reporting success.
Tech stack: Swift 6 / SwiftUI / WebKit, Python + Node portable regressions, XCTest and existing macOS/iOS standalone runners.

- [x] Task 1: capture before page handlers; prioritize semantic username fields including implicit text inputs. Extend run_credential_save_tests.py, run RED, fix JS, run GREEN. Add native real-DOM coverage to the existing form runner.
- [x] Task 2: register bridges after UA/viewport rebuild; validate WebView identity and actual frame origin. Add native WebKit/XCTest cases. Bound save-prompt waiting and clear prompts when tabs close; keep secure-input waiting behavior unchanged. Add native lifecycle cases.
- [x] Task 3: refresh the shared vault while the manager is open, with task cancellation on disappearance/lock. Reject missing or changed source rows before Keychain writes, retain valid empty nested collections, and avoid shared-file bookmarks. Extend shipping-store behavior tests for conflict, rollback, empty collections and live refresh.
- [x] Task 4: keep folder addition pending until fallback activation succeeds; propagate failure. Remove reliance on the ineffective task-group timeout in the new-add path. Add focused extracted-production fallback tests where practical.
- [x] Task 5: run available targeted regressions, syntax checks and diff checks; fresh independent review, address confirmed issues, update the review report with evidence and native execution limits.

Review focus: delayed JS form clearing; default text input and competing fields; source rename/deletion and Keychain rollback; popup/frame trust; hidden-window/closed-tab prompt; offline FileProvider.
Native tests cannot run on this Windows host without swiftc/Xcode. Report them as pending, never passed.

Execution evidence (2026-11-05): SPA and username regression assertions failed before their fixes and passed after. New Swift store, presentation, bridge and resolver fixtures have been added but cannot execute on this host (swiftc missing). Available JS/takeover/settings/fresh-install/source-contract regressions passed. Tree-sitter parsed six complete touched Swift files and the five modified BrowserUseManager methods; whole-file BrowserUseManager parsing timed out. Generated Swift fixtures parse successfully; this is not typechecking.
Ruling: repair the existing dirty checkout in place because the approved reviewed changes are already here; preserve concurrent unrelated edits. No commit or cloud build.
Ruling: bound only credential-save waiting; retain the existing secure-input metadata waiting contract. Reuse the new one-shot resolver for both folder-add fallback and cold activation, avoiding the existing task-group join defect.

Final review: independent gpt-6.1-sol/high reviewer completed; two P2 corrections applied (nested empty collection ancestry and native result case count). No remaining confirmed P1/P2; native execution remains unverified.
