import Foundation

/// Represents the logged-in user's YouTube Music account information.
struct AccountInfo: RawRepresentable {
    /// The account display name.
    let name: String?

    /// The profile photo/avatar URL string.
    let thumbnailURL: String?

    init(name: String?, thumbnailURL: String?) {
        self.name = name
        self.thumbnailURL = thumbnailURL
    }

    var thumbnailURLValue: URL? {
        thumbnailURL.flatMap { URL(string: $0) }
    }

    // MARK: - RawRepresentable (for @AppStorage)

    init?(rawValue: String) {
        let parts = rawValue.components(separatedBy: "\n")
        guard parts.count == 2 else { return nil }
        self.name = parts[0].isEmpty ? nil : parts[0]
        self.thumbnailURL = parts[1].isEmpty ? nil : parts[1]
    }

    var rawValue: String {
        "\(name ?? "")\n\(thumbnailURL ?? "")"
    }
}
