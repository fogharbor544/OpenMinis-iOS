import SwiftUI

struct BrowserBookmark: Identifiable, Codable {
    var id = UUID()
    var title: String
    var url: String
}

/// Uses the same application-support directory as browsing history, without its retention limit.
@MainActor
final class BrowserBookmarkStore: ObservableObject {
    static let shared = BrowserBookmarkStore()
    @Published private(set) var entries: [BrowserBookmark] = []
    @Published var errorMessage: String?
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MinisChat/browser_bookmarks.json")
        do {
            if FileManager.default.fileExists(atPath: self.fileURL.path) {
                entries = try JSONDecoder().decode([BrowserBookmark].self, from: Data(contentsOf: self.fileURL))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func normalizedURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    @discardableResult
    func save(_ bookmark: BrowserBookmark) -> Bool {
        guard let url = Self.normalizedURL(bookmark.url) else {
            errorMessage = String(localized: "Enter a valid HTTP or HTTPS address.")
            return false
        }
        var next = entries
        var bookmark = bookmark
        bookmark.url = url.absoluteString
        bookmark.title = bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if bookmark.title.isEmpty { bookmark.title = url.host ?? bookmark.url }
        if let index = next.firstIndex(where: { $0.id == bookmark.id }) {
            next[index] = bookmark
        } else {
            next.insert(bookmark, at: 0)
        }
        return persist(next)
    }

    func delete(at offsets: IndexSet) {
        var next = entries
        next.remove(atOffsets: offsets)
        _ = persist(next)
    }

    private func persist(_ next: [BrowserBookmark]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: fileURL, options: .atomic)
            entries = next
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

struct BrowserBookmarksView: View {
    @ObservedObject var store: BrowserBookmarkStore
    var currentURL: String
    var currentTitle: String
    var onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editing: BrowserBookmark?

    var body: some View {
        NavigationStack {
            List {
                Button {
                    editing = BrowserBookmark(title: currentTitle, url: currentURL)
                } label: {
                    Label("Bookmark Current Page", systemImage: "bookmark.badge.plus")
                }
                .disabled(BrowserBookmarkStore.normalizedURL(currentURL) == nil)
                if store.entries.isEmpty {
                    ContentUnavailableView("No Bookmarks", systemImage: "bookmark", description: Text("Save pages to open them again later."))
                }
                ForEach(store.entries) { bookmark in
                    Button {
                        onSelect(bookmark.url)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bookmark.title).foregroundStyle(.primary)
                            Text(bookmark.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button("Edit") { editing = bookmark }.tint(.blue)
                    }
                    .contextMenu { Button("Edit") { editing = bookmark } }
                }
                .onDelete(perform: store.delete)
            }
            .navigationTitle("Bookmarks")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editing) { bookmark in
                BrowserBookmarkEditor(store: store, bookmark: bookmark)
            }
            .alert("Bookmarks", isPresented: Binding(get: { store.errorMessage != nil && editing == nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK") { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
        }
    }
}

private struct BrowserBookmarkEditor: View {
    @ObservedObject var store: BrowserBookmarkStore
    @State var bookmark: BrowserBookmark
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $bookmark.title)
                TextField("Address", text: $bookmark.url)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Edit Bookmark")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { store.errorMessage = nil; dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if store.save(bookmark) { dismiss() } }
                        .disabled(BrowserBookmarkStore.normalizedURL(bookmark.url) == nil)
                }
            }
        }
    }
}
