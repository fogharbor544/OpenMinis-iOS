"""Exercise the shipping initial ChatStore schema on an empty SQLite database."""
from pathlib import Path
import re
import sqlite3

root = Path(__file__).resolve().parents[2]
source = (root / 'Agent/Chat/ChatStore+Schema.swift').read_text(encoding='utf-8')
setup = source.split('    func exec(')[0]
sqls = []
for match in re.finditer(r'exec\("""\s*(.*?)\s*"""\)|exec\("([^"\n]*)"\)', setup, re.S):
    sql = match[1] or match[2]
    if '\\(' not in sql:
        sqls.append(sql)
db = sqlite3.connect(':memory:')
for _ in range(2):  # first launch and reopening must both initialize cleanly
    for sql in sqls:
        db.execute(sql)
for table, columns in {
    'sessions': {'memory_enabled', 'parent_session_id', 'preview_text', 'folder_id'},
    'messages': {'part_flags', 'reasoning_echo', 'model_id', 'updated_at'},
    'compact_markers': {'last_compacted_message_id', 'version'},
    'sync_dirty_records': {'priority', 'created_at'},
}.items():
    actual = {row[1] for row in db.execute(f'PRAGMA table_info({table})')}
    assert columns <= actual, (table, columns - actual)
db.execute("INSERT INTO sessions(id,model_id,created_at,updated_at) VALUES('new','model',1,1)")
db.execute("INSERT INTO messages(id,session_id,role,parts_json,created_at,sort_order) VALUES('msg','new','user','[]',1,0)")
db.execute("INSERT INTO compact_markers(id,session_id,summary,first_kept_sort_order,compacted_count,created_at,last_compacted_message_id) VALUES('c','new','summary',1,1,2,'msg')")
assert db.execute('SELECT version FROM compact_markers').fetchone()[0] == 2
db.execute("INSERT INTO sync_dirty_records(record_type,record_id,zone_name) VALUES('SessionV2','new','zone')")
assert db.execute('SELECT priority,created_at FROM sync_dirty_records').fetchone() == (0, 0)
assert 'addColumnIfMissing(' not in source
print('PASS: complete fresh schema, idempotent reopen, session/message/compact/sync writes')
