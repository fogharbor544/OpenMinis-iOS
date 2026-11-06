"""Exercise the shipping local backup store with isolated filesystem fixtures."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-swift", action="store_true")
    args = parser.parse_args()
    source = (ROOT / "Agent/Backup/BackupDelivery.swift").read_text(encoding="utf-8")
    assert "struct LocalBackupStorage:" in source, "Local backup storage is missing"
    shipping = source.split("// BEGIN LocalBackupStorage\n", 1)[1].split(
        "// END LocalBackupStorage", 1
    )[0]
    swiftc = shutil.which("swiftc")
    if not swiftc:
        assert not args.require_swift, "swiftc is required for filesystem behavior tests"
        print("NOT RUN: local backup filesystem behavior (swiftc unavailable)")
        return
    with tempfile.TemporaryDirectory(prefix="minis-local-backup-") as temp:
        directory = Path(temp)
        fixture = directory / "Storage.swift"
        fixture.write_text("import Foundation\n" + shipping, encoding="utf-8")
        for version in ("5", "6"):
            binary = directory / "storage-tests"
            subprocess.run([
                swiftc, "-swift-version", version, str(fixture),
                str(Path(__file__).with_name("LocalBackupStorageTests.swift")),
                "-o", str(binary)
            ], check=True, timeout=120)
            subprocess.run([str(binary)], check=True, timeout=30)


if __name__ == "__main__":
    main()
