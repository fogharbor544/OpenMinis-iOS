import SwiftUI
import UIKit
import PhotosUI
import ImageIO

struct BotAvatar: View {
    let profile: BotProfile
    var size: CGFloat = 32
    var playbackID: UUID? = nil
    private var iconColor: Color {
        SessionCategory.all.first { $0.icon == profile.iconSymbol }?.color ?? .green
    }
    var body: some View {
        Group {
            if let data = profile.iconImageData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let preset = BotAvatarPreset.find(profile.avatarPresetID),
                      let cover = UIImage(named: preset.coverAsset) {
                if let playbackID {
                    BotAvatarAnimation(preset: preset, cover: cover, playbackID: playbackID)
                } else { Image(uiImage: cover).resizable().scaledToFit() }
            } else {
                Image(systemName: profile.iconSymbol ?? "bubble.left.fill")
                    .resizable().scaledToFit().padding(size * 0.24)
                    .foregroundStyle(iconColor)
                    .background(iconColor.opacity(0.18), in: Circle())
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// Only primary previews opt into motion. List rows keep the default static renderer.
struct BotAvatarPreview: View {
    let profile: BotProfile
    var size: CGFloat = 80
    var replayTrigger: UUID? = nil
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playbackID: UUID?
    var body: some View {
        Button { replay() } label: {
            BotAvatar(profile: profile, size: size, playbackID: playbackID)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("头像预览")
        .accessibilityValue(BotAvatarPreset.find(profile.avatarPresetID)?.name ?? "自定义头像")
        .accessibilityHint("轻点播放一次头像动作")
        .onAppear { replay() }
        .onDisappear { playbackID = nil }
        .onChange(of: profile.avatarPresetID) { _ in replay() }
        .onChange(of: replayTrigger) { _ in replay() }
        .onChange(of: scenePhase) { if $0 != .active { playbackID = nil } }
        .onChange(of: reduceMotion) { if $0 { playbackID = nil } }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            if ProcessInfo.processInfo.isLowPowerModeEnabled { playbackID = nil }
        }
    }
    private func replay() {
        guard scenePhase == .active, !reduceMotion, !ProcessInfo.processInfo.isLowPowerModeEnabled else {
            playbackID = nil; return
        }
        playbackID = UUID()
    }
}

/// Imagesets are named by the stable catalog ID; atlas is 6 columns x 4 rows.
/// A missing/unavailable asset never replaces a user's existing photo or icon.
@MainActor
final class BotAvatarFrameCache {
    static let shared = BotAvatarFrameCache()
    private var frames: [String: [UIImage]] = [:]
    private var order: [String] = []
    private var memoryWarning: NSObjectProtocol?
    init() {
        memoryWarning = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.frames.removeAll(); self?.order.removeAll() }
            }
    }
    deinit { if let memoryWarning { NotificationCenter.default.removeObserver(memoryWarning) } }
    func load(_ preset: BotAvatarPreset) async -> [UIImage]? {
        if let cached = frames[preset.id] { touch(preset.id); return cached }
        let name = preset.atlasAsset
        let decoded = await Task.detached(priority: .userInitiated) { () -> [UIImage]? in
            guard let data = NSDataAsset(name: name)?.data,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            return Self.decode(atlas)
        }.value
        guard let decoded, !Task.isCancelled else { return nil }
        frames[preset.id] = decoded; touch(preset.id)
        while order.count > 2 { frames.removeValue(forKey: order.removeFirst()) }
        return decoded
    }
    private func touch(_ id: String) { order.removeAll { $0 == id }; order.append(id) }
    nonisolated static func decode(_ atlas: CGImage) -> [UIImage]? {
        guard atlas.width % 6 == 0, atlas.height % 4 == 0,
              atlas.width / 6 == atlas.height / 4, atlas.width / 6 <= 512 else { return nil }
        let side = atlas.width / 6
        var result: [UIImage] = []
        for index in 0..<24 {
            guard let frame = atlas.cropping(to: CGRect(x: index % 6 * side, y: index / 6 * side, width: side, height: side)) else { return nil }
            result.append(UIImage(cgImage: frame))
        }
        return result
    }
}

private struct BotAvatarAnimation: UIViewRepresentable {
    let preset: BotAvatarPreset
    let cover: UIImage
    let playbackID: UUID
    func makeUIView(context: Context) -> BotAvatarImageView {
        let view = BotAvatarImageView()
        view.contentMode = .scaleAspectFit
        view.isAccessibilityElement = false
        return view
    }
    func updateUIView(_ view: BotAvatarImageView, context: Context) {
        guard context.coordinator.token != playbackID else { return }
        context.coordinator.token = playbackID
        view.reset(cover)
        context.coordinator.task?.cancel()
        context.coordinator.task = Task { @MainActor [weak view] in
            guard let frames = await BotAvatarFrameCache.shared.load(preset), !Task.isCancelled, let view,
                  context.coordinator.token == playbackID else { return }
            view.play(frames, cover: cover)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    static func dismantleUIView(_ view: BotAvatarImageView, coordinator: Coordinator) {
        coordinator.task?.cancel(); view.reset(view.cover)
    }
    final class Coordinator {
        var token: UUID?
        var task: Task<Void, Never>?
        deinit { task?.cancel() }
    }
}

final class BotAvatarImageView: UIImageView {
    var cover: UIImage?
    private var pendingFrames: [UIImage]?
    private var timer: Timer?
    private var remainingTicks = 0
    private var observers: [NSObjectProtocol] = []
    func reset(_ cover: UIImage?) {
        stopAnimating(); animationImages = nil; image = cover; self.cover = cover
        pendingFrames = nil
        timer?.invalidate(); timer = nil
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
    }
    func play(_ frames: [UIImage], cover: UIImage) {
        reset(cover)
        // A cached decode can finish before SwiftUI attaches/sizes the native view.
        // Defer only this first mount; detachment clears the request permanently.
        if window == nil || bounds.isEmpty { pendingFrames = frames; return }
        guard visible, !UIAccessibility.isReduceMotionEnabled, !ProcessInfo.processInfo.isLowPowerModeEnabled,
              UIApplication.shared.applicationState == .active else { return }
        animationImages = frames; animationDuration = 2; animationRepeatCount = 1
        startAnimating(); remainingTicks = 20
        for name in [UIApplication.willResignActiveNotification, UIAccessibility.reduceMotionStatusDidChangeNotification,
                     Notification.Name.NSProcessInfoPowerStateDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reset(self?.cover) }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.remainingTicks -= 1
                if !self.visible || self.remainingTicks <= 0 { self.reset(self.cover) }
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    private var visible: Bool {
        guard let window, !isHidden else { return false }
        var rect = convert(bounds, to: window)
        var ancestor = superview
        while let view = ancestor {
            if view.isHidden || view.alpha == 0 { return false }
            if view.clipsToBounds { rect = rect.intersection(view.convert(view.bounds, to: window)) }
            ancestor = view.superview
        }
        return !rect.isEmpty && rect.intersects(window.bounds)
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { reset(cover) } else { playPendingFrames() }
    }
    override func layoutSubviews() { super.layoutSubviews(); playPendingFrames() }
    private func playPendingFrames() {
        guard window != nil, !bounds.isEmpty, let pendingFrames, let cover else { return }
        self.pendingFrames = nil; play(pendingFrames, cover: cover)
    }
    deinit { timer?.invalidate(); observers.forEach(NotificationCenter.default.removeObserver) }
}

struct BotAvatarPicker: View {
    @State private var draft: BotProfile
    let onConfirm: (BotAvatarChoice) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var replayTrigger = UUID()
    @State private var loadingPhoto = false
    @State private var error: String?
    init(profile: BotProfile, onConfirm: @escaping (BotAvatarChoice) -> Bool) {
        _draft = State(initialValue: profile); self.onConfirm = onConfirm
    }
    private var available: [BotAvatarPreset] { BotAvatarPreset.all.filter { UIImage(named: $0.coverAsset) != nil } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        BotAvatarPreview(profile: draft, replayTrigger: replayTrigger)
                        Text(draft.iconImageData != nil ? "自定义照片" : BotAvatarPreset.find(draft.avatarPresetID)?.name ?? "系统图标")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                Section("宝可梦") {
                    if available.isEmpty {
                        Text("头像素材暂不可用，可选择系统图标或自定义照片。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 12)], spacing: 16) {
                            ForEach(available) { preset in
                                choiceButton(name: preset.name, selected: draft.iconImageData == nil && draft.avatarPresetID == preset.id) {
                                    selectedPhoto = nil; loadingPhoto = false; replayTrigger = UUID()
                                    draft.iconImageData = nil; draft.iconSymbol = "bubble.left.fill"; draft.avatarPresetID = preset.id
                                } icon: {
                                    BotAvatar(profile: BotProfile(name: "", iconSymbol: "bubble.left.fill", avatarPresetID: preset.id), size: 52)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                Section("系统图标") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 12)], spacing: 16) {
                        ForEach(SessionCategory.all, id: \.key) { category in
                            choiceButton(name: category.label, selected: draft.iconImageData == nil && draft.avatarPresetID == nil && draft.iconSymbol == category.icon) {
                                selectedPhoto = nil; loadingPhoto = false; replayTrigger = UUID()
                                draft.iconImageData = nil; draft.avatarPresetID = nil; draft.iconSymbol = category.icon
                            } icon: {
                                Image(systemName: category.icon).font(.title3).foregroundStyle(category.color)
                                    .frame(width: 44, height: 44).background(category.color.opacity(0.18), in: Circle())
                            }
                        }
                    }.padding(.vertical, 8)
                }
                Section("自定义照片") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Choose Custom Image", systemImage: "photo").frame(minHeight: 44)
                    }
                    if loadingPhoto { ProgressView("正在读取照片") }
                }
                if let error { Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) } }
            }
            .navigationTitle("更改头像").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if onConfirm(BotAvatarChoice(profile: draft)) { dismiss() }
                        else { error = "未能保存头像，请关闭后重试。" }
                    }.disabled(loadingPhoto)
                }
            }
            .task(id: selectedPhoto) {
                guard let item = selectedPhoto else { return }
                loadingPhoto = true; error = nil
                defer { if selectedPhoto == item { loadingPhoto = false } }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                        if !Task.isCancelled { error = String(localized: "Unable to read this image.") }; return
                    }
                    try Task.checkCancellation()
                    guard selectedPhoto == item else { return }
                    draft.iconImageData = Self.thumbnail(image); draft.avatarPresetID = nil; replayTrigger = UUID()
                } catch is CancellationError { } catch { self.error = error.localizedDescription }
            }
        }
    }
    private func choiceButton<Icon: View>(name: String, selected: Bool, action: @escaping () -> Void,
                                         @ViewBuilder icon: () -> Icon) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                icon().frame(height: 56)
                Text(LocalizedStringKey(name)).font(.caption).foregroundStyle(.primary).multilineTextAlignment(.center)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.caption)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.4))
            }.frame(maxWidth: .infinity, minHeight: 88).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(Text(LocalizedStringKey(name))).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private static func thumbnail(_ image: UIImage) -> Data? {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let side: CGFloat = 192
        let result = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let scale = max(side / image.size.width, side / image.size.height)
            let width = image.size.width * scale, height = image.size.height * scale
            image.draw(in: CGRect(x: (side - width) / 2, y: (side - height) / 2, width: width, height: height))
        }
        return result.jpegData(compressionQuality: 0.85)
    }
}
