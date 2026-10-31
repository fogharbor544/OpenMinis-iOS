"""Render shipping SwiftUI settings rows in an isolated iOS simulator app."""
from pathlib import Path
import json
import platform
import plistlib
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT.parents[1] / "build/validation/ui-layout"
BUNDLE = "com.openminis.layout-validation"


def run(*args, **kwargs):
    kwargs.setdefault("timeout", 60)
    return subprocess.run(args, check=True, text=True, **kwargs)


def capture(*args):
    return subprocess.check_output(args, text=True, timeout=60).strip()


def main():
    devices = json.loads(capture("xcrun", "simctl", "list", "devices", "available", "--json"))["devices"]
    phones = [device for runtime, values in devices.items() if ".iOS-" in runtime
              for device in values if device["name"].startswith("iPhone")]
    if not phones:
        raise RuntimeError("No iOS simulator runtime is installed; native layout checks did not run")
    device = next((item for item in phones if item["state"] == "Booted"), phones[0])
    udid = device["udid"]
    booted_here = device["state"] != "Booted"
    OUTPUT.mkdir(parents=True, exist_ok=True)
    try:
        if booted_here:
            run("xcrun", "simctl", "boot", udid)
        run("xcrun", "simctl", "bootstatus", udid, "-b", timeout=240)
        sdk = capture("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path")
        arch = "arm64" if platform.machine() == "arm64" else "x86_64"
        with tempfile.TemporaryDirectory(prefix="minis-ui-layout-") as temp:
            app = Path(temp) / "LayoutValidation.app"
            app.mkdir()
            info = {"CFBundleIdentifier": BUNDLE, "CFBundleName": "LayoutValidation", "CFBundleExecutable": "LayoutValidation",
                    "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
                    "MinimumOSVersion": "16.0", "UIDeviceFamily": [1, 2], "UILaunchScreen": {}}
            (app / "Info.plist").write_bytes(plistlib.dumps(info))
            run("xcrun", "swiftc", "-swift-version", "5", "-sdk", sdk, "-target", f"{arch}-apple-ios16.0-simulator",
                str(ROOT / "Views/ContentView/Support/SettingsRowStyle.swift"),
                str(ROOT / "MinisTests/Standalone/SettingsRowLayoutTests.swift"), "-o", str(app / "LayoutValidation"), timeout=180)
            run("codesign", "--force", "--sign", "-", str(app))
            run("xcrun", "simctl", "install", udid, str(app))
            run("xcrun", "simctl", "launch", "--terminate-running-process", udid, BUNDLE)
            container = Path(capture("xcrun", "simctl", "get_app_container", udid, BUNDLE, "data"))
            result_file = container / "Documents/result.json"
            for _ in range(90):
                if result_file.exists():
                    break
                time.sleep(1)
            else:
                raise RuntimeError("Native renderer did not finish; no layout pass claimed")
            result = json.loads(result_file.read_text(encoding="utf-8"))
            for item in result_file.parent.iterdir():
                if item.suffix in {".png", ".json"}:
                    shutil.copy2(item, OUTPUT / item.name)
            assert not result["failures"], result["failures"]
            assert len(result["cases"]) == 16
            assert len(result["list_cases"]) == 4
            print("PASS: 16 native component layouts plus 4 real List contexts with visible-title OCR and row-height checks")
    finally:
        if booted_here:
            subprocess.run(["xcrun", "simctl", "shutdown", udid], check=False, timeout=30)


if __name__ == "__main__":
    main()
