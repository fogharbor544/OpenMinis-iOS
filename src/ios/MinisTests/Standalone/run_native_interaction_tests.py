"""Exercise shipping secure presentation and native avatar code in a scene-based simulator fixture."""
from pathlib import Path
import json
import platform
import plistlib
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT.parents[1] / "build/validation/native-interactions"
BUNDLE = "com.openminis.native-interactions"


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
        with tempfile.TemporaryDirectory(prefix="minis-native-interactions-") as temp:
            app = Path(temp) / "InteractionValidation.app"
            app.mkdir()
            info = {"CFBundleIdentifier": BUNDLE, "CFBundleName": "InteractionValidation", "CFBundleExecutable": "InteractionValidation",
                    "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
                    "MinimumOSVersion": "16.0", "UIDeviceFamily": [1, 2], "UILaunchScreen": {},
                    "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": True}}
            (app / "Info.plist").write_bytes(plistlib.dumps(info))
            passwords = (ROOT / "Agent/BrowserUse/BrowserPasswords.swift").read_text(encoding="utf-8")
            presentation = passwords.split("// BEGIN BrowserSecurePresentation", 1)[1].split("// END BrowserSecurePresentation", 1)[0]
            driver = app.parent / "BrowserSecurePresentation.swift"
            driver.write_text("import UIKit\n" + presentation, encoding="utf-8")
            types = app.parent / "BotAvatarTypes.swift"
            types.write_text((ROOT / "Views/ContentView/Bots/BotWorkspaceStore.swift").read_text(encoding="utf-8").split("struct BotSessionOwner:", 1)[0], encoding="utf-8")
            run(swiftc, "-swift-version", "5", "-sdk", sdk, "-target", f"{arch}-apple-ios16.0-simulator",
                str(driver), str(types), str(ROOT / "Views/ContentView/Bots/BotAvatar.swift"),
                str(ROOT / "MinisTests/Standalone/NativeInteractionTests.swift"), "-o", str(app / "InteractionValidation"), timeout=180)
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
            assert len(result["cases"]) >= 24
            print(f"PASS: {len(result['cases'])} native interaction/renderer fixture assertions; see result.json for limitations")
    finally:
        if booted_here:
            subprocess.run(["xcrun", "simctl", "shutdown", udid], check=False, timeout=30)


if __name__ == "__main__":
    main()
