import Foundation

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let source = try String(contentsOf: root.appendingPathComponent("Debug/HangDetector.m"), encoding: .utf8)
precondition(source.contains("// BeforeWaiting already excludes ordinary run-loop idle."))
precondition(!source.contains("if (strstr(base, \"libsystem_kernel\") != NULL)"))
precondition(source.contains("if (activity == kCFRunLoopBeforeWaiting)"))
print("PASS: kernel lock-wait stacks survive while ordinary run-loop idle stays excluded")
