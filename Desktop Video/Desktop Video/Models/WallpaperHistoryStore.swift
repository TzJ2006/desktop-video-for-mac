import Foundation
import AppKit

class WallpaperHistoryStore: ObservableObject {
    static let shared = WallpaperHistoryStore()

    @Published var entries: [WallpaperHistoryEntry] = []

    private let storageKey = "wallpaperHistory"
    /// 历史（played=true）条目上限
    private let maxHistory = 100
    /// 壁纸库（inLibrary=true）条目上限，与 MediaAccess.scanFolder 的枚举上限一致
    private let maxLibrary = 1000

    private init() {
        loadEntries()
    }

    /// 壁纸画廊条目：仅 inLibrary=true，按用户设定排序；URL 唯一（插入时已去重）。
    func libraryEntries(sortedBy order: AppState.LibrarySortOrder) -> [WallpaperHistoryEntry] {
        Self.sortLibrary(entries.filter { $0.inLibrary }, by: order)
    }

    /// 指定屏幕的历史记录：在该屏幕上设为过壁纸的条目，按该屏最近使用在前。
    /// 旧数据（playedScreens 为空）视为属于所有屏幕，保证升级后历史不丢失。
    /// screenID 为空（无有效屏幕选择，如早期启动/无显示器）时回退显示全部历史，避免误判为「无历史」。
    func playedEntries(for screenID: String) -> [WallpaperHistoryEntry] {
        entries.filter {
            $0.played && (screenID.isEmpty || $0.playedScreens.isEmpty || $0.playedScreens[screenID] != nil)
        }
            .sorted {
                let l = $0.playedScreens[screenID] ?? $0.lastUsedAt ?? $0.timestamp
                let r = $1.playedScreens[screenID] ?? $1.lastUsedAt ?? $1.timestamp
                return l > r
            }
    }

    /// 记录一次「设为壁纸」：置 played=true 并标记所在屏幕；若已在库中则保留 inLibrary。
    func record(url: URL, contentType: String, screenID: String) {
        let now = Date()
        if let index = entries.firstIndex(where: { $0.urlString == url.absoluteString }) {
            var entry = entries.remove(at: index)
            entry.timestamp = now
            entry.played = true
            entry.lastUsedAt = now
            entry.playedScreens[screenID] = now
            entries.insert(entry, at: 0)
        } else {
            entries.insert(
                WallpaperHistoryEntry(
                    url: url, contentType: contentType,
                    played: true, inLibrary: false,
                    addedAt: now, lastUsedAt: now,
                    playedScreens: [screenID: now]),
                at: 0)
        }
        trim()
        saveEntries()
    }

    /// 批量添加进「壁纸库」（文件夹批量添加用）：inLibrary=true、played=false。
    /// 已存在的条目保持原状，避免扰动已有历史。
    func recordMany(_ items: [(url: URL, contentType: String)]) {
        guard !items.isEmpty else { return }
        var changed = false
        let now = Date()
        for (url, contentType) in items {
            if entries.contains(where: { $0.urlString == url.absoluteString }) { continue }
            entries.insert(
                WallpaperHistoryEntry(
                    url: url, contentType: contentType,
                    played: false, inLibrary: true,
                    addedAt: now),
                at: 0)
            changed = true
        }
        guard changed else { return }
        trim()
        saveEntries()
    }

    /// 确保 URL 在壁纸库中（单文件添加 / 网页快捷入口用）；首次加入时记录 addedAt。
    func ensureInLibrary(url: URL, contentType: String) {
        if let index = entries.firstIndex(where: { $0.urlString == url.absoluteString }) {
            guard !entries[index].inLibrary else { return }
            entries[index].inLibrary = true
            entries[index].addedAt = Date()
        } else {
            entries.insert(
                WallpaperHistoryEntry(
                    url: url, contentType: contentType,
                    played: false, inLibrary: true),
                at: 0)
        }
        trim()
        saveEntries()
    }

    /// 从壁纸库移除；若条目同时存在于历史则仅去掉库标记，否则整行删除。
    func removeFromLibrary(entry: WallpaperHistoryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        if entries[index].played {
            entries[index].inLibrary = false
        } else {
            entries.remove(at: index)
        }
        saveEntries()
    }

    func remove(entry: WallpaperHistoryEntry) {
        removeFromLibrary(entry: entry)
    }

    /// 清空指定屏幕的历史记录：移除该屏的使用标记，保留壁纸库条目。
    /// 旧数据（无屏幕归属）随任意一次清除一并清掉；仍被其它屏幕使用的条目保留。
    func clearHistory(for screenID: String) {
        for index in entries.indices where entries[index].played {
            if entries[index].playedScreens.isEmpty {
                entries[index].played = false
                entries[index].lastUsedAt = nil
            } else {
                entries[index].playedScreens[screenID] = nil
                if entries[index].playedScreens.isEmpty {
                    entries[index].played = false
                    entries[index].lastUsedAt = nil
                }
            }
        }
        entries.removeAll { !$0.inLibrary && !$0.played }
        saveEntries()
    }

    private func trim() {
        // 历史按屏幕分别限量：每块屏幕各保留最近 maxHistory 条，避免某块屏幕的历史
        // 被其它屏幕的新记录按全局上限挤出（per-screen 过滤与全局 trim 不一致会导致整屏历史消失）。
        var historyKeep = Set<String>()
        let screenIDs = Set(entries.filter { $0.played }.flatMap { $0.playedScreens.keys })
        for screenID in screenIDs {
            historyKeep.formUnion(
                entries.filter { $0.played && $0.playedScreens[screenID] != nil }
                    .sorted { ($0.playedScreens[screenID] ?? .distantPast) > ($1.playedScreens[screenID] ?? .distantPast) }
                    .prefix(maxHistory)
                    .map(\.id)
            )
        }
        // 旧数据（无屏幕归属）按全局最近使用保留 maxHistory 条
        historyKeep.formUnion(
            entries.filter { $0.played && $0.playedScreens.isEmpty }
                .sorted { ($0.lastUsedAt ?? $0.timestamp) > ($1.lastUsedAt ?? $1.timestamp) }
                .prefix(maxHistory)
                .map(\.id)
        )
        let libraryKeep = Set(
            entries.filter { $0.inLibrary }
                .sorted { $0.addedAt > $1.addedAt }
                .prefix(maxLibrary)
                .map(\.id)
        )
        let keep = historyKeep.union(libraryKeep)
        entries = entries.filter { keep.contains($0.id) }
    }

    private static func sortLibrary(
        _ items: [WallpaperHistoryEntry],
        by order: AppState.LibrarySortOrder
    ) -> [WallpaperHistoryEntry] {
        switch order {
        case .nameAsc:
            return items.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        case .nameDesc:
            return items.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedDescending
            }
        case .recentAdd:
            return items.sorted { $0.addedAt > $1.addedAt }
        case .recentUse:
            return items.sorted {
                ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast)
            }
        }
    }

    private func loadEntries() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([WallpaperHistoryEntry].self, from: data)
        else { return }
        entries = decoded
        migrateLegacyPlayedScreens()
    }

    /// 旧版本历史无屏幕归属（playedScreens 为空）。首次加载时把它们归到主显示器，
    /// 使「按屏幕切换历史」可见生效——否则旧历史会在所有屏幕上重复显示，切换屏幕看起来像没变化。
    /// 必须归到当前活动的屏幕（而非可能已断开的 lastScreen），否则会被过滤掉而完全不显示。
    /// NSScreen.main 偶发为 nil（早期启动）时回退到任一在用屏幕，仅真正无显示器才跳过。
    private func migrateLegacyPlayedScreens() {
        guard let mainID = (NSScreen.main ?? NSScreen.screens.first)?.dv_displayUUID else { return }
        var changed = false
        for index in entries.indices where entries[index].played && entries[index].playedScreens.isEmpty {
            entries[index].playedScreens[mainID] = entries[index].lastUsedAt ?? entries[index].timestamp
            changed = true
        }
        if changed { saveEntries() }
    }

    private func saveEntries() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
