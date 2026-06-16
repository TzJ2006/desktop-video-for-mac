import Foundation

struct WallpaperHistoryEntry: Codable, Identifiable {
    var id: String { urlString }
    let urlString: String
    let contentType: String  // "video", "image", or "web"
    var timestamp: Date
    let fileName: String
    /// 是否真正被设为过壁纸（=计入「历史记录」）。
    var played: Bool
    /// 是否出现在「壁纸」画廊（快捷切换入口）。
    var inLibrary: Bool
    /// 加入壁纸库的时间，用于「最近添加」排序。
    var addedAt: Date
    /// 最近一次被设为壁纸的时间，用于「最近使用」排序与历史记录顺序。
    var lastUsedAt: Date?
    /// 各屏幕上最近一次被设为壁纸的时间（screen UUID → 时间）。
    /// 历史记录按屏幕过滤/排序的依据。旧数据无此字段，解码为空字典，
    /// 并在显示时视为「属于所有屏幕」以避免升级后历史丢失。
    var playedScreens: [String: Date]

    init(
        url: URL,
        contentType: String,
        played: Bool = true,
        inLibrary: Bool? = nil,
        addedAt: Date = Date(),
        lastUsedAt: Date? = nil,
        playedScreens: [String: Date] = [:]
    ) {
        self.urlString = url.absoluteString
        self.contentType = contentType
        let now = Date()
        self.timestamp = now
        self.fileName = url.lastPathComponent
        self.played = played
        self.inLibrary = inLibrary ?? !played
        self.addedAt = addedAt
        self.lastUsedAt = lastUsedAt ?? (played ? now : nil)
        self.playedScreens = playedScreens
    }

    private enum CodingKeys: String, CodingKey {
        case urlString, contentType, timestamp, fileName, played
        case inLibrary, addedAt, lastUsedAt, playedScreens
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        urlString = try c.decode(String.self, forKey: .urlString)
        contentType = try c.decode(String.self, forKey: .contentType)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        fileName = try c.decode(String.self, forKey: .fileName)
        played = try c.decodeIfPresent(Bool.self, forKey: .played) ?? true
        inLibrary = try c.decodeIfPresent(Bool.self, forKey: .inLibrary) ?? !played
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? timestamp
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
            ?? (played ? timestamp : nil)
        playedScreens = try c.decodeIfPresent([String: Date].self, forKey: .playedScreens) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(urlString, forKey: .urlString)
        try c.encode(contentType, forKey: .contentType)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(fileName, forKey: .fileName)
        try c.encode(played, forKey: .played)
        try c.encode(inLibrary, forKey: .inLibrary)
        try c.encode(addedAt, forKey: .addedAt)
        try c.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
        try c.encode(playedScreens, forKey: .playedScreens)
    }

    var url: URL? { URL(string: urlString) }
    var isVideo: Bool { contentType == "video" }
    var isWeb: Bool { contentType == "web" }

    /// 用于界面展示的名称。网页取 host（或完整 URL），文件取文件名。
    var displayName: String {
        if isWeb {
            guard let url else { return urlString }
            return url.host ?? urlString
        }
        return fileName
    }
}
