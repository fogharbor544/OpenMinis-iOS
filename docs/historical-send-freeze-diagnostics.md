# Historical send freeze diagnostics

## 2026-11-02

- The foreground SIGKILL log excludes memory pressure/OOM: footprint was 59–103 MB, about 3.2 GB system memory remained free, CPU was 3%, and no WebViews, shell processes, or background task grants were active.
- The run stopped after `inputText CLEARED` and before `send START`. The main thread therefore blocked in the synchronous path between clearing the draft and beginning send; this is consistent with a foreground watchdog kill, not API or WebView work.
- `HangDetector` previously discarded every stack whose leaf frame was in `libsystem_kernel`, so real lock/semaphore waits were misclassified as ordinary run-loop idle. That removed the diagnostic stack needed to locate the blockage.
- Commit `a0f753a` removes the incorrect kernel-leaf filter and adds a regression that verifies kernel blocking stacks survive while ordinary run-loop idle remains excluded.
- Cloud run `41439550170`: `source-checks` and `device-build` passed; the new `Kernel blocking hang stack regression` passed. `ui-layout` still fails on the known native-history-send fixture, but the run produced a valid unsigned IPA.
- Next reproduction should look for `--- Last HangDetector Stacks (before exit) ---` in the crash report. That stack, rather than the normal run logs, is now the key evidence for identifying the exact blocking call.
