// Isolated simulator fixtures: real presentation coordinator and avatar renderer,
// synthetic lifecycle notifications/images, no live website or credentials.
import SwiftUI
import UIKit

@MainActor final class InteractionAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Validation", sessionRole: session.role)
        configuration.delegateClass = InteractionSceneDelegate.self
        return configuration
    }
}

@MainActor final class InteractionSceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?
    private var started = false
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.rootViewController?.view.backgroundColor = .systemBackground
        self.window = window; window.makeKeyAndVisible()
    }
    func sceneDidBecomeActive(_ scene: UIScene) {
        guard !started else { return }; started = true
        Task { await validate() }
    }
    private func pause(_ seconds: Double = 0.35) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
    private func wait(_ predicate: () -> Bool, seconds: Double = 3) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if predicate() { return true }; await pause(0.05)
        }
        return predicate()
    }
    private func validate() async {
        guard let window, let scene = window.windowScene, let root = window.rootViewController else { return }
        await pause(0.5)
        var failures: [String] = [], cases: [String] = []
        func check(_ condition: Bool, _ name: String) {
            cases.append(name); if !condition { failures.append(name) }
        }
        let other = UIWindow(windowScene: scene)
        other.rootViewController = UIViewController(); other.makeKeyAndVisible(); window.makeKeyAndVisible()
        check(BrowserSecurePresentation.presenter(preferredWindow: other) === other.rootViewController, "request-owned non-key window preferred")
        other.isHidden = true
        check(BrowserSecurePresentation.presenter(preferredWindow: other) === root, "hidden request window falls back")
        let overlay = UIWindow(windowScene: scene); overlay.windowLevel = .alert
        overlay.rootViewController = UIViewController(); overlay.makeKeyAndVisible()
        check(BrowserSecurePresentation.presenter(preferredWindow: overlay) === root, "overlay window excluded")
        overlay.isHidden = true; window.makeKeyAndVisible()

        var count = 0, ends: [String] = []
        func controller() -> UIViewController {
            count += 1
            let value = UIHostingController(rootView: Text("Native secure-input presentation fixture"))
            value.modalPresentationStyle = .fullScreen; return value
        }
        window.isHidden = true
        let delayed = BrowserSecurePresentation(preferredWindow: window, timeoutNanoseconds: 500_000_000,
            sourceIsValid: { true }, makeController: controller, onEnd: { ends.append($0) })
        delayed.start(); delayed.start()
        await pause(0.8)
        check(count == 0 && ends.isEmpty && delayed.phase == .waitingForWindow, "waiting has no presentation timeout or duplicate start")
        // Synthetic background event while waiting must preserve the metadata request.
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        check(delayed.phase == .waitingForWindow, "background pending request retained")
        window.makeKeyAndVisible()
        let shown = await wait({ delayed.phase == .awaitingUser })
        check(shown && count == 1, "visible foreground window presents once")
        let expired = await wait({ delayed.phase == .finished })
        check(expired && ends == ["expired"], "timeout begins only after presentation and completes once")
        delayed.stop(); await pause()

        count = 0; ends = []
        window.isHidden = true
        let cancelled = BrowserSecurePresentation(preferredWindow: window, sourceIsValid: { true },
            makeController: controller, onEnd: { ends.append($0) })
        cancelled.start(); cancelled.stop(); window.makeKeyAndVisible(); await pause()
        check(cancelled.phase == .finished && count == 0 && ends.isEmpty, "cancelled pending request never appears")

        var valid = false
        let invalid = BrowserSecurePresentation(preferredWindow: window, sourceIsValid: { valid },
            makeController: controller, onEnd: { ends.append($0) })
        invalid.start(); await pause()
        check(count == 0 && ends == ["cancelled: source_changed"], "invalid origin ends without a card")

        count = 0; ends = []; valid = true
        let blocker = UIViewController(); blocker.modalPresentationStyle = .fullScreen
        root.present(blocker, animated: true)
        let transition = BrowserSecurePresentation(preferredWindow: window, sourceIsValid: { valid },
            makeController: controller, onEnd: { ends.append($0) })
        transition.start()
        check(transition.phase == .waitingForWindow && count == 0, "transition defers presentation")
        let afterTransition = await wait({ transition.phase == .awaitingUser })
        check(afterTransition && count == 1, "transition completion retries once")
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        check(transition.phase == .finished && ends == ["cancelled: background"], "displayed card cancels on background event")
        root.dismiss(animated: false); await pause()

        count = 0; ends = []
        let changed = BrowserSecurePresentation(preferredWindow: window, sourceIsValid: { valid },
            makeController: controller, onEnd: { ends.append($0) })
        changed.start(); _ = await wait({ changed.phase == .awaitingUser })
        valid = false
        let invalidated = await wait({ changed.phase == .finished })
        check(invalidated && ends == ["cancelled: source_changed"] && count == 1, "origin change after presentation cancels once")
        await pause()

        // Synthetic atlas tests exercise only decoding/playback, not the requested artwork.
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let atlas = UIGraphicsImageRenderer(size: CGSize(width: 192, height: 128), format: format).image { context in
            for frame in 0..<24 {
                UIColor(hue: CGFloat(frame) / 24, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                context.fill(CGRect(x: frame % 6 * 32 + 4, y: frame / 6 * 32 + 4, width: 24, height: 24))
            }
        }
        let frames = BotAvatarFrameCache.decode(atlas.cgImage!) ?? []
        check(frames.count == 24 && frames.allSatisfy { $0.size == CGSize(width: 32, height: 32) }, "24 square atlas cells decoded")
        check(frames.first?.pngData() != frames.last?.pngData(), "frames preserve distinct poses/order")
        let malformed = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100), format: format).image { _ in }
        check(BotAvatarFrameCache.decode(malformed.cgImage!) == nil, "malformed atlas rejected")
        if let cover = frames.first {
            let image = BotAvatarImageView(frame: CGRect(x: 20, y: 100, width: 80, height: 80))
            root.view.addSubview(image)
            image.play(frames, cover: cover)
            check(image.animationRepeatCount == 1 && image.animationDuration == 2 && image.isAnimating, "native single 2-second playback")
            let completed = await wait({ image.animationImages == nil }, seconds: 3)
            check(completed && image.image === cover && !image.isAnimating, "single playback returns to cover and releases frames")
            image.play(frames, cover: cover)
            NotificationCenter.default.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
            check(!image.isAnimating && image.animationImages == nil, "motion setting notification stops playback")
            image.play(frames, cover: cover)
            NotificationCenter.default.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
            check(!image.isAnimating && image.animationImages == nil, "power setting notification stops playback")
            image.play(frames, cover: cover); image.frame.origin.y = -500; await pause()
            check(!image.isAnimating && image.animationImages == nil, "offscreen playback stops")
            image.frame.origin.y = 100; await pause()
            check(!image.isAnimating, "visibility recovery does not replay")
            image.play(frames, cover: cover); image.removeFromSuperview()
            check(!image.isAnimating && image.animationImages == nil, "detachment releases playback frames")
        }
        // Missing art must use the old icon; exercise picker layouts across accessibility sizes.
        let profile = BotProfile(name: "Fixture", iconSymbol: "terminal.fill", avatarPresetID: "pikachu")
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for (width, height, dark, large) in [(320.0, 568.0, false, false), (375.0, 812.0, true, true), (667.0, 375.0, true, false)] {
            let host = UIHostingController(rootView: BotAvatarPicker(profile: profile, onConfirm: { _ in true })
                .environment(\.dynamicTypeSize, large ? .accessibility3 : .large)
                .environment(\.colorScheme, dark ? .dark : .light))
            root.addChild(host); root.view.addSubview(host.view); host.didMove(toParent: root)
            host.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
            host.view.layoutIfNeeded(); await pause()
            let name = "avatar-picker-\(Int(width))-\(dark ? "dark" : "light")-\(large ? "ax3" : "regular")"
            let snapshot = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            do { try snapshot.pngData()?.write(to: output.appendingPathComponent(name + ".png")) }
            catch { failures.append(name + " snapshot failed") }
            check(host.view.bounds.width == width, name + " rendered")
            host.willMove(toParent: nil); host.view.removeFromSuperview(); host.removeFromParent()
        }
        let result: [String: Any] = ["cases": cases, "failures": failures,
            "limitations": "Synthetic lifecycle and atlas fixtures; no real login, production character art, physical device, VoiceOver navigation or keyboard acceptance."]
        do { try JSONSerialization.data(withJSONObject: result, options: .prettyPrinted).write(to: output.appendingPathComponent("result.json")) }
        catch { NSLog("Native interaction test result write failed") }
    }
}

@main struct InteractionMain {
    static func main() { UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(InteractionAppDelegate.self)) }
}
