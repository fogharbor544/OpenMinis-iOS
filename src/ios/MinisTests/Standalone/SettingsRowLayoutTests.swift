// Runs in an isolated simulator app, using the shipping shared SwiftUI rows.
import SwiftUI
import UIKit

@MainActor
final class LayoutTestDelegate: NSObject, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UIHostingController(rootView: Text("Settings layout checks"))
        window?.makeKeyAndVisible()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.checkLayouts() }
        return true
    }

    private func checkLayouts() {
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
                        failures.append("\(name): long value did not reflow below its label")
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
        do {
            let data = try JSONSerialization.data(withJSONObject: ["cases": cases, "failures": failures], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appendingPathComponent("result.json"))
        } catch { fatalError("Unable to write native layout results: \(error)") }
    }
}

@main
enum LayoutTestMain {
    static func main() {
        UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(LayoutTestDelegate.self))
    }
}
