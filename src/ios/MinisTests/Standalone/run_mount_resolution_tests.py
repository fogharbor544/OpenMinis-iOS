"""Run the shipping bookmark-resolution deadline without a real FileProvider."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / "Views/Settings/MountedFoldersManager.swift").read_text(encoding="utf-8")
assert "// BEGIN MountBookmarkResolution" in source, "shipping bounded resolver is missing"
shipping = source.split("// BEGIN MountBookmarkResolution", 1)[1].split("// END MountBookmarkResolution", 1)[0]
tests = r'''
@main struct ResolutionTests {
    static func main() async throws {
        let expected = URL(fileURLWithPath: "/synthetic/fixture")
        let start = Date()
        let value = try await MountBookmarkResolution.resolve(timeout: 1) { (expected, false) }
        precondition(value.0 == expected && !value.1)
        precondition(Date().timeIntervalSince(start) < 0.5, "fast resolver must not wait for timeout")
        let blocked = DispatchSemaphore(value: 0)
        let timeoutStart = Date()
        do {
            _ = try await MountBookmarkResolution.resolve(timeout: 0.05) {
                blocked.wait()
                return (expected, false)
            }
            preconditionFailure("blocked FileProvider must time out")
        } catch {
            precondition(Date().timeIntervalSince(timeoutStart) < 0.5, "deadline must not join blocked work")
        }
        blocked.signal()
        try await Task.sleep(nanoseconds: 100_000_000)
        do {
            _ = try await MountBookmarkResolution.resolve(timeout: 1) { throw NSError(domain: "fixture", code: 42) }
            preconditionFailure("resolver failure must propagate")
        } catch { precondition((error as NSError).code == 42) }
        print("PASS: shipping mount resolver fast success, bounded timeout, late result and failure propagation")
    }
}
'''
with tempfile.TemporaryDirectory(prefix="minis-mount-tests-") as temporary:
    temporary = Path(temporary)
    fixture = temporary / "MountTests.swift"
    fixture.write_text("import Foundation\n" + shipping + tests, encoding="utf-8")
    for version in ("5", "6"):
        binary = temporary / "mount-tests"
        subprocess.run(["swiftc", "-swift-version", version, "-parse-as-library", str(fixture), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True, timeout=10)
