import SwiftUI
import UIKit
import ImageIO

private struct AvatarGallery: View {
    var body: some View {
        VStack(spacing: 18) {
            Text("原创伙伴").font(.largeTitle.bold())
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                ForEach(BotAvatarPreset.all) { preset in
                    VStack(spacing: 6) {
                        BotAvatar(profile: BotProfile(name: preset.name, avatarPresetID: preset.id), size: 72)
                        Text(preset.name).font(.caption)
                    }
                }
            }
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(UIColor.systemBackground))
    }
}

private struct AnimatedAvatarLayoutFixture: View {
    let profile: BotProfile
    let playbackID: UUID
    var body: some View {
        Form {
            ForEach([80, 92], id: \.self) { side in
                Section {
                    VStack(spacing: 8) {
                        Button {} label: {
                            BotAvatar(profile: profile, size: CGFloat(side), playbackID: playbackID)
                        }.buttonStyle(.plain)
                        Text("云朵小熊").font(.subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 8)
                }
            }
        }
    }
}

@main @MainActor final class BotAvatarNativeTests: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var cases: [String] = []
    private var failures: [String] = []
    private var limitations: [String] = ["Isolated shipping avatar components; does not exercise live model routing or full-app navigation."]

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let host = UIHostingController(rootView: AnyView(AvatarGallery()))
        let window = UIWindow(frame: UIScreen.main.bounds); window.rootViewController = host
        self.window = window; window.makeKeyAndVisible()
        Task { await validate(host: host, window: window) }
        return true
    }

    private func check(_ condition: Bool, _ name: String) {
        cases.append(name); if !condition { failures.append(name) }
    }
    private func pause(_ seconds: Double = 0.25) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    private var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private func snapshot(_ window: UIWindow, name: String) throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let data = UIGraphicsImageRenderer(bounds: window.bounds, format: format).pngData { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try data.write(to: documents.appendingPathComponent(name + ".png"))
        check(!data.isEmpty, name)
    }

    private func avatarImages(in view: UIView) -> [BotAvatarImageView] {
        if let image = view as? BotAvatarImageView { return [image] }
        return view.subviews.flatMap { avatarImages(in: $0) }
    }

    private func validate(host: UIHostingController<AnyView>, window: UIWindow) async {
        await pause(0.5)
        do {
            for preset in BotAvatarPreset.all {
                guard let data = NSDataAsset(name: preset.atlasAsset)?.data,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil),
                      let frames = BotAvatarFrameCache.decode(atlas) else { check(false, "decode-" + preset.id); continue }
                check(frames.count == 16 && frames.allSatisfy { $0.size.width > 300 && $0.size.width <= 315 }
                      && BotAvatarFrameCache.shared.poster(preset) != nil, "decode-" + preset.id)
            }
            var draft = BotProfile(name: "old", instructions: "old", avatarPresetID: "mint-otter")
            let choice = BotAvatarChoice(profile: draft)
            draft.name = "renamed while picker open"; draft.instructions = "updated responsibilities"; draft.memoryEnabled = false
            choice.apply(to: &draft)
            check(draft.name == "renamed while picker open" && draft.instructions == "updated responsibilities"
                  && draft.memoryEnabled == false && draft.avatarPresetID == "mint-otter", "avatar-transaction-preserves-edits")
            window.overrideUserInterfaceStyle = .light; await pause(); try snapshot(window, name: "avatar-gallery-light")
            window.overrideUserInterfaceStyle = .dark; await pause(); try snapshot(window, name: "avatar-gallery-dark")

            if let frames = await BotAvatarFrameCache.shared.load(BotAvatarPreset.all[0]), let cover = frames.first {
                let image = BotAvatarImageView(frame: CGRect(x: 12, y: 60, width: 96, height: 96))
                window.addSubview(image)
                if !UIAccessibility.isReduceMotionEnabled && !ProcessInfo.processInfo.isLowPowerModeEnabled {
                    image.play(frames, cover: cover); await pause(0.1)
                    check(image.isAnimating && image.animationRepeatCount == 1 && image.animationDuration == 2, "one-shot-start")
                    await pause(2.2); check(!image.isAnimating && image.animationImages == nil, "one-shot-finish")
                    image.play(frames, cover: cover); await pause(0.1); check(image.isAnimating, "tap-replay")
                    image.removeFromSuperview(); check(!image.isAnimating && image.animationImages == nil, "offscreen-stop")
                    window.addSubview(image); image.play(frames, cover: cover)
                    NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
                    check(!image.isAnimating && image.animationImages == nil, "background-stop")
                } else { limitations.append("Animation start checks skipped because the simulator has Reduce Motion or Low Power Mode enabled.") }
                image.removeFromSuperview()
            }
            let profile = BotProfile(name: "指挥官", avatarPresetID: "cloud-bear")
            host.rootView = AnyView(AnimatedAvatarLayoutFixture(profile: profile, playbackID: UUID()))
            await pause(0.35)
            let animatedViews = avatarImages(in: host.view).sorted { $0.bounds.width < $1.bounds.width }
            check(animatedViews.count == 2, "swiftui-form-mounts-both-animated-avatars")
            for (image, expected) in zip(animatedViews, [CGFloat(80), CGFloat(92)]) {
                check(abs(image.bounds.width - expected) < 0.5 && abs(image.bounds.height - expected) < 0.5,
                      "swiftui-animation-bounds-" + String(Int(expected)))
                check(image.contentMode == .scaleAspectFit, "swiftui-animation-aspect-fit-" + String(Int(expected)))
            }
            if !UIAccessibility.isReduceMotionEnabled && !ProcessInfo.processInfo.isLowPowerModeEnabled {
                check(animatedViews.count == 2 && animatedViews.allSatisfy(\.isAnimating), "swiftui-avatars-actively-playing")
            }
            try snapshot(window, name: "avatar-motion-early")
            await pause(0.65)
            check(animatedViews.allSatisfy { abs($0.bounds.width - $0.bounds.height) < 0.5 && $0.bounds.width <= 92.5 },
                  "swiftui-animation-bounds-stable-mid-playback")
            try snapshot(window, name: "avatar-motion-middle")
            for iteration in 0..<3 {
                host.rootView = AnyView(Text("Conversation"))
                await pause(0.1)
                host.rootView = AnyView(BotAvatar(profile: profile, size: 92))
                await pause(0.1)
                check(avatarImages(in: host.view).isEmpty && animatedViews.allSatisfy { !$0.isAnimating },
                      "static-commander-return-" + String(iteration))
            }
            window.overrideUserInterfaceStyle = .light
            host.rootView = AnyView(BotAvatarPicker(profile: profile) { _ in true })
            await pause(2.4); try snapshot(window, name: "avatar-picker-light")
            window.overrideUserInterfaceStyle = .dark
            host.rootView = AnyView(BotAvatarPicker(profile: profile) { _ in true }
                .environment(\.dynamicTypeSize, .accessibility3))
            await pause(2.4); try snapshot(window, name: "avatar-picker-accessibility-dark")
            func images(_ view: UIView) -> [UIImageView] { (view as? UIImageView).map { [$0] } ?? view.subviews.flatMap(images) }
            check(images(host.view).allSatisfy { !$0.isAnimating }, "picker-static-after-one-shot")
            if !UIAccessibility.isReduceMotionEnabled { limitations.append("System Reduce Motion is not enabled; its setting transition still requires device acceptance.") }
        } catch { failures.append(error.localizedDescription) }
        do {
            let result: [String: Any] = ["cases": cases, "failures": failures, "limitations": limitations]
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: documents.appendingPathComponent("result.json"))
        } catch { fatalError("Unable to write avatar test result: \(error)") }
    }
}
