"""Portable checks of the shipping auxiliary-usage SQL, not Swift behavior/type checking."""
from pathlib import Path
import json
from contextlib import closing
import re
import sqlite3
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "Agent/Chat/ChatStore+UsageStats.swift").read_text(encoding="utf-8")
READ = re.search(r'"(SELECT token_usage FROM messages WHERE id = .*?)"', SOURCE).group(1)
WRITE = re.search(r'"(UPDATE messages SET token_usage = .*?)"', SOURCE).group(1)
STATS = SOURCE.split("func fetchUsageStats()", 1)[1].split('"""', 2)[1]

class AuxiliaryUsageSQLTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = str(Path(self.temp.name) / "chat.sqlite")
        self.db = sqlite3.connect(self.path)
        self.db.executescript("""
            CREATE TABLE sessions(id TEXT PRIMARY KEY, model_id TEXT);
            CREATE TABLE messages(id TEXT PRIMARY KEY, session_id TEXT, role TEXT,
                token_usage TEXT, updated_at REAL, created_at REAL, model_id TEXT,
                model_display_name TEXT, provider_type TEXT, parts_json TEXT);
            INSERT INTO sessions VALUES ('s', 'model');
        """)
        self.primary = dict(inputTokens=100, outputTokens=20, cacheCreationTokens=4,
                            cacheReadTokens=3, latestContextTokens=120, estimatedRequestTokens=115)
        self.db.execute("INSERT INTO messages VALUES (?,?,?,?,?,?,?,?,?,?)",
                        ("reply", "s", "assistant", json.dumps(self.primary), 0, 1000,
                         "model", "Model", "provider", '[{"type":"text","value":"Answer"}]'))
        self.db.commit()
    def tearDown(self):
        self.db.close(); self.temp.cleanup()
    def test_scoped_read_rejects_wrong_owner_role_and_missing_message(self):
        self.assertIsNone(self.db.execute(READ, ("reply", "other")).fetchone())
        self.assertIsNone(self.db.execute(READ, ("missing", "s")).fetchone())
        self.db.execute("UPDATE messages SET role='user' WHERE id='reply'")
        self.assertIsNone(self.db.execute(READ, ("reply", "s")).fetchone())
    def test_existing_reply_keeps_chat_and_context_with_durable_accounting(self):
        # Counter arithmetic/JSON coding are covered by the native Swift fixture.
        # This exercises the actual production SQL against SQLite and a reopen.
        usage = json.loads(self.db.execute(READ, ("reply", "s")).fetchone()[0])
        usage.update(auxiliaryInputTokens=10, auxiliaryOutputTokens=5,
                     auxiliaryCacheCreationTokens=2, auxiliaryCacheReadTokens=1)
        row = self.db.execute(WRITE, (json.dumps(usage), 1001, "reply", "s"))
        self.assertEqual(row.rowcount, 1); self.db.commit()
        with closing(sqlite3.connect(self.path)) as reopened:
            loaded = json.loads(reopened.execute(READ, ("reply", "s")).fetchone()[0])
            self.assertEqual({key: loaded[key] for key in self.primary}, self.primary)
            self.assertEqual(loaded["auxiliaryInputTokens"], 10)
            self.assertEqual(reopened.execute("SELECT COUNT(*), parts_json FROM messages").fetchone(),
                             (1, '[{"type":"text","value":"Answer"}]'))
            stats = reopened.execute(STATS).fetchall()
            self.assertEqual(len(stats), 1)
            self.assertEqual(stats[0][0], "model")
            self.assertEqual(json.loads(stats[0][1])["auxiliaryOutputTokens"], 5)
    def test_update_cannot_create_or_move_a_message(self):
        self.assertEqual(self.db.execute(WRITE, ("{}", 1001, "missing", "s")).rowcount, 0)
        self.assertEqual(self.db.execute(WRITE, ("{}", 1001, "reply", "other")).rowcount, 0)
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM messages").fetchone()[0], 1)

if __name__ == "__main__":
    unittest.main()
