import Foundation

// MARK: - Artist

/// Represents an artist.
struct Artist: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let thumbnailURL: URL?
    let songCount: Int?

    init(id: String, name: String, thumbnailURL: URL? = nil, songCount: Int? = nil) {
        self.id = id
        self.name = name
        self.thumbnailURL = thumbnailURL
        self.songCount = songCount
    }
}

extension Artist {
    /// Creates an Artist from API response data.
    init?(from data: [String: Any]) {
        let name = (data["name"] as? String) ?? "Unknown Artist"

        // Artist ID is optional for inline references
        let artistId = (data["id"] as? String) ?? (data["browseId"] as? String) ?? UUID().uuidString

        self.id = artistId
        self.name = name

        // Parse thumbnail
        if let thumbnails = data["thumbnails"] as? [[String: Any]],
           let lastThumbnail = thumbnails.last,
           let urlString = lastThumbnail["url"] as? String
        {
            self.thumbnailURL = URL(string: urlString)
        } else {
            self.thumbnailURL = nil
        }

        // Parse song count if available (from subtitle like "42 songs")
        if let subtitle = data["subtitle"] as? String {
            let numbers = subtitle.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            self.songCount = Int(numbers)
        } else {
            self.songCount = nil
        }
    }
}
