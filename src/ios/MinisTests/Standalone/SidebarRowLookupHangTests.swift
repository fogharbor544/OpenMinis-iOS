#!/usr/bin/env swift
// [T-sidebar-row-lookup-miss] + [T-hang-suspend-gap] + [T-home-list-perf-diag] + [T-main-stall-diag]
//
// Field hang reports 2026-10-03 (1.15 (8), iPhone18,4, ~4,700 sessions):
//   - 04:46:24, 2 s after launch: main thread 2-3 s in ContentView.sessionForRow
//     → ChatSession initializeWithCopy / destroy. Rows that missed the id cache
//     (rebuilt only in `.onChange(of: sessions)`, after the first render pass)
//     re-derived and scanned the whole list per row.
//   - "1095217ms" / "55848ms" hangs whose span covered the app being suspended:
//     HangDetector measured with mach_continuous_time and counted suspension.
//
// The row-lookup memo and HomeListPerf went with the retired conversation
// list (the home is the Bot workspace); the HangDetector guards remain.
//
// Run: swift SidebarRowLookupHangTests.swift
import Foundation

var failures = 0
func check(_ label: String, _ cond: Bool) {
    print(cond ? "  ✅ \(label)" : "  ❌ \(label) — expected true, got false")
    if !cond { failures += 1 }
}
let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
func source(_ rel: String) -> String {
    (try? String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)) ?? ""
}
let hang = source("Debug/HangDetector.m")
print("\n▶️  3. HangDetector excludes suspension")
check("a monitor poll more than 1 s late is treated as the process being frozen",
      hang.contains("static const double kSuspendGapMs = 1000.0;")
      && hang.contains("if (gapMs > kSuspendGapMs) {"))
check("frozen time is tied to the current beat and subtracted from busyMs",
      hang.contains("if (beat != suspendedBeat) { suspendedBeat = beat; suspendedTicks = 0; }")
      && hang.contains("uint64_t frozen = (lastBeat == suspendedBeat) ? suspendedTicks : 0;")
      && hang.contains("double busyMs = ticksToMs(span - frozen);"))
check("a stall that was all suspension is not reported", hang.contains("if (frozen >= span) continue;"))

print("\n▶️  4. [MainStall] sub-threshold awake spans")
check("a span opens on wake-up (AfterWaiting / Entry), first opener wins",
      hang.contains("if ((activity == kCFRunLoopAfterWaiting || activity == kCFRunLoopEntry) && g_awakeStart == 0) {"))
check("the closing observer runs after Core Animation's commit (order LONG_MAX, BeforeWaiting)",
      hang.contains("NULL, kCFRunLoopBeforeWaiting, true, LONG_MAX, lateBeforeWaitingCallback, &ctx);"))
check("the late observer is removed on stop and on a failed start",
      hang.components(separatedBy: "CFRunLoopRemoveObserver(CFRunLoopGetMain(), g_lateObserver, kCFRunLoopCommonModes);").count == 3)
check("spans of 5 s or more are left to the hang path (suspension / nested loops)",
      hang.contains("if (ms < kStallBucketMs[0] || ms >= kStallIgnoreMs) return;"))
check("the monitor thread reports stalls each poll, summary only when something was slow",
      hang.contains("hd_reportStalls(); // [T-main-stall-diag]") && hang.contains("if (c25 == 0) return;"))
check("no display link in the stall path", !hang.contains("displayLinkWithTarget"))
check("[T-main-stall-marks] detail threshold 100 ms; marks are main-only and listed in the detail line",
      hang.contains("static const double kStallDetailMs = 100.0;")
      && hang.contains("+ (void)mark:(NSString *)label {\n    if (!pthread_main_np()) return;")
      && hang.contains("| during: %s") && hang.contains("\"(after %s -%.0fms)\""))

print(failures == 0 ? "\n✅ ALL PASSED" : "\n❌ \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
