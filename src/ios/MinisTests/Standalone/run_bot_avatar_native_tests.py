"""Validate shipping original-avatar decoding, animation lifecycle and native picker layouts."""
from pathlib import Path
import json
import platform
import plistlib
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT.parents[1] / "build/validation/bot-avatar-ui"
BUNDLE = "com.openminis.bot-avatar-validation"


def run(*args, **kwargs):
    kwargs.setdefault("timeout", 60)
    return subprocess.run(args, check=True, text=True, **kwargs)


def capture(*args, timeout=60):
    return subprocess.check_output(args, text=True, timeout=timeout).strip()


def main():
    # Resolve the toolchain before the simulator's first-boot work competes
    # for resources. SDK discovery timed out after boot on an ARM worker.
    sdk = capture("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path", timeout=120)
    swiftc = capture("xcrun", "--find", "swiftc")
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
        arch = "arm64" if platform.machine() == "arm64" else "x86_64"
        with tempfile.TemporaryDirectory(prefix="minis-bot-avatar-ui-") as temp:
            app = Path(temp) / "AvatarValidation.app"
            app.mkdir()
            info = {"CFBundleIdentifier": BUNDLE, "CFBundleName": "AvatarValidation", "CFBundleExecutable": "AvatarValidation",
                    "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
                    "MinimumOSVersion": "16.0", "UIDeviceFamily": [1, 2], "UILaunchScreen": {}}
            (app / "Info.plist").write_bytes(plistlib.dumps(info))
            assets = Path(temp) / "Avatars.xcassets"
            assets.mkdir()
            (assets / "Contents.json").write_text('{"info":{"author":"xcode","version":1}}')
            for folder in (ROOT / "Assets.xcassets").glob("BotAvatar-*-atlas.dataset"):
                shutil.copytree(folder, assets / folder.name)
            run("xcrun", "actool", str(assets), "--compile", str(app), "--platform", "iphonesimulator",
                "--minimum-deployment-target", "16.0", "--target-device", "iphone", timeout=180)
            run(swiftc, "-swift-version", "5", "-sdk", sdk, "-target", f"{arch}-apple-ios16.0-simulator",
                str(ROOT / "Views/ContentView/Bots/BotWorkspaceStore.swift"),
                str(ROOT / "Views/ContentView/Bots/BotAvatar.swift"),
                str(ROOT / "MinisTests/Standalone/BotAvatarNativeTests.swift"), "-o", str(app / "AvatarValidation"), timeout=180)
            run("codesign", "--force", "--sign", "-", str(app))
            run("xcrun", "simctl", "install", udid, str(app))
            container = Path(capture("xcrun", "simctl", "get_app_container", udid, BUNDLE, "data"))
            result_file = container / "Documents/result.json"
            result_file.unlink(missing_ok=True)
            run("xcrun", "simctl", "launch", "--terminate-running-process", udid, BUNDLE)
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
            assert len(result["cases"]) >= 18
            assert len(list(OUTPUT.glob("*.png"))) == 6
            print(f"PASS: {len(result['cases'])} shipping-avatar native assertions and 6 moving/picker/gallery snapshots; see result.json for limits")
    finally:
        if booted_here:
            subprocess.run(["xcrun", "simctl", "shutdown", udid], check=False, timeout=30)


if __name__ == "__main__":
    main()
