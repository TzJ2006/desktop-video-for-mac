import SwiftUI

struct HistoryItemRow: View {
    let entry: WallpaperHistoryEntry
    let onDoubleClick: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: entry.isWeb ? "globe" : (entry.isVideo ? "film" : "photo"))
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 64, height: 48)
            .clipped()
            .cornerRadius(4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.1))
            )

            // File info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.fileName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    Text(LocalizedStringKey(L(entry.isWeb ? "Web" : (entry.isVideo ? "Video" : "Image"))))
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(entry.isWeb ? Color.purple.opacity(0.15) : (entry.isVideo ? Color.blue.opacity(0.15) : Color.green.opacity(0.15)))
                        )
                        .foregroundColor(entry.isWeb ? .purple : (entry.isVideo ? .blue : .green))
                }

                HStack(spacing: 8) {
                    Text(entry.timestamp, style: .relative)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    if let url = entry.url {
                        Text(entry.isWeb ? url.absoluteString : url.deletingLastPathComponent().path)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleClick() }
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        guard !entry.isWeb, let url = entry.url else { return }
        thumbnail = await ThumbnailGenerator.generate(for: url, isVideo: entry.isVideo)
    }
}
