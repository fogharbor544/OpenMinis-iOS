import SwiftUI
import Security
import WebKit
import UniformTypeIdentifiers
import UIKit

struct BrowserCredential: Identifiable, Codable {
    var id = UUID()
    var origin: String
    var username: String
    var password: String
}

@MainActor
protocol BrowserCredentialVault {
    func read() throws -> Data?
    func write(_ data: Data) throws
}

@MainActor
struct KeychainBrowserCredentialVault: BrowserCredentialVault {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.openminis.browser.credentials",
         kSecAttrAccount as String: "vault",
         kSecAttrSynchronizable as String: false]
    }

    func read() throws -> Data? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return data
    }

    func write(_ data: Data) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}

@MainActor
final class BrowserCredentialStore: ObservableObject {
    @Published private(set) var entries: [BrowserCredential] = []
    @Published private(set) var isUnlocked = false
    @Published var errorMessage: String?
    private let vault: any BrowserCredentialVault
    private let authenticate: () async -> Bool

    init(vault: (any BrowserCredentialVault)? = nil,
         authenticate: @escaping () async -> Bool = {
             await BiometricAuth.authenticate(reason: String(localized: "Unlock browser passwords"))
         }) {
        self.vault = vault ?? KeychainBrowserCredentialVault()
        self.authenticate = authenticate
    }
    private var unlockGeneration = UUID()

    static func origin(for text: String) -> String? {
        guard let url = URL(string: text), url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        if let port = url.port, port != 443 { components.port = port }
        return components.string
    }

    func unlock() async {
        let generation = UUID()
        unlockGeneration = generation
        guard await authenticate() else {
            errorMessage = String(localized: "Authentication was cancelled or unavailable.")
            return
        }
        guard unlockGeneration == generation else { return }
        do {
            if let data = try vault.read() {
                entries = try JSONDecoder().decode([BrowserCredential].self, from: data)
            } else { entries = [] }
            isUnlocked = true
            errorMessage = nil
        } catch { errorMessage = String(localized: "Unable to read browser passwords from Keychain.") }
    }

    func lock() { unlockGeneration = UUID(); entries = []; isUnlocked = false }

    @discardableResult
    func save(_ entry: BrowserCredential) -> Bool {
        guard isUnlocked, let origin = Self.origin(for: entry.origin), !entry.password.isEmpty else {
            errorMessage = String(localized: "Enter an HTTPS website and a password.")
            return false
        }
        var entry = entry
        entry.origin = origin
        var next = entries
        if let index = next.firstIndex(where: { $0.id == entry.id }) {
            guard !next.contains(where: { $0.id != entry.id && $0.origin == origin && $0.username == entry.username }) else {
                errorMessage = String(localized: "This website and username already have a saved password. Edit that entry instead.")
                return false
            }
            next[index] = entry
        } else if let index = next.firstIndex(where: { $0.origin == origin && $0.username == entry.username }) {
            entry.id = next[index].id
            next[index] = entry
        } else { next.append(entry) }
        return persist(next)
    }

    func delete(_ entry: BrowserCredential) {
        guard isUnlocked else { return }
        _ = persist(entries.filter { $0.id != entry.id })
    }

    /// Explicit one-way import. The user-selected source is never rewritten.
    @discardableResult
    func importFile(_ url: URL) -> Bool {
        guard isUnlocked else { return false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let object = try JSONSerialization.jsonObject(with: data)
            let rows = try Self.validatedRows(object)
            var next = entries
            for row in rows {
                guard let credential = Self.credential(row) else { throw NSError(domain: "BrowserCredentialFile", code: 1) }
                var imported = credential
                if let existing = entries.first(where: { $0.origin == imported.origin && $0.username == imported.username }) { imported.id = existing.id }
                if let index = next.firstIndex(where: { $0.origin == imported.origin && $0.username == imported.username }) {
                    imported.id = next[index].id
                    next[index] = imported
                } else { next.append(imported) }
            }
            guard !rows.isEmpty else { throw NSError(domain: "BrowserCredentialFile", code: 2) }
            return persist(next)
        } catch {
            errorMessage = "导入失败。请选择包含网站、用户名和密码的 JSON 文件；支持 origin/url/website、username/account/email 和 password 字段。"
            return false
        }
    }

    private static let siteKeys = ["origin", "url", "website", "login_url", "site", "domain"]
    private static let userKeys = ["username", "account", "email", "login", "user"]

    private static func credential(_ row: [String: Any], siteHint: String? = nil) -> BrowserCredential? {
        let site = siteKeys.compactMap { row[$0] as? String }.first ?? siteHint
        guard let site, let origin = origin(for: site.contains("://") ? site : "https://" + site),
              let username = userKeys.compactMap({ row[$0] as? String }).first,
              let password = row["password"] as? String, !password.isEmpty else { return nil }
        return BrowserCredential(origin: origin, username: username, password: password)
    }

    /// Accept arrays, named collections and domain-keyed vaults without changing their layout.
    private static func fileRows(_ object: Any, siteHint: String? = nil) throws -> [[String: Any]] {
        if let rows = object as? [Any] { return try rows.flatMap { try fileRows($0, siteHint: siteHint) } }
        guard let root = object as? [String: Any] else { return [] }
        if let entry = credential(root, siteHint: siteHint) {
            return [["origin": entry.origin, "username": entry.username, "password": entry.password]]
        }
        if root["password"] != nil { throw NSError(domain: "BrowserCredentialFile", code: 3) }
        return try root.flatMap { key, value in
            try fileRows(value, siteHint: siteKeys.compactMap { root[$0] as? String }.first ?? (key.contains(".") ? key : siteHint))
        }
    }

    private static func validatedRows(_ object: Any) throws -> [[String: Any]] {
        let rows = try fileRows(object)
        guard rows.isEmpty else { return rows }
        if let array = object as? [Any], array.isEmpty { return [] }
        if let root = object as? [String: Any] {
            if root.isEmpty { return [] }
            if ["entries", "credentials", "passwords", "accounts"].contains(where: { (root[$0] as? [Any])?.isEmpty == true }) { return [] }
        }
        throw NSError(domain: "BrowserCredentialFile", code: 4)
    }

    private func persist(_ next: [BrowserCredential]) -> Bool {
        do {
            try vault.write(JSONEncoder().encode(next))
            entries = next
            errorMessage = nil
            return true
        } catch {
            errorMessage = "无法保存密码，请确认设备已设置锁屏密码后重试。原记录未改变。"
            return false
        }
    }

    /// Used only to mask saved passwords in assistant replies, never exposed as a tool result.
    static func passwordsForRedaction() -> [String] {
        var passwords: [String] = []
        if let data = try? KeychainBrowserCredentialVault().read(),
           let saved = try? JSONDecoder().decode([BrowserCredential].self, from: data) {
            passwords += saved.map(\.password)
        }
        return Array(Set(passwords.filter { !$0.isEmpty })).sorted { $0.count > $1.count }
    }

    static func hasLogin(for url: String) -> Bool {
        guard let origin = origin(for: url) else { return false }
        if let data = try? KeychainBrowserCredentialVault().read(),
           let entries = try? JSONDecoder().decode([BrowserCredential].self, from: data),
           entries.contains(where: { $0.origin == origin }) { return true }
        return false
    }

}

struct BrowserPasswordsView: View {
    @ObservedObject var manager: BrowserUseManager
    @StateObject private var store = BrowserCredentialStore()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var editing: BrowserCredential?
    @State private var deleting: BrowserCredential?
    @State private var importing = false
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                if store.isUnlocked {
                    Section {
                        Button("Add Password") {
                            editing = BrowserCredential(origin: BrowserCredentialStore.origin(for: manager.currentURL) ?? "", username: "", password: "")
                        }
                        Button("从已有密码文件导入") { importing = true }
                        Button("Save Login from Current Page") { Task { await capture() } }
                            .disabled(busy || BrowserCredentialStore.origin(for: manager.currentURL) == nil)
                    } footer: {
                        Text("密码仅保存在本机 Keychain。手动导入不会修改源文件。填充仅匹配相同 HTTPS 网站，不会自动提交登录。")
                    }
                    if store.entries.isEmpty { Text("No Saved Passwords").foregroundStyle(.secondary) }
                    ForEach(store.entries) { entry in
                        Section {
                            Button { editing = entry } label: {
                                VStack(alignment: .leading) {
                                    Text(entry.origin)
                                    Text(entry.username).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if entry.origin == BrowserCredentialStore.origin(for: manager.currentURL) {
                                Button("Fill Login") { Task { await fill(entry) } }.disabled(busy)
                            }
                            Button("Delete", role: .destructive) { deleting = entry }
                        }
                    }
                } else {
                    Button("Unlock Passwords") { Task { await store.unlock() } }
                }
                if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
                if let message { Text(message).foregroundStyle(.secondary) }
            }
            .navigationTitle("Passwords")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(item: $editing) { entry in BrowserCredentialEditor(store: store, entry: entry) }
            .confirmationDialog("Delete saved password?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Delete", role: .destructive) { if let deleting { store.delete(deleting) }; deleting = nil }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first, store.importFile(url) { message = "密码已导入本机 Keychain；源文件未修改。" }
                case .failure: message = "无法打开密码文件。"
                }
            }
            .task { await store.unlock() }
            .onChange(of: scenePhase) { phase in
                if phase == .background { editing = nil; deleting = nil; store.lock() }
            }
        }
    }

    private func capture() async {
        guard let origin = BrowserCredentialStore.origin(for: manager.currentURL) else { return }
        busy = true
        defer { busy = false }
        do {
            let value = try await manager.webView.callAsyncJavaScript("""
                if (location.origin !== origin) return null;
                const fields = [...document.querySelectorAll('input[type="password"]')].filter(e => e.getClientRects().length && !e.disabled);
                if (fields.length !== 1 || !fields[0].value) return null;
                const password = fields[0];
                const scope = password.form || document;
                const username = scope.querySelector('input[autocomplete="username"], input[type="email"], input[type="text"]');
                return {username: username?.value || '', password: password.value};
                """, arguments: ["origin": origin], contentWorld: .defaultClient)
            guard store.isUnlocked, BrowserCredentialStore.origin(for: manager.currentURL) == origin,
                  let values = value as? [String: String], let password = values["password"] else {
                message = String(localized: "No supported login form found on this page."); return
            }
            let username = values["username"] ?? ""
            var entry = store.entries.first { $0.origin == origin && $0.username == username }
                ?? BrowserCredential(origin: origin, username: username, password: password)
            entry.password = password
            editing = entry
        } catch { message = String(localized: "Unable to read this login form.") }
    }

    private func fill(_ entry: BrowserCredential) async {
        busy = true
        defer { busy = false }
        guard await BiometricAuth.authenticate(reason: String(localized: "Fill browser password")),
              store.isUnlocked, BrowserCredentialStore.origin(for: manager.currentURL) == entry.origin else { return }
        let result = await BrowserCredentialFiller.request(entry, manager: manager)
        message = result ? "安全登录流程已完成。" : "安全登录已取消或不可用。"
    }
}

private struct BrowserCredentialEditor: View {
    @ObservedObject var store: BrowserCredentialStore
    @State var entry: BrowserCredential
    @State private var reveal = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                TextField("Website", text: $entry.origin).keyboardType(.URL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Username", text: $entry.username).textContentType(.username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if reveal { TextField("Password", text: $entry.password).textInputAutocapitalization(.never).autocorrectionDisabled() }
                else { SecureField("Password", text: $entry.password).textContentType(.password) }
                Toggle("Show Password", isOn: $reveal)
                if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Edit Password")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { if store.save(entry) { dismiss() } } }
            }
            .onDisappear { entry.password = "" }
        }
    }
}

@MainActor
enum BrowserCredentialFiller {
    /// Saved credentials use the same isolated native flow as newly requested values.
    static func request(_ entry: BrowserCredential, manager: BrowserUseManager) async -> Bool {
        guard BrowserUseManager.secureInteractionManager == nil, !manager.isSecureInputActive,
              BrowserCredentialStore.origin(for: manager.currentURL) == entry.origin,
              UIApplication.shared.applicationState == .active,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return false }
        var presenter = root
        while let presented = presenter.presentedViewController { presenter = presented }
        guard !presenter.isBeingDismissed else { return false }
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: false); return }
                let session = BrowserSecureInputSession(manager: manager, origin: entry.origin,
                    requester: "用户手动操作", purpose: "填充已保存的账号密码", selector: "input[type=password]", kind: .password) { status in
                    continuation.resume(returning: !status.contains("cancelled") && !status.contains("expired"))
                }
                session.secret = entry.password; session.username = entry.username; session.useSavedAccount = true
                BrowserUseManager.secureInteractionManager = manager
                BrowserUseManager.secureInteractionGeneration = UUID()
                manager.secureInputProtected = true
                manager.secureInputSession = session
                manager.lastScreenshot = nil
                session.present(from: presenter)
            }
        }, onCancel: {
            Task { @MainActor in manager.secureInputSession?.finish("cancelled") }
        })
    }

    fileprivate static func fill(_ entry: BrowserCredential, manager: BrowserUseManager) async throws -> Bool {
        guard manager.secureInputSession != nil, manager.secureInputProtected,
              BrowserCredentialStore.origin(for: manager.currentURL) == entry.origin else { return false }
        let result = try await manager.webView.callAsyncJavaScript("""
                if (location.origin !== origin) return false;
                const fields = [...document.querySelectorAll('input[type="password"]')].filter(e => e.getClientRects().length && !e.disabled && !e.readOnly && e.autocomplete !== 'new-password');
                if (fields.length !== 1) return false;
                const passwordField = fields[0];
                window.addEventListener('pagehide', () => { passwordField.value = ''; }, {once: true});
                const scope = passwordField.form || document;
                const usernameField = scope.querySelector('input[autocomplete="username"], input[type="email"], input[type="text"]');
                const set = (field, value) => {
                    if (!field || field.disabled || field.readOnly) return;
                    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(field, value);
                    field.dispatchEvent(new Event('input', {bubbles: true}));
                    field.dispatchEvent(new Event('change', {bubbles: true}));
                };
                set(usernameField, username);
                set(passwordField, password);
                return true;
                """, arguments: ["origin": entry.origin, "username": entry.username, "password": entry.password], contentWorld: .defaultClient)
        return result as? Bool == true
    }
}

struct BrowserLoginAutofillButton: View {
    @ObservedObject var manager: BrowserUseManager
    var isAgentBusy: Bool
    var onChoose: () -> Void
    @StateObject private var store = BrowserCredentialStore()
    @State private var available = false
    @State private var filling = false
    @State private var feedback: String?
    var body: some View {
        Group {
            if available && !isAgentBusy {
                Button {
                    filling = true
                    Task {
                        defer { filling = false; store.lock() }
                        await store.unlock()
                        guard store.isUnlocked else { feedback = store.errorMessage; return }
                        let matches = store.entries.filter { $0.origin == BrowserCredentialStore.origin(for: manager.currentURL) }
                        guard matches.count == 1, let entry = matches.first else { onChoose(); return }
                        guard !isAgentBusy else { return }
                        let filled = await BrowserCredentialFiller.request(entry, manager: manager)
                        feedback = filled ? "安全登录流程已完成。" : "安全登录已取消或不可用。"
                    }
                } label: { Label(filling ? "正在填充" : "填充已保存的账号密码", systemImage: "key.fill") }
                .disabled(filling).frame(minHeight: 44)
            }
        }
        .task(id: manager.currentURL + String(manager.isLoading)) {
            available = !manager.isLoading && BrowserCredentialStore.hasLogin(for: manager.currentURL)
        }
        .alert("密码管理器", isPresented: Binding(get: { feedback != nil }, set: { if !$0 { feedback = nil } })) {
            Button("好", role: .cancel) { feedback = nil }
        } message: { Text(feedback ?? "") }
    }
}

// BEGIN PasswordReplyRedactor
/// Hold a possible secret suffix until the following chunk disambiguates it.
/// This prevents a password arriving across multiple deltas from flashing in chat or TTS.
enum PasswordReplyRedactor {
    static func redact(_ text: String, passwords: [String], streaming: Bool) -> String {
        guard !passwords.isEmpty else { return text }
        var value = text
        for password in passwords where !password.isEmpty {
            value = value.replacingOccurrences(of: password, with: "[密码已隐藏，请在密码管理器查看]")
        }
        if streaming {
            var held = 0
            for password in passwords where password.count > 1 {
                let maximum = min(password.count - 1, value.count)
                guard maximum > 0 else { continue }
                for length in stride(from: maximum, through: 1, by: -1) {
                    if value.hasSuffix(String(password.prefix(length))) { held = max(held, length); break }
                }
            }
            if held > 0 { value.removeLast(held) }
        }
        return value
    }
}
// END PasswordReplyRedactor


// Secrets exist only in this native session; no Codable, tool payload or history field.
@MainActor
final class BrowserSecureInputSession: ObservableObject {
    enum Kind: String { case password, pin, otp
        var label: String {
            switch self { case .password: return "密码"; case .pin: return "PIN"; case .otp: return "验证码" }
        }
    }
    let id = UUID()
    let origin: String
    let requester: String
    let purpose: String
    let selector: String
    let kind: Kind
    let manager: BrowserUseManager
    @Published var secret = ""
    @Published var username = ""
    @Published var reveal = false
    @Published var filled = false
    @Published var confirmedLogin = false
    @Published var feedback: String?
    @Published var busy = false
    @Published var shielded = false
    @Published var updateExisting = false
    var useSavedAccount = false
    let store: BrowserCredentialStore
    private var completion: ((String) -> Void)?
    private weak var controller: UIViewController?
    private var timeout: Task<Void, Never>?
    private var ended = false

    init(manager: BrowserUseManager, origin: String, requester: String, purpose: String,
         selector: String, kind: Kind, store: BrowserCredentialStore? = nil, completion: @escaping (String) -> Void) {
        self.store = store ?? BrowserCredentialStore()
        self.manager = manager; self.origin = origin; self.requester = requester
        self.purpose = purpose; self.selector = selector; self.kind = kind; self.completion = completion
    }

    func present(from presenter: UIViewController) {
        let controller = UIHostingController(rootView: BrowserSecureInputView(session: self))
        controller.isModalInPresentation = true
        controller.modalPresentationStyle = .fullScreen
        self.controller = controller
        presenter.present(controller, animated: true)
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000_000)
            guard !Task.isCancelled else { return }
            self?.finish("expired")
        }
    }

    func fill() async {
        guard !busy, !ended, !secret.isEmpty,
              !manager.isLoading, BrowserCredentialStore.origin(for: manager.webView.url?.absoluteString ?? "") == origin else {
            feedback = "网站已变化或输入为空，请取消后重新请求。"; return
        }
        busy = true
        defer { busy = false }
        // Lock before crossing into WebKit; JS exceptions must never surface their arguments.
        manager.secureInputProtected = true
        do {
            let result: Bool
            if useSavedAccount {
                result = try await BrowserCredentialFiller.fill(BrowserCredential(origin: origin, username: username, password: secret), manager: manager)
            } else {
                let value = try await manager.webView.callAsyncJavaScript(Self.fillScript,
                    arguments: ["origin": origin, "selector": selector, "secret": secret, "kind": kind.rawValue],
                    in: nil, contentWorld: .defaultClient)
                result = value as? Bool == true
            }
            guard !ended else { manager.finishSecureInput(); return }
            guard result else { feedback = "未找到唯一、可编辑的安全输入框，未填充。"; return }
            filled = true; reveal = false
            feedback = "已安全填充。请在网页中完成登录，再确认结果；应用不会自动提交。"
            if kind != .password { secret = "" }
        } catch { if !ended { feedback = "安全填充失败，请重试或取消。" } }
    }

    // BEGIN NativeSecureFillScript
    static let fillScript = """
        if (location.origin !== origin) return false;
        const fields = [...document.querySelectorAll(selector)];
        if (fields.length !== 1) return false;
        const field = fields[0];
        if (!(field instanceof HTMLInputElement) || !field.getClientRects().length || field.disabled || field.readOnly) return false;
        if (kind === 'password' && (field.type !== 'password' || field.autocomplete === 'new-password')) return false;
        if (kind !== 'password' && !['password', 'text', 'tel', 'number'].includes(field.type)) return false;
        // PIN/OTP remain visually masked; no plaintext value is returned.
        if (kind !== 'password') field.type = 'password';
        // Erase this document before WebKit can place it in the back-forward cache.
        window.addEventListener('pagehide', () => { field.value = ''; }, {once: true});
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(field, secret);
        field.dispatchEvent(new Event('input', {bubbles: true}));
        field.dispatchEvent(new Event('change', {bubbles: true}));
        return true;
        """
    // END NativeSecureFillScript

    func prepareSave() async {
        guard !ended, filled, kind == .password, confirmedLogin, !busy else { return }
        busy = true
        defer { busy = false }
        await store.unlock()
        guard !ended else { store.lock(); return }
        guard store.isUnlocked else { feedback = store.errorMessage; return }
        updateExisting = store.entries.contains { $0.origin == origin && $0.username == username }
        feedback = updateExisting ? "同一网站和账号已有密码。请确认更新。" : "请确认将密码保存到本机 Keychain。"
    }

    func save() {
        guard !ended, filled, confirmedLogin, kind == .password, store.isUnlocked else { return }
        let previous = store.entries.first { $0.origin == origin && $0.username == username }
        var entry = previous ?? BrowserCredential(origin: origin, username: username, password: secret)
        entry.password = secret
        guard store.save(entry) else { feedback = store.errorMessage; return }
        finish(previous == nil ? "saved" : "updated")
    }

    func finish(_ status: String) {
        guard !ended else { return }
        ended = true; timeout?.cancel(); timeout = nil
        secret = ""; username = ""; reveal = false; shielded = true; store.lock()
        manager.secureInputSession = nil
        manager.finishSecureInput()
        let callback = completion; completion = nil
        controller?.dismiss(animated: true) { [weak manager = manager] in manager?.objectWillChange.send() }
        callback?("reference=\(id.uuidString); \(status)")
    }
}

private struct BrowserSecureInputView: View {
    @ObservedObject var session: BrowserSecureInputSession
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    BrowserWebView(manager: session.manager)
                    BrowserLoadErrorOverlay(manager: session.manager)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("安全输入 · " + session.kind.label, systemImage: "lock.shield").font(.headline)
                        Text(session.origin).font(.subheadline).textSelection(.enabled)
                        Text("请求 Bot：" + session.requester)
                        Text("用途：" + session.purpose)
                        Text("输入由原生通道交给此网站；模型只收到状态。完成后刷新网页并清空输入框，保留登录状态。")
                            .font(.footnote).foregroundStyle(.secondary)
                        if !session.filled {
                            if session.reveal { TextField(session.kind.label, text: $session.secret) }
                            else { SecureField(session.kind.label, text: $session.secret) }
                            Toggle("显示输入", isOn: $session.reveal)
                            Button("提交到网页") { Task { await session.fill() } }
                                .disabled(session.secret.isEmpty || session.busy).frame(minHeight: 44)
                        } else if session.kind == .password {
                            Toggle("我已在网页中确认登录成功", isOn: $session.confirmedLogin)
                            TextField("账号（用于区分此网站的密码）", text: $session.username)
                                .disabled(session.store.isUnlocked)
                            if session.store.isUnlocked {
                                Button(session.updateExisting ? "确认更新密码" : "确认保存密码") { session.save() }
                                    .disabled(!session.confirmedLogin).frame(minHeight: 44)
                            } else {
                                Button("保存密码") { Task { await session.prepareSave() } }
                                    .disabled(!session.confirmedLogin || session.busy).frame(minHeight: 44)
                            }
                            Button("暂不保存") { session.finish("filled_not_saved") }.frame(minHeight: 44)
                        } else {
                            Button("完成，不保存") { session.finish("filled") }.frame(minHeight: 44)
                        }
                        if let feedback = session.feedback { Text(feedback).font(.footnote).foregroundStyle(.secondary) }
                    }
                    .textInputAutocapitalization(.never).autocorrectionDisabled().padding()
                }.frame(maxHeight: 330).background(.regularMaterial)
            }
            .navigationTitle("安全登录").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("取消") { session.finish("cancelled") }
            } }
        }
        .privacySensitive()
        .overlay { if session.shielded { Color(UIColor.systemBackground).ignoresSafeArea().overlay(Label("安全输入已遮蔽", systemImage: "lock.fill")) } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in session.shielded = true; session.reveal = false }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in session.shielded = false }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in session.finish("cancelled") }
    }
}
