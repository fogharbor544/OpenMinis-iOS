// Runs in an isolated simulator app, using the shipping shared SwiftUI rows.
import SwiftUI
import UIKit
import Vision

@MainActor
final class LayoutTestDelegate: NSObject, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UIHostingController(rootView: Text("Settings layout checks"))
        window?.makeKeyAndVisible()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            Task { await self.checkLayouts() }
        }
        return true
    }

    private func checkLayouts() async {
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var failures: [String] = []
        var cases: [[String: Any]] = []
        for width in [320.0, 375.0, 667.0, 1024.0] {
            for dark in [false, true] {
                for large in [false, true] {
                    let type: DynamicTypeSize = large ? .accessibility5 : .large
                    let scheme: ColorScheme = dark ? .dark : .light
                    let name = "\(Int(width))-\(dark ? "dark" : "light")-\(large ? "ax5" : "regular")"
                    let short = SettingsDetailRow(title: "技能", systemImage: "puzzlepiece.extension", color: .purple, value: "3 项")
                    let long = SettingsDetailRow(title: "提醒事项", systemImage: "checklist", color: .orange,
                                                 value: "每个会话首次询问，仅允许访问已经选择的项目")
                    func measure<V: View>(_ view: V) -> CGSize {
                        let host = UIHostingController(rootView: view.environment(\.dynamicTypeSize, type).environment(\.colorScheme, scheme))
                        host.overrideUserInterfaceStyle = dark ? .dark : .light
                        host.loadViewIfNeeded()
                        return host.sizeThatFits(in: CGSize(width: width - 32, height: 2000))
                    }
                    let shortSize = measure(short)
                    let longSize = measure(long)
                    if !longSize.height.isFinite || longSize.height <= 0 || longSize.width > width - 31 {
                        failures.append("\(name): detail row exceeds its available width or has invalid height")
                    }
                    if width <= 375, !large, longSize.height <= shortSize.height + 8 {
                        failures.append("\(name): long value did not wrap into readable lines")
                    }
                    if large, shortSize.height <= 44 {
                        failures.append("\(name): accessibility text did not expand the row")
                    }
                    let gallery = VStack(alignment: .leading, spacing: 16) {
                        SettingsRowLabel(title: "Agent 工具", systemImage: "wrench.and.screwdriver", color: .orange)
                        Divider()
                        short
                        Divider()
                        long
                        Divider()
                        SettingsDetailRow(title: "日历", systemImage: "calendar", color: .orange, value: "未开启", valueColor: .primary)
                    }
                    .padding(16)
                    .frame(width: width, alignment: .leading)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .environment(\.dynamicTypeSize, type)
                    .environment(\.colorScheme, scheme)
                    let renderer = ImageRenderer(content: gallery)
                    renderer.scale = 1
                    var png: Data?
                    UITraitCollection(userInterfaceStyle: dark ? .dark : .light).performAsCurrent {
                        png = renderer.uiImage?.pngData()
                    }
                    if let data = png {
                        do { try data.write(to: output.appendingPathComponent(name + ".png")) }
                        catch { failures.append("\(name): \(error)") }
                    } else { failures.append("\(name): renderer did not produce an image") }
                    cases.append(["name": name, "short_height": Double(shortSize.height), "long_height": Double(longSize.height), "long_width": Double(longSize.width)])
                }
            }
        }
        var listCases: [[String: Any]] = []
        for dark in [false, true] {
            for large in [false, true] {
                let name = "list-375-\(dark ? "dark" : "light")-\(large ? "ax5" : "regular")"
                let host = UIHostingController(rootView: listContent
                    .environment(\.dynamicTypeSize, large ? .accessibility5 : .large)
                    .environment(\.colorScheme, dark ? .dark : .light))
                host.overrideUserInterfaceStyle = dark ? .dark : .light
                guard let parent = window?.rootViewController else { fatalError("Missing test window") }
                parent.addChild(host)
                host.view.frame = CGRect(x: 0, y: 0, width: 375, height: 1100)
                parent.view.addSubview(host.view)
                host.didMove(toParent: parent)
                parent.view.layoutIfNeeded()
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { continuation.resume() }
                }
                host.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
                    host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                }
                do {
                    guard let png = image.pngData(), let cgImage = image.cgImage else { fatalError("List image unavailable") }
                    try png.write(to: output.appendingPathComponent(name + ".png"))
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.recognitionLanguages = ["en-US"]
                    request.usesLanguageCorrection = false
                    try VNImageRequestHandler(cgImage: cgImage).perform([request])
                    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined()
                        .lowercased().filter { $0.isLetter }
                    let expected = large ? ["Instructions", "Skills"]
                        : ["Instructions", "Skills", "Connectors", "Agents", "Environment", "Calendar", "Photos"]
                    for title in expected where !text.contains(title.lowercased()) {
                        failures.append("\(name): visible list title missing: \(title)")
                    }
                    let observations = request.results ?? []
                    if !large {
                        if let title = recognizedBounds("Instructions", in: observations),
                           let value = recognizedBounds("Not set", in: observations) {
                            if value.minX <= title.maxX || value.maxX < 0.8 || abs(value.midY - title.midY) > 0.015 {
                                failures.append("\(name): empty instruction state is not on the trailing side of its title")
                            }
                        } else { failures.append("\(name): instruction alignment could not be verified") }
                    }
                    if let status = recognizedBounds("hours ago", in: observations) {
                        if !large && status.maxX < 0.7 {
                            failures.append("\(name): browser time is not aligned to the trailing side")
                        }
                    } else { failures.append("\(name): browser time did not remain readable on one line") }
                    let maximumHeight = maximumVisibleRowHeight(host.view)
                    if maximumHeight <= 0 || maximumHeight > (large ? 350 : 160) {
                        failures.append("\(name): inflated native list row: \(maximumHeight)")
                    }
                    listCases.append(["name": name, "recognized_text": text, "maximum_row_height": Double(maximumHeight)])
                } catch { failures.append("\(name): \(error)") }
                host.willMove(toParent: nil)
                host.view.removeFromSuperview()
                host.removeFromParent()
            }
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: ["cases": cases, "list_cases": listCases, "failures": failures], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appendingPathComponent("result.json"))
        } catch { fatalError("Unable to write native layout results: \(error)") }
    }

    /// These are the production row views inside the same native control
    /// containers as the failing screens, rather than detached component renders.
    private var listContent: some View {
        NavigationStack {
            List {
                Section {
                    Text("Browser preview").frame(minHeight: 44)
                } header: {
                    BotBrowserSectionHeader(
                        title: "Realtime browser for a deliberately long Bot name",
                        status: "12 hours ago", isRunning: false
                    ) { Button("Refresh") {} }
                }
                Section("Configuration") {
                    Button {} label: {
                        SettingsDetailRow(title: "Instructions", systemImage: "text.alignleft", color: .gray, value: "Not set")
                    }.foregroundStyle(.primary)
                    NavigationLink { Text("Destination") } label: {
                        SettingsDetailRow(title: "Skills", systemImage: "puzzlepiece.extension", color: .purple, value: "5 / 5")
                    }
                    NavigationLink { Text("Destination") } label: {
                        SettingsDetailRow(title: "Connectors", systemImage: "square.stack.3d.up", color: .indigo, value: "0 / 0")
                    }
                    NavigationLink { Text("Destination") } label: {
                        SettingsDetailRow(title: "Agents", systemImage: "person.2", color: .blue, value: "0")
                    }
                    NavigationLink { Text("Destination") } label: {
                        SettingsDetailRow(title: "Environment", systemImage: "terminal", color: .teal, value: "0")
                    }
                }
                Section("Capabilities") {
                    capabilityRow("Calendar", icon: "calendar")
                    capabilityRow("Photos", icon: "photo")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("List context")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func capabilityRow(_ title: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Button {} label: {
                HStack {
                    SettingsDetailRow(title: title, systemImage: icon, color: .orange, value: "Not enabled", valueColor: .primary)
                    Image(systemName: "chevron.right")
                }.frame(minHeight: 44)
            }.buttonStyle(.plain).foregroundStyle(.primary)
            Divider()
            HStack {
                Text("Bot access").foregroundStyle(.secondary)
                Spacer()
                Menu("Allow") { Button("Allow") {} }.frame(minHeight: 44)
            }.font(.subheadline)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
    }

    private func recognizedBounds(_ text: String, in observations: [VNRecognizedTextObservation]) -> CGRect? {
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first,
                  let range = candidate.string.range(of: text, options: .caseInsensitive) else { continue }
            if let rectangle = try? candidate.boundingBox(for: range) {
                return rectangle.boundingBox
            }
        }
        return nil
    }

    private func maximumVisibleRowHeight(_ view: UIView) -> CGFloat {
        let own = (view as? UICollectionView)?.visibleCells.map { $0.bounds.height }.max() ?? 0
        return max(own, view.subviews.map(maximumVisibleRowHeight).max() ?? 0)
    }
}

@main
enum LayoutTestMain {
    static func main() {
        UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(LayoutTestDelegate.self))
    }
}
