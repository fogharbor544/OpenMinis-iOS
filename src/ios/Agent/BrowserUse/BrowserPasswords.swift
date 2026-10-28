import SwiftUI
import Security
import WebKit

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

    init(vault: any BrowserCredentialVault = KeychainBrowserCredentialVault(),
         authenticate: @escaping () async -> Bool = {
             await BiometricAuth.authenticate(reason: String(localized: "Unlock browser passwords"))
         }) {
        self.vault = vault
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

    private func persist(_ next: [BrowserCredential]) -> Bool {
        do {
            try vault.write(JSONEncoder().encode(next))
            entries = next
            errorMessage = nil
            return true
        } catch {
            errorMessage = String(localized: "Unable to save passwords. Check that a device passcode is enabled.")
            return false
        }
    }
}

struct BrowserPasswordsView: View {
    @ObservedObject var manager: BrowserUseManager
    @StateObject private var store = BrowserCredentialStore()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var editing: BrowserCredential?
    @State private var deleting: BrowserCredential?
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
                        Button("Save Login from Current Page") { Task { await capture() } }
                            .disabled(busy || BrowserCredentialStore.origin(for: manager.currentURL) == nil)
                    } footer: {
                        Text("Passwords stay in this device's Keychain. Filling supports HTTPS login forms in the main page; embedded frames, passkeys and multi-step logins may require manual entry.")
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
            .task { await store.unlock() }
            .onDisappear { store.lock() }
            .onChange(of: scenePhase) { _, phase in
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
            message = (result as? Bool == true)
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
