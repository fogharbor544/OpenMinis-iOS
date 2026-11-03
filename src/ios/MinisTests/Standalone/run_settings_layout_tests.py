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


def capture(*args, timeout=60):
    return subprocess.check_output(args, text=True, timeout=timeout).strip()


def run_retry(*args, attempts=3, timeout=180, **kwargs):
    """Run a simulator command, retrying a bounded number of times.

    The simulator service on the runner is slow and times out intermittently,
    especially while the device-build job compiles in parallel. One timed-out
    call must not fail the whole native gate.
    """
    failure = None
    for _ in range(attempts):
        try:
            return subprocess.run(args, check=True, text=True, timeout=timeout, **kwargs)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
            failure = error
            time.sleep(5)
    raise failure


def capture_retry(*args, timeout=120, attempts=3):
    """Query the simulator with a bounded retry.

    The simulator service is slow to answer right after the runner boots, and
    a timed-out query must not fail the whole native layout gate.
    """
    failure = None
    for _ in range(attempts):
        try:
            return capture(*args, timeout=timeout)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
            failure = error
            time.sleep(5)
    raise failure


def launch_app(udid, bundle):
    """Launch the validation app and keep its crash report on failure."""
    try:
        run_retry("xcrun", "simctl", "launch", "--terminate-running-process", udid, bundle, timeout=120)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        reports = Path.home() / "Library/Logs/DiagnosticReports"
        if reports.is_dir():
            for report in sorted(reports.glob(f"{bundle}*.ips"), key=lambda item: item.stat().st_mtime, reverse=True)[:1]:
                shutil.copy2(report, OUTPUT / report.name)
        raise


def main():
    # Resolve the toolchain before the simulator's first-boot work competes
    # for resources. SDK discovery timed out after boot on an ARM worker.
    sdk = capture_retry("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path")
    swiftc = capture("xcrun", "--find", "swiftc")
    devices = json.loads(capture_retry("xcrun", "simctl", "list", "devices", "available", "--json"))["devices"]
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
        run_retry("xcrun", "simctl", "bootstatus", udid, "-b", timeout=300)
        arch = "arm64" if platform.machine() == "arm64" else "x86_64"
        with tempfile.TemporaryDirectory(prefix="minis-ui-layout-") as temp:
            app = Path(temp) / "LayoutValidation.app"
            app.mkdir()
            info = {"CFBundleIdentifier": BUNDLE, "CFBundleName": "LayoutValidation", "CFBundleExecutable": "LayoutValidation",
                    "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
                    "MinimumOSVersion": "16.0", "UIDeviceFamily": [1, 2], "UILaunchScreen": {}}
            (app / "Info.plist").write_bytes(plistlib.dumps(info))
            run(swiftc, "-swift-version", "5", "-sdk", sdk, "-target", f"{arch}-apple-ios16.0-simulator",
                str(ROOT / "Views/ContentView/Support/SettingsRowStyle.swift"),
                str(ROOT / "Views/ContentView/Support/BotBrowserSectionHeader.swift"),
                str(ROOT / "MinisTests/Standalone/SettingsRowLayoutTests.swift"), "-o", str(app / "LayoutValidation"), timeout=180)
            run("codesign", "--force", "--sign", "-", str(app), timeout=120)
            run_retry("xcrun", "simctl", "install", udid, str(app), timeout=180)
            launch_app(udid, BUNDLE)
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
