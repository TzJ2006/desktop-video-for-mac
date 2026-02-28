import Foundation

struct WallpaperHistoryEntry: Codable, Identifiable {
    var id: String { urlString }
    let urlString: String
    let contentType: String  // "video" or "image"
    var timestamp: Date
    let fileName: String

    init(url: URL, contentType: String) {
        self.urlString = url.absoluteString
        self.contentType = contentType
        self.timestamp = Date()
        self.fileName = url.lastPathComponent
    }

    var url: URL? { URL(string: urlString) }
    var isVideo: Bool { contentType == "video" }
}
