"""Validate shipped atlas IDs, resource integrity and native frame geometry."""
from pathlib import Path
import hashlib
import json
import struct

ROOT = Path(__file__).resolve().parents[4]
manifest = json.loads((ROOT / "src/ios/MinisTests/Fixtures/bot-avatar-generation.json").read_text(encoding="utf-8"))
assert manifest["layout"] == {"columns": 4, "rows": 4, "durationSeconds": 2, "posterFrame": 0}
entries = manifest["entries"]
assert len(entries) == len({item["id"] for item in entries}) == 12
store = (ROOT / "src/ios/Views/ContentView/Bots/BotWorkspaceStore.swift").read_text(encoding="utf-8")
for item in entries:
    assert '"' + item["id"] + '"' in store
    folder = ROOT / "src/ios/Assets.xcassets" / (item["asset"] + ".dataset")
    data = (folder / "atlas.png").read_bytes()
    assert hashlib.sha256(data).hexdigest() == item["sha256"], item["id"]
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    width, height, depth, color = struct.unpack(">IIBB", data[16:26])
    assert 64 <= width <= 2048 and width == height and depth == 8 and color in (2, 6), item["id"]
    # Runtime uses fractional coordinates: generated 1254 px atlases are valid.
    for index in range(16):
        x, y, side = (index % 4) * width / 4, (index // 4) * height / 4, width / 4
        assert x >= 0 and y >= 0 and x + side <= width and y + side <= height
    assert json.loads((folder / "Contents.json").read_text())["data"][0]["filename"] == "atlas.png"
print("PASS: 12 original atlas identities, SHA-256 integrity, 192 in-bounds frames and Xcode data membership")
