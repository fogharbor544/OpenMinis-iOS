"""Scale baseline for shipping visible-search SQL; synthetic temporary SQLite only.
Does not measure Swift snippet decoding, actor contention, or device performance.
"""
from pathlib import Path
from contextlib import closing
import json
import re
import sqlite3
import statistics
import tempfile
import time

source = (Path(__file__).resolve().parents[2] / "Agent/Chat/ChatStore+Search.swift").read_text(encoding="utf-8")
def template(name):
    return source.split("static func " + name + "(", 1)[1].split('"""', 2)[1]

def likes(text):
    return re.sub(r'\\\(anyLike\("([^"]+)", termCount: n\)\)',
                  lambda match: "(" + match[1] + " LIKE ?1 ESCAPE '\\')", text)

query = likes(template("visibleSQL").replace(r"\(visibleHitClause(termCount: n))", likes(template("visibleHitClause"))))
assert "\\(" not in query, "Update extraction for changed production SQL"
with tempfile.TemporaryDirectory(prefix="minis-search-scale-") as temporary:
    for count in [1000, 10000, 100000]:
        with closing(sqlite3.connect(str(Path(temporary) / (str(count) + ".sqlite")))) as db:
            db.executescript("""
                CREATE TABLE sessions(id TEXT PRIMARY KEY,title TEXT,model_id TEXT,created_at REAL,updated_at REAL,category TEXT);
                CREATE TABLE messages(id TEXT PRIMARY KEY,session_id TEXT,parts_json TEXT,sort_order REAL);
                CREATE INDEX message_session ON messages(session_id,sort_order);
            """)
            db.executemany("INSERT INTO sessions VALUES(?, ?, 'fixture', 0, ?, NULL)",
                           [(str(i), "Synthetic", i) for i in range(100)])
            db.executemany("INSERT INTO messages VALUES(?,?,?,?)", (
                (str(i), str(i % 100), json.dumps([{"type":"text", "value":"sample " * 40 + ("needle" if i == count - 1 else "text")}]), i)
                for i in range(count)))
            db.commit()
            for term, expected in [("absent-token", 0), ("sample", 100), ("needle", 1)]:
                samples = []
                for _ in range(7):
                    start = time.perf_counter()
                    rows = db.execute(query, ("%" + term + "%",)).fetchall()
                    samples.append((time.perf_counter() - start) * 1000)
                    assert len(rows) == expected
                print(json.dumps(dict(messages=count, query=term, median_ms=round(statistics.median(samples), 2), max_ms=round(max(samples), 2), sqlite=sqlite3.sqlite_version)))
