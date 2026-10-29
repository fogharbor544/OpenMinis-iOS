import SwiftUI
import Security
import WebKit
import UniformTypeIdentifiers

struct BrowserCredential: Identifiable, Codable {
    var id = UUID()
    var origin: String
    var username: String
    var password: String
    var sourceBookmark: Data?
    var isSharedVault: Bool?
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
    private let legacyVaultURL: URL

    init(vault: (any BrowserCredentialVault)? = nil, legacyVaultURL: URL? = nil,
         authenticate: @escaping () async -> Bool = {
             await BiometricAuth.authenticate(reason: String(localized: "Unlock browser passwords"))
         }) {
        self.vault = vault ?? KeychainBrowserCredentialVault()
        self.legacyVaultURL = legacyVaultURL ?? Self.sharedVaultURL
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
            if FileManager.default.fileExists(atPath: legacyVaultURL.path) {
                _ = importFile(legacyVaultURL, sharedVault: true)
            }
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
        let previous = entries.first { $0.id == entry.id }
        if entry.sourceBookmark == nil, let source = previous?.sourceBookmark, let index = next.firstIndex(where: { $0.id == entry.id }) { next[index].sourceBookmark = source; next[index].isSharedVault = previous?.isSharedVault }
        return persist(next, replacing: previous)
    }

    func delete(_ entry: BrowserCredential) {
        guard isUnlocked else { return }
        _ = persist(entries.filter { $0.id != entry.id }, replacing: entry)
    }

    /// A user-selected JSON source stays linked so editing/deleting never leaves a stale copy.
    static var sharedVaultURL: URL {
        AIChatViewModel.minisSharedPersistentDir.appendingPathComponent("password_manager/vault.json")
    }

    @discardableResult
    func importFile(_ url: URL, sharedVault: Bool = false) -> Bool {
        guard isUnlocked else { return false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let object = try JSONSerialization.jsonObject(with: data)
            let rows = try Self.validatedRows(object)
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            var next = sharedVault ? entries.filter { $0.isSharedVault != true } : entries
            for row in rows {
                guard let credential = Self.credential(row) else { throw NSError(domain: "BrowserCredentialFile", code: 1) }
                var imported = credential
                if let existing = entries.first(where: { $0.origin == imported.origin && $0.username == imported.username }) { imported.id = existing.id }
                imported.sourceBookmark = bookmark
                imported.isSharedVault = sharedVault
                if let index = next.firstIndex(where: { $0.origin == imported.origin && $0.username == imported.username }) {
                    imported.id = next[index].id
                    next[index] = imported
                } else { next.append(imported) }
            }
            guard sharedVault || !rows.isEmpty else { throw NSError(domain: "BrowserCredentialFile", code: 2) }
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

    private static func replaceInFile(_ object: Any, old: BrowserCredential, replacement: BrowserCredential?, siteHint: String? = nil) -> Any? {
        if let rows = object as? [Any] {
            return rows.compactMap { replaceInFile($0, old: old, replacement: replacement, siteHint: siteHint) }
        }
        guard var root = object as? [String: Any] else { return object }
        if let entry = credential(root, siteHint: siteHint), entry.origin == old.origin, entry.username == old.username {
            guard let replacement else { return nil }
            let siteKey = siteKeys.first { root[$0] != nil } ?? "origin"
            let userKey = userKeys.first { root[$0] != nil } ?? "username"
            root[siteKey] = replacement.origin
            root[userKey] = replacement.username
            root["password"] = replacement.password
            return root
        }
        for (key, value) in root {
            root[key] = replaceInFile(value, old: old, replacement: replacement, siteHint: siteKeys.compactMap { root[$0] as? String }.first ?? (key.contains(".") ? key : siteHint))
        }
        return root
    }

    private func persist(_ next: [BrowserCredential], replacing old: BrowserCredential? = nil) -> Bool {
        var sourceURL: URL?
        var previousData: Data?
        var scoped = false
        var sourceChanged = false
        defer { if scoped { sourceURL?.stopAccessingSecurityScopedResource() } }
        do {
            if let old, let bookmark = old.sourceBookmark {
                var stale = false
                let url: URL
                if old.isSharedVault == true { url = legacyVaultURL }
                else { url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) }
                sourceURL = url
                scoped = url.startAccessingSecurityScopedResource()
                if FileManager.default.fileExists(atPath: url.path) {
                    let data = try Data(contentsOf: url)
                    let object = try JSONSerialization.jsonObject(with: data)
                    _ = try Self.validatedRows(object)
                    let replacement = next.first { $0.id == old.id }
                    let output = Self.replaceInFile(object, old: old, replacement: replacement) ?? [String: Any]()
                    previousData = data
                    try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
                    sourceChanged = true
                }
            }
            try vault.write(JSONEncoder().encode(next))
            entries = next
            errorMessage = nil
            return true
        } catch {
            if sourceChanged, let url = sourceURL, let previousData {
                do { try previousData.write(to: url, options: .atomic) }
                catch { errorMessage = "密码保存失败，源文件回滚也失败，请检查源文件与密码管理器。"; return false }
            }
            errorMessage = "无法同步密码，请确认设备密码已开启，关联文件仍可读写。未从密码管理器移除记录。"
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
        if let data = try? Data(contentsOf: sharedVaultURL),
           let object = try? JSONSerialization.jsonObject(with: data),
           let rows = try? fileRows(object) { passwords += rows.compactMap { credential($0)?.password } }
        return Array(Set(passwords.filter { !$0.isEmpty })).sorted { $0.count > $1.count }
    }

    static func hasLogin(for url: String) -> Bool {
        guard let origin = origin(for: url) else { return false }
        if let data = try? KeychainBrowserCredentialVault().read(),
           let entries = try? JSONDecoder().decode([BrowserCredential].self, from: data),
           entries.contains(where: { $0.origin == origin }) { return true }
        if let data = try? Data(contentsOf: sharedVaultURL),
           let object = try? JSONSerialization.jsonObject(with: data),
           let rows = try? fileRows(object) { return rows.contains { credential($0)?.origin == origin } }
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
                        Text("密码保存在本机 Keychain，同时读取 shared/password_manager/vault.json。来自文件的记录在修改或删除时同步原文件。填充仅匹配相同 HTTPS 网站，不会自动提交登录。")
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
                    if let url = urls.first, store.importFile(url) { message = "密码已保存，请在密码管理器中查看。关联文件的修改和删除会同步。" }
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
        do {
            let result = try await BrowserCredentialFiller.fill(entry, manager: manager)
            message = result
                ? String(localized: "Login filled. Review the page before signing in.")
                : String(localized: "No supported login form found on this page.")
        } catch { message = String(localized: "Unable to fill this login form.") }
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
    static func fill(_ entry: BrowserCredential, manager: BrowserUseManager) async throws -> Bool {
        guard BrowserCredentialStore.origin(for: manager.currentURL) == entry.origin else { return false }
        let result = try await manager.webView.callAsyncJavaScript("""
                if (location.origin !== origin) return false;
                const fields = [...document.querySelectorAll('input[type="password"]')].filter(e => e.getClientRects().length && !e.disabled && !e.readOnly && e.autocomplete !== 'new-password');
                if (fields.length !== 1) return false;
                const passwordField = fields[0];
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
                        do {
                            let filled = try await BrowserCredentialFiller.fill(entry, manager: manager)
                            feedback = filled ? "已填充，请确认后登录。" : "当前页面未找到支持的登录表单。"
                        } catch { feedback = "无法填充当前页面。" }
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
