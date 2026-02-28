import Foundation

class WallpaperHistoryStore: ObservableObject {
    static let shared = WallpaperHistoryStore()

    @Published var entries: [WallpaperHistoryEntry] = []

    private let storageKey = "wallpaperHistory"
    private let maxEntries = 100

    private init() {
        loadEntries()
    }

    func record(url: URL, contentType: String) {
        if let index = entries.firstIndex(where: { $0.urlString == url.absoluteString }) {
            var entry = entries.remove(at: index)
            entry.timestamp = Date()
            entries.insert(entry, at: 0)
        } else {
            let entry = WallpaperHistoryEntry(url: url, contentType: contentType)
            entries.insert(entry, at: 0)
        }

        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }

        saveEntries()
    }

    func remove(entry: WallpaperHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        saveEntries()
    }

    func clearAll() {
        entries.removeAll()
        saveEntries()
    }

    private func loadEntries() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([WallpaperHistoryEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func saveEntries() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
