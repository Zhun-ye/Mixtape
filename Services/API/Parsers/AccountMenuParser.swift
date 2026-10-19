import Foundation

/// Parses account menu responses from the API.
enum AccountMenuParser {
    /// Parses account info from the account menu response.
    /// Response path: actions[0].openPopupAction.popup.multiPageMenuRenderer.header.activeAccountHeaderRenderer
    /// - Parameter data: The response from the account/account_menu endpoint
    /// - Returns: Parsed AccountInfo, or nil if parsing fails
    static func parse(from data: [String: Any]) -> AccountInfo? {
        guard let actions = data["actions"] as? [[String: Any]],
              let firstAction = actions.first,
              let openPopupAction = firstAction["openPopupAction"] as? [String: Any],
              let popup = openPopupAction["popup"] as? [String: Any],
              let multiPageMenuRenderer = popup["multiPageMenuRenderer"] as? [String: Any],
              let header = multiPageMenuRenderer["header"] as? [String: Any],
              let activeAccountHeaderRenderer = header["activeAccountHeaderRenderer"] as? [String: Any]
        else {
            return nil
        }

        // Extract account name
        let name = self.extractText(from: activeAccountHeaderRenderer["accountName"])

        // Extract thumbnail URL
        let thumbnailURL = self.extractThumbnailURLString(from: activeAccountHeaderRenderer["accountPhoto"])

        return AccountInfo(name: name, thumbnailURL: thumbnailURL)
    }

    /// Extracts text from a runs-based text object.
    private static func extractText(from value: Any?) -> String? {
        guard let textObject = value as? [String: Any],
              let runs = textObject["runs"] as? [[String: Any]],
              let firstRun = runs.first,
              let text = firstRun["text"] as? String
        else {
            return nil
        }
        return text
    }

    /// Extracts thumbnail URL string from a thumbnails object.
    /// Removes size parameters (after "=") to get the full-size image.
    private static func extractThumbnailURLString(from value: Any?) -> String? {
        guard let photoObject = value as? [String: Any],
              let thumbnails = photoObject["thumbnails"] as? [[String: Any]],
              let firstThumbnail = thumbnails.first,
              var urlString = firstThumbnail["url"] as? String
        else {
            return nil
        }

        // Remove size parameters to get full resolution
        // e.g., "https://...=s48-c-k-c0x00ffffff-no-rj" -> "https://..."
        if let equalsIndex = urlString.firstIndex(of: "=") {
            urlString = String(urlString[..<equalsIndex])
        }

        return urlString
    }
}
