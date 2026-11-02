"""Run the shipping latest-position transition and custom layout in real UIKit.
The fixture replaces app/model/network boundaries; it does not reproduce an LLM request or physical keyboard/gesture.
"""
from pathlib import Path
import json
import os
import platform
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


def run(*args, **kwargs):
    kwargs.setdefault("timeout", 60)
    return subprocess.run(args, check=True, text=True, **kwargs)


def capture(*args, timeout=60):
    return subprocess.check_output(args, text=True, timeout=timeout).strip()


def build_sources(folder):
    coordinator=ROOT/"Agent/MessageList/CollectionViewMessageListV3/Coordinator"
    scroll=(coordinator/"MessageListV3Coordinator+Scroll.swift").read_text(encoding="utf-8")
    methods=scroll[scroll.index("        func requestLatestPosition()"):scroll.rfind("\n}")]
    snapshots=(coordinator/"MessageListV3Coordinator+Snapshot.swift").read_text(encoding="utf-8")
    start=snapshots.index("            if snapshotApplyInProgress ||")
    end=snapshots.index("            // [T-bridge-message-ui-leak]",start)
    guard=snapshots[start:end]
    fixture=Path(__file__).with_name("ChatSendNativeTests.swift").read_text(encoding="utf-8")
    fixture=fixture.replace("SHIPPING_SNAPSHOT_GUARD",guard).replace("    // SHIPPING_SCROLL_METHODS",methods)
    (folder/"Fixture.swift").write_text(fixture,encoding="utf-8")
    layout=(ROOT/"Agent/MessageList/MessageListLayout.swift").read_text(encoding="utf-8")
    core=layout.split("/// Height of the assistant header row",1)[0]
    stream=layout.split("enum StreamGrowthPin",1)[1].split("// END StreamGrowthPin",1)[0]
    background=layout.split("private final class BotReplyBackground",1)[1]
    infrastructure=(ROOT/"Agent/MessageList/MessageListInfrastructure.swift").read_text(encoding="utf-8")
    item="enum MessageListItem"+infrastructure.split("enum MessageListItem",1)[1].split("// MARK: - Self-Sizing Cell",1)[0]
    spacing=(ROOT/"Agent/MessageList/CollectionViewMessageListV3/Support/QueuedCandidateSpacing.swift").read_text(encoding="utf-8")
    (folder/"Layout.swift").write_text(core+"\n"+item+"\n"+spacing+"\nenum StreamGrowthPin"+stream+"\nprivate final class BotReplyBackground"+background,encoding="utf-8")


def main():
    output = Path(os.environ.get("NATIVE_SEND_ARTIFACTS", str(ROOT.parents[1] / "build/validation/chat-send-native")))
    output.mkdir(parents=True, exist_ok=True)
    sdk = capture("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path")
    swiftc = capture("xcrun", "--find", "swiftc")
    devices=json.loads(capture("xcrun","simctl","list","devices","available","--json"))["devices"]
    phones=[d for r,ds in devices.items() if ".iOS-" in r for d in ds if d["name"].startswith("iPhone")]
    if not phones: raise RuntimeError("No iOS simulator installed")
    device=next((d for d in phones if d["state"]=="Booted"),phones[0]);udid=device["udid"]
    booted_here=device["state"]!="Booted"
    bundle="com.openminis.chat-send-validation"
    try:
        if booted_here: run("xcrun","simctl","boot",udid)
        run("xcrun","simctl","bootstatus",udid,"-b",timeout=240)
        arch="arm64" if platform.machine()=="arm64" else "x86_64"
        with tempfile.TemporaryDirectory(prefix="minis-chat-send-") as temp:
            folder=Path(temp);app=folder/"ChatSendValidation.app";app.mkdir()
            info={"CFBundleIdentifier":bundle,"CFBundleName":"ChatSendValidation","CFBundleExecutable":"ChatSendValidation","CFBundlePackageType":"APPL","CFBundleVersion":"1","CFBundleShortVersionString":"1.0","MinimumOSVersion":"16.0","UIDeviceFamily":[1,2],"UILaunchScreen":{}}
            (app/"Info.plist").write_bytes(plistlib.dumps(info))
            build_sources(folder)
            run(swiftc,"-swift-version","5","-sdk",sdk,"-target",f"{arch}-apple-ios16.0-simulator",str(folder/"Fixture.swift"),str(folder/"Layout.swift"),"-o",str(app/"ChatSendValidation"),timeout=180)
            run("codesign","--force","--sign","-",str(app))
            run("xcrun","simctl","install",udid,str(app))
            run("xcrun","simctl","launch",udid,bundle)
            container=Path(capture("xcrun","simctl","get_app_container",udid,bundle,"data"))
            report=container/"Documents/chat-send-native-results.json"
            for _ in range(120):
                if report.exists(): break
                time.sleep(0.5)
            if not report.exists(): raise RuntimeError("Native send test stalled; no report")
            result=json.loads(report.read_text())
            for artifact in report.parent.glob("chat-send-native*"): shutil.copy2(artifact,output/artifact.name)
            if result["failures"] or len(result["cases"])<15: raise RuntimeError(result)
            print("PASS: native shipping send transition/layout",result)
    finally:
        subprocess.run(["xcrun","simctl","terminate",udid,bundle],capture_output=True)
        if booted_here: subprocess.run(["xcrun","simctl","shutdown",udid],capture_output=True)

if __name__ == "__main__":
    if len(sys.argv)==3 and sys.argv[1]=="--generate-only":
        folder=Path(sys.argv[2]);folder.mkdir(parents=True,exist_ok=True);build_sources(folder)
    else: main()
