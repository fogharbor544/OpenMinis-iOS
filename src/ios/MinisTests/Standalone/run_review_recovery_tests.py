"""Review regressions: portable source/SQL checks plus isolated shipping Swift on macOS.

The portable checks do not replace XCTest or an iOS build. Native fixtures never
use live credentials: all three Security operations in the extracted writer are
replaced with FakeSecurity, and every filesystem/defaults input is temporary.
"""
from pathlib import Path
import argparse
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

def read(name):
    return (ROOT / name).read_text(encoding="utf-8")

def between(source, start, end):
    return source.split(start, 1)[1].split(end, 1)[0]

class RecoveryContracts(unittest.TestCase):
    def test_batch_commit_controls_success_and_notifications(self):
        source = between(read("Agent/Chat/ChatStore+Messages.swift"), "func appendMessages(", "func sessionWriteStats(")
        self.assertIn('"BEGIN IMMEDIATE TRANSACTION"', source)
        self.assertIn('defer { if !committed { sqlite3_exec(db, "ROLLBACK"', source)
        self.assertIn('guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else { return false }', source)
        self.assertLess(source.index("committed = true"), source.index("pendingSyncSessionIds.formUnion"))
        self.assertIn("guard setMessagePresentation", source)

    def test_production_insert_rolls_back_on_second_row_failure(self):
        source = read("Agent/Chat/ChatStore+Messages.swift")
        sql = re.search(r'INSERT INTO messages .*?VALUES \([^\n]+\)', source, re.S).group()
        columns = re.search(r'INSERT INTO messages \(([^)]+)\)', sql).group(1).split(", ")
        db = sqlite3.connect(":memory:", isolation_level=None)
        self.addCleanup(db.close)
        db.execute("CREATE TABLE messages (" + ", ".join(['id TEXT PRIMARY KEY'] + ['"' + c + '"' for c in columns[1:]]) + ")")
        db.execute("CREATE TRIGGER fail BEFORE INSERT ON messages WHEN NEW.id='second' BEGIN SELECT RAISE(ABORT,'injected'); END")
        def row(identifier):
            values = dict.fromkeys(columns)
            values.update(id=identifier, session_id="fixture", role="user", parts_json="[]")
            return tuple(values[c] for c in columns)
        # Executes shipping INSERT and SQLite transaction semantics, not Swift control flow.
        db.execute("BEGIN IMMEDIATE TRANSACTION")
        db.execute(sql, row("first"))
        with self.assertRaises(sqlite3.DatabaseError):
            db.execute(sql, row("second"))
        db.execute("ROLLBACK")
        self.assertEqual(db.execute("SELECT count(*) FROM messages").fetchone()[0], 0)
        db.execute("PRAGMA query_only=ON")
        with self.assertRaises(sqlite3.DatabaseError):
            db.execute(sql, row("blocked"))

    def test_durable_ids_and_recovery_only_follow_success(self):
        source = read("Agent/Chat/AIChatViewModel+Persistence.swift")
        write = source.index("guard await ChatStore.shared.appendMessage(raw)")
        self.assertGreater(source.index("live.persistedMessageID = raw.id", write), write)
        queue = read("Agent/Chat/AIChatViewModel+PromptQueue.swift")
        self.assertIn("guard let pid = await self.persistAgentMessage(queueAgentMsg", queue)
        self.assertIn("guard let pid = await persistAgentMessage(queueMsg", queue)
        self.assertIn("guard await ChatStore.shared.appendMessages(rows)", read("Agent/Chat/UserAskCenter.swift"))

    def test_native_capability_boundary_precedes_setup(self):
        native = (ROOT.parents[1] / "deps/ish/kernel/native_offload.c").read_text(encoding="utf-8")
        body = between(native, "static int exec_handler(", "// Close write ends")
        self.assertLess(body.index("!permission_check(guest_file)"), body.index("get_root_source()"))
        self.assertLess(body.index("if (cancelled)"), body.index("ret = handler("))
        bridge = read("NativeOffloads/NativeOffloadUtils.m")
        self.assertIn("native_offload_set_permission_check(noff_authorize_executable)", bridge)
        self.assertIn("noff_current_fs_context()", bridge)
        self.assertIn("MinisFsRouter.shared.sid(for: fsContext)", read("Agent/Offload/OffloadPermissionManager.swift"))

    def test_permission_queue_owns_continuations_and_sheet_state(self):
        manager = read("Agent/Offload/OffloadPermissionManager.swift")
        self.assertIn("queuedRequests.append(request)", manager)
        self.assertIn("withTaskCancellationHandler", manager)
        self.assertIn("queuedRequests.remove(at: index)", manager)
        self.assertIn("@Published private(set) var pendingRequest", manager)
        self.assertNotIn("$manager.pendingRequest", read("Views/Chat/OffloadPermissionDialog.swift"))

    def test_slot_handoff_reserves_before_resume(self):
        source = between(read("Agent/Chat/ChatLifecycleSupport.swift"), "private func resumeNextWaiter()", "// END SessionSlots")
        self.assertLess(source.index("runningSessions.insert(next.id)"), source.index("next.continuation.resume"))
        self.assertIn("runningSessions.count < maxConcurrent", source)

    def test_file_cancellation_and_atomic_overwrite(self):
        source = read("Agent/Chat/FileToolIO.swift")
        self.assertIn("withTaskCancellationHandler", source)
        self.assertIn("cancellation.setCancellationHandler", source)
        self.assertIn("cancellation.cancel()", source)
        self.assertIn("try data.write(to: target, options: .atomic)", source)
        self.assertIn("try cancellation.check()", source)

    def test_recovery_failures_keep_evidence(self):
        source = read("Agent/Backup/BackupRestoreJournal.swift")
        self.assertIn("if !failed {", source)
        self.assertIn("unreadable recovery marker retained", source)
        self.assertIn("try fm.copyItem(at: saved, to: staged)", source)
        importer = read("Agent/Backup/BackupImporter.swift")
        self.assertIn("try rollback(snapshot)", importer)
        self.assertNotIn("try? rollback(snapshot)", importer)

    def test_keychain_update_precedes_legacy_delete(self):
        body = between(read("Providers/ProviderConfigStore.swift"), "private static func writeCredential(", "static func saveAPIKey(")
        self.assertLess(body.index("SecItemUpdate("), body.index("SecItemAdd("))
        self.assertLess(body.index("guard status == errSecSuccess"), body.index("SecItemDelete("))
        self.assertIn("return false", body)
        self.assertIn("providersFailed", read("Agent/Backup/BackupSecretsImporter.swift"))

    def test_schedule_receipts_and_final_admission(self):
        runner = read("Agent/Jobs/ScheduledJobRunner.swift")
        self.assertGreaterEqual(runner.count("guard canDispatch(job) else"), 5)
        self.assertIn("await receipt.wait()", runner)
        self.assertIn("result: result.text", runner)
        self.assertIn("scheduledJobId: job.id", runner)
        loop = read("Agent/Chat/AIChatViewModel+AgentLoop.swift")
        self.assertLess(loop.index("completeScheduledTurn(message:"), loop.index("let endInjection ="))
        self.assertIn("scheduledTurnReceipts.removeValue", read("Agent/Chat/AIChatViewModel+ProgrammaticPrompt.swift"))

    def test_fallback_eof_usage_and_offload_failure(self):
        fallback = read("Agent/Chat/AIChatViewModel+Fallback.swift")
        self.assertIn("provider: requestProvider", fallback)
        self.assertIn("requestProvider = await makeAgentProvider(for: nextEntry)", fallback)
        loop = read("Agent/Chat/AIChatViewModel+AgentLoop.swift")
        self.assertNotIn("stopReason == nil && toolEntries.isEmpty", loop)
        self.assertIn("buildRawMessage(assistantMessage, tokenUsage: turnUsage", loop)
        offload = read("Agent/Chat/AIChatViewModel+Offloading.swift")
        self.assertTrue(re.search(r"guard let \w+ = offloadContextContent", offload), "offload replacement must require a saved file")
        self.assertIn("return nil", offload)

    def test_locked_previews_and_expired_background_assertion(self):
        view = read("Views/ContentView/Bots/BotWorkspaceView.swift")
        self.assertIn("isBotContentLocked(bot)", view)
        self.assertIn("!sessionLocks.isVisuallyLocked(result.session.id)", view)
        self.assertIn('BiometricAuth.authenticate(reason: AppLocalized("Unlock conversation"))', view)
        assertion = read("Agent/Backup/BackupActivityLock.swift")
        self.assertIn("assertion.end()", between(assertion, "beginBackgroundTask(withName:", "if assertion.id"))


def native_fixtures(swiftc):
    with tempfile.TemporaryDirectory(prefix="minis-review-") as temporary:
        root = Path(temporary)
        writer = "private static func writeCredential(" + between(read("Providers/ProviderConfigStore.swift"), "private static func writeCredential(", "    @discardableResult\n    static func saveAPIKey(")
        writer = writer.replace("private static func", "static func")
        for old, new in [("SecItemUpdate(", "FakeSecurity.update("), ("SecItemAdd(", "FakeSecurity.add("), ("SecItemDelete(", "FakeSecurity.delete(")]:
            writer = writer.replace(old, new)
        assert not re.search(r"\bSecItem(?:Update|Add|Delete)\s*\(", writer)
        replacement = "private static func replaceContents(" + between(read("FileProvider/FileProviderExtension.swift"), "private static func replaceContents(", "    // MARK: - Modify Item")
        replacement = replacement.replace("private static func", "static func")
        probes = root / "Probes.swift"
        probes.write_text("import Foundation\nimport Security\nimport FileProvider\n@MainActor enum CredentialProbe {\n" + writer + "\n}\nenum FileProviderProbe {\n" + replacement + "\n}\n", encoding="utf-8")
        permissions = root / "Permissions.swift"
        permissions.write_text(read("Agent/Offload/OffloadPermissionManager.swift").split("/// Called by native dispatch", 1)[0], encoding="utf-8")
        slots = root / "Slots.swift"
        lifecycle = read("Agent/Chat/ChatLifecycleSupport.swift")
        slots.write_text("import Foundation\nimport Combine\n" + between(lifecycle, "// BEGIN ConcurrencyLimits", "// END ConcurrencyLimits") + between(lifecycle, "// BEGIN SessionSlots", "// END SessionSlots"), encoding="utf-8")
        receipt = root / "ScheduledTurnReceipt.swift"
        prompts = read("Agent/Chat/AIChatViewModel+ProgrammaticPrompt.swift")
        marker = "@MainActor\nfinal class ScheduledTurnReceipt"
        receipt.write_text(marker + prompts.split(marker, 1)[1], encoding="utf-8")
        binary = root / "review-fixtures"
        subprocess.run([swiftc, "-swift-version", "6", "-parse-as-library", "-o", str(binary),
            str(Path(__file__).with_name("ReviewRecoveryFixtures.swift")), str(probes), str(permissions), str(slots), str(receipt),
            str(ROOT / "Agent/Chat/FileToolIO.swift"), str(ROOT / "Agent/Backup/BackupRestoreJournal.swift")], check=True)
        subprocess.run([str(binary)], check=True, timeout=45)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-swift", action="store_true")
    args = parser.parse_args()
    result = unittest.TextTestRunner(verbosity=1).run(unittest.defaultTestLoader.loadTestsFromTestCase(RecoveryContracts))
    if not result.wasSuccessful():
        sys.exit(1)
    print("PASS: 12 portable source/SQLite checks; these are not Swift runtime tests.")
    compiler = shutil.which("swiftc")
    if compiler and sys.platform == "darwin":
        native_fixtures(compiler)
    elif args.require_swift:
        sys.exit("Native fixtures require macOS and swiftc")
    else:
        print("NOT RUN: native Swift fixtures (requires macOS/swiftc); XCTest and iOS build remain separate.")
