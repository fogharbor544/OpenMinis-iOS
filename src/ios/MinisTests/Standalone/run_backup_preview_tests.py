"""Compile shipping ZIP reader/extractor and test generated, isolated archives."""
from pathlib import Path
import json
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
if sys.platform != "darwin" or not shutil.which("swiftc"):
    sys.exit("NOT RUN: requires macOS and swiftc")
with tempfile.TemporaryDirectory(prefix="minis-preview-") as temporary:
    work = Path(temporary)
    for name, entries in {
        "root": {"manifest.json": b"root", "large.bin": b"x" * 1024 * 1024},
        "wrapped": {"package/manifest.json": b"wrapped", "package/data/file": b"payload"},
        "nested": {"data/nested/manifest.json": b"wrong"},
        "multiple": {"a/manifest.json": b"wrong", "b/file": b"other"},
    }.items():
        with zipfile.ZipFile(work / (name + ".zip"), "w", zipfile.ZIP_DEFLATED) as archive:
            for member, content in entries.items():
                archive.writestr(member, content)
    # Model the exporter's integrity map: one path and digest per member.
    manifest = json.dumps({"integrity": {
        f"blobs/{index:064x}": f"{index:064x}" for index in range(130_000)
    }}).encode()
    assert len(manifest) > 16 * 1024 * 1024
    (work / "expected.json").write_bytes(manifest)
    for name, method in [("large-stored", zipfile.ZIP_STORED), ("large-deflated", zipfile.ZIP_DEFLATED)]:
        with zipfile.ZipFile(work / (name + ".zip"), "w", method) as archive:
            archive.writestr("package/manifest.json", manifest)
            archive.writestr("package/payload.bin", b"not part of preview")
    with zipfile.ZipFile(work / "parallel.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("empty", b"")
        for index in range(24):
            archive.writestr(f"member-{index}", f"entry {index}")
    extractor = ROOT / "Agent/Backup/BackupZipExtractor.swift"
    main = work / "Main.swift"
    main.write_text(r'''
import Foundation
@main struct PreviewTests {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        for (name, expected) in [("root", "root"), ("wrapped", "wrapped"), ("nested", nil), ("multiple", nil)] as [(String, String?)] {
            let data = try BackupPackageReader.readManifest(at: directory.appendingPathComponent(name + ".zip"))
            precondition(data.map { String(decoding: $0, as: UTF8.self) } == expected)
        }
        let expected = try Data(contentsOf: directory.appendingPathComponent("expected.json"), options: .mappedIfSafe)
        for name in ["large-stored", "large-deflated"] {
            let manifest = try BackupPackageReader.readManifest(at: directory.appendingPathComponent(name + ".zip"))
            precondition(manifest == expected)
        }
        precondition(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("large.bin").path))
        let unpacked = directory.appendingPathComponent("unpacked")
        try BackupZipExtractor.extract(directory.appendingPathComponent("parallel.zip"), to: unpacked)
        let empty = try Data(contentsOf: unpacked.appendingPathComponent("empty"))
        precondition(empty.isEmpty)
        for index in 0..<24 {
            let member = try Data(contentsOf: unpacked.appendingPathComponent("member-\(index)"))
            precondition(member == Data("entry \(index)".utf8))
        }
        print("PASS: manifest selection, large stored/deflated manifests and parallel extraction")
    }
}
''', encoding="utf-8")
    binary = work / "preview-tests"
    subprocess.run(["swiftc", "-swift-version", "6", "-parse-as-library", str(extractor), str(ROOT / "Agent/Backup/BackupPackageReader.swift"), str(main), "-o", str(binary)], check=True)
    subprocess.run([str(binary), str(work)], check=True, timeout=30)
